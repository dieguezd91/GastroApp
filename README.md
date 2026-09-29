# GastroApp

GastroApp is a prototype web application for managing small food businesses. It combines point-of-sale operations, daily cash management, products, ingredient inventory, suppliers, purchase invoices, standardized recipes, and recipe costing in a single Blazor Server application.

The repository is currently focused on validating product flows and business rules. It is not yet a production-ready multi-user system.

## Tech Stack

- C#
- ASP.NET Core 7.0
- Blazor Server
- .NET 7.0 target framework
- JSON file persistence through `DataStorageService`
- BCrypt.Net-Next 4.0.3 for password hashing

## Implemented Features

### Authentication and Authorization

- Username/password login
- BCrypt password verification
- Admin and Employee roles
- Authentication-aware navigation
- Admin-only access to management modules
- Authenticated access to the point of sale

A default development administrator is created when seed data is generated:

```text
Username: admin
Password: admin
```

These credentials are intended only for local prototype use.

### Dashboard

The main dashboard displays:

- cash register state;
- opening time and initial cash when open;
- today's sales total;
- direct access to the point of sale;
- admin shortcuts to products, recipes, cash management, and daily summary.

### Product Management

Admin users can:

- create products;
- edit products;
- delete products;
- define sale price;
- optionally define product cost;
- review calculated margin and its visual status.

Margin is calculated as:

```text
(price - cost) / price * 100
```

### Point of Sale

Authenticated users can:

- add products to a cart;
- change quantities by adding repeated products;
- remove cart items;
- clear the cart;
- register a sale when the cash register is open.

Before checkout, the application validates ingredient availability for products that can be matched to a recipe.

### Cash Register

Admin users can:

- open the current cash register with an initial amount;
- view current register information;
- close the register with the counted final amount;
- calculate the expected amount from initial cash plus today's sales;
- calculate the resulting cash difference.

Closing a register also creates a `DailySummary` entry in memory.

### Daily Summary

The daily summary includes:

- total sales;
- transaction count;
- top-selling product;
- top-selling quantity;
- cash opening amount;
- cash closing amount;
- cash difference when the register has been closed.

### Ingredient and Inventory Management

Admin users can manage ingredients with:

- name;
- base unit;
- active/inactive state;
- current stock;
- minimum stock threshold.

Supported units are currently:

- `kg`
- `gr`
- `lt`
- `ml`
- `unidad`

The UI exposes a stock status indicator:

- red when stock is zero or below;
- yellow when stock is at or below the configured minimum;
- green when stock is above the minimum.

Stock can also be adjusted manually.

### Suppliers and Purchase Invoices

Admin users can manage suppliers and register purchase invoices.

An invoice contains:

- date;
- supplier;
- optional invoice number;
- optional notes;
- one or more ingredient items;
- quantity;
- unit;
- unit price.

When an invoice is added, compatible ingredient quantities are converted to the ingredient base unit and added to current stock.

The most recent invoice price for an ingredient is used by recipe costing.

### Recipes and Costing

Admin users can create and edit standardized recipes with:

- recipe name;
- yield;
- ingredient list;
- ingredient quantities;
- calculated total cost;
- calculated unit cost.

Recipe costing uses the latest registered purchase price for each ingredient.

Compatible units are converted automatically:

```text
1 kg = 1000 gr
1 lt = 1000 ml
```

Weight and volume are not converted across categories.

If a recipe ingredient uses an incompatible unit, that ingredient is excluded from the cost calculation.

### Cost Change Indicators

Each recipe stores:

- `LastCalculatedCost`
- `LastCalculatedAt`

When a recipe is recalculated, the absolute percentage variation from the previous unit cost determines its indicator:

- green: less than 10%;
- yellow: 10% to less than 30%;
- red: 30% or greater.

For the first calculation, the indicator defaults to green.

### Stock Consumption from Sales

When a sale is completed:

1. GastroApp looks for a recipe whose name matches the sold product name.
2. Required ingredient quantities are converted to each ingredient's base unit.
3. Available stock is validated.
4. The sale is rejected if a required ingredient does not have enough stock.
5. If validation succeeds, ingredient stock is deducted.

Products without a matching recipe are currently sold without ingredient stock validation or deduction.

## Project Structure

```text
GastroApp/
├── AGENTS.md
├── App.razor
├── GastroApp.csproj
├── Program.cs
├── Models/
│   ├── Product.cs
│   ├── Sale.cs
│   ├── CashRegister.cs
│   ├── DailySummary.cs
│   ├── User.cs
│   ├── UserRole.cs
│   ├── Ingredient.cs
│   ├── Supplier.cs
│   ├── Invoice.cs
│   ├── InvoiceItem.cs
│   ├── Recipe.cs
│   └── RecipeIngredient.cs
├── Services/
│   ├── AuthService.cs
│   ├── UserService.cs
│   ├── DataStorageService.cs
│   ├── ProductService.cs
│   ├── SaleService.cs
│   ├── CashRegisterService.cs
│   ├── IngredientService.cs
│   ├── SupplierService.cs
│   ├── InvoiceService.cs
│   ├── RecipeService.cs
│   └── UnitConverter.cs
├── Pages/
├── Shared/
├── wwwroot/
└── data.json
```

## Architecture

The application currently uses a simple service-oriented structure:

- `Models/` contains application data models.
- `Services/` owns business logic and state coordination.
- `Pages/` contains routable Blazor UI.
- `Shared/` contains shared layout and navigation components.
- `Program.cs` is the composition root.
- `DataStorageService` owns JSON serialization and the main in-memory collections.

Most application services are currently registered as singletons.

Some service relationships are wired after dependency injection construction through setter methods in `Program.cs` to avoid circular constructor dependencies.

For repository-wide agent instructions and source-of-truth rules, see `AGENTS.md`.

## Persistence

Application data is loaded from and serialized to `data.json`.

The stored data includes:

- products;
- sales;
- current cash register;
- daily summaries;
- users;
- ingredients;
- suppliers;
- invoices;
- recipes;
- next-ID counters.

Persistence is still prototype-level. Save operations are not currently invoked uniformly by every service mutation, so not every state change has the same durability guarantees.

## How to Run

From the repository root:

```bash
dotnet restore
dotnet run
```

Use the local URL printed by ASP.NET Core in the terminal.

To validate the project without starting the application:

```bash
dotnet build
```

## Current Constraints

The current implementation has several known architectural limitations:

- `AuthService` is registered as a singleton and stores the current user in memory, so authentication state is not isolated per Blazor circuit.
- Application services share singleton in-memory state.
- JSON persistence provides no database transactions, concurrency control, or multi-instance consistency.
- Save behavior is not uniform across all mutations.
- Product-to-recipe stock consumption is matched by product name to recipe name rather than by a stable relationship ID.
- Deleting or editing an existing invoice does not automatically reconcile stock previously added by that invoice.
- The application has no automated test project in the repository.
- The project targets `net7.0`; framework upgrades should be handled as explicit work rather than incidental changes.

These constraints should be treated as current implementation state, not as intended production architecture.
