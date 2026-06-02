---
name: csharp-defensive-programming
description: "Use when auditing, designing, or implementing C#/.NET code for error handling, input validation, assertions, exception strategy, defensive compatibility (DDL/method signatures), or deciding between exception vs Result vs Try-pattern. Triggers on: empty catch blocks, missing ArgumentNullException.ThrowIfNull, public method without validation, EF Core entity without concurrency token, DDL change without migration script, logging-and-swallow patterns, production-only failure paths. Complements dotnet-best-practices (style/API) and csharp-async (concurrency) by adding the \"how to fail safely\" layer."
priority: high
license: MIT
---

# C# Defensive Programming Methodology

A C#/.NET adaptation of the Code-Complete defensive model (McConnell ch.8), with API-boundary checks inspired by go-defensive, layered with the user's **Defensive Compatibility** DDL contract and Karpathy-style behavior rules.

> **Core Principle**: These guidelines bias toward **correctness over speed** for production systems. For prototypes/spikes (max 1 week), use judgment.

---

## 🚨 Defensive Compatibility · Highest Priority · Mandatory

**Trigger Scenarios**: Adding/modifying fields, method signatures, interfaces, stored procedures, or any DDL changes.

**Hard Constraints**:
1. **Backward Compatible**: New fields and new parameters must be optional with default values; breaking existing callers is forbidden.
2. **Scripts Ship Together**: When modifying stored procedures/views/table structures, you must **synchronously check and prompt** for DDL/upgrade scripts in the same task; code and scripts change and ship together.
3. **Stop First for Breaking Changes**: If compatibility must be broken (deleting fields, changing signature types, changing return structure), **stop immediately**, first prompt the user to save upgrade scripts and confirm before proceeding.
4. **Silent Field Addition = Incident**: Any database field addition must audit callers and migration scripts; inconsistency reports an error directly, disallowing \"code added, script not updated\".

**Pre-Commit Self-Check (Must Answer All)**:
- Do existing callers/old DB versions still work?
- Are upgrade scripts synchronized?
- Do you need to prompt the user to backup change scripts?

> **Source**: From real production incident lessons, **this is the highest priority rule**, overriding convenience.

---

## ⛔ STOP — Never Skip (5 Invariants)

