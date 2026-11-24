# GastroApp: Implemented Features

## Purpose

This document provides a current functional overview of the modules implemented in GastroApp.

It replaces the previous feature notes that had become partially outdated as authentication, JSON persistence, unit conversion, and stock control were added.

For implementation details, current source code is authoritative.

## User Interface

Every screen uses one design system (CSS layers in `wwwroot/css/`, shared Blazor components, Argentine Spanish, `es-AR` formats). The shell has a sidebar (from 72 rem) or a drawer, and a topbar with the cash register status (refreshed every 5 seconds) and the user's role. The menu is grouped by role: **Operación diaria** (everyone), **Caja y ventas** and **Catálogo e inventario** (Admin). Related screens are tabs of one view, each tab keeping its own route: **Productos y categorías**, **Ingredientes e inventario** (stock, movements, physical count) and **Proveedores y facturas**. Recipes, invoices and refunds use a full-width workspace with **← Volver**. *Reportes* and *Configuración* from the prototype are not implemented. See [UserInterface.md](Docs/Architecture/UserInterface.md).

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

`AuthService` is scoped per Blazor Server circuit; login/logout are isolated while business data remains shared. Identity resolves the live user by ID and login-time username/password hash; renamed, deleted or password-changed users lose authentication, and role changes apply on the next check. Management pages explicitly redirect unauthenticated users to `/login` and non-admin users to `/unauthorized`, rechecking permissions at action time. See [Authentication.md](Docs/Architecture/Authentication.md).

The point of sale requires authentication but is not restricted to the Admin role.

## Dashboard

Route:

```text
/
```

The dashboard (**Inicio** for employees, **Panel operativo** for admins) shows:

- current cash register state, opening time and initial cash;
- shift metrics (sales count and total of the open session);
- stock alerts (employees: ingredients out of stock);
- a primary sales action;
- for admins, a priority list, the latest sales and quick links.

## Products

Route:

```text
/products
```

Admin functionality:

- create products;
- edit products;
- delete products (after a confirmation dialog);
- set sale price;
- optionally set product cost;
- assign or change an optional category, or remove it with **Sin categoría**;
- activate or deactivate products without deleting them;
- display each product's category, availability, and calculated margin;
- see **Costo desfasado** when the saved cost differs from the unit cost of the recipe with the same name (exact name match, cent precision) and synchronize only the cost with **Sincronizar costo**.

