# Delete ingredients with history + admin data reset
Branch `feat/ingredient-delete-and-reset` (from `main` c8615a5). No push (main deploys to Render). Spanish UI, English code/docs. Both tasks delete stored data irreversibly (Risk: item 1): each gets its own commit, a harness and independent verification.

## Specs
- S1 (L2 "Permitir borrar igual"): an ingredient can be deleted even when it has history: stock movements, sales stock consumption, or invoice lines. The historical records are kept as they are (not deleted, not rewritten).
- S2 (L3 "Bloquear y avisar qué recetas lo usan"): deletion is rejected while a current recipe uses the ingredient; the message names those recipes. Nothing changes on rejection (ingredients, recipes, ledger, counters, data.json bytes).
- S3: screens that show historical records of a deleted ingredient keep working and show a readable fallback instead of crashing or blanks: the Movimientos tab (incl. its ingredient filter and `/ingredients/{id}/movements` for a deleted id), sales history detail/timeline/refunds, invoices list/workspace, stock count detail. Where a record already stores the ingredient name, use it; otherwise show "Ingrediente eliminado (#id)".
- S4: the delete confirmation dialog explains the effect: history is kept but the ingredient disappears from stock, alerts and pickers.
- S5 (L2 "Sí, botón de admin \"Reiniciar datos\""): an admin-only screen "Reiniciar datos" that "borra todo (ventas, cajas, stock, catálogo) y deja solo el usuario admin": empties products, categories, sales, refunds, stock movements, stock counts, cash registers (incl. the current one), cash movements, cash counts, daily summaries, ingredients, suppliers, invoices, recipes, and removes every user except the admin who runs it (keeping that account and its password). ID counters keep running (no reuse). Persists to data.json.
- S6 (L2 "Es destructivo e irreversible: va con confirmación doble"): two confirmations: a checkbox acknowledging it is irreversible AND typing the exact word `REINICIAR`; the button stays disabled until both hold. The service re-checks that the actor is a live admin; employees and anonymous users get the existing unauthorized handling and nothing changes.
- S7 (parent addition, L4): before emptying, the current data.json is copied to `data.backup-<yyyyMMdd-HHmmss>.json` next to it; if the backup fails, the reset is aborted with nothing changed. Backups are git-ignored. The success message names the backup file.
- S8: docs and help text describe both behaviors.

## Tasks
| ID | Specs | Route | Commit |
| --- | --- | --- | --- |
| T1 | S1-S4, S8 | worker: ingredient delete rule + fallbacks + harness updates + docs | c3b7aa2 |
| T2 | S5-S8 | worker: reset service + admin page + nav + harness + docs | 114ac9c |
| T3 | all | gentle-ai-verify (Risk: item 1) | — |

## Log
- L1: "por ejemplo ahora mismo elimine todo, pero no puedo eliminar ingredientes porque estan asociados a algo, pero ya no queda nada en la memoria"
- L2: user decisions: borrado "Permitir borrar igual"; reinicio "Sí, botón de admin \"Reiniciar datos\"" (option text: "Pantalla solo para admin que borra todo (ventas, cajas, stock, catálogo) y deja solo el usuario admin. Es destructivo e irreversible: va con confirmación doble.").
- L3: user decision on recipes: "Bloquear y avisar qué recetas lo usan (recomendado)".
- L4: parent decisions: automatic backup before reset (S7); ID counters are not reset, to avoid reusing ids that stale sessions or copies could still hold.
- L5: T1 done (c3b7aa2): cancellations and Restock refunds skip a deleted ingredient (no stock change, no movement) instead of failing; changed unit still rejects. T2 done (114ac9c): demo seeding now requires no products AND no users, so a reset store is not re-seeded on restart; other circuits logged in as removed users are logged out on their next check.
