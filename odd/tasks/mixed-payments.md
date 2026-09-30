# Mixed payments — Block 1 / Task 7

## Objective and scope
Allow positive-total sales to have multiple allocations, one per defined PaymentMethod, with positive amounts summing exactly to the discounted Sale.Total. Cash requires ReceivedAmount >= its allocated Amount; noncash requires null tender. Zero totals require no payments. Preserve single-payment and legacy JSON compatibility, notes, discounts, filtering and stock behavior. No fees, tips, refunds, cancellation, processing, reconciliation or database changes.

## Plan and routing
- [x] MP-1: Authoritative service validation for multiple payments, duplicates, exact sums and existing tender rules before mutation. Delegated writer: shared validation and UI require multiple nontrivial files.
- [x] MP-2: POS allocation editor with add/default remaining, edit/remove, live cash change and total/assigned/remaining; invalid raw edits preserve accepted allocations but block checkout; cart/discount changes revalidate. Update Sales.md and IMPLEMENTED_FEATURES.md. Same single writer.
- [x] MP-3: Build, isolated functional checks for all requested cases, persistence/legacy load checks, runtime smoke and independent verification as assessment requires. Delegated verification: command-running trigger.

## Acceptance and checks
Run dotnet build. Verify single-payment compatibility, cash/card, card/transfer, three ways, exact discounted totals, cash-portion change, under/over allocation, duplicate/undefined methods, positive amounts, cash/noncash tender rules, stale cart/discount allocations, JSON reload/legacy defaults, zero-total empty payments, and failure before sale/stock/ID/note mutations. Verify raw invalid input cannot reuse previous valid amounts to checkout. Preserve root data.json; isolate runtime/harness data.

## Workflow configuration
ODD delegated direct; SDD not selected. RDD off (session setting). TDD disabled for this work: no enabling configuration or runner found; ordinary functional checks required, no claimed RED/GREEN cycle. Existing runner: dotnet build; dotnet run for smoke when supported. No repository test project; use an isolated temporary harness without new dependencies if practical.
Delivery: uncommitted working-tree changes; commits pending explicit user request under safety contract. No publishing. Forecast: approximately 300–450 authored changed lines for the coherent allocation behavior and documentation; do not compress or omit checks for line count. No PR requested.

## Progress and evidence
Initial worktree clean on main. Read AGENTS.md and Docs/Architecture/Sales.md before exploration. Scout confirmed existing payment-list persistence and validation-before-mutation ordering. No model/schema change expected.
Engram mirror pending: callable memory tools unavailable.
MP-1, MP-2 and MP-3 complete after independent checks. Writer dotnet build passed (two net7.0 end-of-support warnings); git diff --check passed. Writer did not run harness/runtime because temporary writes were outside its allowed surfaces. Diff: 190 insertions + 111 deletions across four source/documentation files. Native read-only assessment unassessable due to untracked tracking document; returned independent-verifier plan (RDD off). Commit identities: none (not authorized).

## Next step
Implementation and verification complete. No commits or publishing authorized. Browser-rendered/manual responsive testing remains unperformed; component event handlers were exercised by reflection.

## Final verification evidence
Independent verifier ran dotnet build successfully and git diff --check clean. Isolated temporary harness: 59/59 checks passed; covers exact/discounted sums, single/mixed payments, cash change, duplicate/undefined/null/nonpositive entries, tender and overflow rejection, no invalid-checkout mutations, stock deductions, legacy JSON, multi-payment reload, POS raw-input preservation/gating, stale quantity/discount sums, removal, filters/notes and zero-total handling. Fixture locator: OS temp directory tmp.26nrd59nbG; Program.cs and final-run.log retained outside repo. Earlier fixture setup/syntax and incorrect stock expectation were corrected before final pass; no app defect reproduced. Harness emits nullable warnings only in temporary test code.
Runtime smoke started the built app in isolated cwd with repository content root; HTTP returned 302; owned process stopped. Installed runtime required DOTNET_ROLL_FORWARD=Major for smoke. Root data.json SHA-256 unchanged: 1f889a39fd89da611defdaf014025da5febb8180450f4b18956099abebf63b01.
Final parent-directed build spot check via verifier passed: zero errors, two NETSDK1138 warnings (net7.0 end of support). No browser interaction or rendered responsive validation; markup/CSS inspected only. Engram mirror remains pending (tools unavailable).
