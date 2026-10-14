# Cash register sessions and movements

A register is a persisted session, not today's sales total. `DataStorageService.CashRegisters` owns the canonical objects; `CurrentCashRegisterId` selects the open or latest closed session and `CurrentCashRegister` resolves that same object. `CashRegisterService` opens and closes sessions, computes the drawer view through storage, and records the existing daily sales summary separately through `SaleService`.

## Drawer calculation

For a given register ID, expected cash is `InitialAmount + Sale + Income - Expense - Withdrawal`, using only movements with that register ID. `GetCashInflow` sums Sale and Income movements for that register. A movement has a positive amount and a stable ID/type (`Sale=0`, `Income=1`, `Expense=2`, `Withdrawal=3`), timestamp, register ID and optional sale/user/username/reason. Successful cash checkouts create automatic Sale movements; administrators can also append Income, Expense and Withdrawal from `/cash`. Cash applied to the sale, not received tender or change, is counted. Noncash and zero-total checkouts still link to the open register but do not add a movement.

Open and close reject negative amounts, and opening refuses a second open session. Both request an immediate JSON save. Close stores the expected amount and final count on the same session and appends a `DailySummary` whose completed-today sales total/count/top product are **not** drawer inputs. Summary shows the stored closed-session difference separately from current completed sales. Cancelling a sale changes today's completed metrics and restores its exact stock snapshot, but never removes or reverses the original money movement or recomputes a past closed summary. Refunds and reconciliation are out of scope.

## Registered receipts by payment method

`CashRegisterService.GetCurrentPaymentSummary()` derives a detached `CashPaymentSummary` for the canonical current register, **open or closed**. It uses only `Sale.Payments[].Amount` from sales with that exact `CashRegisterId`. All six methods appear in enum order (including zero), followed by `RegisteredTotal`. Dates, completed/cancelled status, tender, change, initial funds and manual movements are not aggregation inputs. Cancelled receipts remain registered: cancellation is not a refund. Completed daily sales and available drawer cash retain their separate contracts above.

The query never persists derived totals or mutates sales, counters, sessions or movements. The summary, rows and warnings have getter-only properties; both collections are detached read-only copies. Decimal precision follows existing sale calculations without rounding. Numeric amounts are nullable specifically to distinguish unavailable results from valid zero receipts.

### Completeness and messages

| `State` | Numeric values | Spanish UI meaning |
|---|---|---|
| `NoSession` | Six zeros and total zero | “Sin sesión de caja seleccionada”; no attribution. Global warnings can still appear. |
| `Complete` | All valid selected-session receipts, including zero | “Resumen completo para esta sesión.” |
| `Partial` | Valid selected-session sales only | “Resumen parcial: revisá las advertencias.” Invalid sales are excluded whole; global gaps also prevent claiming completeness. |
| `Unavailable` | All six amounts and total **null** | “Resumen no disponible”; decimal overflow suppresses every numeric total, not just the overflowing row. |

Warnings expose a typed `Reason`, `Count`, Spanish `Message` and `IsGlobal`. Each excluded sale reports its first detected reason; counts group those reasons, not individual allocations. An aggregate overflow counts the sale that triggered it. `Unavailable` takes priority over partial warnings; validation continues to report other gaps.

| Warning reason | Meaning / message content |
|---|---|
| `UnlinkedHistoricalSales` | **Global** historical sales without a register link, never attributed by date or guessed tender. They do not add amounts to this session. |
| `UnattributedInvalidSales` | **Global** null sale records with no identifiable session. |
| `InvalidSaleItems` | Null/empty item list, null item, nonpositive quantity, negative price or invalid line/sale discount; the total cannot be trusted. Current catalog eligibility is not rechecked for history. |
| `InvalidPayments` | Null collection/allocation, unknown or duplicate method, nonpositive amount. |
| `MissingPayments` | Positive-total sale with no payments. |
| `AllocationMismatch` | Allocations do not equal the model's final discounted total exactly; zero-total sales must have an empty payment list. |
| `ArithmeticOverflow` | Sale-total calculation, allocation sum, method aggregate or registered total exceeded decimal capacity; **all totals unavailable**. |

Receipt validation lives in the cash service, reusing discount rules and model monetary properties, not Razor formulas or checkout tender validation. Missing, insufficient or otherwise malformed historical tender is ignored, including tender on noncash methods. A valid zero-total sale with an empty payment list is complete. An invalid selected sale contributes **none** of its payments even if an earlier allocation was valid. Invalid sales linked to other registers do not affect the selected session; unlinked warnings intentionally cover the entire stored sales collection.

The Admin `/cash` section is titled **Cobros registrados por medio de pago**. It displays all rows and the total, explicit completeness feedback, and warning messages/counts. Opening metadata identifies the current open or closed session. Each render resolves the current canonical pointer and recalculates the summary, so navigation, rerender and existing local cash callbacks use fresh values without changing manual-entry or close behavior. No polling or new cross-circuit broadcasts are added; another circuit's changes become visible at the next existing render/navigation, not through a new real-time guarantee.

