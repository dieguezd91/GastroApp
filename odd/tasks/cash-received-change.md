# Cash received and change — ODD task record

## Intent and scope
Implement Block 1 Task 6: nullable cash ReceivedAmount and derived Change, authoritative pre-mutation validation, current-value POS cash tendering, and historical JSON compatibility. Amount remains applied sale total. Cash requires received >= amount; noncash requires null; zero-total sales have no payments. Preserve discounts, notes, quantities, filters and stock behavior. Do not modify cash register reconciliation, data.json or the user's backup.

## Tasks
1. [x] Implement model, service and POS cash tendering as one coherent work unit. Writer build passed; parent diff readback completed.
2. [x] Update Sales architecture and implemented feature documentation. Both requested documents updated with implementation.
3. [x] Build and independently verify requested compatibility, tender, persistence and regression cases. 38 executable harness checks passed; browser checks unavailable (see evidence).

## Routing and checks
- Delegated direct mapping completed; implementation delegated to one bounded writer (multi-file trigger).
- Verification delegated to gentle-ai-verify according to assessment; dotnet build and isolated runtime harness. Browser interaction when available; disclose unavailable checks.
- No Task 6 strict TDD enablement established; prior task records explicit disabled mode. Ordinary functional verification, no claimed RED/GREEN evidence; no repository test project identified.
- Allowed source/doc edits: Models/Sale.cs, Services/SaleService.cs, Pages/Sales.razor, Docs/Architecture/Sales.md, IMPLEMENTED_FEATURES.md.
- Forecast: approximately 180–300 authored changed lines; delivery strategy ask-on-risk.
- RDD off; no native review start.
- User explicitly authorized the implementation commit after verification. Work-unit branch: feat/cash-received-change. Commit subject: feat(pos): support cash received and change.
- Engram mirror pending/unavailable: no callable memory tools.

## Acceptance and evidence
Build; legacy sales load without inferred cash tender; exact/excess cash; missing/invalid/insufficient cash rejected without sale/stock/ID/save mutation; each noncash method works without received amount and rejects tender data; method switching clears stale input; persistence/reload; zero-total no payments; discounted total used; POS notes, quantities, filters and stock behavior preserved.
Initial branch main. Existing modified data.json and untracked data.manual-test.backup.json preserved.

## Verification progress
Writer dotnet build passed: zero errors, two net7.0 end-of-support warnings. Source/doc diff implements cash required >= amount, noncash null, live latest input parsing, method-switch and cart-reset clearing, zero-total ignored tender. Native read-only assessment unassessable due to untracked files; conservative independent verifier required. No native review started.

## Independent verification evidence
- Verifier re-ran dotnet build: passed, zero errors, two NETSDK1138 net7.0 warnings.
- External temporary console harness (`dotnet run --project Verify.csproj` from OS temp) passed 38 checks using actual built SaleService, DataStorageService and compiled POS methods. Covered legacy missing payments/tender, exact/excess/missing/negative/insufficient cash, invalid payment configurations, all noncash methods, save/reload decimals, zero-total, discounts, notes, quantities, stock deductions, comma/dot culture parsing, latest invalid input, switching, current checkout values, filters and cart retention.
- Invalid checkout assertions observed unchanged sale ID/date, notes, sales, stock and file. Private next-ID counter not independently asserted; code inspection places ID allocation after validation.
- Isolated app smoke started/listened and was ended by timeout; static files unavailable in isolated cwd without wwwroot. No rendered browser UI/responsive interaction checks performed.
- git diff --check passed; documentation readback matches implementation.
- User data and backup SHA256 unchanged before/after verifier: prefixes 7a9aba58 and 1f889a39.
- Temporary harness compile/reflection setup errors corrected outside repository; final run passed. No repository tests added or claimed.

## Next step
Implementation and executable checks complete. Rendered browser smoke remains a manual follow-up. User authorized committing this work unit on feat/cash-received-change with subject `feat(pos): support cash received and change`; Git history provides its commit identity. No push/PR authorized. Engram mirror still unavailable.
