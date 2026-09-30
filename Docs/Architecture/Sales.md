# Sales, discounts, payments, line notes and checkout persistence

## Ownership and line semantics

`Sale` and `SaleItem` represent recorded sales. `SaleService` owns checkout validation, registration, recipe-based stock deduction, and the final persistence call through the singleton `DataStorageService`. The POS component owns its in-progress cart.

- `SaleItem.Notes` is optional text (`string?`), not a modifier or a pricing input. It applies to the entire quantity of that line.
- The POS merges additions by `ProductId`. Adding the same product increases the existing line's quantity and retains its note; separate notes per unit are not supported.
- The Spanish **Observación (opcional)** editor normalizes edits to trimmed text or `null` for blank/whitespace input. Quantity changes retain the note; removing a line or clearing the cart discards it with that line.
- `SaleService.Add()` also normalizes every line's notes after successful validation, so non-UI callers receive the same trim/null behavior. Validation failure occurs before this normalization.
- Notes do not change product identity/name, price, quantity, gross/discount/final amounts, or recipe matching and stock calculations.

Catalog filtering, quantity editing, eligibility rules, and existing authentication boundaries are documented in [ProductCatalog.md](ProductCatalog.md#point-of-sale-boundary), not redefined here.

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

## Payment semantics and POS selection

`Sale` owns a `List<SalePayment>` initialized to an empty collection. Each `SalePayment` persists a `PaymentMethod`, decimal `Amount` applied to the final total, and nullable decimal `ReceivedAmount` for cash tender. `Change` is derived as received minus applied amount only for valid cash tender (positive amount and received at least amount); missing, noncash, or invalid historical configurations yield zero change. Supported enum values are `Cash = 0`, `DebitCard = 1`, `CreditCard = 2`, `Transfer = 3`, `MercadoPago = 4`, and `Other = 5`.

- A new sale with positive `Sale.Total` requires exactly one non-null payment, a defined method, and a positive amount exactly equal to that derived final total after all discounts. There is no tolerance or extra rounding.
- Cash requires `ReceivedAmount` at least `Amount`; exact tender yields zero change, excess yields the difference. Every noncash method requires null `ReceivedAmount` and has zero change. A new sale with total zero requires an empty payment collection, including a sale reduced to zero by a 100% discount. Explicitly null payment collections are invalid.
- `SaleService.ValidateSale()` enforces these rules without mutation, after discount validation and before eligibility/stock checks. `Add()` repeats validation before notes normalization, ID allocation, sale insertion, stock deduction, or saving. Invalid payment data cannot reach those mutations through `Add()`.
- The POS starts with no selected method. For positive totals it requires explicit selection of **Efectivo**, **Tarjeta de débito**, **Tarjeta de crédito**, **Transferencia**, **Mercado Pago**, or **Otro**, and displays the selection beside the final total. Attempting checkout without selection gives Spanish feedback and retains the cart.
- Cash selection reveals a required Spanish tender editor. Its raw text is parsed using the current culture's decimal separator without grouping; blank, malformed, overflowing, negative, and insufficient input is rejected. Feedback and change update from the latest input and discounted total; invalid input cannot reuse a previously valid amount. Switching methods clears the tender text. Noncash checkout applies the exact total with null received amount.
- At checkout the POS creates a candidate sale with one fresh payment using the model's current final total and current cash tender when applicable. It retains the cart and selection on validation failure, and generates a fresh payment on the next attempt, so cart/discount edits cannot leave a stale payment amount.
- At zero total the POS displays that no payment is required and generates no payment, regardless of any earlier selection. Selection remains local to the component, is ignored while total is zero, and resets when the cart is cleared or checkout succeeds. Filters remain unchanged.

The collection leaves room for future mixed payments but this implementation rejects multiple payments. It adds no partial/mixed payments, fees, refunds, cancellation, or external payment processing. Cash register and summary calculations remain based on all sale totals; they are not split or filtered by method.

## Checkout ordering and persistence

`SaleService.Add()` performs these steps in order:

1. Run `ValidateSale()`: reject an empty sale or invalid line, validate each line discount against its gross subtotal, validate the sale discount against the sum of final line subtotals, validate the payment collection against the final total, then delegate eligibility and recipe stock checks to `ValidateStock()`. Failure throws `InvalidOperationException` before normalizing notes, assigning ID/date, registering the sale, deducting stock, or requesting a save.
2. Normalize all line notes: whitespace-only, empty, or missing notes become `null`; other notes use `Trim()`.
3. Allocate the sale ID, set the current date/time, and add the sale to `DataStorageService.Sales`.
4. Run the existing recipe stock deduction. Recipes are matched by line product name; ingredient quantities are multiplied by line quantity and converted through `UnitConverter`. Missing recipes/ingredients and incompatible conversions retain their existing skip behavior. Deduction is skipped if the stock services are not wired.
5. Explicitly call `DataStorageService.SaveToFile()` after deduction returns, requesting a save of the final in-memory sale, stock, and next-ID state. This includes sales without recipes or without any stock deduction; persistence no longer depends on an ingredient mutation.

`IngredientService.TryRemoveStock()` still saves after each successful ingredient deduction. The final sale save does not replace those intermediate writes or redesign the deduction algorithm. The POS prechecks with `ValidateSale()` and displays failures without altering the cart. `Add()` repeats that authoritative validation. The POS resets its cart after `Add()` returns normally and retains it when validation raises `InvalidOperationException`.

## JSON compatibility and limits

`DataStorageService` serializes the `Sales` collection and its items with `System.Text.Json` into `data.json` relative to the process working directory. Notes are included with each sale line and restored on load. Older JSON that omits `Notes` loads with `null`; no migration is required. Normalization happens on new checkout, not as a rewrite of historical sales during loading.

Line and sale discount type/value are saved and restored with their owning objects. With the existing serializer options, enum types are numeric and values are JSON decimals. Legacy JSON omitting discount fields loads with model defaults `None`/`0`, preserving undiscounted totals; no migration or root data-file rewrite is needed. Read-only gross/subtotal/discount/total properties are serialized as derived amounts, but deserialization recomputes them from price, quantity, and discount fields instead of trusting stored totals.

Payments are serialized inside each sale and restored by the existing `System.Text.Json` sale deserialization. Methods use numeric enum values and amounts/received amounts retain decimal precision; read-only `Change` is recomputed from the payment fields on reload, not accepted as stored input. Historical JSON that omits `Payments` loads with the model's empty collection and keeps its existing totals; no inferred payment, migration, or root data-file rewrite is required. Older payments omitting `ReceivedAmount` keep it null rather than inferring tender from `Amount`, and therefore show zero change even for historical cash. Loading does not apply new checkout validation to historical sales, even when their positive totals have no payment or cash tender. Passing such a sale to `Add()` as a new checkout requires a valid payment.

This remains prototype-level persistence, not a transaction or a durable-write acknowledgment. `SaveToFile()` catches and logs write errors rather than propagating them to checkout. A normal return does not guarantee disk persistence. Intermediate ingredient saves can contain partially deducted stock; there is no rollback, locking, or multi-instance consistency. `Add()` stores the supplied sale reference, and exposed storage collections remain mutable. Discounts affect monetary totals only, not quantities or ingredient consumption. Payments record the checkout method, applied amount, and optional cash tender/change; they do not change stock, totals, or authentication. This contract adds no modifiers, cancellation, or kitchen workflow.
