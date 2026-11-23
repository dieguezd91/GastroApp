# User interface: design system, shell and shared components

The UI was ported from the `prototypes/ui-ux/` reference (tokens, layout, components, iconography). Business rules stay in the services; pages and shared components only collect input and render. This document describes the implemented structure; the source code is authoritative.

## Design system (`wwwroot/css/`)

All stylesheets are plain `<link>` tags in `Pages/_Host.cshtml`. They share one cascade-layer order, declared first in `legacy.css`:

```text
legacy → base → theme → layout → components → compat → views → utilities
```

A later layer wins over an earlier one, regardless of selector specificity or file order.

| File | Layer | Contents |
|---|---|---|
| `legacy.css` | `legacy` | Declares the layer order and imports Bootstrap (`bootstrap/bootstrap.min.css`) and `site.css` at the **lowest** priority. |
| `tokens.css` | `theme` | Design tokens as CSS variables (color, space, radius, shadow, type). |
| `base.css` | `base` | Reset and element defaults. |
| `layout.css` | `layout` | App shell (sidebar, topbar, drawer, main area), page header, grids and stacks. |
| `components.css` | `components` | Buttons, fields, cards, tables, badges, banners, tabs, modal, toast, KPI card. |
| `compat.css` | `compat` | Bridge mapping old Bootstrap button classes (`.btn-primary`, `.btn-success`, `.btn-danger`) to the new look. |
| `views.css` | `views`, `utilities` | Login view plus the utility classes. |
| `views/<view>.css` | `views` | One file per screen: `dashboard`, `pos`, `cash`, `catalog`, `inventory`, `recipes`, `purchasing`, `sales-history`. |

Rules:

- **Bootstrap stays in the `legacy` layer** until the last page stops using it; then remove the two `@import` lines in `legacy.css`, `compat.css` and the layer itself.
- New screen styles go in their own `views/<view>.css` (one owner per file), never in `components.css`, unless the rule is reusable by several screens.
- Use tokens (`var(--space-4)`, …) instead of literal values.
- `Shared/MainLayout.razor.css` and `Shared/NavMenu.razor.css` are the only scoped (CSS isolation) stylesheets left; they are small.
- Target widths are 1440 / 1024 / 390 px with no horizontal overflow; language is Argentine Spanish with `es-AR` money/date formats (WCAG 2.2 AA is the goal).

## App shell

`Shared/MainLayout.razor` renders two modes:

- **Authenticated:** `.app-shell` with a sidebar, a topbar and `<main id="main-content">`. A "Saltar al contenido principal" skip link is always first.
- **Anonymous** (login): `.app-shell--auth`, only the page body.

| Piece | Behavior |
|---|---|
| Sidebar | Persistent from `72rem` up; contains `NavMenu`. |
| Drawer | Below `72rem` the same `NavMenu` is rendered a second time inside a native modal `<dialog id="nav-drawer">`, opened by the topbar menu button. `wwwroot/js/shell.js` (`initDrawer`/`disposeDrawer`, imported on demand) opens it, swipe/scroll-away closes it, and it closes itself when the viewport becomes desktop. |
| Topbar | Crumb and title derived from the URL by `MainLayout.GetRouteInfo` (tabbed screens keep their group title), `CashStatusBadge` and a role badge. |
| `CashStatusBadge` | Shows **Caja #N abierta** or **Caja cerrada**. `CashRegisterService` raises no change events, so the component re-reads the current register **every 5 seconds** with a timer; only this component re-renders, and only when the state changed. |
| `SectionNavLink` | `NavLink` subclass with `AlsoMatch` route prefixes, so a sidebar entry of a tabbed view stays active on the tab sub-routes. |

`MainLayout` and `NavMenu` subscribe to `AuthService.OnAuthStateChanged` through `InvokeAsync` and unsubscribe on dispose (see [Authentication.md](Authentication.md)).

## Role navigation

`NavMenu` groups links by role. There are only the two existing roles.

| Group | Entries | Roles |
|---|---|---|
| Operación diaria | Inicio / Panel operativo (`/`), Vender (POS) (`/sales`) | Employee, Admin |
| Caja y ventas | Caja diaria (`/cash`), Historial de cajas (`/cash/history`), Historial de ventas (`/sales/history`), Resumen del día (`/summary`) | Admin |
| Catálogo e inventario | Productos y categorías, Ingredientes y stock, Recetas y costos, Proveedores y facturas | Admin |

The footer shows the user and **Cerrar sesión**. The prototype's *Reportes* and *Configuración* entries (proposals) and its demo bar are **not** implemented. Hiding a link is not authorization: every page still checks the role itself (see [Authentication.md](Authentication.md)).

## Tabbed views

Related screens share one shell component with an accessible tab strip (`role="tablist"`, roving `tabindex`, arrow keys/Home/End). Selecting a tab navigates in-circuit to that tab's route (no reload) and passes `HistoryEntryState` so the destination restores focus to its tab.