| # | Check | Why Critical in C# |
|---|-------|---------------------|
| 1 | **No empty catch blocks** | Swallowed exceptions compound into impossible-to-diagnose production failures |
| 2 | **Public methods must validate all parameters at entry** | Input outside trust boundaries is never trusted, prevent NullReferenceException and other low-level errors |
| 3 | **No side-effecting code in Debug.Assert** | Asserts disappear in Release builds → logic errors (not dead code, logic just doesn't execute) |
| 4 | **External input validated at trust boundary** | \"Internal team API\" is still external — anything crossing process/network/file boundary is hostile until proven otherwise |
| 5 | **EF entity changes must consider concurrency control** | No concurrency token causes silent lost-update bugs |

> **Security Exception**: Auth/authz/crypto/PII code is **never** exempt from the above, regardless of other factors. When in doubt, validate.

---

## 🚨 Crisis Triage (2 minutes, production down)

### Immediate Actions (30 seconds each)
1. **Public method missing `ArgumentNullException.ThrowIfNull` / range check at entry?** Add it NOW.
2. **Empty catch hiding root cause?** Add structured logging (ILogger), then trace to source.
3. **DDL/SP out of sync with code?** Immediately rollback or synchronize scripts.

### Before Deploying Fix (60 seconds)
4. **Does fix match repo's existing error strategy** (exception vs `Result<T>` vs `Try*` pattern)? Grep first.
5. **Is exception thrown at the right abstraction level?** Don't let `SqlException` leak from `GetEmployee()` — wrap as `EmployeeNotFoundException` (or your domain type).

> **Why this works**: These 5 items catch ~80% of C# defensive bugs. Full checklist for non-emergency review.
>
> **Empty catch compounds**: A suppressed error in one layer cascades — your 2 AM debugging self will hate past you.

---

## Key Definitions

### External Input (Treat as Hostile)
**Any data not provably controlled by the current code path**:
- HTTP request body / query / headers / route values
- Files (config, uploads, data files)
- Network (downstream APIs, message queues, gRPC)
- Environment variables, `IConfiguration` values
- Database results (even from your own DB — schema drift, manual fixes)
- Data from **any** other service, including internal services

**Rule of thumb**: If it crosses a process, network, or trust boundary — validate it.

### Assertions in C# (Debug.Assert)
Code that checks itself at runtime. **Only use for conditions that should NEVER happen** (programmer bugs, violated invariants). **Disabled in Release** — anything you put inside must be safe to disappear.

**Key Points**:
- Assert is a **development aid**, not production validation
- **Never put side-effecting code in Assert** (like `ProcessPayment(order)` or state-modifying functions)
- Correct usage: pure condition checks like `Debug.Assert(order.Lines.Count > 0, \"Order must have at least one line\")`

```csharp
// ✅ GOOD: pure check, no side effects
Debug.Assert(order.Lines.Count > 0, "Order must have at least one line");

// ❌ BAD: side-effecting code won't execute in Release!
Debug.Assert(ProcessPayment(order), "Payment must succeed");
```

### Barricade
A damage containment boundary. Public surface of a class/module validates everything that enters; inside the barricade, code can trust the data and use cheaper assertions for internal invariants.

```csharp
public sealed class OrderService(IOrderRepository repo, ILogger<OrderService> log)
{
    public async Task<Order> PlaceAsync(PlaceOrderRequest request, CancellationToken ct)
    {
        // Barricade: validate external input
        ArgumentNullException.ThrowIfNull(request);
        ArgumentException.ThrowIfNullOrWhiteSpace(request.CustomerId);
        ArgumentOutOfRangeException.ThrowIfNegative(request.Quantity);

        var order = Order.Create(request.CustomerId, request.Quantity);
        await repo.AddAsync(order, ct);
        return order;
    }
}
```

> **Limitation**: Barricades reduce redundant validation but do NOT replace defense-in-depth for security-critical paths (auth, crypto, PII). **Bugs in barricade validation happen** — keep critical checks layered.

### Correctness vs Robustness
- **Correctness**: Never return an inaccurate result; no result > wrong result. Default for: medical/finance/audit/payment/inventory systems.
- **Robustness**: Keep software running even if results are sometimes imperfect. Default for: consumer UIs, internal tools, exploratory dashboards.

| Domain | Lean Toward | Key Question |
|--------|-------------|--------------|
| Payment / Billing / Tax | **Correctness** | Would wrong data cause legal/compliance issues? |
| Internal admin tools | **Robustness** | Can a tech user recover from a crash? |
| Data pipelines / ETL | **Correctness** | Does downstream processing assume data integrity? |
| Real-time trading / IoT | **Context-dependent** | Is stale data better or worse than no data? |
| Consumer UI | **Robustness** | Is uptime more important than perfect accuracy? |

### Preconditions / Postconditions
- **Preconditions** — what the caller must guarantee BEFORE calling.
- **Postconditions** — what the method guarantees AFTER returning.
- **Invariants** — what must always be true inside the type's lifetime.

In C#, encode with: `ArgumentNullException.ThrowIfNull`, `ArgumentOutOfRangeException`, `Debug.Assert` (internal), `IValidatableObject` (DTO), and `[ContractAnnotation]` (ReSharper) where available.

---

## C# Boundary Checklist (Priority Order)

When hardening an API boundary (public method, controller endpoint, message handler, DI-injected service entry):

```
Reviewing an API boundary?
├─ 1. Argument validation → ArgumentNullException.ThrowIfNull / ThrowIfNullOrWhiteSpace / range checks
├─ 2. Error strategy → Match repo's pattern (exception vs Result<T> vs TryXxx)
├─ 3. Async safety → async Task (not async void), CancellationToken threaded, no .Result/.Wait()
├─ 4. Resource cleanup → using / await using / IAsyncDisposable; finally for legacy try/catch
├─ 5. Output safety → Don't return mutable internal collections (return IReadOnlyList<T>, immutable record)
├─ 6. Time correctness → DateTimeOffset (not DateTime) for persisted/computed times; TimeSpan for durations
├─ 7. Enum safety → Default 0 = invalid sentinel; or use [FlagsEnum] / SmartEnum
├─ 8. Crypto safety → RandomNumberGenerator (not Random); never use Random for tokens/keys/nonces
├─ 9. NRT discipline → #nullable enable; annotate generics; no silent null returns
├─ 10. Logging discipline → Structured logging (ILogger<T>); no PII; correct log level
└─ 11. Concurrency → Immutable types by default; lock/Interlocked for shared state; SemaphoreSlim for async
```

---

## Decision Flow: Assertion vs Exception vs `Result<T>` vs `Try*`

```text
Handling a potentially bad condition in C#?
│
├─ Should this NEVER happen? (programmer bug, violated invariant)
│   └─ YES → Debug.Assert (development) + ArgumentException / InvalidOperationException (public API)
│
├─ Is it anticipated runtime input (network down, file missing, user typed garbage)?
│   └─ YES → Exception (default) — but check the strategy below
│
├─ Is it expected/normal in the domain (key not found, login failed, validation rejected)?
│   ├─ Caller SHOULD handle it → return `Result<T>` or `OneOf<T, TError>` / discriminated union
│   ├─ Caller MAY handle it → `bool TryXxx(out T value)` pattern
│   └─ Caller SHOULD NOT handle → throw a specific exception type
│
└─ Highly robust system (long-running service, must not crash)?
    └─ BOTH: validate (defensive) AND wrap in try/catch with graceful fallback (offensive recovery)
```

### Choose Your Error Strategy Per Project (and document it)

| Strategy | When to Use | Tradeoff |
|----------|-------------|----------|
| **Exceptions** (default in .NET) | Truly exceptional, deep call stacks, async-heavy | Performance cost on hot paths; can leak across layers if not wrapped |
| **`Result<T>` / `OneOf<T, TError>`** | Domain expected outcomes (login, validation, business rules) | Explicit at call site; forces handling; less idiomatic in BCL |
| **`TryXxx` (bool, out T)** | Cheap, frequent, performance-sensitive parsing (int.TryParse style) | Hides error reason; only works for one error class |
| **Exception + Polly** | External service calls, transient failures | Adds resilience policy; can mask bugs if retries are too broad |

> **Rule**: Pick ONE strategy per module/layer. Mixing "Result here, exception there" in the same codebase is the #1 source of defensive confusion. **Document the choice in `CONTEXT.md` / `docs/adr/`.**

---

## C# Defensive Patterns (Checklist)

### 1. Argument Validation (Cheap, High Value)

```csharp
// .NET 6+ idiomatic
public void Process(string id, int count, Stream stream, CancellationToken ct = default)
{
    ArgumentException.ThrowIfNullOrEmpty(id);
    ArgumentNullException.ThrowIfNull(stream);
    ArgumentOutOfRangeException.ThrowIfNegativeOrZero(count);
    // CancellationToken default-injected; just pass through

    // ... actual work
}
```

> **Note**: `ArgumentNullException.ThrowIfNull` is preferred over `if (x == null) throw new ArgumentNullException(nameof(x));` — shorter, no risk of inverted condition, and analyzable.

### 2. Defensive Disposal (Resource Cleanup)

```csharp
// ✅ GOOD: scope-based
await using var stream = await httpClient.GetStreamAsync(url, ct);
await using var reader = new StreamReader(stream);
// reader & stream disposed even on exception

// ✅ GOOD: explicit finally for legacy code
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

// ❌ BAD: resource leak on exception
var stream = OpenStream();
DoWork(stream);
stream.Close(); // never reached if DoWork throws
```

### 3. Async-Specific Defensive Rules

```csharp
// ❌ BAD: unhandled Task continuation crashes process silently
public Task ProcessAsync() => DoWorkAsync(); // exceptions in unobserved task

// ✅ GOOD: explicit error path
public async Task ProcessAsync(CancellationToken ct)
{
    try
    {
        await DoWorkAsync(ct);
    }
    catch (OperationCanceledException) when (ct.IsCancellationRequested)
    {
        throw; // expected, don't log as error
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "DoWork failed");
        throw new ServiceException("Processing failed", ex); // wrap at right abstraction
    }
}
```

> **Additional rules (see `csharp-async` skill for full guidance)**:
> - Never `.Result` / `.Wait()` (deadlock risk)
> - `async void` **only** for event handlers
> - Thread `CancellationToken` through every layer

### 4. Empty Catch — The Silent Killer

```csharp
// ❌ BAD: silent failure
try { await NotifyAsync(evt, ct); } catch { }

// ❌ BAD: log-and-swallow without rethrow or escalation
try { await NotifyAsync(evt, ct); } catch (Exception ex) { logger.LogWarning(ex, ""); }

// ✅ GOOD: act on the exception
try
{
    await NotifyAsync(evt, ct);
}
catch (HttpRequestException ex) when (IsTransient(ex))
{
    // rethrow, retry, or escalate to a domain-level failure
    throw new NotificationDeliveryException(evt.Id, ex);
}
```

> **Rule**: Every `catch` must do one of: **log + rethrow**, **wrap + throw new**, **retry**, or **record and continue with documented business reason**. "Catch and ignore" is forbidden unless there's a comment explaining the imperative (e.g., "fire-and-forget notification, failure is acceptable").

### 5. NRT + `IValidatableObject` (DDD DTO Validation)

```csharp
public sealed record CreateOrderRequest(
    string CustomerId,
    IReadOnlyList<OrderLine> Lines) : IValidatableObject
{
    public IEnumerable<ValidationResult> Validate(ValidationContext _)
    {
        if (string.IsNullOrWhiteSpace(CustomerId))
            yield return new ValidationResult("CustomerId is required", new[] { nameof(CustomerId) });
        if (Lines is null || Lines.Count == 0)
            yield return new ValidationResult("At least one line is required", new[] { nameof(Lines) });
    }
}
```

### 6. Concurrency Tokens on EF Entities (DbUpdateConcurrencyException Source)

```csharp
// Mark every aggregate root you mutate
public class Order
{
    public Guid Id { get; private set; }
    public uint Version { get; private set; } // [ConcurrencyCheck] in EF
    // ...
}
```

> **Why**: Without a concurrency token, silent lost-update bugs occur. Catch `DbUpdateConcurrencyException` at the service boundary and return a domain-level conflict result.

### 7. Immutability as Defense (Records + `with`)

```csharp
// Prefer records: value-equality, immutable by default
public sealed record Money(decimal Amount, string Currency)
{
    public Money Add(Money other)
    {
        if (Currency != other.Currency)
            throw new InvalidOperationException("Currency mismatch");
        return this with { Amount = Amount + other.Amount };
    }
}
```

> **Why**: Reduces defensive-mutation surface. If you can't mutate shared state, you don't need to defend against mutation races.

---

## Pattern Reuse Gate (Before writing new error handling)

**Search the codebase first. Inconsistency is the worst defensive code smell.**

| Search For | Why |
|------------|-----|
| Same error type elsewhere in the module | Is it logged? Thrown? Wrapped? |
| Established `Result<T>` or exception convention | Don't introduce a new strategy silently |
| Custom exception base classes | Use them — don't throw raw `Exception` |
| Logging patterns (structured vs string interpolation) | Match the existing convention |
| `IValidatableObject` / FluentValidation usage | Don't add a parallel validation system |

**If pattern found**: Follow it. Consistency beats cleverness.
**If no pattern found**: You're establishing one. Document the decision in `docs/adr/`. Get review.

---

## Async & Concurrent Defensive Patterns

### `Task.WhenAll` / `Task.WhenAllSettled` Analog

```csharp
// ❌ BAD: first failure loses context of others
await Task.WhenAll(jobs);

// ✅ GOOD: aggregate failures, decide policy
var results = await Task.WhenAll(jobs.Select(j => j.RunSafelyAsync(ct)));
var failures = results.Where(r => !r.Success).ToList();
if (failures.Count > 0)
{
    logger.LogWarning("{Count} jobs failed", failures.Count);
    // policy: fail entirely, or continue with partial?
}
```

### Cancellation Discipline
- Every public async method takes `CancellationToken ct = default`.
- Check `ct.ThrowIfCancellationRequested()` in long loops.
- `OperationCanceledException` is **expected**, log at `Debug` (not `Error`) and rethrow.

### Channels for Producer/Consumer
- `BoundedChannel` with `FullMode = Wait` or `DropOldest` (not unbounded — memory exhaustion defense).
- See `csharp-concurrency-patterns` skill for deeper guidance.

---

## Offensive Programming (Make Failures Painful in Dev)

> **Paradox**: During development, make errors obvious and obnoxious. During production, make them quiet with structured recovery.

| Technique | C# Example |
|-----------|------------|
| **Make asserts abort** | `Debug.Assert` + `Assert.Fail` is OK; for non-debug use `ThrowIfNull` (not swallowed) |
| **Default switch throws** | `default: throw new UnreachableException();` in exhaustive switches |
| **Fail fast on impossible state** | `InvalidOperationException` for invariant violations in public methods |
| **Throw on unobserved tasks** | `TaskScheduler.UnobservedTaskException` → log fatal in dev, alert in prod |
| **Pre-commit hooks** | Treat warnings as errors (`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`) |

---

## Production Transition (What to Keep, What to Strip)

| Debug Aid | Action | Rationale |
|-----------|--------|-----------|
| `Debug.Assert` for invariants | **KEEP** (becomes no-op in Release; not a runtime cost) | Documents the invariant for next reader |
| `if (DEBUG) LogVerbose(...)` | **REMOVE** or gate by `IsEnabled(LogLevel.Trace)` | Don't leak verbose noise to prod |
| Hard crash on bad data | **WRAP** in try/catch with telemetry | Users need to save work |
| Helpful dev exception messages | **SANITIZE** for prod (no stack traces, no internal paths) | Don't help attackers |
| `Console.WriteLine` for debugging | **REPLACE** with `ILogger<T>` from day 1 | Standardized structured logging |
| Throw on first validation error | **OK** in API controllers; **collect-all** in form/DTO validation | Better UX in UI |

---

## When NOT to Use This Skill

- **Pure functions with records** — no mutable state to defend; trust the type system.
- **Prototype / spike code** (time-boxed ≤ 1 week) — defer error strategy until design stabilizes.
- **Test code / test doubles** — intentionally violate production patterns (e.g., throwing in test setup is fine).
- **Performance-critical inner loops** — only if profiling proves defensive checks cost >5%; otherwise keep them.

> **But**: If the code touches auth, payments, crypto, PII, medical, or compliance — these exceptions do not apply. **Always validate.**

---

## Industry Defensive Programming Best Practices Top 10 (Summary)

Combining OWASP, Microsoft documentation, and industry consensus, the core principles of defensive programming include:

1. **Input Validation Always Comes First** — everything outside trust boundaries is hostile (OWASP Top 10)
2. **Null Checks and Boundary Checks** — prevent NullReferenceException and IndexOutOfRangeException
3. **Exception Handling Strategy** — no empty catch, every exception has handling or logging
4. **Defensive Compatibility** — DDL/API changes must be backward compatible, scripts ship with code (from your incident lessons)
5. **Parameter Validation** — public method entry must validate all inputs (.NET 6+ ThrowIfNull)
6. **Resource Cleanup** — using/await using pattern, prevent resource leaks
7. **Concurrency Safety** — immutability, locks, concurrency tokens
8. **Secure Coding** — avoid outdated algorithms, parameterized queries, output encoding
9. **Logging and Monitoring** — structured logging, no PII in logs
10. **Testing and Assertions** — unit tests cover boundary cases, Debug.Assert for development invariants

---

## Crisis Invariants — Quick Card (Print and Pin)

```
[ ] Defensive compatibility check: DDL/API changes have scripts? Backward compatible?
[ ] No empty catch (log+rethrow, wrap+throw, retry, or documented ignore)
[ ] Public method validates all args (ThrowIfNull / ThrowIfNullOrEmpty / range)
[ ] async Task not async void; CancellationToken threaded
[ ] using / await using for disposables; finally only for legacy
[ ] Result<T> vs Exception strategy matches module convention
[ ] NRT enabled; no silent null returns
[ ] EF aggregate roots have concurrency token
[ ] Structured logging; no PII in logs
[ ] No side-effecting code in Debug.Assert
```

---

## Evidence Summary

| Claim | Source | Application |
|-------|--------|-------------|
| Barricades + assertions split external/internal | McConnell, *Code Complete* ch.8 | Trust boundary design |
| Defensive Compatibility = highest priority | Real production incident lessons | Mandatory, overrides convenience |
| Input validation is primary security principle | OWASP Top 10 | Always validate external input |
| No side effects in Assert | Microsoft documentation | Asserts disappear in Release |
| Think before coding, surgical changes | Karpathy guidelines | Behavior layer for all decisions |
| Prefer records + immutability | Microsoft .NET docs, Wagner *Effective C#* | Reduces defensive surface |

---

## Related Skills (Layered Usage)

- **`dotnet-best-practices`** — naming, LINQ, DI, performance (style layer)
- **`csharp-async`** — async/await, Task, channels (concurrency layer)
- **`modern-csharp-coding-standards`** — records, pattern matching, Span/Memory (syntax layer)
- **`karpathy-guidelines`** — behavior layer (think/simplicity/surgical)
- **`csharp-defensive-programming`** (this skill) — **how to fail safely** (failure layer)

Use this skill **alongside** the others — defensive patterns sit on top of good style and good async, not in place of them.

