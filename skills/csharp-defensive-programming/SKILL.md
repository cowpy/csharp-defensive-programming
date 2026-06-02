---
name: csharp-defensive-programming
description: "适用于审计、设计或实现 C#/.NET 代码，用于错误处理、输入验证、断言、异常策略、防御性兼容性（DDL/方法签名），或决定使用异常 vs Result vs Try 模式。触发条件：空的 catch 块、缺少 ArgumentNullException.ThrowIfNull、公共方法没有验证、EF Core 实体没有并发令牌、DDL 变更没有迁移脚本、记录后忽略模式、仅生产环境的失败路径。补充 dotnet-best-practices（样式/API）和 csharp-async（并发），增加\"如何安全失败\"层。"
priority: high
license: MIT
---

# C# 防御性编程方法论

《代码大全》（McConnell 第 8 章）防御模型的 C#/.NET 改编，结合 go-defensive 的 API 边界检查，融入用户的**防御性兼容** DDL 契约和 Karpathy 风格的行为规则。

> **核心原则**：防御性编程偏向于**正确性胜于速度**，适用于生产系统。对于原型/快速开发（最多 1 周），请自行判断。

---

## 🚨 防御性兼容 · Defensive Compatibility · 最高优先级 · 强制

**触发场景**：新增/修改字段、方法签名、接口、存储过程或任何 DDL 变更。

**强约束**：
1. **向后兼容**：新字段、新参数一律可选 + 默认值；禁止破坏现有调用方。
2. **脚本同发**：改存储过程 / 视图 / 表结构时，必须在同一任务中**同步检查并提示** DDL / 升级脚本；代码与脚本同改同发。
3. **破坏性变更先叫停**：若必须破坏兼容（删字段、改签名类型、改返回结构），**立刻停止**，先提示用户保存升级脚本并确认，再继续。
4. **静默加字段 = 事故**：任何 DB 字段新增都必须审计调用方与迁移脚本；不一致直接报错，不允许"代码加了，脚本没更"。

**提交前自检三问（必答）**：
- 现有调用方 / 老版本 DB 是否仍能正常工作？
- 升级脚本是否已同步？
- 是否需要提示用户备份变更脚本？

> **来源**：源自真实生产事故教训，**这是最高优先级规则**，覆盖便利性。

---

## ⛔ 停止 — 永远不要跳过（5 项不变式）

| # | 检查项 | 为什么关键 |
|---|-------|-----------|
| 1 | **没有空的 catch 块** | 被吞掉的异常会演变成无法诊断的生产故障 |
| 2 | **公共方法入口必须验证所有参数** | 信任边界外的输入永远不可信，防止 NullReferenceException 等低级错误 |
| 3 | **不要在 Debug.Assert 中包含有副作用的代码** | Release 构建中 Assert 会消失 → 导致逻辑错误（不是死代码，是逻辑不执行） |
| 4 | **外部输入在信任边界验证** | "内部团队 API" 仍然是外部的 — 任何跨进程/网络/文件边界的内容都是敌对的 |
| 5 | **EF 实体变更必须考虑并发控制** | 没有并发令牌会导致静默的丢失更新 |

> **安全例外**：身份验证/授权/加密/个人身份信息（PII）代码**绝不**豁免上述规则，无论其他因素如何。有疑问时，验证。

---

## 🚨 危机处理（2 分钟，生产环境已宕机）

### 立即执行（每项 30 秒）
1. **公共方法缺少 `ArgumentNullException.ThrowIfNull` / 入口范围检查？** 现在立即添加。
2. **空的 catch 隐藏了根本原因？** 添加结构化日志（ILogger），然后追溯到源头。
3. **DDL/SP 与代码不同步？** 立即回滚或同步脚本。

### 部署修复前（60 秒）
4. **修复是否与仓库现有错误策略一致**（异常 vs `Result<T>` vs `Try*` 模式）？先搜索一下。
5. **异常是否在正确的抽象层抛出？** 不要让 `SqlException` 从 `GetEmployee()` 泄漏出来 — 包装为 `EmployeeNotFoundException`（或你的域类型）。