| View (shell) | Tab | Route | Page component |
|---|---|---|---|
| Catálogo (`Shared/Catalog/CatalogView`) | Productos | `/products` | `Pages/Products.razor` |
| | Categorías | `/product-categories` | `Pages/ProductCategories.razor` |
| Inventario (`Shared/Inventory/InventoryView`) | Stock y alertas | `/ingredients` | `Pages/Ingredients.razor` |
| | Movimientos | `/ingredients/movements` (all ingredients) and `/ingredients/{id}/movements` (one) | `Pages/IngredientMovements.razor` |
| | Conteo físico | `/stock/count`, `/stock/count/{countId}` | `Pages/StockCount.razor` |
| Compras (`Shared/Purchasing/PurchasingView`) | Facturas | `/invoices` | `Pages/Invoices.razor` |
| | Proveedores | `/suppliers` | `Pages/Suppliers.razor` |

Why the pages stay separate (one component per route, each wrapping the shell) instead of one component with a tab state:

- Existing URLs keep working and open the matching tab.
- `scripts/verify-auth-isolation.ps1` and the stock/cash harnesses pin page classes and methods **by reflection and source text** (for example `Products.ShowAddForm`, `EditProduct`, `SaveProduct`, `DeleteProduct`, `ProductCategories.EditCategory`, `SaveCategory`, `DeleteCategory`). Merging pages would break those pins.

The shell receives the active tab, the counts for the header, and `HeaderActions`/`ChildContent` from the active page. Per-view helpers live next to the shell (`CatalogSupport`, `InventorySupport`, `PurchasingSupport`).

## Shared components (`Shared/`)

| Component | API | Notes |
|---|---|---|
| `Icon` | `Name` (required), `Size` = 18, `Class` | Inline SVG set (24×24, stroke 1.85), decorative (`aria-hidden`). Unknown names fall back to `info`. Icon-only buttons need their own `aria-label`. |
| `Badge` | `Label` (required), `Variant` = `neutral`, `Icon` | Variants `ok`, `warn`, `danger`, `info`, `neutral`, `proposal`. Never rely on color alone: always set a label. |
| `Banner` | `Variant` = `info`, `Title`, `ChildContent`, `Actions` | Variants `ok`, `warn`, `danger`, `info`, `proposal`. `danger` uses `role="alert"`. |
| `KpiCard` | `Label`, `Value` (required), `Meta`, `StatusContent` | `StatusContent` usually holds a `Badge`. |
| `ModalDialog` | `Title` (required), `Subtitle`, `Size` (`md`/`lg`), `LightDismiss` = true, `ChildContent`, `Footer`, `OnClosed(string)`; methods `ShowAsync()`, `CloseAsync(returnValue = "cancel")`, property `IsOpen` | Native `<dialog>` through `wwwroot/js/dialog.js`. The body renders only while open, so each opening starts from fresh child state. The footer is a `<form method="dialog">`: `<button value="x">` closes with that `returnValue` without a server round trip (use `type="button"` to avoid closing). Esc, backdrop click and ✕ report `"cancel"`. Disable `LightDismiss` for forms with unsaved input. |
| `Toast` | Method `Show(message, variant = "ok", durationMs = 4800)`; variants `ok`, `warn`, `danger` | One per page (`<Toast @ref="toast" />`). Popover in the top layer via `wwwroot/js/toast.js`; a new toast replaces the visible one; `durationMs <= 0` keeps it until closed; it stays while it holds focus. While a modal dialog is open the visual toast is suppressed, but the message is still announced through the polite/assertive live regions. |

JavaScript is limited to three small modules imported on demand through JS interop (`dialog.js`, `toast.js`, `shell.js`); every other behavior is Blazor. Components catch `JSDisconnectedException` because the circuit can end first.

Feature components live in folders named after their screen (`Shared/Pos/`, `Shared/Cash/`, `Shared/Catalog/`, `Shared/Inventory/`, `Shared/Recipes/`, `Shared/Purchasing/`, `Shared/SalesHistory/`) and are used only by that screen's page(s).

## Workspace pattern

Long forms use a full-width panel with a **← Volver** button instead of a modal: the page swaps its list for the workspace (`.workspace-panel`) and moves focus back to the list heading on return. Used by:

- **Recetas** (`Pages/Recipes.razor` → `Shared/Recipes/RecipeWorkspace`): multi-ingredient recipe form with a cost preview.
- **Facturas** (`Pages/Invoices.razor` → `Shared/Purchasing/InvoiceWorkspace`): invoice header plus lines.
- **Devoluciones** (`Pages/SalesHistory.razor`): the refund form, while the sale detail dialog yields to it.

The recipe preview runs `RecipeService.CalculateCosts` on a scratch copy of the recipe; nothing is saved until the user confirms.

## Known limits

- **Switching tabs discards page state.** Each tab is its own page, so leaving `/stock/count` mid-count loses the selection and typed quantities.
- **Bootstrap still leaks.** While the `legacy` layer exists, some Bootstrap rules apply to elements the design system does not style (for example Bootstrap `.card` sets `flex-direction: column`, which leaks into `.card.toolbar`). Fix by overriding in the page's `views/<view>.css` or by finishing the Bootstrap removal.
- **Topbar badge polls.** The cash status can lag up to 5 seconds behind another circuit; there is no push mechanism.
- **Direct callbacks are not browser-verified by the harnesses.** The `scripts/verify-*.ps1` checks exercise services and renderer-less callbacks; layout, focus and drawer behavior need a manual browser pass.