A blank name or a price of zero or less shows a validation banner. The drift rule and sync are documented in [ProductCatalog.md](Docs/Architecture/ProductCatalog.md#recipe-cost-sync).

Margin status is based on the calculated percentage:

- negative: red;
- below 30%: orange;
- 30% or greater: green.

## Product Categories

Route:

```text
/product-categories
```

Admin users can create, list, rename, and delete product categories in the **Categorías** tab of **Productos y categorías**.

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

Products whose recipe stock cannot cover one more unit (counting what the cart already reserves) are blocked with `aria-disabled` and the missing ingredient named, and the cart caps `+` and the quantity field at the maximum available (`SaleService.GetAvailability` / `GetMaxQuantity`, see [Sales.md](Docs/Architecture/Sales.md#pos-availability-stock-pre-block)); checkout still validates stock atomically. Cash received defaults to the allocated amount (**Exacto**). After a successful checkout a visual receipt of the stored sale is shown (no print, not a fiscal document) and **Último comprobante** reopens it.

Search and category filters affect only the displayed catalog, never the cart. The detailed projection, editing, and refresh contract is documented in [ProductCatalog.md](Docs/Architecture/ProductCatalog.md#point-of-sale-boundary).

Checkout rejects empty carts, invalid line or sale discounts, invalid payments, missing or inactive products, and nonpositive quantities before validating stock for products that have a recipe with the same name. Positive totals require one or more positive payments with distinct defined methods whose sum exactly equals the final total; cash requires received tender at least its allocated amount, while noncash requires null tender. Zero totals require no payments. The POS parses decimal inputs with the current culture and no grouping, retains accepted allocations on invalid raw edits but blocks checkout until corrected, and creates fresh payments from accepted state at checkout. Cart and discount changes revalidate allocations against the current total; zero totals clear them. Sale discounts apply after line discounts; percentage arithmetic uses decimal without a new currency-rounding policy. Quantity changes or removals that invalidate a fixed discount are rejected until the discount is adjusted.

When validation succeeds, line observations are trimmed (blank becomes `null`), the sale is recorded, recipe ingredient stock is deducted, and the final state is explicitly saved, including sales without recipes. Discount type/value persist with lines and sales; legacy JSON defaults to no discount. Each sale also persists its payment collection with method, applied decimal amount, and nullable cash received amount; change is derived, not a separate tender applied to the sale. Historical JSON missing payments loads with an empty collection, and old cash payments missing received amount retain null and show zero change without inventing tender; new checkout validation does not run during loading. There are no fees or external payment processing (refunds are a separate Admin operation, see Sales history and refunds); daily sales aggregates remain separate from session cash. Applied cash (not tender or change) creates a movement only after successful stock completion, and closed summaries and cash movements are not reversed. The notes, discount and payment semantics, checkout ordering, JSON compatibility, and persistence limits are documented in [Sales.md](Docs/Architecture/Sales.md).

Admins can cancel a selected completed sale from today's Summary with a required reason. Checkout captures only successfully deducted stock quantities, ingredient IDs and units in a reliable snapshot; a new no-ingredient sale has a reliable empty snapshot while legacy sales without a snapshot cannot be restored. Cancellation verifies the current stored Admin, validates all snapshot entries and stock additions before restoring exact stock once, and persists status and user/time/reason audit without changing payments, items, discounts or notes. Cancelled records remain available for audit but are excluded from today's total, count and top product. Refunds are a separate operation (see Sales history and refunds); closed DailySummary records and cash closes are never retroactively corrected; authentication is isolated per circuit, while shared business state and nontransactional writes remain prototype limitations.

### Sales history and refunds

Every new sale records its operator (user ID and username); legacy sales show **Sin registro**.

Routes:

```text
/sales/history
/sales/history/{saleId}
```

Admin-only **Historial de ventas**, linked from the side menu:

- list sales newest first, 10 per page, filtered by inclusive date range, sale number, operator (or **Sin registro**), payment method, cash register, status and product text;
- states derived from the sale and its refunds: **Cobrada**, **Anulada**, **Parcialmente devuelta** and **Devuelta**, with the refunded total; the status filter offers **Cobradas** (never refunded), **Anuladas**, **Parcialmente devueltas** and **Devueltas**;
- open a sale by its stable ID to review lines, discounts, payments, operator, register and its events in chronological order (registration, cancellation, each refund with date, user, reason, amount and refund ID).

From the detail an Admin can:

- **Devolver** total or partially, by line and quantity. The amount is computed (line and sale discounts prorated, with the exact remainder on the last refund), the Admin assigns it per payment method up to what each method collected, and chooses per line **Vuelve a stock** (only with a consumption snapshot from checkout) or **Merma**. A reason and an explicit confirmation are required. The cash part is booked as a `Devolución` outflow of the current open register, linked to the sale, even when the sale belongs to a closed register, which is never rewritten; without an open register a cash refund is rejected. A refund above what was collected or above the remaining units is rejected.
- **Anular** a Collected sale with a required reason and confirmation (restores its stock snapshot). A sale with refunds cannot be cancelled and a cancelled sale cannot be refunded or cancelled again.

Sales are never deleted; refunds are append-only records (`SaleRefunds`). Employees cannot reach the page or either command, and queries revalidate the live Admin actor. Reporting: `/cash` and `/cash/history/{id}` show per payment method and in total the registered receipts, **Devuelto** and **Neto**; `/summary` separates **Ventas brutas**, **Descuentos**, **Anulaciones**, **Devoluciones** (dated today) and **Importe neto**, while **Total Vendido** keeps its meaning (completed sales after discounts, before refunds). A legacy sale without payments is explained as not refundable instead of showing the form. See [Sales.md](Docs/Architecture/Sales.md#seller-refunds-and-sales-history) and [CashRegisters.md](Docs/Architecture/CashRegisters.md#refunds).

## Cash Register

Route:

```text
/cash
```

Admin functionality:

- open the register with an initial amount;
- view register state;
- close the register through a detailed cash count (**Arqueo y cierre de caja**);
- view the session's cash inflow and expected drawer balance;
- review **Cobros registrados por medio de pago** for the current open or closed session: six methods (including zero) and registered total, distinct from completed sales and drawer cash;
- record Income (**Ingreso**), Expense (**Gasto**) or Withdrawal (**Retiro**) with a positive decimal amount and mandatory trimmed reason;
- review all current-session movements, including automatic sales, with date/type/amount, responsible snapshots, reason and sale reference where present;
- receive Spanish validation feedback and in-memory registration confirmation with immediate balance/list update, without reloading;
- see the counted total, expected amount and a **Faltante**/**Sobrante**/**Exacto** difference.

Sessions have stable IDs, persist at open/close, and reject a second open register. Each checkout requires an open register and links the sale to that session, including zero-total and noncash sales. Only applied cash creates an automatic movement after stock completion. Expected drawer cash is opening amount plus Sale and Income movements minus Expense and Withdrawal movements for that session. Manual entries require the current open session and a freshly validated circuit Admin actor, revalidated against stored ID/username/password identity and live Admin role. Expense/Withdrawal cannot exceed available cash. Expected-balance overflow, gross Income inflow overflow and exhausted movement IDs are rejected before mutation or ID allocation. The server owns ID/time/session/audit fields and appends once; no editing or deleting existing entries is offered. Listing uses detached read-only collection snapshots and explicit legacy audit fallbacks. Closing the register creates a daily summary entry. Closing requires a cash count by denomination (positive denominations, non-negative integer quantities, no duplicates, at most 100 lines), an explicit confirmation step, a reason for any nonzero difference and an explicit confirmation of a zero count. The service revalidates the live Admin and rejects the close if movements changed since the review; the stored count records the closing admin and is shown on `/cash`, while registers closed before this feature show no count. See [CashRegisters.md](Docs/Architecture/CashRegisters.md#cash-count-arqueo-and-close).

Registered receipts are a derived, detached read-only cash-service snapshot of payment **Amount** for the exact canonical current session ID, with full decimal precision. Cancelled sales retain their receipts; dates, tender/change, opening funds and manual movements are excluded. Historical unlinked sales produce an explicitly global warning without invented attribution. Invalid selected-session items/discounts or allocations exclude the whole sale with grouped reason/count warnings; valid zero-total sales need no allocations. Missing historical tender is acceptable. Typed completeness states distinguish no session, complete, partial and unavailable; any monetary overflow suppresses every numeric total rather than displaying partial or fabricated zero totals. The Spanish UI refreshes session metadata and receipts on existing renders/navigation/local cash callbacks, without polling or new broadcasts. No derived totals are persisted. See [CashRegisters.md](Docs/Architecture/CashRegisters.md#registered-receipts-by-payment-method).

### Cash register history

Routes:

```text
/cash/history
/cash/history/{registerId}
```

Admin-only, read-only **Historial de cajas**, linked from the side menu and from `/cash`:

- list every session (ID, opening/closing date, **Abierta**/**Cerrada**, initial amount, expected cash, counted amount when closed, **Exacto**/**Sobrante**/**Faltante** difference) newest first, filtered by inclusive opening-date range and status, 10 per page;
- open a session by its stable ID to review its general data, every linked movement (automatic sales distinguished from manual income, expense and withdrawal), registered receipts by payment method with the same completeness states and warnings as `/cash`, the stored cash count (responsible, date, denominations, totals, difference, reason) and the `DailySummary` linked by `CashRegisterId`;
- return to the current register without changing it.

Closed sessions show the amounts stored at close; open sessions show expected cash computed from their movements. Sessions closed without a count, legacy summaries without `CashRegisterId` and unknown IDs are reported explicitly; nothing is reconstructed, attributed by date or invented. Queries revalidate the live Admin actor, never save and never change the current register. Editing, reopening, export and reconciliation are not offered. See [CashRegisters.md](Docs/Architecture/CashRegisters.md#session-history).

## Daily Summary

Route:

```text
/summary
```

Admin users can review:

- today's total sales (completed sales after discounts, before refunds);
- gross sales, discounts, cancellations, refunds dated today and net amount, each with a short note of what it includes;
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
- create ingredients without stock (stock is loaded with purchase invoices; a non-zero stock on creation is rejected; legacy `InitialStock` movements stay readable);
- define minimum stock;
- adjust stock with a mandatory reason and confirmation (**Ajustar stock**);
- register waste with category and reason (**Registrar merma**);
- view the movement history of one or all ingredients with ingredient, date and cause filters (`/ingredients/{id}/movements`, `/ingredients/movements`);
- view stock alerts (**Alertas de stock**): exhausted and below-minimum ingredients with estimated coverage;
- see a visible warning for negative balances (**Stock negativo: requiere ajuste**);
- view the latest known purchase price;
- view stock status.

The edit form shows the stock read-only; stock changes only through the ledger. The unit cannot be changed once an ingredient has stock or movements, and an ingredient referenced by recipes, invoices, sales or movements cannot be deleted (deactivate it). See [Stock.md](Docs/Architecture/Stock.md).

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

Admin users can manage supplier records used by purchase invoices, in the **Proveedores** tab of **Proveedores y facturas**. Deleting a supplier asks for confirmation; its invoices are kept and show **Sin proveedor**.

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

Each line offers only units compatible with the ingredient and is stored converted to the ingredient's own unit (500 gr at 0.1 becomes 0.5 kg at 100), because recipe costing reads the last invoice price as a price per base unit. On creation, quantities are added to ingredient stock. Invoices are created in a full-width workspace; deleting one asks for confirmation (stock is kept).

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
- see a cost preview while editing (calculated on a scratch copy, nothing saved until confirmed);
- recalculate costs from current invoice prices.

Recipes are created and edited in a full-width workspace.

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

Every stock change is a persisted ledger movement with its cause, previous and resulting stock, responsible user and origin document (see [Stock.md](Docs/Architecture/Stock.md)).

### Manual Adjustment and Waste

Administrators adjust stock to a new value with a mandatory reason, or register waste with a category and reason, from the ingredient page; both show a confirmation and never leave a negative balance.

### Purchase Entry

Creating an invoice adds the purchased quantity to ingredient stock as `InvoiceReceipt` movements linked to the invoice.

### Sale Consumption

A completed sale deducts recipe ingredient quantities when the sold product name matches a recipe name, as one atomic batch aggregated per ingredient. Cancellations and restock refunds return stock through linked movements.

The sale is blocked, without any partial deduction, when a required ingredient does not have sufficient stock.

## Persistence

`DataStorageService` stores application state in `data.json`.

Persisted collections include:

- products (including optional category IDs and availability);
- product categories;
- sales;
- canonical cash register sessions, cash movements, cash counts, and current session ID;
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

Business/data services are registered as singletons in `Program.cs`; `AuthService` alone is scoped per Blazor Server circuit. No singleton captures it.

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

- authentication is in-memory per circuit and does not survive a replacement circuit or full reload;
- shared application state is singleton-based;
- JSON persistence is not transactional;
- save behavior is inconsistent across some service mutations;
- products and recipes are linked for stock consumption (and the cost sync) by matching names;
- recipe yield is not applied to stock deduction: a sale deducts the full recipe quantity per unit sold, and the POS availability check mirrors it;
- recalculating a recipe from its card calculates costs twice, so its variation indicator ends green;
- switching tabs of a tabbed view discards unsaved page state (for example a count in progress);
- Bootstrap remains in the lowest CSS layer until the last page stops using it;
- deleting an invoice does not roll back stock;
- editing an invoice does not reconcile previously applied stock;
- no database is integrated;
- no automated test project is currently present.

These are implementation facts, not final product requirements.