## Manual movement boundary

`CashRegisterService.AddManualMovement(type, amount, reason, actor)` owns manual entries. It accepts only Income, Expense and Withdrawal, a positive decimal amount, a required trimmed reason and the current canonical open session. Expense and Withdrawal cannot exceed that session's available expected cash; spending exactly the available balance is allowed. There is no new rounding rule.

The Spanish `/cash` form resolves a fresh actor from its scoped `AuthService` and rechecks Admin on every click, not just page initialization. The singleton cash service never captures authentication state. At the trusted in-process command boundary it independently validates the actor against the live stored user: positive ID, nonblank username/password hash, matching username and password hash, and Admin role on both actor and canonical user. This is not a credential-authenticating public API; a future remote entry point needs its own authentication boundary. See [Authentication.md](Authentication.md).

Before allocating an ID or changing state, the command checks the expected-balance arithmetic, the gross Sale + Income inflow for an Income entry, and movement-counter capacity. Gross inflow can overflow even when withdrawals leave expected cash small. Rejection changes neither ledger nor counters and requests no save. After validation, the server constructs ID, local timestamp, current session ID and canonical responsible-user snapshots, sets `SaleId = null`, appends once and requests the existing `SaveToFile`. The command offers no editing or deletion of previous rows.

`GetCurrentMovements()` returns a read-only collection of detached copies for the current session, including automatic Sale entries and a current closed session. Mutating a returned model cannot change historical ledger objects. With no session it returns an empty collection. Existing storage collections and `GetCurrent()` retain their older mutable contracts; this is not a global immutability redesign.

The page lists ID, date, Spanish type, signed amount, responsible snapshot, reason and optional sale ID. Missing legacy responsible/reason fields display explicit fallbacks rather than invented audit data. Successful submission clears amount/reason, confirms the entry and rerenders balance and ledger in the submitting circuit without a reload. Invalid raw decimal text cannot reuse an earlier accepted amount; Spanish errors retain the form values for correction. No cross-circuit refresh broadcast is introduced.

## JSON compatibility and identity

JSON persists `CashRegisters`, `CashMovements`, `CurrentCashRegisterId`, `NextCashRegisterId`, and `NextCashMovementId`. Loading recovers register, movement, and sale next counters from the larger of their saved values and the maximum existing IDs plus one. Duplicate/nonpositive IDs, exhausted IDs/counters, null session or movement entries, invalid movement references or types, multiple open sessions, or a pointer to a nonexistent session fail loading clearly instead of silently reassigning linked identities. A legacy file containing only `CurrentCashRegister` imports that one session (ID 1 when the old field had no ID or ID 0); negative IDs fail and positive IDs are preserved. Canonical sessions with ID 0 are never repaired. If `CashRegisters` is present, it wins even when empty; the old object is never imported again. Missing pointer selects the open session or the latest closed session by opening date (then ID). Repeated loads replace these collections rather than duplicating imported sessions. Historical sales without `CashRegisterId` remain null: no link, tender, or movement is guessed from old sales or old expected-cash values.

## Limits

This is single-process, prototype-level JSON persistence. `SaveToFile` logs write failures rather than guaranteeing disk durability; ingredient deductions may perform intermediate saves before the final sale/snapshot/movement save. Failed deduction leaves earlier writes and an unreliable sale snapshot, but no cash movement. Mutable shared collections have no locking or transaction rollback; callers must not infer durable atomic checkout from a normal return. Manual entry uses the same logged-save-failure mechanism: UI confirmation acknowledges in-memory registration, not guaranteed disk durability. Concurrent validation and writes are not atomic. Refunds, ledger editing/deletion, session-history browsing and advanced reconciliation remain out of scope.

## Verification

Run from the repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-payment-summary.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-cash-movements.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-auth-isolation.ps1
dotnet build
```

The dependency-free payment harness checks six individual methods, zero/mixed/discounted/precise receipts, Amount versus tender, session identity/dates, global historical warnings, whole-sale rejection, all overflow paths, cancelled receipts, manual/initial exclusions, read-only nonmutation, save/reload, closed/current-pointer lifecycle and render-tree refresh. It uses a new retained OS-temp fixture and checks the authorized live project/data hashes before and after. It does not prove real browser layout, accessibility or cross-circuit rendering; those remain independent browser verification work.

The dependency-free cash harness references the application in a retained OS-temp fixture; storage construction and JSON reads/writes run only in that scratch working directory. It checks signs, exact cash caps, actor/session/input rejection, both overflow paths, counter exhaustion, rejection without mutation, detached projections, audit and ID reloads, legacy JSON, direct component callbacks and sale/cancellation/close regressions. Both live project/data hashes are checked before and after. Direct callbacks and source assertions do not prove browser rendering: independently verify the form, responsive ledger, success/error display and two-circuit behavior in an isolated browser fixture.
