---
name: code-complexity-governor
version: 1.0.0
description: 强制管控代码圈复杂度、分支、条件、返回路径、嵌套层级，所有代码生成/重构/评审自动校验，跨IDE/LLM工具通用
tags: code-quality, complexity, refactor, code-review
scope: 所有业务逻辑函数/方法，排除测试、迁移、自动生成代码
severity_rule:
  CRITICAL: 必须重构，禁止合入/交付
  MAJOR: 建议重构，需注释豁免并团队评审
  MINOR: 可读性优化建议
---

# 1. Function & Method Complexity Rules

## Hard Thresholds（CRITICAL违规，必须整改）
1. Single method valid code lines ≤ 40（不含空行、注释、大括号）
2. Cyclomatic complexity ≤ 8
3. Max control flow nesting depth ≤ 3（if/for/while/try嵌套，超过3层强制扁平化）
4. Single if condition logical operators (&& / ||) ≤ 3

## Return Path Standard（MAJOR违规）
1. Multiple guard-clause returns are allowed for readability
2. If return statements count > 4 → mark as major refactor requirement
3. Ban scattered returns inside long methods; gather edge-case guards at method top
4. Void method without return is unlimited; only count explicit `return value;`

## Single Responsibility Requirement
- Every function must do one clear thing; mixed responsibilities split into helpers
- When adding new business logic:
  1. First check if current method already exceeds any complexity threshold
  2. If new code increases nesting/branches/duplication, refactor existing method first
  3. Do NOT inject extra logic into oversized methods unless no safe alternative + add `// ComplexExempt: Business special case` annotation with team review

# 2. If & Condition Readability Rules
1. Never pack >3 independent logical checks in one single if expression
   Bad: if (user.Active && order.Paid && stock.Available && api.Health)
   Good: Extract boolean variable / small helper method
2. Name extracted condition with intent-based names: `IsUserOrderValid`, `HasEnoughStock`, `ShouldTriggerRetry`
3. Avoid mixing unrelated business rules in one combined condition; split by business domain

# 3. Refactoring Mandatory Checklist
Before finalizing code changes, self-verify all items:
- [ ] No method crossed line / cyclomatic / nesting hard limit
- [ ] No if statement with over 3 &&/|| logic conditions
- [ ] No scattered returns inside long functions; guard clauses centralized top
- [ ] No duplicated logic extracted to shared helper
- [ ] Variable/method names describe intent, not implementation details
- [ ] If return paths >4, split sub-logic into private helper methods

# 4. Skill Execution Flow（所有AI工具统一执行逻辑）
1. When generating new code: auto comply all thresholds, never output violating code
2. When refactoring existing code: first list all complexity violations + provide rewritten clean version
3. When running code review: classify each issue by severity, give exact line + refactor sample
4. When user asks to add logic to an over-complex method: block direct modification, output refactor plan first

# 5. Exemption Mechanism
Only allow bypass rules when all satisfied:
1. Mark method header annotation: `// ComplexRuleExempt: [reason text]`
2. Record PR/CR comment with team member approval
3. Limit exempt methods to core orchestration logic only, ban business CRUD exempt

# 6. Related Skills
- **csharp-defensive-programming** — defensive error handling and validation
- **dotnet-best-practices** — naming, LINQ, DI, performance guidelines
- **modern-csharp-coding-standards** — records, pattern matching, Span/Memory