> **为什么这样有效**：这 5 项能捕获约 80% 的 C# 防御性 bug。完整检查清单用于非紧急审查。
>
> **空 catch 会让问题恶化**：一层中被抑制的错误会蔓延开来 — 你凌晨 2 点调试自己时会恨死过去的自己。

---

## 关键定义

### 外部输入（视为敌对）
**任何不能证明由当前代码路径控制的数据**：
- HTTP 请求体 / 查询 / 头部 / 路由值
- 文件（配置、上传、数据文件）
- 网络（下游 API、消息队列、gRPC）
- 环境变量、`IConfiguration` 值
- 数据库结果（即使来自你自己的 DB — 模式漂移、手动修复）
- 来自**任何**其他服务的数据，包括内部服务

**经验法则**：如果它跨进程、网络或信任边界 — 验证它。

### C# 中的断言（Debug.Assert）
在运行时检查自身的代码。**仅用于永远不应发生的条件**（程序员 bug、违反不变式）。**在 Release 中禁用** — 你放在里面的任何代码都必须可以安全消失。

**关键点**：
- Assert 是**开发辅助工具**，不是生产验证手段
- **绝对不要在 Assert 里写有副作用的代码**（如 `ProcessPayment(order)` 或修改状态的函数）
- 正确用法：纯条件检查，如 `Debug.Assert(order.Lines.Count > 0, "订单必须至少有一行")`

```csharp
// ✅ 正确：纯检查，无副作用
Debug.Assert(order.Lines.Count > 0, "Order must have at least one line");

// ❌ 错误：有副作用的代码在 Release 中不会执行！
Debug.Assert(ProcessPayment(order), "Payment must succeed");
```

### 防波堤（Barricade）
一个损伤遏制边界。类/模块的公共表面验证所有进入的内容；在防波堤内部，代码可以信任数据，并对内部不变式使用更便宜的断言。

```csharp
public sealed class OrderService(IOrderRepository repo, ILogger<OrderService> log)
{
    public async Task<Order> PlaceAsync(PlaceOrderRequest request, CancellationToken ct)
    {
        // 防波堤：验证外部输入
        ArgumentNullException.ThrowIfNull(request);
        ArgumentException.ThrowIfNullOrWhiteSpace(request.CustomerId);
        ArgumentOutOfRangeException.ThrowIfNegative(request.Quantity);

        var order = Order.Create(request.CustomerId, request.Quantity);
        await repo.AddAsync(order, ct);
        return order;
    }
}
```

> **局限性**：防波堤减少了冗余验证，但不能替代安全关键路径的深度防御（身份验证、加密、PII）。**防波堤验证中的 bug 确实会发生** — 保持关键检查的分层。

### 正确性 vs 健壮性
- **正确性**：绝不返回不准确的结果；没有结果 > 错误结果。默认用于：医疗/金融/审计/支付/库存系统。
- **健壮性**：保持软件运行，即使结果有时不完美。默认用于：消费者 UI、内部工具、探索性仪表板。

| 领域 | 倾向于 | 关键问题 |
|---|---|---|
| 支付 / 账单 / 税务 | **正确性** | 错误数据会导致法律/合规问题吗？ |
| 内部管理工具 | **健壮性** | 技术用户能从崩溃中恢复吗？ |
| 数据管道 / ETL | **正确性** | 下游处理是否假设数据完整性？ |
| 实时交易 / IoT | **取决于上下文** | 过期数据比没有数据更好还是更差？ |
| 消费者 UI | **健壮性** | 正常运行时间比完美准确性更重要吗？ |

### 前置条件 / 后置条件
- **前置条件** — 调用者在调用前必须保证什么。
- **后置条件** — 方法在返回后保证什么。
- **不变式** — 在类型的生命周期内必须始终为真的内容。

