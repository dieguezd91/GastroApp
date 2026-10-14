# Block 2 — Manual cash movements

## Objective and constraints
Admin-only Income/Expense/Withdrawal on current open session: positive decimal, mandatory trimmed reason, fresh circuit actor, server-owned ID/date/session/responsible; immediate balance/list. Preserve Initial + Sale + Income - Expense - Withdrawal, historical JSON and append-only command behavior. Reject insufficient funds, overflow and exhausted IDs before mutation. No scoped AuthService capture, dependencies, unrelated refactors, live data edits, commits or push. Preserve auth ec4c9ea and user net8 csproj change.

## Tasks
- [x] CASH-1: Service command/detached query, Spanish /cash UI, English docs and deterministic tests. Delegated gentle-ai-worker (multi-file trigger), self-checks passed.
- [x] CASH-2: Independent deterministic and real browser verification. Delegated gentle-ai-verify (independent/external trigger), scoped acceptance checks passed; extended coverage pending below.

## Implementation
Six feature files: Services/CashRegisterService.cs, Pages/Cash.razor, Docs/Architecture/CashRegisters.md, IMPLEMENTED_FEATURES.md, scripts/verify-auth-isolation.ps1, scripts/verify-cash-movements.ps1. AddManualMovement validates input/current session/canonical live actor/funds/expected and gross-inflow overflow/capacity before allocation/append/save. GetCurrentMovements returns detached read-only copies, including Sale and legacy nullable audit fields. UI resolves current scoped actor at click, parses decimal safely and shows Spanish validation/confirmation. Existing sales/model/storage behavior unchanged.

## Executed checks
Writer RED: missing command/query 2 failures before source; GREEN 81 then 87 cash checks. Independent repeat: 87 cash and 255 auth checks, zero failures; dotnet build zero warnings/errors; git diff --check passed (line-ending advisory only).
Actual two Admin Chrome/CDP contexts plus Employee/anonymous against fresh OS-temp cwd fixture: access denial, all movement signs/balances (130/125/110), Spanish invalid zero/negative/malformed/reason/funds errors with byte-identical rejected state, immediate list/confirmation, actor IDs 4/4/5 without mixing, legacy audit fallbacks. Reload and actual server restart retain ledger and recover next ID 5 while requiring login. Mixed checkout applied cash 50/tender100/change50/debit100 creates movement50. Cancellation actor4 leaves ledger intact; close expected161/count160. Prefilled stale form after other Admin closes rejects with unchanged fixture. IDs unique, session1 association. Responsive DOM smoke 390x844 no page overflow, table scroll local. Final ALL BROWSER CHECKS PASSED; server/browser stopped. Earlier scratch driver assumptions corrected; not application defects.
Data/csproj hashes unchanged: 0f8def10c364036b406c8d225f8e5fa059b26954 / 190890656d669c27c178fc53dfc526a9a184e818. No live app startup/dependency installation/commit/push.
Evidence: OS-temp gastro-cash-browser-l3iols/verify.cjs, verification.log and final-observations.json; cash harness gastro-cash-180575dcd7a0477584d450c18ef589fa; auth harness gastro-auth-4680dc4b206b47cb94e46a10401fd01a.

## Review and limitations
Native ASSESS initially unassessable (untracked declaration); independent verifier ran. INSPECT with cash harness selected stopped managed_assets_outdated; no lineage or approval. Tooling sync not executed in this application scope. Existing logged-save-failure/nontransactional shared-state limits persist. Other circuits update on rerender/navigation, no shared refresh broadcast. Browser overflow/ID exhaustion/live identity changes not executed (deterministic checks cover them); reconnect, alternate decimal cultures and concurrency stress not executed. Responsive check is layout smoke, not visual screenshot review.

## Delivery and next step
The user subsequently authorized a commit after payment-method totals were implemented. Both cash features share edited surfaces and are committed together with tests/docs; the pre-existing GastroApp.csproj change is excluded. No push authorized. Resolve identity with git log --format=%H --grep='feat(cash): add manual movements and payment summaries' -1. Earlier no-commit statements describe the implementation phase. Human review and optional tooling maintenance/native review remain pending. Payment-method totals are implemented in the separate payment-method-totals task document.
