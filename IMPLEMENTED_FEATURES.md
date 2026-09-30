# GastroApp: Implemented Features

## Purpose

This document provides a current functional overview of the modules implemented in GastroApp.

It replaces the previous feature notes that had become partially outdated as authentication, JSON persistence, unit conversion, and stock control were added.

For implementation details, current source code is authoritative.

## Authentication

GastroApp currently provides application-level authentication through:

- `AuthService`;
- `UserService`;
- BCrypt password hashing;
- `Admin` and `Employee` roles.

The default seeded development account is:

```text
admin / admin
```

Management pages explicitly redirect unauthenticated users to `/login` and non-admin users to `/unauthorized`.

The point of sale requires authentication but is not restricted to the Admin role.

## Dashboard

Route:

```text
/
```

The dashboard shows:

- current cash register state;
- opening time;
- initial cash;
- today's sales total;
- a primary sales action when the register is open;
- admin quick links.

## Products

Route:

```text
/products
```

Admin functionality:

- create products;
- edit products;
- delete products;
- set sale price;
- optionally set product cost;
- assign or change an optional category, or remove it with **Sin categoría**;
- activate or deactivate products without deleting them;
- display each product's category, availability, and calculated margin.

Margin status is based on the calculated percentage:

- negative: red;
- below 30%: orange;
- 30% or greater: green.

## Product Categories

Route:

```text
/product-categories
```

Admin users can create, list, rename, and delete product categories from the **PRODUCTOS** navigation section.

Category names are trimmed, required, and unique ignoring case. Categories have stable IDs, so renaming does not change product assignments. A category with assigned products cannot be deleted: those products must first be reassigned or left without a category. Validation failures are displayed in Spanish.

Existing products remain uncategorized until explicitly assigned. Category and product changes are saved through `DataStorageService`.

The implemented service, JSON, authentication, and POS boundaries are documented in [ProductCatalog.md](Docs/Architecture/ProductCatalog.md).

## Point of Sale

Route:

```text
/sales
```

Authenticated users can:

- browse active products using **Todos**, a category, or **Sin categoría** (only offered when uncategorized products exist), combined with case-insensitive name search;
- add products to a cart;
- increment, decrement, or directly edit positive integer quantities; decrementing one removes the line, and invalid edits retain the previous quantity;
- add an optional observation applying to the entire quantity of each cart line;
- edit line and whole-sale discounts as none, percentage, or a fixed decimal amount (line fixed amounts apply once, not per unit); invalid edits retain the previous cart and restore the editor;
- remove items;
- clear the cart;
- review line gross, discount and final subtotals, then the sale's post-line subtotal, discount and final total;
- allocate a positive-total sale across one or more unique methods (**Efectivo**, **Tarjeta de débito**, **Tarjeta de crédito**, **Transferencia**, **Mercado Pago**, **Otro**), edit or remove allocations and review assigned/remaining amounts; cash tender must cover its own allocation and displays live change;
- complete a sale when the cash register is open; a zero-total sale requires no payment method.

