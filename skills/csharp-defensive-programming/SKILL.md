---
name: csharp-defensive-programming
description: "Use when auditing, designing, or implementing C#/.NET code for error handling, input validation, assertions, exception strategy, defensive compatibility (DDL/method signatures), or deciding between exception vs Result vs Try-pattern. Triggers on: empty catch blocks, missing ArgumentNullException.ThrowIfNull, public method without validation, EF Core entity without concurrency token, DDL change without migration script, logging-and-swallow patterns, production-only failure paths. Complements dotnet-best-practices (style/API) and csharp-async (concurrency) by adding the 'how to fail safely' layer."
priority: high
license: MIT
---

# C# Defensive Programming Methodology

A C#/.NET adaptation of the Code-Complete defensive model (McConnell ch.8), with API-boundary checks inspired by go-defensive, layered with the user's `防御性兼容` DDL contract and Karpathy-style behavior rules.

> **Tradeoff:** These guidelines bias toward **correctness over speed** for production systems. For prototypes/spikes (max 1 week), use judgment.

---

## STOP — Never Skip (4 Invariants)

| # | Check | Why Critical in C# |
|---|-------|---------------------|
| 1 | **No executable code in `Debug.Assert`** | Code disappears in `Release` builds → silent dead code |
| 2 | **No empty `catch` blocks (no `catch { }` or `catch (Exception) { }` without action)** | Swallowed exceptions compound into impossible-to-diagnose production failures |
| 3 | **External input validated at trust boundary** | "Internal team API" is still external — anything crossing process/network/file boundary is hostile until proven otherwise |
| 4 | **Defensive compatibility on DDL/signature changes** | New fields/params must be optional+defaulted; code & migration scripts ship together; breaking changes HALT and ask first |

> **Security exception:** Auth/authz/crypto/PII code is **never** exempt from #1-#4, regardless of other factors. When in doubt, validate.

---

## CRISIS TRIAGE (2 minutes, production down)

### Immediate (30s each)
1. **Public method missing `ArgumentNullException.ThrowIfNull` / range check on entry?** Add it NOW.
2. **Empty `catch` hiding root cause?** Add structured logging (ILogger), then trace to source.
3. **`Debug.Assert` containing mutations, I/O, or `await`?** Extract to standalone statement + log.

### Before Deploying Fix (60s)
4. **Does fix match repo's existing error strategy** (exception vs `Result<T>` vs `Try*` pattern)? Grep first.
5. **Is exception thrown at the right abstraction level?** Don't let `SqlException` leak from `GetEmployee()` — wrap as `EmployeeNotFoundException` (or your domain type).

> **Why this works:** These 5 items catch ~80% of C# defensive bugs. Full checklist (24 items) is for non-emergency review.
>
> **Empty catch compounds.** A suppressed error in one layer cascades — your 2 AM debugging self will hate past-you.

---

## Key Definitions

### External Input (treat as hostile)
**Any data not provably controlled by the current code path:**
- HTTP request body / query / headers / route values
- Files (config, uploads, data files)
- Network (downstream APIs, message queues, gRPC)
- Environment variables, `IConfiguration` values
- Database results (even from your own DB — schema drift, manual fixes)
- Data from **any** other service, including internal ones

**Rule of thumb:** If it crosses a process, network, or trust boundary — validate.

### Assertion in C# (`Debug.Assert`)
Code that checks itself at runtime. **Use only for conditions that should NEVER occur** (programmer bugs, violated invariants). Disabled in `Release` — anything you put inside must be safe to vanish.

```csharp
// GOOD: pure check, no side effects
Debug.Assert(order.Lines.Count > 0, "Order must have at least one line");
```

```csharp
// BAD: side-effecting code inside assertion
Debug.Assert(ProcessPayment(order), "Payment must succeed"); // Payment skipped in Release!
```

### Barricade (防波堤)
A damage-containment boundary. Public surface of a class/module validates everything that enters; inside the barricade, code can trust the data and use cheaper assertions for internal invariants.

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

> **Limitation:** Barricades reduce redundant validation but do NOT replace defense-in-depth for security-critical paths (auth, crypto, PII). **Bugs in barricade validation happen** — keep critical checks layered.

### Correctness vs Robustness
- **Correctness:** Never return an inaccurate result; no result > wrong result. Default for: medical/finance/audit/payment/inventory systems.
- **Robustness:** Keep software running even if results are sometimes imperfect. Default for: consumer UIs, internal tools, exploratory dashboards.

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

## C# Boundary Checklist (in priority order)

When hardening an API boundary (public method, controller endpoint, message handler, DI-injected service entry):

