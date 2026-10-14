# Cash register sessions and movements

A register is a persisted session, not today's sales total. `DataStorageService.CashRegisters` owns the canonical objects; `CurrentCashRegisterId` selects the open or latest closed session and `CurrentCashRegister` resolves that same object. `CashRegisterService` opens and closes sessions, computes the drawer view through storage, and records the existing daily sales summary separately through `SaleService`.

## Drawer calculation

For a given register ID, expected cash is `InitialAmount + Sale + Income - Expense - Withdrawal`, using only movements with that register ID. `GetCashInflow` sums Sale and Income movements for that register. A movement has a positive amount and a stable ID/type (`Sale=0`, `Income=1`, `Expense=2`, `Withdrawal=3`), timestamp, register ID and optional sale/user/username/reason. Successful cash checkouts create automatic Sale movements; administrators can also append Income, Expense and Withdrawal from `/cash`. Cash applied to the sale, not received tender or change, is counted. Noncash and zero-total checkouts still link to the open register but do not add a movement.

Open rejects a negative amount and a second open session; close rejects invalid counts. Both request an immediate JSON save. Close requires a detailed cash count (see [Cash count (arqueo) and close](#cash-count-arqueo-and-close)); it stores the expected amount and the counted total as the final amount on the same session, stores the count itself, and appends a `DailySummary` whose completed-today sales total/count/top product are **not** drawer inputs. Summary shows the stored closed-session difference separately from current completed sales. Cancelling a sale changes today's completed metrics and restores its exact stock snapshot, but never removes or reverses the original money movement or recomputes a past closed summary. Refunds and reconciliation are out of scope.

## Cash count (arqueo) and close

Closing a session requires a detailed physical count; no manual final amount or unvalidated close path exists (`Close(decimal)` was removed). `CashRegisterService.Close(CashCountRequest, actor)` is the only close.

### Line rules

`CashCountCalculator` is the single owner, shared by `PreviewCount`, `Close` and JSON loading. A line has a positive decimal denomination, a non-negative integer quantity and `Subtotal = Denomination × Quantity`. Denominations cannot repeat by decimal value (`1000` and `1000.00` collide); at most 100 lines are accepted. Arithmetic is checked: subtotal, total or difference overflow is rejected (“El conteo supera el límite permitido.”). An empty list or all-zero quantities count as zero. `PreviewCount(lines, expected)` is pure, returning detached read-only lines, counted/expected/difference and an `Exact | Surplus | Shortage` outcome.

### Review token and stale detection

`GetCountReview()` (open current session only) returns a value-equality record: register ID, expected amount (from the session movements, never from the UI), movement count and last movement ID. Any new movement changes it, so an Income of X followed by an Expense of X is detected even though the expected balance is unchanged. `Close` recomputes the token and throws `CashCountReviewOutdatedException` (an `InvalidOperationException` carrying `Current`) when it differs. The page keeps its snapshot until the user presses **Actualizar saldo esperado**, or until a stale `CloseCash` adopts `Current`; either way it leaves the confirmation step and requires a new review.

### Close contract

Validation order: non-null request; live Admin actor (same helper as manual movements: stored ID/username/password hash and Admin role on actor and stored user, `UnauthorizedAccessException` otherwise); current register exists, is open, matches `Review.RegisterId` and has no count; stale check; line validation and totals; reason; zero confirmation; `Confirmed`. A nonzero difference needs a non-blank trimmed reason; a counted amount of zero needs `ZeroCountConfirmed`; `Confirmed` must be true. Top product and today's totals are computed before mutating. A single mutation block then sets `FinalAmount`, `ExpectedAmount`, `IsOpen = false` and `CloseDate`, appends the `CashCount` (same timestamp, stored user ID/username, detached lines, trimmed reason or `null`) and the `DailySummary` (now with `CashRegisterId`), and requests one `SaveToFile`. Every rejection leaves registers, movements, counts, summaries, counters and persisted bytes unchanged. No compensating movements are created, `Difference = FinalAmount − ExpectedAmount` is unchanged, and sales, payments, cancellation and manual-movement rules are untouched.

### Stored count

There is one `CashCount` snapshot per closed register in `DataStorageService.CashCounts`: register ID, `CountedAt`, user ID/username, lines, expected, counted, difference and optional reason. `DailySummary.CashRegisterId` links the summary to its session and is `null` for legacy summaries. `GetCount(registerId)` returns a detached deep copy, or `null` for historical registers without a count.

Loading rejects with `InvalidDataException`: explicit `CashCounts` null, a null entry, null `Lines` or a null line, an unknown or duplicate register ID, a count on an open register, an invalid line (denomination ≤ 0, negative quantity, duplicate denomination, wrong subtotal), `CountedAmount` different from the sum of subtotals, `Difference` different from counted − expected, or a mismatch with its register (`FinalAmount` ≠ counted or `ExpectedAmount` ≠ expected). Arithmetic is checked. A missing property is an empty list, and closed registers without counts stay valid. Repeated loads replace the collection.

### Page flow

The **Arqueo y cierre de caja** card has denomination/quantity text rows (current-culture parsing; blank rows ignored; partial or unparseable rows show inline errors), a per-row subtotal from `PreviewCount`, **Total contado**, the reviewed **Esperado en caja**, a **Faltante**/**Sobrante**/**Exacto** difference label and a reason field marked mandatory when the difference is nonzero. Razor only parses raw text. **Revisar cierre** rechecks the circuit Admin, rows, reason and staleness, then shows a confirmation panel with a required “Confirmo que el efectivo contado es cero” checkbox when the count is zero; **Confirmar cierre definitivo** calls `CloseCash`. Any edit leaves the confirmation step. Count-flow errors use a dedicated `countError`, rendered inside the card; `cashError` remains for open/movement errors. Success stays on `/cash`, clears the form, shows “Caja cerrada. Arqueo registrado.” and links to the day summary without a forced reload. A closed current session shows **Arqueo registrado** (responsible, date, expected, counted, labelled difference, reason or “Sin motivo (cierre exacto)”, denomination breakdown). A historical closed register shows “Esta caja se cerró sin arqueo detallado.” with only its stored expected/final/difference, and no invented responsible or breakdown.

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

JSON persists `CashRegisters`, `CashMovements`, `CashCounts`, `CurrentCashRegisterId`, `NextCashRegisterId`, and `NextCashMovementId`. Loading recovers register, movement, and sale next counters from the larger of their saved values and the maximum existing IDs plus one. Duplicate/nonpositive IDs, exhausted IDs/counters, null session or movement entries, invalid movement references or types, multiple open sessions, or a pointer to a nonexistent session fail loading clearly instead of silently reassigning linked identities. A legacy file containing only `CurrentCashRegister` imports that one session (ID 1 when the old field had no ID or ID 0); negative IDs fail and positive IDs are preserved. Canonical sessions with ID 0 are never repaired. If `CashRegisters` is present, it wins even when empty; the old object is never imported again. Missing pointer selects the open session or the latest closed session by opening date (then ID). Repeated loads replace these collections rather than duplicating imported sessions. Legacy files without `CashCounts` load with an empty list, and `DailySummary.CashRegisterId` stays null for legacy summaries. Historical sales without `CashRegisterId` remain null: no link, tender, or movement is guessed from old sales or old expected-cash values.

## Limits

This is single-process, prototype-level JSON persistence. `SaveToFile` logs write failures rather than guaranteeing disk durability; ingredient deductions may perform intermediate saves before the final sale/snapshot/movement save. Failed deduction leaves earlier writes and an unreliable sale snapshot, but no cash movement. Mutable shared collections have no locking or transaction rollback; callers must not infer durable atomic checkout from a normal return. Manual entry uses the same logged-save-failure mechanism: UI confirmation acknowledges in-memory registration, not guaranteed disk durability. Concurrent validation and writes are not atomic. The stale-review check is optimistic and in-process, not a lock: validation and the close mutation are not atomic against concurrent writers, and nothing is pushed across circuits; another circuit sees the stale alert on its next render or when it confirms. Refunds, ledger editing/deletion, session-history browsing and advanced reconciliation remain out of scope.

## Verification

Run from the repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-payment-summary.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-cash-movements.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-cash-count.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-auth-isolation.ps1
dotnet build
```

The dependency-free payment harness checks six individual methods, zero/mixed/discounted/precise receipts, Amount versus tender, session identity/dates, global historical warnings, whole-sale rejection, all overflow paths, cancelled receipts, manual/initial exclusions, read-only nonmutation, save/reload, closed/current-pointer lifecycle and render-tree refresh. It uses a new retained OS-temp fixture and checks the authorized live project/data hashes before and after. It does not prove real browser layout, accessibility or cross-circuit rendering; those remain independent browser verification work.

The dependency-free cash harness references the application in a retained OS-temp fixture; storage construction and JSON reads/writes run only in that scratch working directory. It checks signs, exact cash caps, actor/session/input rejection, both overflow paths, counter exhaustion, rejection without mutation, detached projections, audit and ID reloads, legacy JSON, direct component callbacks and sale/cancellation/close regressions. Both live project/data hashes are checked before and after. Direct callbacks and source assertions do not prove browser rendering: independently verify the form, responsive ledger, success/error display and two-circuit behavior in an isolated browser fixture.

The cash-count harness uses the same retained OS-temp fixture and live-hash guard. It checks line rules and overflow, exact/surplus/shortage closes, reason and confirmation rules, actor/session rejection without mutation, stale detection (including +X/−X), two-admin attribution, save/reload, legacy and corrupted `CashCounts` JSON, record consistency, payment/sale regressions and renderer-less `/cash` callbacks. Direct callbacks do not prove browser layout.
