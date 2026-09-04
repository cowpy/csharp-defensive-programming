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
# 历史教训：旧版本脚本只链接了 builtin\work\*（work 模型目录），
# 而 TRAE 主界面实际读取 .trae-cn\skills -> .agents\skills（真实目录），
# 该路径从未接到仓库，导致蒸馏的原则写进 .agents 副本后与仓库分叉（两套版本）。
# ==========================================================================

param(
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

$repoSkills = 'C:\AI-Skills\github\csharp-defensive-programming\skills'
$skills     = @('lhg-dev-thinking', 'lhg-dev-doc', 'lhg-skill-new')

# 固定主落点（TRAE 主界面读取链 + 全局技能目录）
$mainRoots = @(
    'C:\Users\Administrator\.trae-cn\skills',
    'C:\Users\Administrator\.agents\skills'
)

# work 模型目录：自动枚举，TRAE 新增模型自动覆盖
$workBase = 'C:\Users\Administrator\.trae-cn\builtin\work'
$workRoots = @()
if (Test-Path $workBase) {
    $workRoots = Get-ChildItem $workBase -Directory | ForEach-Object { Join-Path $_.FullName 'skills' }
}

function Get-LinkStatus {
    param([string]$Path, [string]$Target)
    if (-not (Test-Path $Path)) { return 'MISSING' }
    $item = Get-Item $Path -Force
    if ($item.LinkType -eq 'Junction' -and ($item.Target -join ';') -eq $Target) { return 'OK' }
    if ($item.LinkType -eq 'Junction') { return 'WRONG-TARGET' }
    return 'FORK'   # 实体目录：内容独立于仓库，分叉隐患
}

function New-SkillJunction {
    param([string]$Path, [string]$Target)

    $status = Get-LinkStatus -Path $Path -Target $Target
    if ($status -eq 'OK') { return 'skip' }
    if (Test-Path $Path) {
        # 实体目录或指向别处的链接：先备份再替换，防止内容丢失
        $backup = "$Path.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Rename-Item -Path $Path -NewName (Split-Path $backup -Leaf)
    }
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    New-Item -ItemType Junction -Path $Path -Target $Target -Force | Out-Null
    return "linked(was $status)"
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

Write-Host ""
if ($problems -gt 0) {
    Write-Warning "发现 $problems 处异常（FORK=实体副本分叉 / MISS=未链接 / BAD=指向错误）。运行不带 -VerifyOnly 的安装命令修复。"
    exit 1
}
Write-Host "全部链接正常：所有位置均为 Junction -> git 仓库事实源。"
exit 0
