# csharp-defensive-programming

A C#/.NET defensive programming methodology for AI coding agents. Distills the "how to fail safely" layer of .NET development: error handling, input validation, assertion strategy, exception/Result/Try-pattern decisions, and **defensive compatibility** for DDL/contract changes.

> A C# adaptation of the Code-Complete defensive model (McConnell ch.8), with API-boundary checks inspired by `go-defensive`, layered with a `防御性兼容` DDL contract and Karpathy-style behavior rules.

## Install

```bash
npx skills add cowpy/csharp-defensive-programming
```

Or to install globally for all your projects:

```bash
npx skills add cowpy/csharp-defensive-programming -g -y
```

## What This Skill Covers

- **STOP — 4 Invariants** (Never skip): no side effects in `Debug.Assert`, no empty catch, validate external input, defensive compatibility on DDL changes.
- **Crisis Triage** (2 min, production down): prioritized defensive bug hunt.
- **Core Definitions**: external input, assertion, Barricade, Correctness vs Robustness.
- **C# Boundary Checklist** (11 steps, priority-ordered).
- **Decision Flowchart**: `Debug.Assert` vs Exception vs `Result<T>` vs `Try*`.
- **7 C# Defensive Patterns**: argument validation, defensive disposal, async safety, empty-catch discipline, NRT + `IValidatableObject`, EF concurrency tokens, immutability.
- **Pattern Reuse Gate** — search codebase first, match the existing error strategy.
- **Defensive Compatibility · DDL/Migration/Contract** — backward compatible by default, code & scripts ship together, HALT on breaking changes.
- **Async & Concurrent Defensive Patterns** — `CancellationToken` discipline, `Task.WhenAll` failure aggregation.
- **Offensive Programming** — make failures painful in dev, quiet in production.
- **Production Transition** — what to keep, what to strip before ship.
- **Crisis Invariants Quick Card** — printable 10-item checklist.

## When to Invoke

The skill triggers (per its `description`) on:

- Empty catch blocks / logging-and-swallow patterns
- Missing `ArgumentNullException.ThrowIfNull` / range checks
- Public method without validation
- EF Core entity without concurrency token → silent lost-update bugs
- DDL change without migration script
- Exception strategy confusion (mixing `Result<T>` and exceptions)
- Production-only failure paths / unobserved task exceptions
- Choosing between `Debug.Assert`, exception, `Result<T>`, or `Try*`

## Companion Skills (use alongside)

| Layer | Skill | What It Covers |
|-------|-------|----------------|
| Style / API | `dotnet-best-practices` | Naming, LINQ, DI, performance |
| Concurrency | `csharp-async` | `async`/`await`, Task, Channels |
| Syntax | `modern-csharp-coding-standards` | records, pattern matching, Span/Memory |
| Behavior | `karpathy-guidelines` | Think / Simplicity / Surgical |
| **Failure** | **`csharp-defensive-programming`** (this) | **How to fail safely** |

## Repository Structure

```
.
├── README.md
├── LICENSE                                      # MIT
├── .gitignore
└── skills/
    └── csharp-defensive-programming/
        ├── SKILL.md                             # Main skill content
        └── metadata.json                        # Skill metadata
```

## License

MIT © [cowpy](https://github.com/cowpy)

## Inspirations & Credits

- **cc-defensive-programming** by [ryanthedev](https://github.com/ryanthedev/code-foundations) — theoretical framework (Barricade, Assertion, Correctness vs Robustness, Pattern Reuse Gate).
- **go-defensive** by [cxuu](https://github.com/cxuu/golang-skills) — API boundary 8-step checklist.
- **Code Complete** (McConnell, ch.8) — foundational defensive programming theory.
- **karpathy-guidelines** — behavior layer (think before coding, simplicity first, surgical changes).