在 C# 中，使用以下方式编码：`ArgumentNullException.ThrowIfNull`、`ArgumentOutOfRangeException`、`Debug.Assert`（内部）、`IValidatableObject`（DTO），以及可用时的 `[ContractAnnotation]`（ReSharper）。

---

## C# 边界检查清单（按优先级顺序）

在强化 API 边界时（公共方法、控制器端点、消息处理器、DI 注入的服务入口）：

```
正在审查 API 边界？
├─ 1. 参数验证 → ArgumentNullException.ThrowIfNull / ThrowIfNullOrWhiteSpace / 范围检查
├─ 2. 错误策略 → 匹配仓库模式（异常 vs Result<T> vs TryXxx）
├─ 3. 异步安全 → async Task（不是 async void），传递 CancellationToken，不要 .Result/.Wait()
├─ 4. 资源清理 → using / await using / IAsyncDisposable；传统 try/catch 用 finally
├─ 5. 输出安全 → 不要返回可变的内部集合（返回 IReadOnlyList<T>、不可变记录）
├─ 6. 时间正确性 → 持久化/计算时间用 DateTimeOffset（不是 DateTime）；持续时间用 TimeSpan
├─ 7. 枚举安全 → 默认 0 = 无效标记；或使用 [FlagsEnum] / SmartEnum
├─ 8. 加密安全 → RandomNumberGenerator（不是 Random）；永远不要将 Random 用于令牌/密钥/随机数
├─ 9. NRT 规范 → #nullable enable；标注泛型；不要静默返回 null
├─ 10. 日志规范 → 结构化日志（ILogger<T>）；没有 PII；正确的日志级别
└─ 11. 并发 → 默认使用不可变类型；共享状态用 lock/Interlocked；异步用 SemaphoreSlim
```

---

## 决策流程：断言 vs 异常 vs Result<T> vs Try*

```text
在 C# 中处理可能的坏条件？
│
├─ 这应该永远不会发生？（程序员 bug、违反不变式）
│   └─ 是 → Debug.Assert（开发）+ ArgumentException / InvalidOperationException（公共 API）
│
├─ 是预期的运行时输入（网络中断、文件缺失、用户输入垃圾）？
│   └─ 是 → 异常（默认）— 但检查下面的策略
│
├─ 是域中预期的/正常的（键未找到、登录失败、验证被拒绝）？
│   ├─ 调用者应该处理 → 返回 Result<T> 或 OneOf<T, TError> / 可区分联合
│   ├─ 调用者可能处理 → bool TryXxx(out T value) 模式
│   └─ 调用者不应该处理 → 抛出特定异常类型
│
└─ 高度健壮的系统（长时间运行的服务，绝不能崩溃）？
    └─ 两者都：验证（防御性）并用 try/catch 包装加优雅回退（进攻性恢复）
```

### 每个项目选择你的错误策略（并记录它）

| 策略 | 何时使用 | 权衡 |
|---|---|---|
| **异常**（.NET 中默认） | 真正异常的、深层调用栈、大量异步 | 热路径上的性能成本；如果不包装可能跨层泄漏 |
| **Result<T> / OneOf<T, TError>** | 域预期结果（登录、验证、业务规则） | 调用点明确；强制处理；在 BCL 中不太习惯 |
| **TryXxx（bool, out T）** | 廉价、频繁、性能敏感的解析（int.TryParse 风格） | 隐藏错误原因；仅适用于一种错误类别 |
| **异常 + Polly** | 外部服务调用、临时故障 | 增加恢复策略；如果重试范围太广可能掩盖 bug |

> **规则**：每个模块/层选择**一种**策略。同一代码库中混合"这里用 Result，那里用异常"是防御性混乱的首要来源。**在 `CONTEXT.md` / `docs/adr/` 中记录选择。**

---

## C# 防御性模式（检查清单）

### 1. 参数验证（廉价、高价值）

