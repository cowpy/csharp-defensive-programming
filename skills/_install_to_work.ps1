# ==========================================================================
# LHG skills 安装/验证脚本：把 git 仓库内的技能以 Junction 方式链接到各 IDE 技能目录
# 事实源（唯一）：本仓库 skills\<技能名>\
# 修改技能只改仓库一处，所有链接位置即时生效；改完 git commit/push 即可同步远程。
#
# 用法：
#   pwsh -ExecutionPolicy Bypass -File skills\_install_to_work.ps1              # 安装/修复链接
#   pwsh -ExecutionPolicy Bypass -File skills\_install_to_work.ps1 -VerifyOnly  # 只验证不改动（漂移检查）
#
# 设计原则：
#   - 约定（仓库路径、链接落点、命名）写死在脚本里，LLM 不需要每次重新探测/询问；
#   - 但"链接是否生效"必须由脚本自动验证（零 token 成本），不靠记忆和假设；
#   - work 模型目录自动枚举，TRAE 新增模型目录无需改脚本；
#   - 同名实体目录（非 Junction）= 分叉隐患，验证时显式报告 FORK。
#
# 铁律：一跳直达。IDE 目录必须直接 Junction 到仓库，禁止「IDE -> .agents -> 仓库」的两跳链：
#   2026-09-09 实测 CodeBuddy 不识别两跳（技能在列表里凭空消失）；
#   .trae\skills\lhg-dev-thinking 也曾因 .agents 中转退化成两跳。
#   所以 .agents\skills 这一层被改成 Junction 时，所有下游链接必须同步改成一跳直达仓库。
#
# 兄弟脚本：skills\_install_to_codebuddy.ps1（CodeBuddy 专用，落点 ~/.codebuddy\skills）。
#   两个脚本各管各的落点、互不依赖：本脚本不碰 ~/.codebuddy，CodeBuddy 脚本不碰 .agents/.trae*。
#
# 2026-09-09 变更：$skills 纳入 code-complexity-governor 与 csharp-defensive-programming。
#   这两个技能原先在 .agents\skills 是实体副本（内容已核对与仓库一致，仅 CRLF/LF 差异），
#   现统一改为 Junction -> 仓库；旧副本备份在 C:\AI-Skills\_backups\agents\。
#
# 历史教训：旧版本脚本只链接了 builtin\work\*（work 模型目录），
# 而 TRAE 主界面实际读取 .trae-cn\skills -> .agents\skills（真实目录），
# 该路径从未接到仓库，导致蒸馏的原则写进 .agents 副本后与仓库分叉（两套版本）。
# ==========================================================================

param(
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

$repoSkills  = 'C:\AI-Skills\github\csharp-defensive-programming\skills'
# 例外：trae-importer 也在本仓库内（仅作 git 版本管理、防丢失），
# 但它只服务 WorkBuddy、不链到 Trae 各落点，故不列入本数组
$skills      = @(
    'lhg-dev-thinking',
    'lhg-dev-doc',
    'lhg-skill-new',
    'code-complexity-governor',
    'csharp-defensive-programming'
)
# 备份区必须在 IDE 技能扫描范围之外：留在技能根目录内的 *.backup-* 会被 IDE 索引成同名重复技能
# （2026-09-04 实测：TRAE 调用技能时从 .trae-cn\skills\<技能>.backup-* 加载，而非从 Junction 加载）
$backupRoot  = 'C:\AI-Skills\_backups'

# 固定主落点（TRAE 主界面读取链 + 全局技能目录）
$mainRoots = @(
    'C:\Users\Administrator\.trae-cn\skills',   # TRAE 国内版（TraeWork）主界面读取链
    'C:\Users\Administrator\.trae\skills',      # TRAE 国际版（TraeCode）
    'C:\Users\Administrator\.agents\skills'     # 全局共享技能池（Qoder/Continue/CodeBuddy 也读它）
)
# 注：.qoder\skills 与 .continue\skills 不在本脚本落点内（非 TRAE 家族）。
#     若手工给它们建链接，同样必须「一跳直达仓库」，不要指向 .agents 中转。

# work 模型目录：自动枚举，TRAE 新增模型自动覆盖
$workBase = 'C:\Users\Administrator\.trae-cn\builtin\work'
$workRoots = @()
if (Test-Path $workBase) {
    $workRoots = Get-ChildItem $workBase -Directory | ForEach-Object { Join-Path $_.FullName 'skills' }
}

function Get-LinkStatus {
    param([string]$Path, [string]$Target)
    # 用 Get-Item 而非 Test-Path 判存在：断链 Junction（目标已删）Test-Path 返回 false，会误判成 MISSING
    $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return 'MISSING' }
    if ($item.LinkType -eq 'Junction' -and ($item.Target -join ';') -eq $Target) { return 'OK' }
    if ($item.LinkType) { return 'WRONG-TARGET' }
    return 'FORK'   # 实体目录：内容独立于仓库，分叉隐患
}