```
Reviewing an API boundary?
├─ 1. Argument validation  → ArgumentNullException.ThrowIfNull / ThrowIfNullOrWhiteSpace / range checks
├─ 2. Error strategy       → Match repo's pattern (exception vs Result<T> vs TryXxx)
├─ 3. Async safety         → async Task (not async void), CancellationToken threaded, no .Result/.Wait()
├─ 4. Resource cleanup     → using / await using / IAsyncDisposable; finally for legacy try/catch
├─ 5. Output safety        → Don't return mutable internal collections (return IReadOnlyList<T>, immutable record)
├─ 6. Time correctness     → DateTimeOffset (not DateTime) for persisted/computed times; TimeSpan for durations
├─ 7. Enum safety          → Default to 0 = invalid sentinel; or use [FlagsEnum] / SmartEnum
├─ 8. Crypto safety        → RandomNumberGenerator (not Random); never use Random for tokens/keys/nonces
├─ 9. NRT discipline       → #nullable enable; annotate generics; no silent null returns
├─ 10. Logging discipline  → Structured logging (ILogger<T>); no PII; correct log level
└─ 11. Concurrency         → Immutable types by default; lock/Interlocked for shared state; SemaphoreSlim for async
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
| **`TryXxx` (bool, out T)** | Cheap, frequent, performance-sensitive parsing (int.TryParse style) | Hides the error reason; only works for one error class |
| **Exception + Polly** | External service calls, transient failures | Adds resilience policy; can mask bugs if retries are too broad |

> **Rule:** Pick ONE strategy per module/layer. Mixing "Result here, exception there" in the same codebase is the #1 source of defensive confusion. **Document the choice in `CONTEXT.md` / `docs/adr/`.**

---

## The C# Defensive Patterns (Checklist)

### 1. Argument Validation (Cheap, High-Value)

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

> **Note:** `ArgumentNullException.ThrowIfNull` is preferred over `if (x == null) throw new ArgumentNullException(nameof(x));` — shorter, no risk of inverted condition, and analyzable.

### 2. Defensive Disposal (Resource Cleanup)

```csharp
// GOOD: scope-based
await using var stream = await httpClient.GetStreamAsync(url, ct);
await using var reader = new StreamReader(stream);
// reader & stream disposed even on exception

// GOOD: explicit finally for legacy code
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

// BAD: resource leak on exception
var stream = OpenStream();
DoWork(stream);
stream.Close(); // never reached if DoWork throws
```

### 3. Async-Specific Defensive Rules

```csharp
// BAD: unhandled Task continuation crashes process silently
public Task ProcessAsync() => DoWorkAsync(); // exceptions in unobserved task

// GOOD: explicit error path
public async Task ProcessAsync(CancellationToken ct)
{
    try
    {
        await DoWorkAsync(ct);
    }
    catch (OperationCanceledException) when (ct.IsCancellationRequested)
    {
        throw; // expected, do not log as error
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "DoWork failed");
        throw new ServiceException("Processing failed", ex); // wrap at right abstraction
    }
}
```

> **Additional rules (see `csharp-async` skill for full guidance):**
> - Never `.Result` / `.Wait()` (deadlock risk)
> - `async void` ONLY for event handlers
> - Thread `CancellationToken` through every layer

### 4. Empty Catch — The Silent Killer

```csharp
// BAD: silent failure
try { await NotifyAsync(evt, ct); } catch { }

// BAD: log-and-swallow without rethrow or escalation
try { await NotifyAsync(evt, ct); } catch (Exception ex) { logger.LogWarning(ex, ""); }

// GOOD: act on the exception
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

> **Rule:** Every `catch` must do one of: **log + rethrow**, **wrap + throw new**, **retry**, or **record and continue with a documented business reason**. "Catch and ignore" is forbidden unless there's a comment explaining the imperative (e.g., "fire-and-forget notification, failure is acceptable").

### 5. NRT + `IValidatableObject` (DDD DTO Validation)

```csharp
public sealed record CreateOrderRequest(
    string CustomerId,
    IReadOnlyList<OrderLine> Lines) : IValidatableObject
{
    public IEnumerable<ValidationResult> Validate(ValidationContext _)
    {
        if (string.IsNullOrWhiteSpace(CustomerId))
            yield return new ValidationResult("CustomerId required", new[] { nameof(CustomerId) });
        if (Lines is null || Lines.Count == 0)
            yield return new ValidationResult("At least one line required", new[] { nameof(Lines) });
    }
}
```

### 6. Concurrency Tokens on EF Entities (DbUpdateConcurrencyException source)

```csharp
// Mark every aggregate root you mutate
public class Order
{
    public Guid Id { get; private set; }
    public uint Version { get; private set; } // [ConcurrencyCheck] in EF
    // ...
}
```

> **Why:** Without a concurrency token, silent lost-update bugs occur. Catch `DbUpdateConcurrencyException` at the service boundary and return a domain-level conflict result.

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

> **Why:** Reduces defensive-mutation surface. If you can't mutate shared state, you don't need to defend against mutation races.

---

## Pattern Reuse Gate (BEFORE writing new error handling)

**Search the codebase first. Inconsistency is the worst defensive code smell.**

| Search For | Why |
|------------|-----|
| Same error type elsewhere in the module | Is it logged? Thrown? Wrapped? |
| Established `Result<T>` or exception convention | Don't introduce a new strategy silently |
| Custom exception base classes | Use them — don't throw raw `Exception` |
| Logging patterns (structured vs string interpolation) | Match the existing convention |
| `IValidatableObject` / FluentValidation usage | Don't add a parallel validation system |

