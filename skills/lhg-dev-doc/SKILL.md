---
name: "lhg-dev-doc"
description: "代码-文档双向同步体系（薄宪法 project_rules.md + docs/ 骨架）的初始化与执行。新项目初始化文档体系、任务开始按加载链取文档、提交前检查文档同步、任务收尾输出文档清单时调用。与 lhg-dev-thinking 互补：thinking 管怎么想，本技能管怎么记。"
---

# LHG 文档宪法（代码-文档双向同步体系）

本技能是「文档跟随代码同步更新」工作法的**单一事实源**：通用规则、目录骨架、模板文件都在本技能内；各项目仓库内的 `project_rules.md` 是**薄实例**，只放项目特有的技术约束与指针，方法论不在项目内复制。

与 `lhg-dev-thinking` 的分工：thinking 管编码原则与架构决策（怎么想）；本技能管文档骨架、同步铁律、变更方案与任务收尾（怎么记）。两者可同时调用。

## 三种工作模式

### 模式一：init（新项目落地文档体系）

触发：用户说「初始化文档体系 / 建 project_rules / 接入文档宪法」，或在没有 `project_rules.md` 的仓库首次开展较复杂任务时主动建议。

步骤：
1. 探测仓库根是否已有 `project_rules.md`：
   - 已有 → 不覆盖，提示用户走「模式二 apply」；如用户要求升级，先备份旧文件再生成并逐条 diff 给用户确认。
2. 探测项目技术栈（用于填充宪法 §5 技术约束段），不确定的列出来问用户，禁止编造：
   - .NET Framework（Web.config + 旧式 csproj）还是 SDK 风格 .NET Core/5+？对应 C# 语言版本约束。
   - 是否有 SQL 存储过程 / 发版脚本 / 升级脚本目录？基线源与执行脚本是否双轨？
   - 是否有 Webhook/开放平台对接、定时 Job、导入导出等高频场景？
   - 前端形态（MVC cshtml / SPA / 小程序）与编码约束（BOM/CRLF 等）。
3. 复制模板（本技能 `templates/` 目录）到目标仓库：
   - `templates/project_rules.tpl.md` → 仓库根 `project_rules.md`，替换 `{{PROJECT_NAME}}`，按探测结果填充 §5，项目无关的占位条目删除而不是留空。
   - `templates/docs/00-README.tpl.md` → `docs/00-README.md`
   - `templates/docs/10-glossary.tpl.md` → `docs/10-glossary.md`
   - `templates/docs/11-directory-map.tpl.md` → `docs/11-directory-map.md`（**必须**按仓库真实目录结构填写首批映射行，禁止留模板示例行）
   - `templates/docs/30-requirements/README.md` → `docs/30-requirements/README.md`
   - `templates/docs/40-analysis/README.md` → `docs/40-analysis/README.md`
   - `templates/docs/50-summaries/README.md` → `docs/50-summaries/README.md`
   - `templates/docs/60-flows/README.md` → `docs/60-flows/README.md`
   - `templates/docs/70-modules/README.md` → `docs/70-modules/README.md`
   - `templates/docs/70-modules/module.tpl.md` → `docs/70-modules/_template.md`（新建模块文档时复制为 `<模块名>.md`）
   - `templates/docs/80-changes/_template.md` → `docs/80-changes/_template.md`
   - `templates/docs/90-archive/README.md` → `docs/90-archive/README.md`
   - `templates/docs/99-personal/README.md` → `docs/99-personal/README.md`
4. 向用户输出：创建的文件清单、§5 预填了哪些约束、哪些探测项不确定需人工补。
5. 提醒：在仓库 `AGENTS.md` / `.trae` 规则 / CLAUDE.md 中加一行指针「每次任务先读 project_rules.md」，保证 AI 会话能发现宪法（可用 skills-index-snippets 技能）。

### 模式二：apply（任务执行中遵守宪法）

触发：任务开始且仓库根存在 `project_rules.md`（用户说「按项目规则来」或开始编码任务时）。

步骤：
1. 读仓库根 `project_rules.md`（薄宪法）。
2. 按宪法 §1 加载链取文档：读 `docs/11-directory-map.md` 命中任务涉及模块 → **只读**对应 `docs/70-modules/*.md`；术语歧义才读 `docs/10-glossary.md`；`docs/90-archive/` 不主动加载。**禁止一次性加载 docs/ 全部文件。**
3. 按宪法 §3 改动分级判断：
   - 改 SP/表结构/升级脚本、新接口/改接口签名/改状态机、跨模块改动 → **先**在 `docs/80-changes/<yyyyMMdd>-<主题>.md` 写方案（模板 `docs/80-changes/_template.md`），给用户确认后再写代码。
   - 单模块 bug 修复/文案/小调整 → 不需要方案，改代码时顺手更新 module 文档。
   - 纯实验 Spike → 不进 docs，玩完删。
