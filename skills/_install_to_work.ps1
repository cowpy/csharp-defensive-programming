# ==========================================================================
# LHG skills 安装脚本：把 git 仓库内的技能以 Junction 方式链接到各 IDE 技能目录
# 事实源（唯一）：本仓库 skills\<技能名>\
# 修改技能只改仓库一处，所有链接位置即时生效；改完 git commit/push 即可同步远程。
#
# 历史教训：旧版本脚本只链接了 builtin\work\*（work 模型目录），
# 而 TRAE 主界面实际读取 .trae-cn\skills -> .agents\skills（真实目录），
# 该路径从未接到仓库，导致蒸馏的原则写进 .agents 副本后与仓库分叉（两套版本）。
# 本脚本同时链接三类位置，杜绝分叉。
# ==========================================================================

$ErrorActionPreference = 'Stop'

$repoSkills = 'C:\AI-Skills\github\csharp-defensive-programming\skills'
$skills     = @('lhg-dev-thinking', 'lhg-dev-doc', 'lhg-skill-new')
$models     = @('default', 'deidamia', 'hebe', 'iphigenia', 'metis', 'thetis')

# 三类链接落点：
#   1) .trae-cn\skills               —— TRAE 主界面技能列表读取路径
#   2) .agents\skills                —— .trae-cn\skills 旧链接的实际目标（全局技能安装目录）
#   3) .trae-cn\builtin\work\<model> —— 各 work 模型会话的技能目录
$linkRoots = @(
    'C:\Users\Administrator\.trae-cn\skills',
    'C:\Users\Administrator\.agents\skills'
)

function New-SkillJunction {
    param([string]$Path, [string]$Target, [string]$Label)

    if (Test-Path $Path) {
        $item = Get-Item $Path -Force
        if ($item.LinkType -eq 'Junction' -and ($item.Target -join ';') -eq $Target) {
            Write-Host "  [skip] $Label 已是 Junction -> $Target"
            return
        }
        # 真实目录（非链接）或指向别处的链接：先备份再替换，防止内容丢失
        $backup = "$Path.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Host "  [backup] $Label 存在实体内容，备份到 $backup"
        Rename-Item -Path $Path -NewName (Split-Path $backup -Leaf)
    }
    New-Item -ItemType Junction -Path $Path -Target $Target -Force | Out-Null
    Write-Host "  [linked] $Label -> $Target"
}

foreach ($skill in $skills) {
    $src = Join-Path $repoSkills $skill
    if (-not (Test-Path (Join-Path $src 'SKILL.md'))) {
        Write-Warning "仓库中找不到 $src\SKILL.md，跳过"
        continue
    }
    Write-Host "=== $skill ==="

    foreach ($root in $linkRoots) {
        New-SkillJunction -Path (Join-Path $root $skill) -Target $src -Label $root
    }

    foreach ($m in $models) {
        $dst = "C:\Users\Administrator\.trae-cn\builtin\work\$m\skills\$skill"
        New-SkillJunction -Path $dst -Target $src -Label "work\$m"
    }
}

Write-Host ""
Write-Host "完成。验证命令："
Write-Host "  Get-Item 'C:\Users\Administrator\.trae-cn\skills\lhg-dev-thinking' | Select-Object LinkType, Target"