function New-SkillJunction {
    param([string]$Path, [string]$Target)

    $status = Get-LinkStatus -Path $Path -Target $Target
    if ($status -eq 'OK') { return 'skip' }
    $note = ''
    $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType) {
        # 旧链接本身不含内容，备份无意义（备份了反而会留下跟随仓库内容变化的"幽灵技能"）；
        # [IO.Directory]::Delete($Path, $false) 只删 reparse point，绝不动链接目标
        [IO.Directory]::Delete($Path, $false)
        $note = ', old link removed'
    } elseif ($item) {
        # 实体目录可能含独有内容：移到 IDE 扫描范围之外的备份区，禁止留在技能根目录内
        if (-not (Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null }
        $dest = Join-Path $backupRoot ("{0}.backup-{1}" -f (Split-Path $Path -Leaf), (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $i = 2
        while (Test-Path $dest) { $dest = Join-Path $backupRoot ("{0}.backup-{1}-{2}" -f (Split-Path $Path -Leaf), (Get-Date -Format 'yyyyMMdd-HHmmss'), $i); $i++ }
        Move-Item -Path $Path -Destination $dest
        $note = ", entity moved to $dest"
    }
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    New-Item -ItemType Junction -Path $Path -Target $Target -Force | Out-Null
    return "linked(was $status$note)"
}

$allTargets = @()
foreach ($root in $mainRoots) { $allTargets += [pscustomobject]@{ Root = $root; Label = $root } }
foreach ($root in $workRoots) {
    $model = Split-Path (Split-Path $root -Parent) -Leaf
    $allTargets += [pscustomobject]@{ Root = $root; Label = "work\$model" }
}

$problems = 0
foreach ($skill in $skills) {
    $src = Join-Path $repoSkills $skill
    if (-not (Test-Path (Join-Path $src 'SKILL.md'))) {
        Write-Warning "仓库中找不到 $src\SKILL.md，跳过"
        continue
    }
    Write-Host "=== $skill ==="
    foreach ($t in $allTargets) {
        $dst = Join-Path $t.Root $skill
        if ($VerifyOnly) {
            $st = Get-LinkStatus -Path $dst -Target $src
            $tag  = switch ($st) { 'OK' { '[OK]   ' } 'FORK' { '[FORK] ' } 'MISSING' { '[MISS] ' } default { '[BAD]  ' } }
            Write-Host ("  {0} {1}" -f $tag, $t.Label)
            if ($st -ne 'OK') { $problems++ }
        } else {
            $r = New-SkillJunction -Path $dst -Target $src
            Write-Host ("  [{0}] {1}" -f $r, $t.Label)
        }
    }
}

if (-not $VerifyOnly) {
    Write-Host ""
    Write-Host "=== 安装后自动验证 ==="
    & $PSCommandPath -VerifyOnly
    exit $LASTEXITCODE
}

# 两跳链扫描：<IDE 目录>\<技能> -> .agents\<技能>(Junction) -> 仓库 这种链会让技能在 IDE 里加载不到
foreach ($t in $allTargets) {
    Get-ChildItem $t.Root -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType -and $_.Target -and (Get-Item ($_.Target -join ';') -Force -ErrorAction SilentlyContinue).LinkType } |
        ForEach-Object {
            $mid = Get-Item ($_.Target -join ';') -Force
            Write-Host ("  [2-HOP] {0} -> {1} -> {2}  -- 两跳链接，IDE 可能加载不到，请改为一跳直达仓库" -f $_.FullName, ($_.Target -join ';'), ($mid.Target -join ';'))
            $problems++
        }
}

# STRAY 扫描：备份残留（*.backup-*）留在技能扫描根内会被 IDE 索引成重复技能
foreach ($t in $allTargets) {
    Get-ChildItem $t.Root -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*.backup-*' } |
        ForEach-Object {
            Write-Host "  [STRAY] $($_.FullName)  -- 备份残留在技能扫描目录内，会被 IDE 索引成重复技能，请移走或删除"
            $problems++
        }
}

Write-Host ""
if ($problems -gt 0) {
    Write-Warning "发现 $problems 处异常（FORK=实体副本分叉 / MISS=未链接 / BAD=指向错误 / 2-HOP=两跳链接不可见 / STRAY=备份残留被索引风险）。链接问题运行不带 -VerifyOnly 的安装命令修复；STRAY 与 2-HOP 需按提示手工处理。"
    exit 1
}
Write-Host "全部链接正常：所有位置均为 Junction -> git 仓库事实源。"
exit 0
