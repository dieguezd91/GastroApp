# Ingredient stock ledger, adjustments, history and alerts

Stock is an append-only ledger. `Ingredient.CurrentStock` is the running balance and `DataStorageService.StockMovements` (persisted in `data.json` with `NextStockMovementId`) records why it changed. `IngredientService` owns every rule; pages only collect inputs and show the service errors in Spanish next to the field.

## Movement model

A `StockMovement` has a stable `Id`, `IngredientId`, `Date`, `Type`, a **signed** `Quantity` in the ingredient unit (`Unit`, a snapshot), `PreviousStock`, `ResultingStock` (`ResultingStock = PreviousStock + Quantity`), an optional `Reason`, a `WasteCategory` (only for waste), the responsible user snapshot (`UserId`, `Username`, both null when the operation had no authenticated actor) and the origin link (`SaleId`, `RefundId`, `InvoiceId`, `StockCountId`). Movements are never edited or deleted; `GetMovements` returns detached copies.

| Type (persisted value) | Sign | Origin | Reason |
| --- | --- | --- | --- |
| `InvoiceReceipt` (0) | + | invoice | no |
| `SaleConsumption` (1) | − | sale | no |
| `SaleCancellationReturn` (2) | + | sale | cancellation reason |
| `RefundReturn` (3) | + | sale and refund | refund reason |
| `Adjustment` (4) | ± | manual | mandatory |
| `Waste` (5) | − | manual, with `WasteCategory` | mandatory |
| `CountAdjustment` (6) | ± | stock count | mandatory |
| `InitialStock` (7) | + | opening balance of an ingredient created before the rule below (legacy, never written again) | no |

Numeric values are persisted: never reorder. `InitialStock` (label **Stock inicial**, origin **Alta del ingrediente**) is kept only so movements already stored stay readable. Spanish labels live in `StockMovementLabels`. Waste categories (independent from sales): Vencimiento, Rotura o derrame, Error de preparación, Otro.

## Single mutation path

`CurrentStock` is only written by `IngredientService.Commit`, after `Prepare` validated a whole batch without mutating anything: unknown ingredient, incompatible unit, zero or wrongly signed quantity, missing reason or category, overflow, exhausted IDs and a decrease below zero are rejected, leaving objects, counters and `data.json` bytes unchanged. `Commit` cannot fail after `Prepare`; the caller saves once. `IngredientService.Add` creates an ingredient **without stock**: a non-zero `CurrentStock` is rejected with `Un ingrediente nuevo se crea sin stock: el stock ingresa con las facturas de compra.`, leaving ingredients, ledger, counters and `data.json` unchanged, and the create form has no stock field (it links to `/invoices`). Stock enters through invoice receipts (purchases) and, afterwards, manual adjustment, waste and physical count. `Update` never changes stock (the edit form shows it read-only), and `AddStock`/`TryRemoveStock` no longer exist. Loading `data.json` validates the ledger (balances, signs, links) and rejects a corrupt file; history of deleted ingredients or invoices stays loadable.

Callers pass the circuit user as `actor`; manual commands (`AdjustStock`, `RegisterWaste`, `ApplyCountAdjustments`) revalidate a live Admin through `DataStorageService.RequireLiveAdmin`.

## Atomic sale deduction