4. 编码过程中执行 §2 同步铁律：
   - 改了代码逻辑、接口签名、目录结构、状态机、SP/表结构 → 同一次提交内同步更新对应 module 文档与 11-directory-map.md（新增模块/目录时加映射行）。
   - 模块文档懒生成：命中的模块没有文档，第一次改动时补建（结构见 `docs/70-modules/README.md`），并在地图加行。
   - module 文档只写代码读不出来的东西：职责边界、跨模块契约、状态机、决策原因、已知坑。禁止抄字段清单/方法签名。
   - 发现过时文档当场修正或删除，禁止只增不减。
5. 行数预算（宪法 §4）：宪法 ≤120 行、glossary ≤100 行、单个 module ≤200 行；module 超限按代码子目录拆，拆分边界 = 代码目录边界 = 业务域边界。
6. 任务收尾按宪法 §7 输出四项清单：① 改动的代码文件 ② 更新/新建的文档文件 ③ 归档的 change 文件 ④ 提醒人工复核文档-代码一致性。
7. 变更完成后：change 方案的 delta 要点合并进对应 module 文档 → change 文件移入 `docs/90-archive/` → 代码与文档同一 commit。

### 模式三：check（提交前同步检查）

触发：用户说「提交前检查 / 文档同步检查」，或执行 git commit 前。

逐项核对，有违规先修再提交：
1. 本次 diff 是否含 SP/表结构/升级脚本/接口签名/状态机/目录结构变更？有 → 是否存在对应 `docs/80-changes/` 方案（或已归档）？涉及的 `docs/70-modules/*.md` 是否同 commit 更新？
2. 新增代码目录/新模块 → `docs/11-directory-map.md` 是否加了映射行？
3. 新建 module 文档是否登记进地图、命名是否与地图「模块文档」列一致？
4. module 文档是否抄了字段清单/方法签名（应删除，代码里有）？
5. 文档行数是否超预算（宪法 120 / glossary 100 / module 200）？
6. 已完成的 change 文件是否还躺在 `docs/80-changes/`（应归档到 90-archive）？
7. 代码与文档是否在同一 commit（禁止代码先提交、文档后补）？

输出格式：逐条 ✅/⚠️，⚠️ 项给出具体文件与修复动作；不通过不得提交。

## 通用规则（所有模式共同遵守）

- **方法论只在本技能内迭代**：项目内 `project_rules.md` 只放项目实例（技术约束、模块指针、项目特有血泪教训）。发现通用规则需要调整 → 改本技能，不改各项目副本；项目特有规则 → 写进项目宪法 §5。
- **本技能的事实源在 git 仓库**：`C:\AI-Skills\github\csharp-defensive-programming\skills\lhg-dev-doc`。各 IDE 技能目录（`.trae-cn\skills`、`.agents\skills`、`builtin\work\*`）通过 Junction 链接到仓库，改仓库一处即全局生效；发现未链接的独立副本时，以仓库为准并重建 Junction，禁止在副本上直接改。
- **项目特有内容不得蒸馏进本技能**：某平台/某系统的限制（如特定 Webhook 平台 URL 规范、某库 SQL 双轨目录）留在项目宪法，通用化前先确认是否真的跨项目成立。
- **破坏性变更先叫停**：DDL/接口签名/存储过程变更遵循向后兼容优先，新参数可选带默认值；脚本与代码同改同发；必须破坏兼容时停下来让用户确认升级脚本。
- **大批量产物必须配 AI 索引**：数据库 SP/表、API 清单、枚举字典等数量一多的产物，必须同时产出一份轻量索引（名称 + 一句话职责 + 文件指针），AI 先读索引再按需取详情，禁止让 AI 全量扫描；索引必须与产物**同源生成**（同一工具/同一流程自动产出），禁止手写索引——手写索引必然漂移，等于制造第二种双写。
- **禁止行为**：禁止一次性加载 docs/ 全部文档；禁止改代码跳过文档同步；禁止编造不存在的需求/接口/目录；禁止擅自推翻 module 文档「决策与坑」段的既有方案（需用户明确同意）；禁止大段一次性重构（按模块拆分，一个模块完成并同步文档后再下一个）。
- 文档语言与用户交流语言一致；文件内引用路径用仓库相对路径。