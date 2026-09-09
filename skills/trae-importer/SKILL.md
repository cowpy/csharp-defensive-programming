---
name: trae-importer
description: 将 Trae（TraeCode / TraeWork）本机已下载的全局技能（skills）与全局规则（user_rules）一键迁移到 WorkBuddy。当用户想把 Trae 安装目录/工作目录里的 skills、全局规则导入 WorkBuddy 时使用。会先做安全审计（扫描 rm -rf、curl|sh、IEX、reverse shell 等危险模式），仅安装审计通过的技能，并把规则转换为带触发条件的技能。
disable: false
---

# Trae → WorkBuddy 迁移器

> 📦 **事实源（git）**：`C:\AI-Skills\github\csharp-defensive-programming\skills\trae-importer`
> ⚠️ 本技能是 **WorkBuddy 专用**，不在 `_install_to_work.ps1` 的 `$skills` 链接数组内
> （该脚本落点是 Trae 各目录，链过去无意义）。进仓库只为版本管理、防丢失。
> **改动后需手动同步回** `~/.workbuddy/skills/trae-importer/`。

把 Trae（国内版 TraeWork / 国际版 TraeCode）本机已存在的 skills 与全局规则迁移到 WorkBuddy 的用户技能目录 `~/.workbuddy/skills/`。

## 何时使用
- 用户说"把 Trae 的技能/规则导入 WorkBuddy""迁移 Trae skills""traecode/trae work 的规则装过来"等。
- 用户在 Trae 里攒了一批 skills 或 user_rules，想在 WorkBuddy 复用。

## 源位置（本机自动探测）
- TraeCode 全局技能：`~/.trae/skills/`（内含指向 `~/.agents/skills/` 真实内容的软链接）
- TraeWork 全局技能：`~/.trae-cn/skills/`
- 真实技能内容：`~/.agents/skills/`（55+ 个）
- 全局规则：`~/.trae-cn/user_rules/*.md`、`~/.trae/user_rules/*.md`
- 内置人格技能（可选）：`~/.trae-cn/builtin/trae`、`~/.trae-cn/builtin/work`

## 用法
技能自带 Python 脚本 `trae_to_workbuddy.py`，两步执行：

1. **先审计（不写入）**：
   ```
   python trae_to_workbuddy.py --dry-run
   ```
2. **确认无误后导入**：
   ```
   python trae_to_workbuddy.py --apply
   ```
3. （可选）连 Trae 内置人格技能一起导入：在上方命令后加 `--include-builtin`

## 关键行为
- **解析软链接**：`.trae/skills` 里大量软链接指向 `~/.agents/skills`，脚本用 `os.path.realpath` 复制真实内容，避免装一堆断链。
- **安全审计**：扫描每个技能目录中的危险模式（rm -rf 绝对路径、curl|sh、wget|sh、powershell -enc、IEX、base64 -d|sh、reverse shell、os.system、subprocess shell=True、eval/exec 等）。命中即标记为"需人工复核"、**不自动安装**，除非在 `REVIEWED_SAFE` 白名单中（已人工复核的误报：dotnet-devcert-trust、redis-development、security-best-practices）。
- **frontmatter 规范化**：移除 WorkBuddy 不识别的 `invocable` 字段，确保有 `disable: false`。
- **规则→技能**：每条 Trae 全局规则（首行 `标签1|标签2|...` + 要点）转为一个技能，标签写进 `description` 作为触发条件，技能名用规则文件唯一时间戳避免中文标签碰撞丢规则。
- **去重**：同名技能只装一份（第二份自动跳过）；不会覆盖 WorkBuddy 已有技能。

## BOM：技能静默失效的头号原因

Trae 导出的 `SKILL.md` 常带 **UTF-8 BOM**（Windows 环境产物，实测 `lhg-dev-thinking` 就带）。

**为什么致命**：WorkBuddy 读取技能用 `fs.readFile(p, 'utf-8')` + 正则 `/^---\r?\n([\s\S]*?)\r?\n---/`
解析 frontmatter。Node 的 `utf-8` **不剥离 BOM**，而正则以 `^` 锚定且无 `m` 标志 → 文件首字节是 BOM 时
匹配必然失败 → frontmatter 退化为空 → 技能降级为「用目录名当 description」→ **永远不会被自动触发**，
而且**不报错、不告警**，纯静默失效，表现为技能列表里显示成 `名称: 名称`。

**迁移脚本已自动处理**：`install_skill` 在复制后调用 `strip_bom_tree()` 递归剥离整个技能目录内
`.md/.markdown/.yml/.yaml/.json/.txt` 的 BOM，读取处统一用 `utf-8-sig`。正常迁移无需手工干预。

**但手工编辑后仍需体检**（记事本 / 部分 Windows 编辑器保存会重新加 BOM）：

```
python check_skill_health.py            # 检查 ~/.workbuddy/skills
python check_skill_health.py --fix      # 自动去 BOM（会先备份 .bak）
```

