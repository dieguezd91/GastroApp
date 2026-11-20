# M15 — Ingredients, stock and movements
Source: `Docs/Architecture/GastroApp_Documento_Diseno_Producto.docx`, module M15 (core only) and rules 9.3/9.4. Branch `feat/stock-movements` (from `feat/sales-history-refunds` ee29f05).
No `data.json`/csproj edits; no push. Spanish UI, English code/docs. Product decisions delegated by the user (L1) are recorded in L2.

## Specs
- S1 (ledger): "Registrar ingresos por compras, consumos de preparación/venta, ajustes, mermas, devoluciones y transferencias." Transfers need multiple locations (out of scope, L2); every other stock change becomes a persisted movement.
- S2 (movement data): "Mostrar para cada movimiento origen, cantidad, unidad, stock anterior y posterior, fecha, motivo y responsable."
- S3 (history): "Consultar historial por ingrediente y período con filtros por causa."
- S4 (counts): "Realizar conteos físicos, comparar con existencia registrada y confirmar diferencias."
- S5 (alerts): "Configurar alertas de mínimo, agotamiento y cobertura estimada según consumo."
- S6 (no silent overwrite): "Todo ajuste debe incluir causa y dejar registro, no sustituir el saldo sin historial."
- S7 (purchases): "Una compra solo incrementa stock cuando la mercadería se recibe y acepta." Today an invoice is the reception; its stock-in becomes a movement linked to the invoice (L2).
- S8 (waste): "Las mermas tienen categoría y motivo independientes de las ventas."
- S9 (no double deduction): "El sistema no debe descontar dos veces ingredientes usados en una preparación." A sale deducts all-or-nothing: validate aggregated requirements before any mutation (fixes the partial-deduction path, L3).
- S10 (negative stock): "Una existencia negativa requiere una política explícita del negocio y una advertencia visible." Policy (L2): manual operations never produce negative stock; existing negative balances show a visible warning.
- S11 (traceability): "Cada variación de inventario tiene causa y puede rastrearse al documento u operación de origen." Movements link to sale, refund, invoice or count.
- S12 (corrections): "Se distinguen corrección de datos en borrador, anulación de operación, devolución de dinero y ajuste de existencias." / "Toda excepción sensible requiere motivo y responsable, y queda visible para supervisión."
- S13 (integrity guards, L3): unit change is rejected once an ingredient has stock or movements; deleting an ingredient referenced by recipes, invoices, sales or movements is rejected (deactivate instead).

## Tasks
| ID | Specs | Route | Commit |
| --- | --- | --- | --- |
| T1 | S1, S2, S6, S7, S9, S11 | worker: `StockMovement` ledger + single mutation path in `IngredientService`, persistence; sale deduction (atomic), cancellation restore, refund restock, invoice receipt through it; actor passed from pages; harness | — |
| T2 | S2, S3, S5, S6, S8, S10, S12, S13 | worker: Ingredients page (stock read-only in edit form; adjustment with reason; waste with category; guards), per-ingredient history page with filters, alerts with coverage; docs | — |
| T3 | S4, S10, S12 | worker: physical count flow (select ingredients, counted vs registered, reasons, confirm → count record + movements); docs | — |
| T4 | all | gentle-ai-verify (Risk item 1: persisted format change; stock mutation paths) | — |

## Log
- L1: "commitea y segui con lo que te parezca mas razonable" — parent chose M15 as next module.
- L2: parent decisions (delegated): scope = M15 core only (no locations, transfers, lots, expiry, committed stock, valuation); negative stock rejected for manual operations, legacy negative shown with warning; legacy stock without history is not migrated (history shows "saldo previo sin historial"); invoice edit/delete semantics stay for M16; waste categories: Vencimiento, Rotura o derrame, Error de preparación, Otro.
- L3: exploration (gentle-ai-explore): mutators `IngredientService.Update/AdjustStock/AddStock/TryRemoveStock` take no actor; `SaleService` Cancel/Refund mutate `CurrentStock` directly; `SaleService.Add` adds the sale before `DeductStockFromSale` and each `TryRemoveStock` saves, so a later failure leaves partial deductions and an in-memory sale; `ValidateStock` checks per line, not aggregated; Ingredients edit form writes back a stale `CurrentStock`; unit change breaks later cancel/refund; ingredient delete has no reference check; `AuthService` is scoped, services are singletons (actor must be passed).
