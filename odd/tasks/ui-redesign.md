# UI redesign — port `prototypes/ui-ux/` to the Blazor app
Source: `prototypes/ui-ux/` (README, `docs/DESIGN_SYSTEM.md`, `docs/NAVIGATION_MAP.md`, `docs/UX_DECISIONS.md`, `styles/`, `js/views/`, `screenshots/`). Branch `feat/ui-redesign` (from `main` f16587e).
No `data.json` edits; no push (main deploys to Render). Spanish UI, English code/docs. One reviewable commit per task; behavior changes get their own commit and a `scripts/verify-*.ps1` harness.

## Specs
- S1 (scope, L2): "Toda la app, por fases" — every existing screen adopts the prototype's design system and layouts, phase by phase. The prototype is the visual/UX reference; current services remain the source of business rules except where S8–S10 change them.
- S2 (design system): port the prototype tokens and styles (`styles/tokens.css`, `base.css`, `layout.css`, `components.css`, `views.css`) and its SVG iconography into `wwwroot/`; Argentine Spanish, ARS, `es-AR` formats; WCAG 2.2 AA; responsive at 1440px / 1024px / 390px with zero horizontal overflow.
- S3 (shell and navigation): app shell per `docs/NAVIGATION_MAP.md`: sidebar ≥ 72rem, `<dialog>` drawer below it, topbar with cash-register status and role; menu grouped by role (Empleado: Inicio, Vender; Admin: Operación diaria, Caja y ventas, Catálogo e inventario). Only the two existing roles. The prototype's demo bar (role switcher, scenarios) is not ported.
- S4 (proposals excluded, L2): "Dejarlas afuera" — `#reports` (M20) and `#settings` (M01/M18/M21) are not implemented.
- S5 (tabs, L2): "Unificar en pestañas" — Productos + Categorías, Stock y alertas + Movimientos + Conteo físico, Facturas + Proveedores become tabbed views. Existing URLs (`/products`, `/product-categories`, `/ingredients`, `/ingredients/{id}/movements`, `/stock/count`, `/invoices`, `/suppliers`) keep working and open the matching tab.
- S6 (screens): Login, Dashboard (`/`), POS (`/sales`), Caja (`/cash`), Historial de cajas (`/cash/history`), Historial de ventas (`/sales/history`), Resumen (`/summary`), Catálogo, Inventario, Recetas (`/recipes`), Compras, Acceso denegado (`/unauthorized`) follow the matching prototype view, including its empty, error, validation, loading and success states, and the workspace pattern (full-width panel with "← Volver") for Recetas, Facturas and Devoluciones.
- S7 (preserved behavior): authorization per route, role guards, and every current service rule and validation stay as they are unless S8–S10 change them.
- S8 (POS stock pre-block, L2 "Sí, incluirlas"): per `UX_DECISIONS.md` §2: "los productos sin stock disponible por receta quedan marcados con `aria-disabled="true"` y no permiten agregarse al carrito (explicando qué ingrediente falta). Además, el cálculo descuenta en tiempo real el stock ya reservado por el carrito actual, bloqueando superar el máximo disponible tanto desde las tarjetas como desde `+` o el campo numérico de cantidad, manteniendo la validación atómica al cobrar como segunda línea de defensa."
- S9 (recipe cost sync, L2): per `UX_DECISIONS.md` §4: "se advierte cuando el costo guardado del producto quedó desfasado respecto al último cálculo de receta y se ofrece sincronizarlo en un clic (visibilizando además el contrato actual de coincidencia por nombre exacto)."
- S10 (post-checkout receipt, L2): "comprobante visual inmediato post-cobro" — after a successful checkout the POS shows the sale's receipt (items, discounts, payments, change). Visual only; no fiscal document (M13).

## Tasks
| ID | Specs | Route | Commit |
| --- | --- | --- | --- |
| T1 | S2, S3, S4, S7 | worker: design system CSS + icons in `wwwroot/`, `_Host.cshtml`, `MainLayout`/`NavMenu` shell, topbar, drawer; Login + Acceso denegado | 799aea3 |
| T2 | S6, S7 | worker: Dashboard (`/`) | — |
| T3 | S6, S7 | worker: POS UI (`/sales`): catalog, cart, line dialog, checkout with mixed payments | — |
| T4 | S8 | worker: POS stock availability (service + UI) + `scripts/verify-pos-availability.ps1` | — |
| T5 | S10 | worker: post-checkout receipt | — |
| T6 | S6, S7 | worker: Caja + Historial de cajas | — |
| T7 | S5, S6, S7 | worker: Catálogo tabs (Productos + Categorías) | — |
| T8 | S9 | worker: recipe→product cost drift + one-click sync (service + UI) + harness | — |
| T9 | S5, S6, S7 | worker: Inventario tabs (Stock, Movimientos, Conteo físico) | — |
| T10 | S6, S7 | worker: Recetas workspace | — |
| T11 | S5, S6, S7 | worker: Compras tabs (Facturas workspace + Proveedores) | — |
| T12 | S6, S7 | worker: Historial de ventas (refund workspace) + Resumen | — |
| T13 | all | gentle-ai-verify over the branch; docs (`README.md`, `Docs/Architecture/`) | — |

## Log
- L1: "vamos a implementar estos cambios en la UI" (the changes in `prototypes/ui-ux/`).
- L2: user decisions: alcance "Toda la app, por fases (recomendado)"; propuestas "Dejarlas afuera (recomendado)"; navegación "Unificar en pestañas (recomendado)"; comportamiento (bloqueo de stock en POS, sincronizar costo receta→producto, comprobante post-cobro) "Sí, incluirlas".
- L3: parent decision: work on `feat/ui-redesign`, not `main`, because every push to `main` redeploys the tester's Render instance.
- L4: T1 done (799aea3, hash recorded 1eb0491). Per-view CSS slots `wwwroot/css/views/<view>.css` added (8ab76c4) so parallel workers own disjoint files; parallel workers do not commit or edit this document, the parent does. Known pre-existing failure: `scripts/verify-payment-summary.ps1` pins a csproj hash that no commit since 7a173fd matches (not caused by this branch). `scripts/verify-stock-count.ps1` fails one nav check ("Conteo de stock" link) by design of the new menu; T9 updates it. Slice boundary: T1 alone exceeds ~400 lines (CSS port); publish shape decided at delivery.
