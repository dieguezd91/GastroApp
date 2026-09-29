# Sales, discounts, line notes and checkout persistence

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

## Checkout ordering and persistence

`SaleService.Add()` performs these steps in order:

1. Run `ValidateSale()`: reject an empty sale or invalid line, validate each line discount against its gross subtotal, validate the sale discount against the sum of final line subtotals, then delegate eligibility and recipe stock checks to `ValidateStock()`. Failure throws `InvalidOperationException` before normalizing notes, assigning ID/date, registering the sale, deducting stock, or requesting a save.
2. Normalize all line notes: whitespace-only, empty, or missing notes become `null`; other notes use `Trim()`.
3. Allocate the sale ID, set the current date/time, and add the sale to `DataStorageService.Sales`.
4. Run the existing recipe stock deduction. Recipes are matched by line product name; ingredient quantities are multiplied by line quantity and converted through `UnitConverter`. Missing recipes/ingredients and incompatible conversions retain their existing skip behavior. Deduction is skipped if the stock services are not wired.
5. Explicitly call `DataStorageService.SaveToFile()` after deduction returns, requesting a save of the final in-memory sale, stock, and next-ID state. This includes sales without recipes or without any stock deduction; persistence no longer depends on an ingredient mutation.

`IngredientService.TryRemoveStock()` still saves after each successful ingredient deduction. The final sale save does not replace those intermediate writes or redesign the deduction algorithm. The POS prechecks with `ValidateSale()` and displays failures without altering the cart. `Add()` repeats that authoritative validation. The POS resets its cart after `Add()` returns normally and retains it when validation raises `InvalidOperationException`.

## JSON compatibility and limits

`DataStorageService` serializes the `Sales` collection and its items with `System.Text.Json` into `data.json` relative to the process working directory. Notes are included with each sale line and restored on load. Older JSON that omits `Notes` loads with `null`; no migration is required. Normalization happens on new checkout, not as a rewrite of historical sales during loading.

Line and sale discount type/value are saved and restored with their owning objects. With the existing serializer options, enum types are numeric and values are JSON decimals. Legacy JSON omitting discount fields loads with model defaults `None`/`0`, preserving undiscounted totals; no migration or root data-file rewrite is needed. Read-only gross/subtotal/discount/total properties are serialized as derived amounts, but deserialization recomputes them from price, quantity, and discount fields instead of trusting stored totals.

This remains prototype-level persistence, not a transaction or a durable-write acknowledgment. `SaveToFile()` catches and logs write errors rather than propagating them to checkout. A normal return does not guarantee disk persistence. Intermediate ingredient saves can contain partially deducted stock; there is no rollback, locking, or multi-instance consistency. `Add()` stores the supplied sale reference, and exposed storage collections remain mutable. Discounts affect monetary totals only, not quantities or ingredient consumption. This contract adds no payments, modifiers, cancellation, kitchen workflow, or authentication changes.