**If pattern found:** Follow it. Consistency beats cleverness.
**If no pattern found:** You're establishing one. Document the decision in `docs/adr/`. Get review.

---

## Defensive Compatibility · DDL/Migration/Contract (USER MANDATE)

**Trigger:** Adding/modifying a field, method signature, interface, stored procedure, or any DDL change.

### Hard Constraints

1. **Backward compatible by default.** New fields, new parameters → optional + default value. Never break existing callers.
2. **Code & scripts ship together.** Changing stored proc / view / table? **Synchronously check and update** the migration / DDL script in the same task. Mismatched code and script = incident.
3. **Breaking change → HALT and ask.** Deleting a field, changing a return type, changing a signature incompatibly? **Stop immediately**, surface the breaking change, ask the user to confirm the upgrade path before proceeding.
4. **Silent field additions = incident.** Any DB field addition MUST be audited for callers + migration script. Inconsistency → fail loud, never silently.

### Pre-commit Self-Check (answer all 3)

- [ ] Do existing callers / older DB versions still work?
- [ ] Is the migration / upgrade script in the same commit?
- [ ] Have I surfaced the script path to the user for backup?

> **Origin:** `防御性兼容 · Defensive Compatibility` in workspace `CLAUDE.md`. This is a **highest-priority** rule, overriding convenience.

---

## Async & Concurrent Defensive Patterns

### `Task.WhenAll` / `Task.WhenAllSettled` analog

```csharp
// BAD: first failure loses context of others
await Task.WhenAll(jobs);

// GOOD: aggregate failures, decide policy
var results = await Task.WhenAll(jobs.Select(j => j.RunSafelyAsync(ct)));
var failures = results.Where(r => !r.Success).ToList();
if (failures.Count > 0)
{
    logger.LogWarning("{Count} jobs failed", failures.Count);
    // policy: fail entirely, or continue with partial?
}
```

### Cancellation discipline
- Every public async method takes `CancellationToken ct = default`.
- Check `ct.ThrowIfCancellationRequested()` in long loops.
- `OperationCanceledException` is **expected**, log at `Debug` (not `Error`) and rethrow.

### Channels for producer/consumer
- `BoundedChannel` with `FullMode = Wait` or `DropOldest` (not unbounded — memory exhaustion defense).
- See `csharp-concurrency-patterns` skill for deeper guidance.

---

## Offensive Programming (Make Failures Painful in Dev)

> **Paradoxon:** During development, make errors obvious and obnoxious. During production, make them quiet with structured recovery.

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
| `Console.WriteLine` for debug | **REPLACE** with `ILogger<T>` from day 1 | Standardized structured logging |
| Throw on first validation error | **OK** in API controllers; **collect-all** in form/DTO validation | Better UX in UI |

---

## When NOT to Use This Skill

- **Pure functions with records** — no mutable state to defend; trust the type system.
- **Prototype / spike code** (time-boxed ≤ 1 week) — defer error strategy until design stabilizes.
- **Test code / test doubles** — intentionally violate production patterns (e.g., throwing in test setup is fine).
- **Performance-critical inner loops** — only if profiling proves defensive checks cost >5%; otherwise keep them.

> **But:** if the code touches auth, payments, crypto, PII, medical, or compliance — these exceptions do not apply. **Always validate.**

---

## Crisis Invariants — Quick Card (print and pin)

```
[ ] No code in Debug.Assert body
[ ] No empty catch (log+rethrow, wrap+throw, retry, or documented ignore)
[ ] Public method validates all args (ThrowIfNull / ThrowIfNullOrEmpty / range)
[ ] async Task not async void; CancellationToken threaded
[ ] using / await using for disposables; finally only for legacy
[ ] Result<T> vs Exception strategy matches module convention
[ ] NRT enabled; no silent null returns
[ ] DDL/contract change: backward compatible + migration script + HALT on breaking
[ ] EF aggregate roots have concurrency token
[ ] Structured logging; no PII in logs
```

---

## Evidence Summary

| Claim | Source | Application |
|-------|--------|-------------|
| Barricades + assertions split external/internal | McConnell, *Code Complete* ch.8 | Trust boundary design |
| 8-step API boundary order | go-defensive (cxuu) | Adapted to C# idioms |
| "Garbage in, garbage out" is obsolete | McConnell p.188 | Validate external input always |
| Defensive compatibility = highest-priority DDL rule | User `CLAUDE.md` | Mandatory, overrides convenience |
| Think before coding, surgical changes | Karpathy guidelines | Behavior layer for all decisions |
| Prefer records + immutability | Microsoft .NET docs, Wagner "Effective C#" | Reduces defensive surface |

---

## Related Skills (Layered Usage)

- **`dotnet-best-practices`** — naming, LINQ, DI, performance (style layer)
- **`csharp-async`** — async/await, Task, channels (concurrency layer)
- **`modern-csharp-coding-standards`** — record, pattern matching, Span/Memory (syntax layer)
- **`karpathy-guidelines`** — behavior layer (think/simplicity/surgical)
- **`csharp-defensive-programming`** (this skill) — **how to fail safely** (failure layer)

Use this skill **alongside** the others — defensive patterns sit on top of good style and good async, not in place of them.
