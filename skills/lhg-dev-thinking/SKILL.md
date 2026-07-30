---
name: "lhg-dev-thinking"
description: "Distills and applies LHG's development principles from conversation history. Invoke when user asks to update/apply/refine their development thinking, or when making architectural/naming/API design decisions in this project."
---

# LHG 开发思路蒸馏

本 Skill 记录从对话中沉淀下来的开发原则与决策偏好。每次调用时应先读取本文件，结合当前任务应用这些原则；若对话中产生新的原则，应更新本文件。

## 命名与领域表达

1. **命名反映通用领域，不绑定具体业务方（美宜佳应用中心/开放平台场景）**
   - 在美宜佳应用中心（开放平台）接入场景下，一个应用通常只有一个 Webhook 接收入口，因此 Controller/通用 Service 不应带 `Ats`、`Myjjr` 等具体业务系统前缀。
   - 例：`AtsWebhookController` → `WebhookController`；`AtsWebhookReceiveService` → `WebhookReceiveService`。
   - 只有真正处理某业务方专属逻辑的服务才保留业务前缀，如 `AtsWebhookService`（处理 PMPQ01/ATS 付款返盘业务）。

2. **URL/资源命名优先遵循美宜佳应用中心（开放平台）规范**
   - 开放平台网关对资源段命名、URL path 拼接方式可能有特定限制（如 `web-hooks` vs `webhooks`），即使规范本身有争议，只要平台侧有限制，就先按平台要求实现。
   - 项目内部资源段仍按 REST 习惯用连字符拼接多单词。

## Webhook / 开放平台接入架构

3. **接收层与业务层严格分离（美宜佳应用中心/开放平台 Webhook 场景）**
   - 在美宜佳应用中心（开放平台）Webhook 接入场景下，Controller + 通用 ReceiveService 只负责：接收请求、Challenge 拦截、验签、解密、落库。
   - 平台要求必须在 5 秒内返回 HTTP 200，表示"接收成功"。
   - 具体业务回写、确认、状态更新交给下游 Job 异步处理，不在接收接口里同步执行。

4. **SDK 只封装无状态协议层（美宜佳开放平台 SDK 设计）**
   - 美宜佳开放平台 SDK 里只放：模型（`WebhookPushEvent`）、请求头（`WebhookHeaders`）、验签（`WebhookSignatureVerifier`）、解密（`WebhookDecryptHelper`）、Challenge 处理。
   - SDK 不放：依赖 DB 的日志写入、配置读取、业务过滤。这些属于业务层，不应反向污染 SDK。

5. **验签必须使用原始请求体字符串（美宜佳开放平台 Webhook 验签要求）**
   - 美宜佳开放平台 Webhook Action 不要绑定强类型 model 参数，应使用 `Request.Content.ReadAsStringAsync()` 读取原始 JSON。
   - 原因：框架模型绑定会改变字段顺序、空值、缩进等，导致平台验签失败；且绑定失败时无法保留原始内容排查。

## 接口返回与错误码

6. **统一返回模型**
   - 开放平台相关接口统一返回 `OpenApiRetModel`（含 `code`/`msg`/`data`）。
   - 使用工厂方法创建：`OpenApiRetModel.Ok(...)` / `OpenApiRetModel.Fail(...)` / `OpenApiRetModel.Error(...)`。
   - 禁止裸写 `new OpenApiRetModel()` 或硬编码 `code = 16020200`。

7. **错误码用枚举管理，按业务模块 region 隔离**
   - 扩展 `ApiRetCodeEnum`，按模块分 region（如基础金融、Webhook）。
   - 新增错误码时检查是否与其他值冲突。

## 数据量与风险控制

8. **全量落库前必须评估数据量爆炸风险**
   - 当 topic 被多个系统共享（如所有系统都订阅 `PMPQ01`）时，不能无条件全量落库。
   - 应在写入日志前加过滤：根据 `srcSerialNo`、业务单据存在性、或配置规则判断是否是本系统数据。
   - 不属于本系统的数据直接返回 200，不落库。

9. **不确定的字段格式/数据量，先用真实数据验证**
   - 不要凭猜测设计过滤规则。先接入一笔真实推送，观察 `srcSerialNo` 格式、数据量级，再决定过滤策略。

## 工程实践

10. **代码改动后必须编译验证**
    - 修改后至少编译涉及项目，确认 0 错误后再继续下一步。
    - 优先用 `dotnet build` 或 VS 重新生成。

11. **破坏性/兼容性变更优先停下来评估**
    - 新增字段、方法签名、接口、存储过程、DDL 变更时，必须考虑向后兼容、脚本同步、现有调用方影响。
    - 代码与脚本同改同发，不一致直接报错。

12. **从具体项目蒸馏的原则必须标注适用场景**
    - 不要把平台特有限制（如美宜佳应用中心的 URL 规范、`web-hooks` 命名要求）当成通用最佳实践推广。
    - 也不要把通用设计原则（如 REST 资源命名）硬套到受平台限制的场景。
    - 在原则标题或正文中明确标注是"通用"还是"某平台/某环境特有"。

## Skill 自我更新规则

当用户说以下类似表达时：
- "更新我的开发思路"
- "把这个原则记到我的 skill"
- "蒸馏一下"
- "记录到 lhg-dev-thinking"

执行步骤：
1. 读取本文件（`SKILL.md`）当前内容。
2. 从当前对话中提取新的、可复用的开发原则或决策偏好。
3. 合并到对应分类下，去重、精简表述。
4. 保持条目编号连续，必要时重新归类。
5. 写回本文件。
6. 向用户简要说明更新了哪些条目。
