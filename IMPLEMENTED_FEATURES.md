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
- remove items;
- clear the cart;
- review the total;
- complete a sale when the cash register is open.

Search and category filters affect only the displayed catalog, never the cart. The detailed projection, editing, and refresh contract is documented in [ProductCatalog.md](Docs/Architecture/ProductCatalog.md#point-of-sale-boundary).

Checkout rejects empty carts, missing or inactive products, and nonpositive quantities before validating stock for products that have a recipe with the same name.

When validation succeeds, the sale is recorded and recipe ingredient stock is deducted.

## Cash Register

Route:

```text
/cash
```

Admin functionality:

- open the register with an initial amount;
- view register state;
- close the register with a final counted amount;
- calculate expected cash;
- calculate the final difference.

Closing the register creates a daily summary entry.

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
- current cash register;
- daily summaries;
- users;
- ingredients;
- suppliers;
- invoices;
- recipes;
- next-ID counters.

The application loads this file at startup and seeds initial data when no products are present.

Legacy JSON without categories loads with an empty category collection and uncategorized products. The category next-ID counter is recovered from saved state and existing category IDs.

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
