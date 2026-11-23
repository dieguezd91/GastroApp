# Sales, discounts, payments, line notes and checkout persistence

## Ownership and line semantics

`Sale` and `SaleItem` represent recorded sales. `SaleService` owns checkout validation, registration, recipe-based stock deduction, and the final persistence call through the singleton `DataStorageService`. The POS component owns its in-progress cart.

- `SaleItem.Notes` is optional text (`string?`), not a modifier or a pricing input. It applies to the entire quantity of that line.
- The POS merges additions by `ProductId`. Adding the same product increases the existing line's quantity and retains its note; separate notes per unit are not supported.
- The Spanish **Observación (opcional)** editor normalizes edits to trimmed text or `null` for blank/whitespace input. Quantity changes retain the note; removing a line or clearing the cart discards it with that line.
- `SaleService.Add()` also normalizes every line's notes after successful validation, so non-UI callers receive the same trim/null behavior. Validation failure occurs before this normalization.
- Notes do not change product identity/name, price, quantity, gross/discount/final amounts, or recipe matching and stock calculations.

Catalog filtering, quantity editing and eligibility rules are documented in [ProductCatalog.md](ProductCatalog.md#point-of-sale-boundary). [Authentication.md](Authentication.md) defines circuit identity: POS completion rechecks live authentication, and both Admin and Employee may sell.

## Discount semantics and POS editing

`SaleItem` and `Sale` persist `DiscountType` (`None = 0`, `Percentage = 1`, `Fixed = 2`) and decimal `DiscountValue`. The model owns all derived monetary amounts; the POS displays those properties rather than implementing its own formulas.

- `None` requires value zero. `Percentage` accepts 0 through 100 inclusive. `Fixed` accepts zero through the applicable subtotal inclusive. Negative values and unknown types are invalid.
- A line's `GrossSubtotal` is `Price * Quantity`, clamped to zero. Its percentage discount is calculated from that gross subtotal; its fixed discount is applied **once to the entire line**, not per unit. `DiscountAmount` is subtracted to derive the final line `Subtotal`.
- `Sale.Subtotal` is the sum of final line subtotals. The sale discount applies to this post-line-discount base, never the original gross total. `Sale.Total` subtracts the sale's `DiscountAmount` from that subtotal.
- Arithmetic uses the existing `decimal` precision: percentage is `base * value / 100`. No new currency-rounding policy or two-decimal rounding is introduced, including in display or persistence. Display uses the current culture's decimal separator.
- Derived values are defensive for invalid externally loaded configurations: negative/excessive discount values are clamped to the supported range, unknown types produce zero discount, and final amounts cannot be negative. This does **not** validate or repair the persisted configuration; checkout rejects it through the service.

`SaleService.ValidateDiscount()` is public and side-effect-free, shared by `ValidateSale()` and POS candidate checks. Spanish line and whole-sale controls support **Sin descuento**, **Porcentaje (%)**, and **Importe fijo ($)**. Switching type proposes zero as the new value. A value editor is disabled for `None`.

Editors parse decimal text using the current culture with no thousands separator (the expected separator is shown in the help text). Blank, malformed, decimal overflow, negative, out-of-range, and unknown-type edits are rejected before assigning any cart property. A line candidate is validated against its gross subtotal, and the sale discount is then checked against the candidate post-line subtotal. Thus a valid line edit cannot silently invalidate a fixed sale discount.

Quantity changes and removals also check the candidate discount bases before mutation. If a smaller quantity, larger line discount, or removed line would make an existing fixed discount exceed its base, the operation is rejected; adjust that discount first. Clearing the entire cart explicitly resets the sale and all discounts. Adding an existing product preserves its note and discount configuration while increasing quantity.

Rejected edits retain the prior cart and sale discount, give Spanish feedback in an accessible alert region, and recreate only discount/quantity editors with `@key` to restore their displayed values. Notes and catalog filters are not recreated or reset; there is no page reload. The summary separately identifies line gross/discount/final subtotal and sale post-line subtotal/discount/final total.

## Payment semantics and POS allocations

`Sale` owns a `List<SalePayment>` initialized to an empty collection. Each `SalePayment` persists a `PaymentMethod`, decimal `Amount` applied to the final total, and nullable decimal `ReceivedAmount` for cash tender. `Change` is derived as received minus applied amount only for valid cash tender (positive amount and received at least amount); missing, noncash, or invalid historical configurations yield zero change. Supported enum values are `Cash = 0`, `DebitCard = 1`, `CreditCard = 2`, `Transfer = 3`, `MercadoPago = 4`, and `Other = 5`.

- A positive-total sale requires one or more non-null payments, each with a defined, unique method and positive amount. Their decimal sum must equal the derived final total exactly after all discounts, without tolerance or rounding. Overflowing sums fail validation.
- Cash requires `ReceivedAmount` at least `Amount`; exact tender yields zero change, excess yields the difference. Every noncash method requires null `ReceivedAmount` and has zero change. A new sale with total zero requires an empty payment collection, including a sale reduced to zero by a 100% discount. Explicitly null payment collections are invalid.
- `SaleService.ValidatePayments()` exposes side-effect-free payment validation shared by the POS and `ValidateSale()`. `ValidateSale()` checks it after discounts and before eligibility/stock; `Add()` repeats validation before notes normalization, ID allocation, sale insertion, stock deduction, or saving.
- The POS offers each of **Efectivo**, **Tarjeta de débito**, **Tarjeta de crédito**, **Transferencia**, **Mercado Pago**, and **Otro** once. Adding a method assigns the current remaining amount; the operator can edit its applied amount or remove the row. It displays total, assigned, and remaining. Adding is disabled when nothing remains.
- Cash has its own tender editor and live change based on its allocated portion, not the entire sale. **Efectivo received defaults to the allocated amount** (**Exacto**, zero change) and follows later changes of that amount until the operator types a figure of their own, which is never overwritten; an **Exacto** button restores it. Decimal editors use the current culture's separator without grouping. Blank, malformed, overflowing, nonpositive applied amounts and invalid/insufficient tender retain the last accepted values while recording invalid raw input; checkout stays disabled until corrected. No previous valid tender can be reused through an invalid edit.
- The POS rechecks the current final total on cart, quantity and discount changes and at checkout. It builds fresh payment objects from accepted allocations only; stale sums block checkout. A zero total clears local allocations and creates no payments. Clearing the cart or successful checkout resets the editor; catalog filters remain unchanged.

Mixed allocations record applied amounts but add no fees, tips, refunds, or external payment processing. Only the applied cash portion creates a session movement after successful stock deduction; tender and change do not affect the drawer. Completed daily sales metrics remain separate from session cash; cancellation does not reverse prior cash movements. See [CashRegisters.md](CashRegisters.md).

## POS availability (stock pre-block)

The POS shows, before checkout, which products the recipe stock can still cover. It is a **read-only** projection built on the same `RecipeRequirements` used by checkout, so it cannot drift from the real rule; the atomic validation in `Add()` remains the second line of defense.

- `SaleService.GetAvailability(cart, product)` returns `ProductAvailability(MaxAdditionalUnits, LimitingIngredient, ReservedByCart, InvalidRecipe)`: how many more units fit once the cart's lines reserve their ingredients. `MaxAdditionalUnits == null` means unlimited (no matching recipe by exact name, or stock services not wired); `0` means blocked (`IsBlocked`). The tightest ingredient is reported; `ReservedByCart` says the cart already holds part of it; `InvalidRecipe` flags a nonpositive recipe quantity, which checkout rejects too.
- `SaleService.GetMaxQuantity(cart, item)` returns the largest quantity a line may have after the **other** lines reserve their stock (`null` = no cap). The line itself is ignored, so a copy being edited is capped like the line it replaces.
- Decimal overflow reports `MaxAdditionalUnits = 0`. Neither method mutates anything or saves.
- `Pages/Sales.razor` turns the result into a `TileAvailability` for each tile (`aria-disabled="true"`, the reason naming the missing ingredient, badge **Sin stock** or **Máximo en carrito**) and caps `+` and the numeric quantity field at `GetMaxQuantity`. Blocked products cannot be added from the cards.

Recipes are still matched by product name, and recipe quantities are **not** divided by the recipe yield (see [Known limit: recipe yield](#known-limit-recipe-yield)).

## Post-checkout receipt

After a successful `Add()` the POS opens `ReceiptDialog` with the **stored** `Sale` (ID, date, operator, items, discounts, payments with received cash and change), never the cart. It is visual only: it states that it is not a ticket or fiscal document, and there is no print action. **Nueva venta** (or Esc/✕) closes it and leaves the cart empty. **Último comprobante (#N)** in the page header reopens the last receipt of the session without touching storage.

### Known limit: recipe yield

`RecipeRequirements` multiplies each recipe ingredient quantity by the units sold, **without dividing by `Recipe.Yield`**. A recipe with yield greater than 1 therefore deducts the full recipe per unit sold, and the availability above mirrors that. This pre-dates the UI redesign and was not changed.

## Checkout ordering and persistence

`SaleService.Add()` performs these steps in order:

1. Require the current canonical session to be open, then run `ValidateSale()`: reject an empty sale or invalid line, validate each line discount against its gross subtotal, validate the sale discount against the sum of final line subtotals, validate the payment collection against the final total, then delegate eligibility and recipe stock checks to `ValidateStock()`. Failure throws `InvalidOperationException` before normalizing notes, assigning ID/date, registering the sale, deducting stock, or requesting a save.
2. Normalize all line notes: whitespace-only, empty, or missing notes become `null`; other notes use `Trim()`.
3. Precheck cash movement counter and drawer arithmetic where applicable. Plan the stock deduction and validate it as one batch (step 4) before anything changes. Then allocate the sale ID, overwrite any caller-proposed `CashRegisterId` with the current stable session ID, set the date/time, record the seller and add the sale to `DataStorageService.Sales`.
4. Stock deduction is atomic and goes through the stock ledger ([Stock.md](Stock.md)). `PlanDeductions` matches recipes by line product name, multiplies ingredient quantities by line quantity, converts them through `UnitConverter` and aggregates the requirement per ingredient across all lines; `IngredientService.Prepare` validates the aggregated requirement against current stock without mutating anything (`Stock insuficiente de X. Disponible: ...` rejects the whole sale). Missing recipes/ingredients and incompatible conversions keep their skip behavior, and nonpositive convertible recipe quantities are rejected before checkout. Deduction is skipped if the stock services are not wired. Once the batch is valid, `Commit` cannot fail: it lowers each ingredient and appends one `SaleConsumption` movement per ingredient linked to the sale and its seller. Each deduction also records its ingredient ID, exact quantity in its stock unit and that unit in the aggregate and per-line snapshots, so a sale is never left with a partial deduction or an unreliable snapshot because of a stock failure.
5. Mark the checkout-owned snapshot reliable (including an empty snapshot for no applicable ingredients). If applied cash is positive, append exactly one Sale movement for that amount; noncash and zero-total sales have no movement. Call `DataStorageService.SaveToFile()` once at the end, requesting a save of the final in-memory sale, snapshot, movements, stock and next-ID state. This includes sales without recipes or without any stock deduction.

`IngredientService` no longer exposes `AddStock`/`TryRemoveStock` and no longer saves per ingredient: every stock change is a ledger movement created through its single mutation path and saved once by its caller. The POS prechecks with `ValidateSale()` and displays failures without altering the cart. `Add()` repeats that authoritative validation. The POS resets its cart after `Add()` returns normally and retains it when validation raises `InvalidOperationException`.

## Cancellation and daily view

`SaleStatus.Completed = 0` and `Cancelled = 1`. New checkout rejects prefilled status, cancellation audit or stock snapshot fields; it replaces the caller's empty snapshot with one owned by checkout. `SaleService.Cancel(id, reason, user)` checks the stored sale is Completed, trims and requires a nonblank reason, and verifies the supplied user's stable ID, username and Admin role against storage. The Admin-only Summary lists today's completed sales and resolves a fresh, live circuit actor at action time, verifies Admin, then passes that actor to cancellation. Cancellation prevalidates a reliable non-null snapshot, each positive quantity/ID/unit, the existence and unchanged unit of every ingredient, and checked aggregate additions and final stock for overflow before changing anything. Duplicate ingredient entries aggregate for validation. It restores exactly the captured quantities once, as `SaleCancellationReturn` movements linked to the sale, then records reason, timestamp, user ID and username and saves. Changed recipes have no effect. Missing or malformed stock snapshots cannot be reconstructed from current recipes. Cancelled sales remain in `GetAll()` with original items, notes, discounts and payments; no physical deletion or monetary refund occurs.

`GetToday()`, today's total/count and top-product calculations include only Completed sales; the Summary selector and displayed metrics follow the same filter. Closed `DailySummary` records and past cash reconciliation are **not** retroactively updated. Cash payments are not reversed by cancellation; refunds are a separate operation (below). Authentication identity is isolated per circuit and cancellation audit attribution uses its freshly validated actor. Business state remains singleton/shared; permission checks and writes are not atomic across concurrent changes.

## Seller, refunds and sales history

### Seller recording

`SaleService.Add()` records the operator of every new sale as `Sale.CreatedByUserId` and `CreatedByUsername`, taken from the live authenticated actor (both Admin and Employee may sell). Legacy sales have both fields `null`; the history shows them as **Sin registro** and never infers an operator.

### Daily report: gross, discounts, cancellations, refunds and net (S13)

`SaleService.GetTodayReport()` / `GetReport(day)` derive a read-only `SalesReport` (never persisted; closed `DailySummary` records are not inputs or rewritten). The Admin `/summary` page renders it in the **Ventas, descuentos, anulaciones y devoluciones de hoy** table, each row with a short Spanish note of what it includes:

| Figure | Definition |
| --- | --- |
| **Ventas brutas** (`GrossSales`) | List price (`Price × Quantity`, before line and sale discounts) of the Completed sales dated that day. |
| **Descuentos** (`Discounts`) | Line plus sale discounts of those same sales. |
| **Total Vendido** (`SoldTotal`, unchanged meaning) | `GrossSales − Discounts`; equals `GetTodayTotal()`. Cancelled sales are excluded and refunds are **not** subtracted. |
| **Anulaciones** (`CancelledTotal`, `CancelledCount`) | Final total (after discounts) of the sales dated that day whose status is Cancelled; they are in none of the figures above. |
| **Devoluciones** (`RefundedTotal`, `RefundCount`) | Sum of the `SaleRefund` records **dated that day**, whatever the date of the refunded sale (the refunded sale keeps counting as sold on its own day). |
| **Importe neto** (`NetTotal`) | `SoldTotal − RefundedTotal`; it can be negative when refunds of older sales exceed the day's sales. |

Sales are attributed by sale date and refunds by refund date. Per-method refunded and net figures of a register are in [CashRegisters.md](CashRegisters.md#refunds).

### Refunds and cancellation are separate operations

Cancellation voids the whole sale and restores its stock snapshot; a refund returns money for some or all of the goods and leaves the sale `Completed`. They are recorded separately and never combine: a sale with any recorded refund cannot be cancelled (`La venta tiene devoluciones registradas; no puede anularse.`) and a cancelled sale admits no refund (`La venta anulada no admite devoluciones.`). Sales are never deleted or rewritten by a refund; the refund is an append-only `SaleRefund` record in `DataStorageService.SaleRefunds`.

### Refund rules (`SaleService.Refund`)

`GetRefundability(saleId)`, `PreviewRefund(saleId, lines)` and `Refund(saleId, reason, lines, payments, actor)` own the rules; the page only collects inputs.

- **Admin only.** The actor is revalidated against the live stored user (identity, credentials hash, Admin role).
- **By line and quantity.** Each requested line names a sale item index and a quantity between 1 and the units still unrefunded. A line cannot be repeated in one refund; at least one line and a nonblank reason (trimmed) are required. A refund above what was collected or above the remaining units is rejected before anything changes.
- **Computed amount.** The caller never provides line amounts. A line amount is `line subtotal * quantity / sold quantity`, prorated by the sale discount (`Total / Subtotal`), rounded to cents (away from zero). A refund that covers every remaining unit takes the exact remaining refundable amount, so cumulative refunds always equal the sale total and no rounding cent is lost or invented; the difference is absorbed by the largest line.
- **Per-method caps.** The caller assigns an amount per payment method. Each amount is positive, a method appears once, and no method exceeds what was collected with it minus what was already refunded through it. The assigned amounts must add up exactly to the refund total.
- **Restock or waste, per line (S7).** Each line is marked `Restock` (valid physical return: ingredients go back to stock) or `Waste` (merma: money is returned and stock is untouched). Restock uses the per-line consumption snapshot recorded at checkout (`SaleItem.StockConsumption`), proportionally to the refunded quantity. Legacy lines, or sales whose snapshot is unreliable, have no such snapshot, so only `Waste` is accepted (`... sólo puede devolverse como merma`). All restock quantities are validated before any ingredient changes.
- **Cash goes through the current open register.** The cash part of a refund creates one `CashMovementType.Refund` outflow linked to the original sale in the **current open register**, even when the sale belongs to an already closed register; the earlier close, count and summary stay untouched. With no open register a cash refund is rejected (`Debe haber una caja abierta para devolver efectivo.`), as is an amount above the available drawer cash. Noncash refunds create no movement and, without an open register, are recorded with no register. See [CashRegisters.md](CashRegisters.md#refunds).
- **Refundable money.** `SaleRefundability.CanRefund` is false for a cancelled sale, when no units remain, or when money remains to be refunded but no payment method has a remaining amount (`HasRefundableMoney`), as in a legacy sale without payments: every attempt would fail the exact-sum rule. The detail then shows "La venta no tiene pagos registrados; no puede devolverse." instead of the form.
- **Atomic validation.** Every rejection happens before the single mutation block (ingredients, refund record, cash movement, one save).

### Derived states

`SaleService.GetDisplayStatus(sale, refunds)` derives, without persisting, **Cobrada** (`Collected`), **Anulada** (`Cancelled`), **Parcialmente devuelta** (`PartiallyRefunded`) and **Devuelta** (`Refunded`, every unit refunded). `GetDisplayStatusLabel` provides the Spanish labels shared by the list and the detail.

### Sales history page

The Admin-only `/sales/history` and `/sales/history/{id}` page (**Historial de ventas**) reads through `SaleHistoryService`, which returns detached snapshots and never saves. Entries carry the derived `DisplayStatus` and the refunded total; the status filter offers **Cobradas** (display status Collected only), **Anuladas**, **Parcialmente devueltas** and **Devueltas**. The detail lists lines, discounts, payments and the events in chronological order: sale registration, cancellation and every refund (date, user, reason, amount, refund ID).

The detail has a **Devoluciones** section with past refunds (date, user, reason, lines with quantity × product and **Vuelve a stock**/**Merma**, methods and amounts, total) and, while units remain, the refund form: quantity (0 to remaining) and destination per line (restock disabled with *Sin registro de consumo: solo merma* when there is no snapshot), **Calcular importe** (a non-mutating `PreviewRefund`), an amount per method showing collected, refunded and remaining, a mandatory reason and an explicit confirmation. A note states that cash is reimbursed as an outflow of the current open register. The **Anulación** section is offered only for a Collected sale; otherwise the page explains why it is unavailable. Every callback rechecks the Admin role, and the commands (`Refund`, `Cancel`) are preceded by a strict live `GetDetail`. Service errors are shown in Spanish next to the form; success reloads the detail and the list.

## JSON compatibility and limits

`DataStorageService` serializes the `Sales` collection and its items with `System.Text.Json` into `data.json` relative to the process working directory. Notes are included with each sale line and restored on load. Older JSON that omits `Notes` loads with `null`; no migration is required. Normalization happens on new checkout, not as a rewrite of historical sales during loading.

Line and sale discount type/value are saved and restored with their owning objects. With the existing serializer options, enum types are numeric and values are JSON decimals. Legacy JSON omitting discount fields loads with model defaults `None`/`0`, preserving undiscounted totals; no migration or root data-file rewrite is needed. Read-only gross/subtotal/discount/total properties are serialized as derived amounts, but deserialization recomputes them from price, quantity, and discount fields instead of trusting stored totals.

Payments are serialized inside each sale and restored by the existing `System.Text.Json` sale deserialization. Methods use numeric enum values and amounts/received amounts retain decimal precision; read-only `Change` is recomputed from the payment fields on reload, not accepted as stored input. Historical JSON that omits `Payments` loads with the model's empty collection and keeps its existing totals; no inferred payment, migration, or root data-file rewrite is required. Older payments omitting `ReceivedAmount` keep it null rather than inferring tender from `Amount`, and therefore show zero change even for historical cash. Loading does not apply new checkout validation to historical sales, even when their positive totals have no payment or cash tender. Passing such a sale to `Add()` as a new checkout requires a valid payment.

`SaleRefunds` is persisted at the JSON root with its own `NextSaleRefundId` counter; each refund stores its lines (index, quantity, disposition, computed amount), method amounts, reason, user snapshot and the register that booked it. A legacy file without the list loads an empty ledger; an explicit `null`, a null entry or an inconsistent refund (unknown sale, quantity above the sold units, line or method totals that differ from the refund total, cumulative refunds above the sale total) fails loading clearly. Legacy sales without operator or per-line consumption load unchanged.

Older JSON without `Status` defaults to Completed (`0`), with null audit fields, an empty snapshot and `IsStockConsumptionReliable = false`. Reliable empty snapshots from new no-ingredient checkouts are distinct from legacy sales and can be cancelled without stock changes. New status, audit, stock consumption and reliability fields persist with the sale. Explicit null or malformed snapshots, missing ingredients, changed units and restoration overflow block cancellation before mutations.

This remains prototype-level persistence, not a transaction or a durable-write acknowledgment. `SaveToFile()` catches and logs write errors rather than propagating them to checkout. A normal return does not guarantee disk persistence. Checkout is validated before it mutates and commits in one in-memory block followed by one save, but there is still no locking or multi-instance consistency. `Add()` stores the supplied sale reference, and exposed storage collections remain mutable. Discounts affect monetary totals only, not quantities or ingredient consumption. Payments record the checkout method, applied amount, and optional cash tender/change; only applied cash creates a movement, and payments do not change stock, totals, or authentication. Cancellation prevalidation is in-memory and does not add locking or transactional persistence. This contract adds no modifiers or kitchen workflow.

## Verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-pos-availability.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-sales-refunds.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-sales-history.ps1
```

`verify-pos-availability.ps1` runs in a scratch fixture and covers `GetAvailability`/`GetMaxQuantity` (unlimited, blocked, reserved by cart, multiple ingredients, invalid recipe, overflow), their agreement with checkout and their read-only behavior. Like the other harnesses it does not prove browser layout.
