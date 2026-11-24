# GastroApp

GastroApp is a prototype web application for managing small food businesses. It combines point-of-sale operations, daily cash management, products, ingredient inventory, suppliers, purchase invoices, standardized recipes, and recipe costing in a single Blazor Server application.

The repository is currently focused on validating product flows and business rules. It is not yet a production-ready multi-user system.

## Tech Stack

- C#
- ASP.NET Core 10.0
- Blazor Server
- .NET 10.0 (LTS) target framework
- JSON file persistence through `DataStorageService`
- BCrypt.Net-Next 4.0.3 for password hashing

## Implemented Features

### User Interface

The whole UI follows one design system (tokens, layout and components in `wwwroot/css/`, inline SVG icons) in Argentine Spanish with `es-AR` formats. Details: [Docs/Architecture/UserInterface.md](Docs/Architecture/UserInterface.md).

- App shell with a sidebar (from 72 rem wide) or a drawer on narrow screens, and a topbar with the cash register status and the user's role.
- Role-based menu: **Operación diaria** (everyone), **Caja y ventas** and **Catálogo e inventario** (Admin).
- Related screens are tabs of one view: **Productos y categorías**, **Ingredientes e inventario** (stock, movements, physical count) and **Proveedores y facturas**. Their original URLs still work.
- Long forms (recipes, invoices, refunds) open as a full-width workspace with a **← Volver** button.
- Reusable components for badges, banners, KPI cards, modal dialogs and toasts.
- The prototype's *Reportes* and *Configuración* proposals are intentionally **not** implemented.

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

The main dashboard (**Inicio** for employees, **Panel operativo** for admins) displays:

- cash register state, opening time and initial cash when open;
- shift metrics (sales and total of the open session);
- stock alerts (employees see ingredients out of stock);
- a direct action to the point of sale;
- for admins, a priority list, the latest sales and shortcuts to the other modules.

### Product Management

Admin users manage products and categories in the **Productos y categorías** view (`/products`, `/product-categories`) and can:

- create, edit and delete products (deleting asks for confirmation);
- define sale price and optional product cost, and assign an optional category;
- activate or deactivate products;
- review calculated margin and its visual status;
- see a **Costo desfasado** warning when the saved cost differs from the cost of the recipe with the same name, and synchronize it in one click.

Margin is calculated as:

```text
(price - cost) / price * 100
```

### Point of Sale

Authenticated users can:

- browse the catalog by category and name, and add products to a cart;
- edit quantities, line notes and line or whole-sale discounts;
- remove cart items or clear the cart;
- charge with one or more payment methods (cash shows change; the amount received defaults to the amount due);
- register a sale when the cash register is open and see its receipt right after checkout (visual only, not a fiscal document).

Products whose recipe stock cannot cover one more unit are blocked in the catalog and in the cart (counting what the cart already reserves), naming the missing ingredient. Checkout still validates ingredient availability atomically for products that can be matched to a recipe.

### Cash Register

Admin users can:

- open the current cash register with an initial amount;
- view the session in a KPI strip (opening, cash inflow, expected cash, net receipts);
- record manual income, expenses and withdrawals;
- close the register through a detailed cash count (arqueo) and a confirmation dialog;
- review closed sessions in **Historial de cajas**.

Closing a register also creates a `DailySummary` entry. See [Docs/Architecture/CashRegisters.md](Docs/Architecture/CashRegisters.md).

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

Ingredients, movements and physical counts are the tabs of the **Ingredientes e inventario** view (`/ingredients`, `/ingredients/movements`, `/stock/count`). Admin users can manage ingredients with:

- name;
- base unit;
- active/inactive state;
- current stock (read-only: a new ingredient starts without stock and receives it through purchase invoices, adjustments, waste or counts);
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

Admin users manage suppliers and register purchase invoices in the **Proveedores y facturas** view (`/invoices`, `/suppliers`); invoices are created in a full-width workspace. Invoice and supplier deletion ask for confirmation.

An invoice contains:

- date;
- supplier;
- optional invoice number;
- optional notes;
- one or more ingredient items;
- quantity;
- unit;
- unit price.

