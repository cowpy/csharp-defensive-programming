# 技能目录拓扑：base / .agents / 各 IDE

> 实测日期：2026-09-09　机器：Administrator@Windows（PowerShell 7.6 / .NET 10）
> 本文回答一个问题：**技能到底存在哪？改哪个文件才全局生效？**

## 1. 三个角色

| 角色 | 路径 | 是什么 |
|---|---|---|
| **base（事实源）** | `C:\AI-Skills\github\csharp-defensive-programming\skills\<技能>\` | git 仓库里的**唯一真身**。所有技能内容只在这里改，改完 commit/push |
| **`.agents`（共享实体池）** | `C:\Users\Administrator\.agents\skills\` | 多 IDE 共用的技能实体/链接层。Trae 系列、Qoder、Continue、CodeBuddy 都从它取技能 |
| **各 IDE 目录** | `~/.codebuddy/skills`、`~/.trae/skills`、`~/.trae-cn/skills`、`~/.qoder/skills`、`~/.continue/skills`、`~/.workbuddy/skills` | 各家自己的"技能清单"，里面放的全是**链接**（WorkBuddy 例外：全实体拷贝） |

一句话：**base 是真身，`.agents` 是中转/共享池，各 IDE 目录只是清单。**

## 2. 各目录实测构成（2026-09-09）

| 目录 | 条目 | 实体目录 | Junction | 其中指向 `.agents` | 其中指向 base |
|---|---|---|---|---|---|
| `.agents\skills` | 57 | 52 | 5 | — | 5 |
| `.codebuddy\skills` | 55 | 0 | 55 | 50 | 5 |
| `.trae\skills` | 61 | 8 | 53 | 51 | 2 |
| `.trae-cn\skills` | 80 | 25 | 55 | 50 | 5 |
| `.qoder\skills` | 53 | 0 | 53 | 51 | 2 |
| `.continue\skills` | 53 | 0 | 53 | 51 | 2 |
| `.workbuddy\skills` | 70 | 70 | 0 | — | 0（全拷贝，不支持 Junction） |

注：`.trae-cn` 多出的 25 个实体是 Trae 自建技能（`karpathy-guidelines`、`frontend-design` 等），与 base 无关。

## 3. 拓扑图

```
        base（git 事实源，唯一真身）
        C:\AI-Skills\github\csharp-defensive-programming\skills\<技能>
             ▲                                   ▲
             │ 一跳 Junction（正确姿势）          │ 一跳 Junction
             │                                   │
   ┌─────────┼──────────┬──────────┬─────────┐   │
 .agents   .trae    .trae-cn    .qoder   .continue
 (共享池)                                        │
   ▲                                             │
   └── 50 个老技能仍是「实体副本」── CodeBuddy 通过 .codebuddy 一跳读到它
                                                 │
        .codebuddy\skills ────────────────────────┘（5 个已改为直达 base）

   .workbuddy\skills = 纯拷贝，不在这条链上（WorkBuddy 不识别 Junction）