```csharp
// .NET 6+ 习惯用法
public void Process(string id, int count, Stream stream, CancellationToken ct = default)
{
    ArgumentException.ThrowIfNullOrEmpty(id);
    ArgumentNullException.ThrowIfNull(stream);
    ArgumentOutOfRangeException.ThrowIfNegativeOrZero(count);
    // CancellationToken 默认注入；直接传递即可

    // ... 实际工作
}
```

> **注意**：`ArgumentNullException.ThrowIfNull` 优于 `if (x == null) throw new ArgumentNullException(nameof(x));` — 更短，没有反向条件的风险，并且可分析。

### 2. 防御性释放（资源清理）

```csharp
// ✅ 正确：基于作用域
await using var stream = await httpClient.GetStreamAsync(url, ct);
await using var reader = new StreamReader(stream);
// 即使发生异常，reader 和 stream 也会被释放

// ✅ 正确：传统代码显式使用 finally
IDbConnection conn;
try
{
    conn = OpenConnection();
    // ...
}
finally
{
    conn?.Dispose();
}

// ❌ 错误：异常时资源泄漏
var stream = OpenStream();
DoWork(stream);
stream.Close(); // 如果 DoWork 抛出，永远不会到达
```

### 3. 异步特定防御规则

```csharp
// ❌ 错误：未处理的 Task 延续会静默使进程崩溃
public Task ProcessAsync() => DoWorkAsync(); // 未观察到的 task 中的异常

// ✅ 正确：显式错误路径
public async Task ProcessAsync(CancellationToken ct)
{
    try
    {
        await DoWorkAsync(ct);
    }
    catch (OperationCanceledException) when (ct.IsCancellationRequested)
    {
        throw; // 预期的，不要记录为错误
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "DoWork 失败");
        throw new ServiceException("处理失败", ex); // 在正确的抽象层包装
    }
}
```

> **其他规则（完整指导请见 `csharp-async` 技能）**：
> - 永远不要 `.Result` / `.Wait()`（死锁风险）
> - `async void` **仅**用于事件处理器
> - 每个层都传递 `CancellationToken`

### 4. 空 Catch — 沉默杀手

```csharp
// ❌ 错误：静默失败
try { await NotifyAsync(evt, ct); } catch { }

// ❌ 错误：记录后忽略，没有重新抛出或升级
try { await NotifyAsync(evt, ct); } catch (Exception ex) { logger.LogWarning(ex, ""); }

// ✅ 正确：对异常采取行动
try
{
    await NotifyAsync(evt, ct);
}
catch (HttpRequestException ex) when (IsTransient(ex))
{
    // 重新抛出、重试或升级到域级失败
    throw new NotificationDeliveryException(evt.Id, ex);
}
```

> **规则**：每个 `catch` 必须执行以下之一：**记录 + 重新抛出**、**包装 + 抛出新异常**、**重试**，或**记录并继续，并有明确的业务原因**。"捕获并忽略"是被禁止的，除非有注释解释必要性（例如，"即发即弃通知，失败可以接受"）。

### 5. NRT + IValidatableObject（DDD DTO 验证）

```csharp
public sealed record CreateOrderRequest(
    string CustomerId,
    IReadOnlyList<OrderLine> Lines) : IValidatableObject
{
    public IEnumerable<ValidationResult> Validate(ValidationContext _)
    {
        if (string.IsNullOrWhiteSpace(CustomerId))
            yield return new ValidationResult("CustomerId 是必需的", new[] { nameof(CustomerId) });
        if (Lines is null || Lines.Count == 0)
            yield return new ValidationResult("至少需要一行", new[] { nameof(Lines) });
    }
}
```

### 6. EF 实体上的并发令牌（DbUpdateConcurrencyException 来源）

```csharp
// 标记每个你修改的聚合根
public class Order
{
    public Guid Id { get; private set; }
    public uint Version { get; private set; } // EF 中的 [ConcurrencyCheck]
    // ...
}
```

> **为什么**：没有并发令牌，会发生静默的丢失更新 bug。在服务边界捕获 `DbUpdateConcurrencyException` 并返回域级冲突结果。

