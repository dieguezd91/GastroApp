# Implemented Changes: Recipe Costing and Inventory Integration

## Status

This document describes functionality that is currently present in the repository. It replaces older Spanish notes that no longer fully reflected the implementation.

Current code remains the source of truth.

## 1. Relative Recipe Cost Indicators

Recipe cost indicators no longer depend on fixed absolute currency thresholds.

Each `Recipe` stores:

```csharp
public decimal LastCalculatedCost { get; set; }
public DateTime? LastCalculatedAt { get; set; }
```

`RecipeService.CalculateCosts()` compares the current unit cost with the previously calculated unit cost.

The absolute percentage variation determines the indicator:

- green: variation below 10%;
- yellow: variation from 10% to below 30%;
- red: variation of 30% or greater.

The first calculation defaults to green because there is no previous reference value.

The calculation intentionally uses absolute variation, so an increase and decrease of the same magnitude produce the same indicator.

## 2. Automatic Unit Conversion

`UnitConverter` centralizes conversion between compatible units.

Supported conversions:

```text
kg <-> gr
lt <-> ml
```

The same unit is always considered compatible.

Weight and volume units are not interchangeable, and `unidad` is only compatible with itself.

Main API:

```csharp
decimal? Convert(decimal quantity, string fromUnit, string toUnit)
bool AreCompatible(string unit1, string unit2)
string GetUnitCategory(string unit)
```

A failed or incompatible conversion returns `null`.

## 3. Recipe Cost Calculation

`RecipeService.CalculateCosts()` now:

1. reads the latest known ingredient price from purchase invoices;
2. resolves the ingredient base unit;
3. verifies unit compatibility;
4. converts the recipe quantity to the base unit;
5. calculates the ingredient subtotal;
6. accumulates the recipe total cost;
7. calculates cost per yield unit;
8. updates the relative cost indicator;
9. stores the new calculation reference and timestamp.

If no price exists, the ingredient contributes zero to the calculated cost.

If units are incompatible, the ingredient is excluded from the calculated total.

The recipe editor also exposes compatibility feedback and cost preview behavior.

## 4. Ingredient Stock Tracking

`Ingredient` now includes:

```csharp
public decimal CurrentStock { get; set; }
public decimal MinStock { get; set; }
```

The computed `StockIndicator` reports:

- red when `CurrentStock <= 0`;
- yellow when stock is positive but at or below `MinStock`;
- green when stock is above `MinStock`.

The ingredient management page allows administrators to edit both values and manually adjust current stock.

## 5. Purchase Invoices Increase Stock

When `InvoiceService.Add()` registers an invoice:

1. the invoice receives its ID;
2. every invoice item receives the invoice ID;
3. the invoice is stored;
4. each item quantity is converted to the ingredient base unit;
5. the resulting quantity is added to ingredient stock;
6. application data is saved to `data.json`.

This means purchase invoices currently act as stock-entry operations.

The latest invoice price is also the price source used for recipe costing.

## 6. Sales Validate and Consume Stock

Before checkout, `SaleService.ValidateStock()` validates ingredient availability for products associated with recipes.

The current association rule is name-based:

```text
Product.Name == Recipe.Name
```

For each matching recipe:

1. required ingredient quantities are multiplied by the sale quantity;
2. quantities are converted to the ingredient base unit;
3. current stock is checked;
4. the sale is rejected when a required ingredient has insufficient stock.

After a successful sale, `SaleService` deducts the corresponding ingredient quantities through `IngredientService.TryRemoveStock()`.

Products with no recipe name match bypass ingredient stock validation and deduction.

## 7. Files Involved

Primary files for this functionality:

```text
Models/Ingredient.cs
Models/Recipe.cs
Models/RecipeIngredient.cs
Models/Invoice.cs
Models/InvoiceItem.cs

Services/IngredientService.cs
Services/InvoiceService.cs
Services/RecipeService.cs
Services/SaleService.cs
Services/UnitConverter.cs
Services/DataStorageService.cs

Pages/Ingredients.razor
Pages/Invoices.razor
Pages/Recipes.razor
Pages/Sales.razor

Program.cs
```

## 8. Current Technical Limitations

The implementation is functional but still prototype-level.

Known limitations relevant to these changes:

- Product-to-recipe association uses names rather than a stable ID.
- Invoice deletion does not reverse stock that was previously added.
- Invoice updates do not reconcile stock differences.
- Incompatible units are skipped instead of producing a hard business-rule failure.
- Supported conversion units are limited to `kg`, `gr`, `lt`, `ml`, and identical-unit cases such as `unidad`.
- Stock operations and JSON persistence are not transactional.
- There is no automated test project currently present in the repository.

These points describe the current implementation and should not be interpreted as the intended final production architecture.
