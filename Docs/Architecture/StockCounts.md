# Physical stock counts

Implements S4 (physical counts compared with the registered stock and confirmed), the count side of S10 (no negative stock from manual operations, visible warning for existing negative balances) and S12 (every exception has a reason and a responsible user) of the M15 module. Ingredient stock and the ledger rules are owned by `IngredientService` (see `Stock.md`); a count never writes stock itself.

## Ownership

| Piece | Responsibility |
|---|---|
| `Models/StockCount.cs` | `StockCount` / `StockCountLine` persisted records, request and preview types, `StockCountLabels` (Spanish `Faltante` / `Sobrante` / `Sin diferencia`). |
| `Services/StockCountService.cs` | Singleton. `Preview`, `Confirm`, `GetHistory`, `GetDetail`. |
| `DataStorageService` | `StockCounts` list, `_nextStockCountId` (`NextStockCountId` in JSON), count id allocation/rollback and load validation. |
| `IngredientService.ApplyCountAdjustments` | Validates and applies the differences as `CountAdjustment` movements carrying the count id (all-or-nothing). |
| `Pages/StockCount.razor` | `/stock/count` and `/stock/count/{CountId:int}`, admin only; NavMenu link **Conteo de stock**. |

## Persisted record

`StockCount`: `Id`, `Date`, `UserId`, `Username` (live admin snapshot), optional trimmed `Notes`, `Lines` and `AdjustedLineCount` (lines with a difference, that is, lines that created a movement). A line is a snapshot: `IngredientId`, `IngredientName`, `Unit`, `ExpectedStock` (registered stock at confirmation), `CountedStock`, `Difference = CountedStock − ExpectedStock` and `Reason` (mandatory when the difference is not zero, otherwise `null`). Counts are never edited or deleted. A count with no difference is still recorded (it proves the shelf was checked) and creates no movement.

## Preview

`Preview(lines)` takes `StockCountLineInput { IngredientId, CountedStock }` and returns, in request order, `ExpectedStock` (current registered stock), `CountedStock`, `Difference`, `Kind` (`Shortage` / `Surplus` / `Match`) and `HasNegativeStock` (the registered stock was already negative, shown as a warning). It never mutates storage, counters or `data.json`. It rejects an empty list, a null line, a repeated or unknown ingredient, a missing counted value and a negative counted value.

## Confirm

`Confirm(request, actor)` validates in this order, and any failure leaves counts, movements, stock, counters and `data.json` unchanged:

1. Live administrator (`RequireLiveAdmin`, `UnauthorizedAccessException` otherwise).
2. At least one line; `Confirmed` is true (explicit confirmation).
3. Per line: ingredient exists and is not repeated; counted value present and `>= 0` (S10: counting never produces negative stock); the `ExpectedStock` the operator saw is present and equals the **current** stock, otherwise `El stock cambió desde que se inició el conteo; vuelva a calcular.` (`StockCountService.StaleStockMessage`); a non-blank reason when the difference is not zero; the difference does not overflow.

Stale detection covers the simultaneous case: if another operation (sale, receipt, adjustment, another count) moved the stock after the preview, nothing is applied and the operator must run `Preview` again.

The mutation is one operation under a service lock: the count is appended to `StockCounts` (id allocated), `ApplyCountAdjustments(count.Id, lines, admin)` creates one `CountAdjustment` movement per line with a difference (previous and resulting stock, reason, responsible, `StockCountId`) and saves once. If it throws, the count is removed and its id counter restored (`DiscardStockCount`), so no count is left behind. A count without differences creates no movement, so the service saves once itself. `Confirm` returns a detached copy; `GetHistory()` (newest first) and `GetDetail(id)` return detached copies and never mutate.

## Persistence and loading

`SaveToFile` writes `StockCounts` and `NextStockCountId`. Loading never writes. A file without `StockCounts` is a legacy file and loads as an empty list; an explicit `null`, a null entry or any inconsistency throws `InvalidDataException`: duplicate or non-positive id, missing responsible, no lines or a null/duplicate/invalid line (blank name or unit, negative counted stock, difference different from counted − expected, difference without reason), `AdjustedLineCount` different from the lines with difference, or a count whose adjusted lines do not match its `CountAdjustment` movements (same ingredient, quantity, previous and resulting stock, and no extra movement). The reverse is deliberately not required: movements that reference a count id with no persisted record (written before counts existed) still load, and their ids are reserved so `NextStockCountId` is at least the largest referenced count id plus one.

## Page flow (`/stock/count`)

1. Choose ingredients: filter by name, only low stock (`stock <= minimum`), **Seleccionar todos los activos**, **Seleccionar los visibles**, **Limpiar selección**. Inactive ingredients are listed (marked) and can be counted manually. Existing negative stock shows a visible warning.
2. Type the counted quantity (current-culture decimal). **Comparar** calls `Preview` and shows registered, counted, signed difference and the word `Faltante` / `Sobrante` / `Sin diferencia` (never only color), plus one required reason field per difference.
3. Optional notes, the confirmation checkbox and **Confirmar conteo**. Changing the selection or a quantity drops the comparison (`Invalidate`) and the page re-checks it again on confirm. A stale stock refreshes the registered values, drops the comparison and shows the recount message.
4. Success navigates to `/stock/count/{id}` without forcing a reload. The detail lists lines, differences, reasons, responsible and links each ingredient to `/ingredients/{id}/movements`. The list of past counts links to the same detail.

Every callback (`OnParametersSet`, compare, confirm, selection helpers, detail navigation) calls `EnsureAdmin` first (anonymous → `/login`, employee → `/unauthorized`) and nothing is loaded or changed otherwise; the service revalidates the live administrator on `Confirm`.

## Verification

`scripts/verify-stock-count.ps1` (scratch directory under the OS temp, live `data.json`/`GastroApp.csproj` hashed before and after) covers preview without mutation, confirm with movements linked to the count, lines without difference, every rejection with objects/counters/bytes unchanged (including ledger exhaustion rollback), reload persistence, legacy JSON, corrupt-file rejection and renderer-less page callbacks.