检查项：
1. **BOM**：前 3 字节 == `239,187,191` → 剥离（`.cshtml/.aspx/.config` 等 .NET 文件才**需要** BOM，`SKILL.md` 绝不能带）
2. **frontmatter 可解析**：能正确提取 `name` 与 `description`
3. **description 过短**（< 30 字符）→ 预警，描述太短会漏触发

## lhg 个人技能：源已迁到 git 仓库，且 WorkBuddy 不在链接落点内

**2026-09-04 起的变化**：LHG 的三个个人技能改用 git 仓库作唯一事实源。

- 仓库：`C:\AI-Skills\github\csharp-defensive-programming\skills\`
- 技能：`lhg-dev-thinking`（42KB）、`lhg-dev-doc`（含 `templates/docs/` 骨架）、`lhg-skill-new`
- 安装脚本：仓库内 `skills\_install_to_work.ps1`，`$skills` 数组 + `$mainRoots` 落点
  （`.trae-cn\skills`、`.agents\skills`、`.trae-cn\builtin\work\<model>\skills`）

**关键：落点不含 `~/.workbuddy/skills`** → 仓库更新后 WorkBuddy **不会**自动同步，必须手工搬。
同步时用 `install_skill` 复制（会自动剥 BOM + 规范化 frontmatter），**不要**直接 copytree。

**历史坑（2026-09-08 实测）**：`.agents\skills\lhg-dev-thinking` 曾是与仓库分叉的**实体旧目录**，
从它复制会装到落后三倍的版本（12KB vs 42KB）。**同步前先核对源与已装的字节数**，
差异过大说明装的是分叉副本。

## 检查 lhg 技能是否有更新（用户说"帮我同步/更新"时先跑这个）

```bash
BASE="/c/AI-Skills/github/csharp-defensive-programming/skills"
DST="/c/Users/Administrator/.workbuddy/skills"
for s in lhg-dev-thinking lhg-dev-doc lhg-skill-new; do
  echo "--- $s ---"
  diff -rq "$BASE/$s" "$DST/$s" 2>&1 | head -20          # 列出差异文件
  wc -c "$BASE/$s/SKILL.md" "$DST/$s/SKILL.md" 2>/dev/null  # 字节数对比
done
```

判读：
- 只看文件字节数差异**不够**，必须 `diff` —— 换行符差异（源 LF / 已装 CRLF）会造成大面积假差异。
- 确认是真实内容变更后，用 `trae_to_workbuddy.py` 的 `install_skill()` 安装（自动剥 BOM + 规范化 frontmatter）。
- **先备份 = 先移走（mv 而非 cp）**：`install_skill` 对已存在的目标目录直接返回 `skipped_exists`、**不覆盖**，所以必须把旧目录 `mv` 到 `~/.workbuddy/` **以外**（如工作区 `.workbuddy/tmp/<skill>.old-<日期>/`）再安装；用 `cp` 留底会导致安装被跳过。备份留在 skills 扫描目录内会被当技能加载。
- 装完跑 `check_skill_health.py` 复检。

## Junction 链接到 WorkBuddy：有失效风险，不要贸然用

想把仓库技能用 Junction 链到 WorkBuddy 以图"改仓库即时生效"——**风险未排除**。

Node 22 实测（Windows Junction）：

| 判定方式 | Junction 的 `isDirectory()` |
|---|---|
| `readdirSync(dir, {withFileTypes:true})` 的 Dirent | **false**（`isSymbolicLink() = true`） |
| `statSync(p)`（跟随链接） | true |
| `lstatSync(p)`（不跟随） | false |

WorkBuddy 的 `app.asar` 里 144 处 `withFileTypes` 枚举**全部**用 `entry.isDirectory()` 过滤，
未见任何 `|| isSymbolicLink()` 兼容写法 → 若技能扫描也用该模式，**Junction 会被整个漏掉**，
表现是技能在 WorkBuddy 里凭空消失。

**要用必须先验证**：在 `~/.workbuddy/skills/` 建一个测试 Junction，**重启 WorkBuddy** 后看技能
列表是否出现它。确认能识别再推广；确认不了就保持实体副本 + 按需同步。

## 注意事项
- 仅迁移"全局"技能与规则。Trae 的**项目规则**（项目内 `.trae/rules/*.mdc`）分散在各项目目录，需按需单独处理。
- 迁移后建议在 WorkBuddy 里实际试调几个技能，确认其引用的工具/命令在 WorkBuddy 环境可用（部分 Trae 专属命令可能需适配）。
- 报告写入执行目录的 `trae_import_report.json`。
- **技能触发依赖 description**：WorkBuddy 把所有技能的 name+description 常驻上下文，由模型读描述做语义匹配后才加载正文。所以 description 写得不准 = 技能形同虚设；正文不常驻，装 60 个技能也只有约 2.5% 的常驻开销。