Search and category filters affect only the displayed catalog, never the cart. The detailed projection, editing, and refresh contract is documented in [ProductCatalog.md](Docs/Architecture/ProductCatalog.md#point-of-sale-boundary).

Checkout rejects empty carts, invalid line or sale discounts, invalid payments, missing or inactive products, and nonpositive quantities before validating stock for products that have a recipe with the same name. Positive totals require one or more positive payments with distinct defined methods whose sum exactly equals the final total; cash requires received tender at least its allocated amount, while noncash requires null tender. Zero totals require no payments. The POS parses decimal inputs with the current culture and no grouping, retains accepted allocations on invalid raw edits but blocks checkout until corrected, and creates fresh payments from accepted state at checkout. Cart and discount changes revalidate allocations against the current total; zero totals clear them. Sale discounts apply after line discounts; percentage arithmetic uses decimal without a new currency-rounding policy. Quantity changes or removals that invalidate a fixed discount are rejected until the discount is adjusted.

When validation succeeds, line observations are trimmed (blank becomes `null`), the sale is recorded, recipe ingredient stock is deducted, and the final state is explicitly saved, including sales without recipes. Discount type/value persist with lines and sales; legacy JSON defaults to no discount. Each sale also persists its payment collection with method, applied decimal amount, and nullable cash received amount; change is derived, not a separate tender applied to the sale. Historical JSON missing payments loads with an empty collection, and old cash payments missing received amount retain null and show zero change without inventing tender; new checkout validation does not run during loading. There are no fees, refunds, or external payment processing; daily sales aggregates remain separate from session cash. Applied cash (not tender or change) creates a movement only after successful stock completion, and closed summaries and cash movements are not reversed. The notes, discount and payment semantics, checkout ordering, JSON compatibility, and persistence limits are documented in [Sales.md](Docs/Architecture/Sales.md).

Admins can cancel a selected completed sale from today's Summary with a required reason. Checkout captures only successfully deducted stock quantities, ingredient IDs and units in a reliable snapshot; a new no-ingredient sale has a reliable empty snapshot while legacy sales without a snapshot cannot be restored. Cancellation verifies the current stored Admin, validates all snapshot entries and stock additions before restoring exact stock once, and persists status and user/time/reason audit without changing payments, items, discounts or notes. Cancelled records remain available for audit but are excluded from today's total, count and top product. There are no refunds or retroactive closed DailySummary/cash corrections; singleton authentication remains a prototype isolation limitation.

## Cash Register

Route:

```text
/cash
```

Admin functionality:

- open the register with an initial amount;
- view register state;
- close the register with a final counted amount;
- view the session's cash inflow and expected drawer balance;
- calculate the final difference.

Sessions have stable IDs, persist at open/close, and reject a second open register. Each checkout requires an open register and links the sale to that session, including zero-total and noncash sales. Only applied cash creates an automatic movement after stock completion. Expected drawer cash is opening amount plus Sale and Income movements minus Expense and Withdrawal movements for that session; no manual movement entry is available yet. Closing the register creates a daily summary entry. See [CashRegisters.md](Docs/Architecture/CashRegisters.md).

## Daily Summary

Route:

```text
/summary
```

Admin users can review:

- today's total sales;
- number of sales;
- top-selling product;
- top-selling quantity;
- initial cash;
- final cash;
- cash difference.

## Ingredients and Stock

Route:

```text
/ingredients
```

Admin functionality:

- create ingredients;
- edit ingredients;
- delete ingredients;
- activate/deactivate ingredients;
- configure a base unit;
- define current stock;
- define minimum stock;
- manually adjust stock;
- view the latest known purchase price;
- view stock status.

Supported units currently exposed by the UI:

- `kg`;
- `lt`;
- `unidad`;
- `gr`;
- `ml`.

Stock indicator rules:

- red: no stock;
- yellow: stock at or below the configured minimum;
- green: stock above the minimum.

## Suppliers

Route:

```text
/suppliers
```

Admin users can manage supplier records used by purchase invoices.

The current supplier model is intentionally small and primarily stores supplier identity information.

## Purchase Invoices

Route:

```text
/invoices
```

Admin users can create invoices with:

- date;
- supplier;
- optional invoice number;
- optional notes;
- multiple ingredient items;
- quantity;
- unit;
- unit price.

On creation, invoice quantities are converted when necessary and added to ingredient stock.

Invoice history is also used to resolve the latest purchase price for an ingredient.

The current UI supports creation and deletion. Although `InvoiceService` contains an update method, invoice editing is not exposed by the current page.

## Recipes

Route:

```text
/recipes
```

Admin functionality:

- create recipes;
- edit recipes;
- delete recipes;
- define yield;
- add ingredients;
- calculate total recipe cost;
- calculate unit cost;
- recalculate costs from current invoice prices.

Recipe costing uses the latest invoice price available for each ingredient.

## Unit Conversion

The application centralizes supported conversions in `UnitConverter`.

Supported conversions:

```text
1 kg = 1000 gr
1 lt = 1000 ml
```

Weight-to-volume conversion is not supported.

Identical units are compatible, including `unidad` to `unidad`.

Recipe costing and stock updates use the same conversion helper.

## Recipe Cost Indicators

Recipe cost status is based on change from the previous calculated unit cost rather than on fixed currency values.

Thresholds:

- green: less than 10% variation;
- yellow: 10% to less than 30%;
- red: 30% or greater.

The variation is absolute, so both increases and decreases can trigger yellow or red.

## Inventory Flow

Current stock changes through three paths.

### Manual Adjustment

Administrators can set an ingredient's current stock directly from the ingredient page.

### Purchase Entry

Creating an invoice adds the purchased quantity to ingredient stock.

### Sale Consumption

A completed sale deducts recipe ingredient quantities when the sold product name matches a recipe name.

The sale is blocked when a required ingredient does not have sufficient stock.

## Persistence

`DataStorageService` stores application state in `data.json`.

Persisted collections include:

- products (including optional category IDs and availability);
- product categories;
- sales;
- canonical cash register sessions, cash movements, and current session ID;
- daily summaries;
- users;
- ingredients;
- suppliers;
- invoices;
- recipes;
- next-ID counters.

The application loads this file at startup and seeds initial data when no products are present.

Legacy JSON containing only a current cash register imports that one session without inferring historical sale links or movements. Canonical sessions take precedence when present. Historical sales without register IDs remain unlinked. Legacy JSON without categories loads with an empty category collection and uncategorized products. The category next-ID counter is recovered from saved state and existing category IDs.

Product and category CRUD call `SaveToFile()`. Persistence remains prototype-level, and not every other service mutation currently calls it consistently. Save errors are logged rather than propagated to the UI.

## Service Wiring

Application services are registered as singletons in `Program.cs`.

Current services include:

```text
DataStorageService
ProductService
ProductCategoryService
SaleService
CashRegisterService
UserService
AuthService
SupplierService
InvoiceService
IngredientService
RecipeService
```

Some relationships are configured after service construction:

```text
InvoiceService -> IngredientService
SaleService -> RecipeService
SaleService -> IngredientService
```

This is current implementation state and exists to avoid constructor dependency cycles.

## Current Limitations

The repository currently has the following relevant limitations:

- authentication state is stored in a singleton `AuthService` and is therefore not isolated per Blazor circuit;
- shared application state is singleton-based;
- JSON persistence is not transactional;
- save behavior is inconsistent across some service mutations;
- products and recipes are linked for stock consumption by matching names;
- deleting an invoice does not roll back stock;
- editing an invoice does not reconcile previously applied stock;
- no database is integrated;
- no automated test project is currently present.

These are implementation facts, not final product requirements.
