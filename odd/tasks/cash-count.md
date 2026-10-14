# Block 2 — Advanced cash count (arqueo)

## Objective and constraints
Replace the manual final amount on `/cash` with a detailed, auditable physical cash count integrated into the existing close. Admin-only, revalidated in the singleton service with the circuit actor. Preserve `Difference = FinalAmount - ExpectedAmount`, DailySummary generation, JSON compatibility (historical registers without a count load unchanged, no invented audit), scoped auth vs singleton business separation. No compensating movements, no changes to sales/payments/cancellation/manual movement rules, no session history, refunds, bank reconciliation, framework change, new dependencies, `data.json` edits, commit or push. Preserve the pre-existing uncommitted `GastroApp.csproj` (net8.0) change.

## Design
- Models: `CashCountLine` (Denomination decimal, Quantity int, Subtotal decimal), `CashCount` (CashRegisterId, CountedAt, UserId, Username, Lines, ExpectedAmount, CountedAmount, Difference, Reason?), `CashCountReview` (RegisterId, ExpectedAmount, LastMovementId, MovementCount) as a stale-detection token, `CashCountRequest` (review + raw lines + reason + Confirmed + ZeroCountConfirmed), `CashCountPreview` (calculated lines/total/difference/outcome Exact|Surplus|Shortage).
- Storage: new `CashCounts` collection keyed by stable register ID, saved and loaded in `LoadCashState`; missing property = empty; invalid/duplicate/orphan/open-register/inconsistent counts fail loading. `DailySummary` gains nullable `CashRegisterId` (legacy null).
- Service: `GetCountReview()`, `PreviewCount(lines, expected)`, `Close(CashCountRequest, User? actor)` replaces `Close(decimal)` so no unvalidated close path remains; `GetCount(registerId)` detached copy. All validation (actor, open/current register, duplicates, lines, overflow, reason, confirmations, stale review) before any mutation; then one mutation block and one save. Throws `CashCountReviewOutdatedException` (InvalidOperationException) on stale review.
- UI: count rows (denomination/quantity text inputs, subtotal), totals, expected (reviewed snapshot), visible difference label, reason, review step + explicit confirmation (+ zero confirmation), stale detection message forcing re-review, closed-session registered count view and historical fallback.

## Tasks
- [x] COUNT-1: Models, storage, service close/preview/query + deterministic harness `scripts/verify-cash-count.ps1`; adapt existing harness `Close` calls.
- [x] COUNT-2: `/cash` Spanish UI for count, confirmation, stale review and closed view; UI callback checks.
- [x] COUNT-3: English docs `Docs/Architecture/CashRegisters.md`, `IMPLEMENTED_FEATURES.md`.
- [x] COUNT-4: Independent verification: `dotnet build`, `git diff --check`, all harnesses, browser desktop/mobile when possible.

## Evidence
- COUNT-1 (gentle-ai-worker): RED = verify-cash-count.ps1 compile failure on missing CashCounts/GetCount/CashRegisterId. GREEN: cash-count 167/0, cash-movements 87/0, auth-isolation 255/0, payment-summary 101/0; build 0 warnings/errors; diff --check clean; live csproj/data hashes unchanged. Shared rules in Models/CashCountCalculator.cs; Close(decimal) removed. No commit (user forbids).
- COUNT-2 (gentle-ai-worker): /cash arqueo card, two-step confirmation, stale-review alert/adoption, closed-session "Arqueo registrado" and historical fallback; stays on /cash with link to /summary after close (decision: show the registered count instead of navigating away). Count errors render inside the card (`countError`). cash-count 242/0, cash-movements 87/0, auth 255/0; build clean; diff --check clean. Browser not yet run.
- COUNT-4 (gentle-ai-verify): build 0/0; diff --check clean; harnesses cash-count 242/0, cash-movements 87/0, auth 255/0, payment-summary 101/0; live csproj/data hashes 190890656d669c27c178fc53dfc526a9a184e818 / 0f8def10c364036b406c8d225f8e5fa059b26954 unchanged. Verifier found: second admin's rejected confirm invisible after another admin closed (countError only rendered in open branch). Parent fixed in Pages/Cash.razor (alert rendered when register not open). Browser rerun (Chrome/CDP, two contexts, OS-temp fixture %TEMP%/gastro-count-browser-YdSrqr): 16/0 including subtotals/total, Sobrante/Faltante/Exacto, reason gate, zero checkbox, stale alert without close, Arqueo registrado card, visible rejection, 390x844 no overflow, restart persistence. Post-fix parent rerun of the three regression harnesses 87/0, 255/0, 101/0.
- Native review: inspect stopped at managed_assets_outdated (gentle-ai sync not run; tooling outside app scope). No commit/push per user instruction.

## Delivery
User authorized the commit after verification: `feat(cash): close register through audited cash count` on fix/authentication-circuit-isolation; resolve identity with git log --format=%H --grep='feat(cash): close register through audited cash count' -1. Pre-existing GastroApp.csproj net8 change excluded. No push.