```

## 4. 五条铁律（踩过坑才写的）

1. **一跳可用，两跳不可见。**
   CodeBuddy 实测：`.codebuddy\<技能>` → `.agents\<技能>`(又是 Junction) → base 这种两跳链，技能**在列表里直接消失**（`lhg-dev-thinking` 之前就是这个状态）。所以任何 IDE 目录都必须**一跳直达 base**。
2. **只改 base，绝不在副本上改。** 实体副本 = 分叉隐患（历史上 `.agents\skills\lhg-dev-thinking` 就是落后三倍的旧副本）。
3. **删旧链接只删 reparse point**：`[IO.Directory]::Delete($path, $false)`，绝不能用 `Remove-Item -Recurse`（会连真身一起删）。
4. **备份必须移出技能扫描目录**：留在 `skills\` 内的 `*.backup-*` 会被 IDE 当成同名技能索引，出现"幽灵重复技能"。统一备份区：`C:\AI-Skills\_backups\`。
5. **健康检查必须走真实路径**：本机 .NET 10 拒绝遍历 Junction（`无法遍历该路径，因为它包含不受信任的装入点`），穿链接读会被误报成"技能不存在"。另外 `SKILL.md` 不能带 BOM（带 BOM → frontmatter 解析失败 → 技能静默失效）。

## 5. 各家 IDE 的技能来源（容易误解的点）

- **CodeBuddy 至少有三个来源**（实测）：
  1. `~/.codebuddy/skills`（用户技能，全 Junction）
  2. `~/.agents/skills` 本身 —— 证据：`csharp-async` 只存在于 `.agents`，却出现在 CodeBuddy 技能列表里
  3. 插件市场 `~/.codebuddy/plugins/marketplaces/*/plugins/*/skills/`（如 `find-skills`、`pdf`）
- **Trae / Qoder / Continue**：`~/.trae|trae-cn|qoder|continue/skills` 里的链接 → `.agents\skills`（或直接 → base）。
- **WorkBuddy**：只认实体目录，靠 `trae_to_workbuddy.py` 复制同步。

## 6. 当前落点状态（2026-09-09 改完后）

| 技能 | base | `.agents` | `.codebuddy` | `.trae` | `.trae-cn` | work 模型目录×10 | `.qoder` | `.continue` | `.workbuddy` |
|---|---|---|---|---|---|---|---|---|---|
| lhg-dev-thinking | 真身 | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | — | — | 拷贝 |
| lhg-dev-doc | 真身 | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | — | — | 拷贝 |
| lhg-skill-new | 真身 | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | — | — | 拷贝 |
| code-complexity-governor | 真身 | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 拷贝(旧) |
| csharp-defensive-programming | 真身 | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 1跳→base | 拷贝(旧) |
| trae-importer | 真身 | — | —（WorkBuddy 专用，不链） | — | — | — | — | — | 拷贝 |

（`.qoder` / `.continue` 未链 lhg 三个：它们不是 TRAE 家族，不在 `_install_to_work.ps1` 落点内；需要时手工建一跳链接。）

## 7. 脚本职责划分

| 脚本 | 落点 | 说明 |
|---|---|---|
| `skills\_install_to_work.ps1` | `.trae-cn\skills`、`.trae\skills`、`.agents\skills`、`.trae-cn\builtin\work\<model>\skills`（自动枚举 10 个模型） | **Trae 侧**。`$skills` 含 5 个（lhg 三个 + code-complexity-governor + csharp-defensive-programming）；含两跳链扫描 |
| `skills\_install_to_codebuddy.ps1` | `~/.codebuddy\skills` | **CodeBuddy 专属**（新建）。默认链 5 个，`-IncludeAll` 才链 trae-importer，`-VerifyOnly` 只查不改 |

CodeBuddy 脚本用法：
```powershell
pwsh -ExecutionPolicy Bypass -File skills\_install_to_codebuddy.ps1              # 安装/修复
pwsh -ExecutionPolicy Bypass -File skills\_install_to_codebuddy.ps1 -VerifyOnly  # 漂移检查
```
两个脚本互不依赖，各自只管自己的落点；`_install_to_work.ps1` 不会因为 CodeBuddy 脚本而变化。

## 8. 2026-09-09 变更记录

1. 新建 `_install_to_codebuddy.ps1`，把 5 个技能以**一跳 Junction** 链到 `~/.codebuddy\skills`（原先 `lhg-dev-thinking` 是失效的两跳链，`lhg-dev-doc`/`lhg-skill-new` 根本没链）。
2. 把 `.agents\skills` 里的两个实体副本改为 Junction → base：
   - `code-complexity-governor`（改前与 base **字节完全相同**）
   - `csharp-defensive-programming`（改前与 base 内容一致，仅 CRLF/LF 换行差异，21691 vs 21231 字节）
   - 旧实体已移到 `C:\AI-Skills\_backups\agents\<技能>.backup-20260909-094518\`
3. **连带修正**：`.trae` / `.trae-cn` / `.qoder` / `.continue` 里指向 `.agents\skills` 这两个技能的链接，一并由「.agents 中转」改为**一跳直达 base**。原因：`.agents` 那层一旦变成 Junction，下游就退化成两跳 → 这些 IDE 里技能会消失（CodeBuddy 已经踩过）。
4. 实测验证：`use_skill lhg-dev-doc` 通过 `~/.codebuddy\skills\lhg-dev-doc` 成功加载（内容来自 base）。
5. 更新 `_install_to_work.ps1`：
   - `$skills` 纳入 `code-complexity-governor`、`csharp-defensive-programming`；
   - `$mainRoots` 增加 `.trae\skills`（Trae 国际版）——此前该目录里 `lhg-dev-thinking` 是 `.agents` 中转的两跳链、`lhg-dev-doc`/`lhg-skill-new` 完全缺失；
   - 新增**两跳链扫描**（与 CodeBuddy 脚本同款）；
   - 头部补充"一跳直达"铁律与兄弟脚本说明。
   - 执行后补齐：`.trae\skills` 三个 lhg 技能改/建为一跳→base，10 个 work 模型目录新增这两个技能的链接。两个脚本 `-VerifyOnly` 均 exit 0。

## 9. 遗留项 / 风险

- `.workbuddy\skills` 仍是这两个技能的**旧实体拷贝**，且 WorkBuddy 不支持 Junction → 需要时用 `trae_to_workbuddy.py` 重新复制同步（不要直接 copytree，要剥 BOM）。
- `.trae-cn\builtin\work\<model>\skills` 的 10 个模型目录已由脚本自动覆盖；将来 Trae 新增模型目录无需改脚本（自动枚举）。
- `trae-importer` 未链入 CodeBuddy（WorkBuddy 专用），需要的话用 `-IncludeAll`。
- 新链/改链后，CodeBuddy 的**技能列表**可能要重启窗口才刷新（`use_skill` 实测是即时生效的）。