`SaleService.Add` aggregates the requirement per ingredient across all lines, validates it as one batch and only then commits, so a sale never leaves a partial deduction. Cancellation restores the reliable consumption snapshot and a refund with disposition *Restock* returns the proportional quantity, both as movements linked to the sale (and refund). A *Waste* disposition changes no stock. An invoice is the goods reception: each applicable item becomes an `InvoiceReceipt` movement linked to the invoice, in the ingredient unit (gr/kg and ml/lt converted); deleting an invoice keeps stock and movements. The purchasing UI additionally stores each invoice line already converted (see [Purchasing invoice lines](#purchasing-invoice-lines)). See [Sales.md](Sales.md#checkout-ordering-and-persistence).

## Purchasing invoice lines

`/invoices` (the **Facturas** tab of the purchasing view, see [UserInterface.md](UserInterface.md#tabbed-views)) lets the Admin type a line in any unit compatible with the ingredient (gr/kg for weight, ml/lt for volume; an ingredient in `unidad` only offers `unidad`). `PurchasingFormat.BuildItem` stores the line **in the ingredient's own unit**, converting both quantity and unit price: 500 gr at 0.1 → 0.5 kg at 100 per kg. This matters because `RecipeService` reads the last invoice price through `InvoiceService.GetLastPriceForIngredient` as a price **per ingredient base unit**; a line stored in another unit would corrupt recipe costing. A line typed in the base unit is stored as typed. `InvoiceService.Add` and the `InvoiceReceipt` movements are unchanged; they simply receive lines already in the ingredient unit. Invoice and supplier deletion ask for confirmation; deleting a supplier keeps its invoices, which then show **Sin proveedor**. Invoice editing is still not exposed.

## Adjustments and waste

- **Ajustar stock** (`AdjustStock(id, newStock, reason, actor)`): the Admin types the new stock and a mandatory reason; the dialog shows the resulting difference and requires an explicit confirmation. A negative target, an unchanged value and a blank reason are rejected. It never substitutes the balance silently: the difference becomes an `Adjustment` movement.
- **Registrar merma** (`RegisterWaste(id, quantity, category, reason, actor)`): a positive quantity in the ingredient unit, not above the current stock, with a category and a mandatory reason, also confirmed in the dialog.

## Negative stock policy

Manual operations and sales never produce a negative balance (`Stock insuficiente de X. Disponible: ...`). Increases are never rejected for the resulting balance, so a receipt, a return or an adjustment to a valid target can repair a negative balance that exists in legacy data. Any ingredient with `CurrentStock < 0` shows the visible warning **Stock negativo: requiere ajuste** on `/ingredients`, in the alerts and in its history.

## Integrity guards

- `Update` rejects a unit change (exact comparison) when the ingredient has stock ≠ 0 or any movement: `No se puede cambiar la unidad de un ingrediente con stock o movimientos.` The edit form also disables the unit selector in that case.
- `Delete` rejects an ingredient referenced by a recipe, an invoice item, a sale consumption snapshot (aggregate or per line) or a movement: `El ingrediente tiene registros asociados; desactívelo en lugar de eliminarlo.` Deactivate it instead. Deleting an unknown ingredient stays a no-op.

## History

`/ingredients/{id}/movements` (one ingredient) and `/ingredients/movements` (every ingredient, the **Movimientos** tab of the inventory view) are Admin only, rechecked on every parameter change and callback. They list movements newest first, 20 per page, with an **Ingrediente** selector (all or one) and, for the all-ingredients list, an ingredient column: date, type, signed quantity with unit, previous → resulting stock, reason, waste category, responsible (`Sin registro` when none) and the origin (sale/refund → `/sales/history/{saleId}`, invoice → `/invoices`, count → `/stock/count/{id}`). Filters: the ingredient, an inclusive date range (calendar days; an inverted range is an error) and a cause. `StockMovementFilter` is the service-side contract.

**Saldo previo sin historial.** Stock that existed before the ledger (legacy `data.json`, never migrated) has no movements. The page shows `Saldo previo sin historial: X` when the ingredient has no movements but a nonzero stock (X = stock) or when its oldest movement has a nonzero `PreviousStock` (X = that value). It is computed on the whole history, so it does not appear or vanish with the filters.

## Inventory view and routes

The three stock screens are tabs of one inventory view (**Ingredientes e inventario**), each with its own route: **Stock y alertas** `/ingredients`, **Movimientos** `/ingredients/movements` (and `/ingredients/{id}/movements`), **Conteo físico** `/stock/count`. The sidebar has a single **Ingredientes y stock** entry that is active on all of them. Each tab is a separate page, so switching tabs discards unsaved page state. See [UserInterface.md](UserInterface.md).

## Alerts and coverage

`IngredientService.GetStockAlerts(days = 7, asOf = today)` is a read-only query returning `StockAlert` read models for active ingredients: **Agotado** (`OutOfStock`, stock ≤ 0, including a legacy negative balance) and **Bajo mínimo** (`BelowMinimum`, 0 < stock ≤ `MinStock`). `GetConsumption(id, from, to)` is the net sale consumption over whole calendar days (consumption minus cancellation and refund returns, never negative; waste, adjustments and counts are not consumption). Estimated coverage in days is `CurrentStock × days / consumption` (equal to stock divided by the average daily consumption); zero for an exhausted ingredient with consumption, and unknown (`Sin consumo reciente`) without consumption in the window. Alerts are ordered by level, then shortest coverage first, unknown last, then name. They are listed in **Alertas de stock** on `/ingredients`.

## Physical counts

The physical count flow (`/stock/count`, the **Conteo físico** tab) and its movements are documented in [StockCounts.md](StockCounts.md); it applies differences through `IngredientService.ApplyCountAdjustments` and the same ledger.

## Limits

Prototype-level persistence: no locking, transactions or multi-instance consistency, and a normal return does not guarantee disk persistence (`SaveToFile` logs write errors). Out of scope: multiple locations and transfers, lots and expiry, committed stock and inventory valuation. Movement dates use the registration time; an invoice date is not a reception date.