A line can be typed in any unit compatible with the ingredient; it is stored converted to the ingredient base unit (500 gr at 0.1 becomes 0.5 kg at 100) and added to current stock.

The most recent invoice price for an ingredient is used by recipe costing.

### Recipes and Costing

Admin users can create and edit standardized recipes in a full-width workspace with a live cost preview, with:

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
├── Models/                  # data models (products, sales, cash, stock, recipes, ...)
├── Services/                # business logic, one service per domain + UnitConverter
├── Pages/                   # routable Blazor pages (one per route)
├── Shared/
│   ├── MainLayout, NavMenu, SectionNavLink, CashStatusBadge   # app shell
│   ├── Icon, Badge, Banner, KpiCard, ModalDialog, Toast       # shared components
│   └── Pos/ Cash/ Catalog/ Inventory/ Recipes/ Purchasing/ SalesHistory/   # per-screen components
├── wwwroot/
│   ├── css/                 # design system layers + views/<screen>.css
│   └── js/                  # dialog.js, toast.js, shell.js (loaded on demand)
├── Docs/Architecture/       # architecture documents
├── scripts/                 # verify-*.ps1 harnesses
├── odd/                     # task specs
└── data.json
```

## Architecture

The application currently uses a simple service-oriented structure:

- `Models/` contains application data models.
- `Services/` owns business logic and state coordination.
- `Pages/` contains routable Blazor UI.
- `Shared/` contains the app shell, shared UI components and per-screen components (see [Docs/Architecture/UserInterface.md](Docs/Architecture/UserInterface.md)).
- `Program.cs` is the composition root.
- `DataStorageService` owns JSON serialization and the main in-memory collections.

Most application services are registered as singletons; `AuthService` alone is scoped per Blazor circuit.

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

### Run with Docker

The repository includes a `Dockerfile` that publishes the app and serves it on port `8080`:

```bash
docker build -t gastroapp .
docker run -p 8080:8080 gastroapp
```

Then open `http://localhost:8080`. The container starts from the `data.json` committed in the repository; changes made inside the container are lost when the container is recreated.

The Dockerfile restores with only `GastroApp.csproj` copied. Since .NET 10 the Blazor script (`_framework/blazor.server.js`) is a static web asset that restore only pulls in when it sees `.razor` files, so the project sets `RequiresAspNetWebAssets`. To check that the published output still contains the script without Docker, run:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-publish-assets.ps1
```

## Current Constraints

The current implementation has several known architectural limitations:

- `AuthService` is scoped per Blazor circuit and stores the login in memory, so a full reload, a new tab or a replacement circuit starts unauthenticated (see [Docs/Architecture/Authentication.md](Docs/Architecture/Authentication.md)).
- All other application services share singleton in-memory state.
- JSON persistence provides no database transactions, concurrency control, or multi-instance consistency.
- Save behavior is not uniform across all mutations.
- Product-to-recipe stock consumption (and the recipe cost sync) is matched by product name to recipe name rather than by a stable relationship ID.
- Recipe yield is not applied to stock deduction: `SaleService.RecipeRequirements` deducts the full recipe quantity per unit sold, so recipes with a yield above 1 over-deduct ingredients. The POS availability check mirrors checkout and inherits the same behavior.
- Recalculating a recipe from its card runs the cost calculation twice (`CalculateCosts`, then again inside `RecipeService.Update`), so the cost variation indicator ends green after **Recalcular** because the previous cost is overwritten before the comparison.
- `scripts/verify-payment-summary.ps1` pins `data.json` and `GastroApp.csproj` hashes that no commit since `7a173fd` matches, so it fails independently of the UI changes.
- Each tab of a tabbed view is a separate page: switching tabs discards unsaved page state (for example a physical count in progress).
- Bootstrap is still loaded in the lowest CSS layer until every page stops using it; some of its rules can leak into new components.
- The topbar cash status refreshes by polling every 5 seconds; there is no push across circuits.
- Deleting or editing an existing invoice does not automatically reconcile stock previously added by that invoice.
- The application has no automated test project in the repository.
- The project targets `net10.0` (LTS); framework upgrades should be handled as explicit work rather than incidental changes.

These constraints should be treated as current implementation state, not as intended production architecture.
