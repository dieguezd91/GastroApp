# Sale-line notes and checkout persistence

## Ownership and line semantics

`Sale` and `SaleItem` represent recorded sales. `SaleService` owns checkout validation, registration, recipe-based stock deduction, and the final persistence call through the singleton `DataStorageService`. The POS component owns its in-progress cart.

- `SaleItem.Notes` is optional text (`string?`), not a modifier or a pricing input. It applies to the entire quantity of that line.
- The POS merges additions by `ProductId`. Adding the same product increases the existing line's quantity and retains its note; separate notes per unit are not supported.
- The Spanish **Observación (opcional)** editor normalizes edits to trimmed text or `null` for blank/whitespace input. Quantity changes retain the note; removing a line or clearing the cart discards it with that line.
- `SaleService.Add()` also normalizes every line's notes after successful validation, so non-UI callers receive the same trim/null behavior. Validation failure occurs before this normalization.
- Notes do not change product identity/name, price, quantity, `SaleItem.Subtotal` (`Price * Quantity`), `Sale.Total` (the sum of subtotals), or recipe matching and stock calculations.

Catalog filtering, quantity editing, eligibility rules, and existing authentication boundaries are documented in [ProductCatalog.md](ProductCatalog.md#point-of-sale-boundary), not redefined here.

## Checkout ordering and persistence

`SaleService.Add()` performs these steps in order:

1. Run `ValidateStock()`. Failure throws `InvalidOperationException` before normalizing notes, assigning ID/date, registering the sale, deducting stock, or requesting a save.
2. Normalize all line notes: whitespace-only, empty, or missing notes become `null`; other notes use `Trim()`.
3. Allocate the sale ID, set the current date/time, and add the sale to `DataStorageService.Sales`.
4. Run the existing recipe stock deduction. Recipes are matched by line product name; ingredient quantities are multiplied by line quantity and converted through `UnitConverter`. Missing recipes/ingredients and incompatible conversions retain their existing skip behavior. Deduction is skipped if the stock services are not wired.
5. Explicitly call `DataStorageService.SaveToFile()` after deduction returns, requesting a save of the final in-memory sale, stock, and next-ID state. This includes sales without recipes or without any stock deduction; persistence no longer depends on an ingredient mutation.

`IngredientService.TryRemoveStock()` still saves after each successful ingredient deduction. The final sale save does not replace those intermediate writes or redesign the deduction algorithm. The POS resets its cart after `Add()` returns normally and retains it when validation raises `InvalidOperationException`.

## JSON compatibility and limits

`DataStorageService` serializes the `Sales` collection and its items with `System.Text.Json` into `data.json` relative to the process working directory. Notes are included with each sale line and restored on load. Older JSON that omits `Notes` loads with `null`; no migration is required. Normalization happens on new checkout, not as a rewrite of historical sales during loading.

This remains prototype-level persistence, not a transaction or a durable-write acknowledgment. `SaveToFile()` catches and logs write errors rather than propagating them to checkout. A normal return does not guarantee disk persistence. Intermediate ingredient saves can contain partially deducted stock; there is no rollback, locking, or multi-instance consistency. `Add()` stores the supplied sale reference, and exposed storage collections remain mutable. This contract adds no payments, discounts, modifiers, cancellation, kitchen workflow, or authentication changes.