### 7. 不可变性作为防御（记录 + with）

```csharp
// 优先使用记录：值相等、默认不可变
public sealed record Money(decimal Amount, string Currency)
{
    public Money Add(Money other)
    {
        if (Currency != other.Currency)
            throw new InvalidOperationException("货币不匹配");
        return this with { Amount = Amount + other.Amount };
    }
}
```

> **为什么**：减少防御性修改表面。如果你不能修改共享状态，就不需要防御修改竞争。

---

## 模式重用门（在编写新错误处理之前）

**首先搜索代码库。不一致是最糟糕的防御性代码气味。**

| 搜索内容 | 为什么 |
|---|---|
| 模块其他地方相同的错误类型 | 它被记录了吗？被抛出了吗？被包装了吗？ |
| 已建立的 Result<T> 或异常约定 | 不要悄悄引入新策略 |
| 自定义异常基类 | 使用它们 — 不要抛出原始 Exception |
| 日志模式（结构化 vs 字符串插值） | 匹配现有约定 |
| IValidatableObject / FluentValidation 使用 | 不要添加并行验证系统 |

**如果找到模式**：遵循它。一致性胜过聪明。
**如果没找到模式**：你正在建立一个。在 `docs/adr/` 中记录决定。获得审查。

---

## 异步和并发防御模式

### Task.WhenAll / Task.WhenAllSettled 类似物

```csharp
// ❌ 错误：第一个失败会丢失其他失败的上下文
await Task.WhenAll(jobs);

// ✅ 正确：聚合失败，决定策略
var results = await Task.WhenAll(jobs.Select(j => j.RunSafelyAsync(ct)));
var failures = results.Where(r => !r.Success).ToList();
if (failures.Count > 0)
{
    logger.LogWarning("{Count} 个作业失败", failures.Count);
    // 策略：完全失败，还是继续部分执行？
}
```

### 取消规范
- 每个公共异步方法都接受 `CancellationToken ct = default`。
- 在长循环中检查 `ct.ThrowIfCancellationRequested()`。
- `OperationCanceledException` 是**预期的**，以 `Debug`（不是 `Error`）记录并重新抛出。

### 生产者/消费者用 Channels
- `BoundedChannel` 带 `FullMode = Wait` 或 `DropOldest`（不是无界 — 内存耗尽防御）。
- 更深入的指导请见 `csharp-concurrency-patterns` 技能。

---

## 进攻性编程（在开发中让失败更痛苦）

> **悖论**：在开发期间，让错误明显且讨厌。在生产期间，用结构化恢复让它们安静。

| 技术 | C# 示例 |
|---|---|
| **让断言中止** | Debug.Assert + Assert.Fail 可以；非调试用 ThrowIfNull（不吞掉） |
| **默认 switch 抛出** | 穷举 switch 中使用 default: throw new UnreachableException(); |
| **不可能状态快速失败** | 公共方法中不变式违反用 InvalidOperationException |
| **未观察到的 task 抛出** | TaskScheduler.UnobservedTaskException → 开发中记录致命，生产中告警 |
| **预提交钩子** | 把警告当作错误（<TreatWarningsAsErrors>true</TreatWarningsAsErrors>） |

---

## 生产过渡（保留什么，移除什么）

| 调试辅助工具 | 操作 | 理由 |
|---|---|---|
| 不变式的 Debug.Assert | **保留**（Release 中变为 no-op；没有运行时成本） | 为下一个读者记录不变式 |
| if (DEBUG) LogVerbose(...) | **移除** 或用 IsEnabled(LogLevel.Trace) 门控 | 不要向生产泄漏冗长噪音 |
| 坏数据上的硬崩溃 | **用 try/catch 加遥测包装** | 用户需要保存工作 |
| 有用的开发异常消息 | **为生产清理**（没有堆栈跟踪，没有内部路径） | 不要帮助攻击者 |
| 用于调试的 Console.WriteLine | **从第一天起就用 ILogger<T> 替换** | 标准化结构化日志 |
| 第一个验证错误就抛出 | API 控制器中**可以**；表单/DTO 验证中**收集所有** | UI 中更好的用户体验 |

