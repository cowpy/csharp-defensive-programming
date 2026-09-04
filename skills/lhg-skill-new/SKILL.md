---
name: "lhg-skill-new"
description: "创建/蒸馏新的 LHG 个人技能时的固定流程：技能以 git 仓库为唯一事实源，按 Junction 链接到各 IDE 技能目录。用户说「新建技能/蒸馏一个技能/做个新 skill/加个 lhg 技能/把这套流程沉淀成技能」时调用。"
---

# LHG 新技能蒸馏/创建流程（固定套路，免重复说明）

本技能是"创建 LHG 个人技能"这件事的单一事实源。以后用户说一句话（如"新建个技能 lhg-xxx 管 yyy"），按本流程走完，不需要用户再解释仓库在哪、怎么链接、怎么提交。

## 约定（写死，不问用户、不让 LLM 重新推导）vs 验证（必须由脚本自动做）

**权衡原则**：不"探测"的是**我们自己定的约定**（仓库路径、链接落点、命名）——这些不会自己变，每次重新问用户/重新推导拓扑只费 token 还容易错；但**执行结果必须验证**——链接是否真生效、有没有分叉副本，不靠记忆和假设，交给 PowerShell 脚本检查（零 LLM token，1 秒出结果）。

- **唯一事实源**：`C:\AI-Skills\github\csharp-defensive-programming\skills\<技能名>\`
- **链接落点（全部 Junction 到仓库）**：
  1. `C:\Users\Administrator\.trae-cn\skills\<技能名>`（TRAE 主界面读取）
  2. `C:\Users\Administrator\.agents\skills\<技能名>`
  3. `C:\Users\Administrator\.trae-cn\builtin\work\<model>\skills\<技能名>`——**work 模型目录由脚本自动枚举**，TRAE 新增模型目录无需改脚本、无需手工维护名单。
- **命名一致性**：目录名 = SKILL.md frontmatter `name` = metadata.json `name`，全部用 `lhg-` 前缀 + kebab-case。
- **技能目录构成**：`SKILL.md`（必需）+ `metadata.json`（必需）+ 资源目录（按需，如 `templates/`）。
- **安装/验证脚本**：`skills\_install_to_work.ps1`，新技能必须加进 `$skills` 数组，否则换机/重装会漏链。
- **运行环境**：脚本含中文注释，必须用 PowerShell 7（Windows PowerShell 5.1 按 GBK 解析会报语法错误）。

## 漂移检查（应对 TRAE 升级/目录变化）

```powershell
# 只验证不改动：逐位置报告 [OK] / [FORK]实体副本分叉 / [MISS]未链接 / [BAD]指向错误
pwsh -ExecutionPolicy Bypass -File skills\_install_to_work.ps1 -VerifyOnly
```

- 安装命令跑完会**自动追加一次验证**，无需单独跑。
- 主动跑漂移检查的时机：① 新建/更新技能后；② TRAE 升级后（可能新增 work 模型目录或重置技能目录）；③ 怀疑技能没生效/内容是旧版时。
- 报告 `[FORK]` = 该位置是实体目录、内容独立于仓库（分叉事故，正是 lhg-dev-thinking 当年两套版本的根因）；不带参数重跑安装命令即可自动备份并修复。

## 执行步骤（照做）

1. **一次问清**：技能名（不确定就给 2-3 个候选，风格参考 `lhg-dev-thinking`/`lhg-dev-doc`）+ 一句话职责 + 触发场景。其余信息不要再追问。
2. **建 `SKILL.md`**：
   - frontmatter 只有 `name` + `description`；description 写清"做什么 + 何时触发"。
   - 正文结构参考已有技能：开头一句话定位 → 分节规则/模式（每条标注"通用/某场景特有"）→ 末尾附"触发词 / 自我更新规则"。
   - SKILL.md 写法可参考 `skill-creator` 技能的通用建议，但**仓库布局与链接流程以本技能为准**，不按它的安装方式走。
3. **建 `metadata.json`**：复制 `skills\lhg-dev-doc\metadata.json` 改 `name`/`description`/`keywords`/`categories`/`skill.triggers`/`skill.path`；`author.name` 固定 `LHG`，`license` 固定 `MIT`。
4. **登记安装脚本**：把技能名追加到 `skills\_install_to_work.ps1` 的 `$skills` 数组。
5. **跑安装脚本**（pwsh 7）：脚本对已存在的实体目录自动备份为 `*.backup-<时间戳>` 后替换，不丢内容；work 模型目录自动枚举。
6. **验证（脚本自动做，不靠肉眼假设）**：安装脚本结尾自动跑 `-VerifyOnly` 漂移检查，逐位置输出 `[OK]/[FORK]/[MISS]/[BAD]`；必须全部 `[OK]` 且退出码 0 才算完成，有异常不带参数重跑修复，再不行停下来报告用户。
7. **更新 README.md**：技能清单加一条（编号顺延，中英各一句简介）+ Repository Structure 树补目录行。
8. **git 提交**：仓库目录内 `git branch --show-current` + `git status` 确认 → add 新目录/`_install_to_work.ps1`/README.md → 一个 conventional commit（如 `feat: add lhg-xxx skill ...`）→ `git push` → `git log --oneline -3` 验证落在正确分支。push 失败（网络）要显眼提醒，不 silently 积压。
9. **汇报**：技能名、触发词、链接验证结果、commit hash，四样即可，不啰嗦。

## 蒸馏对话为技能的取舍

- 只沉淀**跨项目可复用**的方法/规则/套路；某平台/某系统特有内容留在该项目的 `project_rules.md`（见 lhg-dev-doc 技能）。
- 保留"教训案例"（事故根因比抽象规则更能防复发）；规则编号连续，重复条目去重合并。
- 规则要可执行（带命令、清单、阈值），不写空话。

## 铁律

- 永远只在 git 仓库里改技能内容；发现任何 IDE 技能目录里存在独立实体副本（漂移检查报 `[FORK]`）= 分叉事故，以仓库为准、跑安装脚本重建 Junction。
- **验证交给脚本，不交给记忆**：约定可以写死不探测，但"链接是否生效"必须看 `-VerifyOnly` 输出；不跑验证就宣称完成 = 没做完。
- 新技能不进 `$skills` 数组 = 没做完。
- 改完即 commit + push；本地链接即时生效，push 只影响远程备份。
