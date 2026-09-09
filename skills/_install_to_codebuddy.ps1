# ==========================================================================
# CodeBuddy 专用技能安装/验证脚本：把 git 仓库内的技能以 Junction 方式链到 CodeBuddy 技能目录
# 事实源（唯一）：本仓库 skills\<技能名>\
# 只改仓库一处，CodeBuddy 即时生效；改完 git commit/push 即可同步远程。
#
# 用法：
#   pwsh -ExecutionPolicy Bypass -File skills\_install_to_codebuddy.ps1               # 安装/修复链接
#   pwsh -ExecutionPolicy Bypass -File skills\_install_to_codebuddy.ps1 -VerifyOnly   # 只验证不改动（漂移检查）
#   pwsh -ExecutionPolicy Bypass -File skills\_install_to_codebuddy.ps1 -IncludeAll   # 连 trae-importer 一起链
#
# 与 _install_to_work.ps1（Trae/WorkBuddy 专用）的关系：
#   - 本脚本【只】操作 CodeBuddy 的 ~/.codebuddy/skills，不碰 .agents / .trae* / .workbuddy
#     也不修改 _install_to_work.ps1 的任何逻辑；两个脚本互不依赖，可各自独立运行。
#   - 为什么【不复用】 .agents\skills 那一层（即 .codebuddy -> .agents -> 仓库 的两跳链）：
#     实测 CodeBuddy 只识别一跳 Junction。.codebuddy\skills\lhg-dev-thinking 是指向
#     .agents\skills\lhg-dev-thinking（该处又是 Junction -> 仓库）的两跳链，
#     结果 lhg-dev-thinking 在 CodeBuddy 技能列表里根本不可见；
#     而指向实体目录的一跳链（其余 50+ 个技能）全部正常可见。
#     => 结论：CodeBuddy 的链接必须【一跳直达仓库】。
#
# 手工卸载某个技能的链接（只删链接，绝不动仓库内容）：
#   [IO.Directory]::Delete("$env:USERPROFILE\.codebuddy\skills\<技能名>", $false)
# ==========================================================================

param(
    [switch]$VerifyOnly,
    [switch]$IncludeAll
)

$ErrorActionPreference = 'Stop'

$repoSkills = 'C:\AI-Skills\github\csharp-defensive-programming\skills'
# 默认链接清单：仓库内对 CodeBuddy 有价值的技能
# 说明：trae-importer 是 WorkBuddy 专用迁移器，默认不链进 CodeBuddy（-IncludeAll 才链）
$skills     = @(
    'lhg-dev-thinking',
    'lhg-dev-doc',
    'lhg-skill-new',
    'code-complexity-governor',
    'csharp-defensive-programming'
)
if ($IncludeAll) { $skills += 'trae-importer' }

# CodeBuddy 用户级技能目录（可用 -cbRoot 覆盖，便于在新机器/新账号上试跑）
$cbRoot = 'C:\Users\Administrator\.codebuddy\skills'

# 备份区必须在 IDE 技能扫描范围之外：留在技能根目录内的 *.backup-* 会被 IDE 索引成同名重复技能
$backupRoot = 'C:\AI-Skills\_backups\codebuddy'

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

function Test-SkillSource {
    # 健康检查一律走【仓库真实路径】，绝不穿过 Junction 读取：
    # 本机 .NET 10 对"不受信任的装入点"会拒绝遍历 Junction（ReadAllBytes/Get-Content 直接抛异常），
    # 穿过链接读会被误报成"技能不存在"。
    param([string]$Dir)

    $md = Join-Path $Dir 'SKILL.md'
    if (-not (Test-Path -LiteralPath $md)) { return 'NO-SKILL.md' }
    $bytes = [System.IO.File]::ReadAllBytes($md)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { return 'BOM' }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text -notmatch '(?s)\A---\r?\n.*?\r?\n---') { return 'NO-FRONTMATTER' }
    if ($text -notmatch '(?m)^name:\s*\S') { return 'NO-NAME' }
    if ($text -notmatch '(?m)^description:\s*\S') { return 'NO-DESC' }
    return 'OK'
}

$problems = 0

if (-not (Test-Path $cbRoot)) {
    Write-Warning "CodeBuddy 技能目录不存在：$cbRoot（CodeBuddy 未安装或路径已变，请用 -cbRoot 指定）"
    exit 2
}

foreach ($skill in $skills) {
    $src = Join-Path $repoSkills $skill
    Write-Host "=== $skill ==="

    $health = Test-SkillSource -Dir $src
    if ($health -ne 'OK') {
        Write-Host "  [SRC-$health] $src  -- 事实源本身有问题，跳过链接（先修仓库里的 SKILL.md）"
        $problems++
        continue
    }

    $dst = Join-Path $cbRoot $skill
    if ($VerifyOnly) {
        $st = Get-LinkStatus -Path $dst -Target $src
        $tag = switch ($st) { 'OK' { '[OK]   ' } 'FORK' { '[FORK] ' } 'MISSING' { '[MISS] ' } default { '[BAD]  ' } }
        Write-Host ("  {0} {1}" -f $tag, $dst)
        if ($st -ne 'OK') { $problems++ }
    } else {
        $r = New-SkillJunction -Path $dst -Target $src
        Write-Host ("  [{0}] {1}" -f $r, $dst)
    }
}

# 两跳链扫描：CodeBuddy 不识别 .codebuddy\<技能> -> .agents\<技能>(Junction) -> 仓库 这种链，
# 表现为技能在 CodeBuddy 里凭空消失。发现即报告（不在本脚本职责内自动改 .agents，避免影响 Trae 侧）。
$twoHop = Get-ChildItem $cbRoot -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.LinkType -and $_.Target -and (Get-Item $_.Target -Force -ErrorAction SilentlyContinue).LinkType
}
foreach ($j in $twoHop) {
    Write-Host ("  [2-HOP] {0} -> {1} -> {2}  -- CodeBuddy 不识别两跳链接，该技能不会出现在技能列表" -f $j.Name, ($j.Target -join ';'), ((Get-Item $j.Target -Force).Target -join ';'))
    $problems++
}

# STRAY 扫描：备份残留（*.backup-*）留在技能扫描根内会被 IDE 索引成重复技能
Get-ChildItem $cbRoot -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*.backup-*' } |
    ForEach-Object {
        Write-Host "  [STRAY] $($_.FullName)  -- 备份残留在技能扫描目录内，会被 IDE 索引成重复技能，请移走或删除"
        $problems++
    }

Write-Host ""
if ($problems -gt 0) {
    Write-Warning "发现 $problems 处异常（FORK=实体副本分叉 / MISS=未链接 / BAD=指向错误 / 2-HOP=两跳链接不可见 / STRAY=备份残留被索引风险 / SRC-*=仓库事实源本身有问题）。链接问题运行不带 -VerifyOnly 的安装命令修复；STRAY 与 2-HOP 需按提示手工处理。"
    exit 1
}
Write-Host "全部链接正常：$cbRoot 下每个目标技能均为一跳 Junction -> git 仓库事实源。"
Write-Host "提示：CodeBuddy 在启动时扫描技能目录，新增/改动链接后需重启 CodeBuddy（或重新加载窗口）才会出现在技能列表。"
exit 0