---

## 何时不使用此技能

- **带记录的纯函数** — 没有可变状态要防御；信任类型系统。
- **原型/快速开发代码**（时间盒 ≤ 1 周） — 推迟错误策略直到设计稳定。
- **测试代码/测试替身** — 故意违反生产模式（例如，测试设置中抛出是可以的）。
- **性能关键的内部循环** — 仅在分析证明防御性检查成本 >5% 时；否则保留它们。

> **但是**：如果代码涉及身份验证、支付、加密、PII、医疗或合规 — 这些例外不适用。**始终验证。**

---

## 业界防御性编程最佳实践 Top 10（提炼总结）

结合 OWASP、Microsoft 文档和业界共识，防御性编程的核心原则包括：

1. **输入验证永远是第一位** — 信任边界外的一切都是敌对的（OWASP Top 10）
2. **空检查与边界检查** — 防止 NullReferenceException 和 IndexOutOfRangeException
3. **异常处理策略** — 不要空 catch，每个异常都要有处理或记录
4. **防御性兼容性** — DDL/API 变更必须向后兼容，脚本与代码同发（源自你的事故教训）
5. **参数验证** — 公共方法入口必须验证所有输入（.NET 6+ ThrowIfNull）
6. **资源清理** — using/await using 模式，防止资源泄漏
7. **并发安全** — 不可变性、锁、并发令牌
8. **安全编码** — 避免过时算法、参数化查询、输出编码
9. **日志与监控** — 结构化日志，不记录 PII
10. **测试与断言** — 单元测试覆盖边界情况，Debug.Assert 用于开发期不变式

---

## 危机不变式 — 快速卡片（打印并贴起来）

```
[ ] 防御性兼容检查：DDL/API 变更有脚本吗？向后兼容吗？
[ ] 没有空 catch（记录+重新抛出、包装+抛出、重试，或记录的忽略）
[ ] 公共方法验证所有参数（ThrowIfNull / ThrowIfNullOrEmpty / 范围）
[ ] async Task 不是 async void；传递 CancellationToken
[ ] 可释放对象用 using / await using；仅传统代码用 finally
[ ] Result<T> vs 异常策略匹配模块约定
[ ] 启用 NRT；没有静默 null 返回
[ ] EF 聚合根有并发令牌
[ ] 结构化日志；日志中没有 PII
[ ] Debug.Assert 中没有副作用代码
```

---

## 证据摘要

| 主张 | 来源 | 应用 |
|---|---|---|
| 防波堤 + 断言划分外部/内部 | McConnell，《代码大全》第 8 章 | 信任边界设计 |
| 防御性兼容性 = 最高优先级 | 真实生产事故教训 | 强制要求，覆盖便利性 |
| 输入验证是首要安全原则 | OWASP Top 10 | 始终验证外部输入 |
| 不要在 Assert 中放副作用代码 | Microsoft 文档 | Release 模式下 Assert 会消失 |
| 编码前思考，手术式变更 | Karpathy 准则 | 所有决策的行为层 |
| 优先使用记录 + 不可变性 | Microsoft .NET 文档 | 减少防御性表面 |

---

## 相关技能（分层使用）

- **`dotnet-best-practices`** — 命名、LINQ、DI、性能（样式层）
- **`csharp-async`** — async/await、Task、channels（并发层）
- **`modern-csharp-coding-standards`** — 记录、模式匹配、Span/Memory（语法层）
- **`karpathy-guidelines`** — 行为层（思考/简洁/手术式）
- **`csharp-defensive-programming`**（本技能）— **如何安全失败**（失败层）

与其他技能**一起**使用此技能 — 防御性模式位于良好样式和良好异步之上，而不是替代它们。

