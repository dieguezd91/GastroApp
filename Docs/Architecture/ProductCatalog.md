# Product catalog and category contract

## Ownership and identity

`ProductService` owns product CRUD and category assignment validation. `ProductCategoryService` owns category CRUD and name validation. Both use the singleton `DataStorageService`; `Program.cs` registers both services as singletons.

- A `ProductCategory` has an integer `Id` and a `Name`.
- `Product.CategoryId` is nullable: `null` means **Sin categoría**. A product has at most one category.
- `Product.IsActive` is a persisted boolean, defaulting to `true` for new products. Deactivation preserves product identity, category assignments, and sale history; it prevents new checkout rather than deleting the product.
- Relationships use category IDs, not names. Renaming a category preserves its ID and product assignments.
- Adding a category allocates an ID from `GetNextProductCategoryId()`. The service trims names, rejects blank names, and rejects duplicates using `StringComparison.OrdinalIgnoreCase` after trimming both names.
- Updating a category applies the same validation, excluding its own ID. Updating or deleting an unknown category ID is a no-op.
- Deletion is rejected with `InvalidOperationException` while any product refers to the category. Administrators must first change or remove those assignments; deletion never cascades to products.
- Product add/update accepts `null` or an existing category ID. A nonexistent ID raises `ArgumentException` before changing the stored product.

`ProductCategoryService.GetAll()` and `GetById()` return copies so form edits do not bypass category validation. `ProductService.GetAll()` returns the stored product list, and `GetById()` returns the stored product reference; the product page explicitly copies fields into its editing model before saving.

## JSON persistence and legacy compatibility

`DataStorageService` reads and writes `data.json` relative to the process working directory using `System.Text.Json`.

- Saved state includes `ProductCategories`, `NextProductCategoryId`, and each product's optional `CategoryId` alongside the existing collections and counters.
- Older product JSON without `CategoryId` deserializes with `null`.
- Older product JSON without `IsActive` retains the model initializer's `true` value during `System.Text.Json` deserialization. Explicit `false` values remain inactive; serialization includes `IsActive` with the other product properties. No data-file migration is required.
- A missing or null `ProductCategories` collection loads as an empty list. No default categories are seeded.
- On load, the category counter is at least 1, at least the saved counter when present, and greater than every loaded category ID.
- Successful product and category add/update/delete operations call `SaveToFile()`.

This is not a transactional store. Save/load exceptions are caught and logged by `DataStorageService`; the UI does not receive a durable-write acknowledgment. Validation does not repair dangling IDs already present in externally modified JSON. There is no locking, multi-instance consistency, or concurrent edit resolution.

## Administration and authentication

- `/product-categories` exposes category creation, listing, renaming, and deletion with Spanish validation feedback from the service.
- Its initialization and CRUD callbacks check `AuthService`: unauthenticated users redirect to `/login`, and non-admin users redirect to `/unauthorized`, with the same destinations and forced navigation used by `/products`.
- The category navigation link appears in the admin-only **PRODUCTOS** section.
- `/products` retains its existing initialization checks. Its form supports assigning/changing a category or selecting **Sin categoría** to remove the assignment; the list displays the category name or **Sin categoría**. Category choices refresh when loading products or opening a form, and after an invalid assignment error.
- The product form exposes an **Activo (disponible para la venta)** checkbox for creation and editing; new forms start active. The list shows **Activo** or **Inactivo**. Editing copies `IsActive` into the separate form model, and `ProductService.Update()` copies it back before saving.

These are application-level component checks, not ASP.NET authorization policies. `AuthService` remains a singleton with shared current-user state, not isolated per Blazor circuit. This feature does not redesign authentication or add authorization to the catalog services.

## Point of sale boundary

`/sales` still requires authentication, allows both roles, and only exposes selling when the cash register is open.

- The category filter starts at **Todos** and name search starts empty. The visible catalog includes only active products matching both the selected category and the name search. Search uses a trimmed substring with `StringComparison.OrdinalIgnoreCase` and updates as the user types.
- Category options come from `ProductCategoryService.GetAll()`; empty categories remain selectable and show an empty-results message.
- **Sin categoría** is offered only when the loaded product list contains a product with `CategoryId == null`.
- Availability, category ID/null assignment, and name search compose as an `IEnumerable<Product>` projection. Filtering does not replace the stored list, remove cart lines, change quantities/prices/totals, clear validation errors, or reload the page. **Todos** still excludes inactive products; an empty match shows the existing empty-results message.
- Filters and `currentSale` are independent component-local state. Adding a product creates a quantity-one line or increments the existing line, and ignores inactive products. Each line supports increment, decrement, direct integer editing, and removal; decrementing one removes the line without assigning zero.
- Direct edits are parsed before assigning `SaleItem.Quantity`. Blank, noninteger, out-of-range, zero, and negative input is rejected with Spanish feedback, retaining the previous quantity and restoring its displayed value. Increment at `int.MaxValue` is rejected rather than overflowing. Valid cart mutations clear stale validation feedback; rejected edits preserve the valid cart. Subtotals and totals remain derived from the existing `SaleItem`/`Sale` properties.
- `SaleService.ValidateStock()` first rejects empty carts, missing products, inactive products, and nonpositive quantities. `SaleItem.Quantity` is an integer, so fractional quantities cannot be represented. Eligibility checks resolve each line's `ProductId` against the current catalog, even if the product was deactivated or deleted after being carted, and run even without stock services.
- After eligibility checks, the existing recipe-name-based stock validation runs unchanged. `SaleService.Add()` repeats the same validation and throws `InvalidOperationException` on failure before assigning a sale ID/date, registering the sale, or deducting stock. Calling `Add()` directly cannot bypass eligibility or the existing stock checks. The POS's existing pre-check displays validation feedback without clearing the cart.
- Sale lines retain their existing product ID, name, price, and quantity; categories do not alter sale history or the existing name-based product-to-recipe stock linkage.

Category options are loaded on POS initialization. There is no catalog change notification subscription or automatic cross-circuit refresh; navigating back to the page reloads its options. Product references remain shared through the existing service behavior.
