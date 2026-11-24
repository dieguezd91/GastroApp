# Ingredients are created without stock
Branch `fix/ingredient-no-initial-stock` (from `main` 0f3931a). No push (main deploys to Render). Spanish UI, English code/docs.

## Specs
- S1 (L1): "al crear un ingrediente, no deberia poder cargar stock inicial, el stock se carga con las compras del ingrediente". The create form has no "Stock inicial" field, and `IngredientService.Add` rejects a non-zero `CurrentStock` with a clear Spanish message, leaving ingredients, ledger, counters and `data.json` unchanged.
- S2: stock keeps entering only through the existing paths: invoice receipt (purchases), plus the existing manual adjustment, waste and physical count. Those paths are unchanged.
- S3: legacy data stays readable: the `StockMovementType.InitialStock` value (7), its label "Stock inicial" and its origin text are kept for movements already stored.
- S4: help text and docs that describe ingredient creation reflect the rule (`Docs/Architecture/Stock.md`, README / IMPLEMENTED_FEATURES if they mention opening stock).

## Tasks
| ID | Specs | Route | Commit |
| --- | --- | --- | --- |
| T1 | S1-S4 | worker: service rule + form + harness updates + docs | — |

## Log
- L1: "al crear un ingrediente, no deberia poder cargar stock inicial, el stock se carga con las compras del ingrediente. Es un poco raro el manejo de los productos porque al crear un producto no se asocia a los ingredientes pero para borrar un producto si"
- L2: the second sentence (products) is not part of this task; parent asks the user what they observed.
