# M12 — Sales history, cancellations and refunds
Source: `Docs/Architecture/GastroApp_Documento_Diseno_Producto.docx`, module M12. Branch `feat/sales-history-refunds` (from `feat/cash-register-history` bd12bf8).
No commit of `data.json`/csproj; no push. Spanish UI, English code/docs.

## Specs
- S1 (history list): "Listado histórico por fecha, número, operador, canal, cliente, medio de pago, caja y estado." Channel and customer do not exist in the data model yet (M06/M17): no filter is invented for them.
- S2 (search): "Búsqueda por producto, referencia de venta o comprobante."
- S3 (detail): "Detalle completo de líneas, descuentos, pagos, observaciones, responsables y eventos."
- S4 (states): "Estados diferenciados de venta cobrada, cancelada, parcialmente devuelta y devuelta."
- S5 (cancellation): "Anulación completa con motivo obligatorio, responsable y momento."
- S6 (refund): "Devolución total o parcial, con método e importe reintegrado." Partial refund is by line and quantity; the amount is computed (line and sale discounts prorated) — L3.
- S7 (stock vs waste): "Registro de diferencias entre devolución de dinero, retorno al stock y merma." Each refunded line is marked returned-to-stock or waste — L3. "La reincorporación de ingredientes o productos al inventario ocurre solo si existe retorno físico válido."
- S8 (no deletion): "No se eliminan físicamente las ventas ya registradas."
- S9 (separate operations): "Anular una venta y devolver dinero son operaciones distintas y deben registrarse por separado."
- S10 (rejections): "Una anulación repetida o una devolución superior a lo cobrado debe ser rechazada."
- S11 (roles): "Acciones restringidas por rol y consulta de auditoría." Refunds and cancellation are Admin only — L4.
- S12 (closed register): a cash refund for a sale whose register is closed is recorded as an outflow in the current open register, linked to the original sale; the old close stays untouched. With no open register, a cash refund is rejected — L2. M11: "La corrección de una caja cerrada exige una operación de conciliación identificable, no reescribir el cierre."
- S13 (reporting): "Los reportes distinguen ventas brutas, descuentos, anulaciones, devoluciones e importe neto."

## Tasks
| ID | Specs | Route | Commit |
| --- | --- | --- | --- |
| T1 | S1, S3 | inline: record operator (user ID/username) on new sales; legacy sales show "Sin registro" | 902d2e4 |
| T2 | S1-S5, S8, S11 | worker: admin `/sales/history` list with filters/paging and detail incl. cancellation action; read-only history queries | f3ac356 |
| T3 | S4, S6, S7, S9, S10, S12, S13 | worker: refund model + service command, `CashMovementType.Refund` outflow, per-line consumption snapshot for new sales, receipts netting, harness | 902d2e4 |
| T4 | S6, S7, S12, S13 | inline/worker: refund UI in sale detail, refunds in detail events, docs (`Sales.md`, `CashRegisters.md`, `IMPLEMENTED_FEATURES.md`) | 10277d1 |
| T6 | S13, S6 | worker: correction after T5 — render gross/discounts/cancellations/refunds/net on /summary and refunded/net on cash summaries; CanRefund false without assignable payments; regression checks | bafeae4 |
| T5 | all | gentle-ai-verify (Risk item 1: persisted format change of sales and cash movements) | verified at bafeae4 |

## Log
- L1: "quiero continuar el desarrollo de esta aplicacion con ODD, el documento de diseño es GastroApp_Documento_Diseno_Producto.docx" — user chose "M12 Historial de ventas y devoluciones".
- L2: closed register → "Egreso en la caja abierta actual (Recomendado)".
- L3: partial refund → "Por línea y cantidad (Recomendado)".
- L4: permissions → "Solo Admin (Recomendado)".
- L11: T5 recheck (gentle-ai-verify) at bafeae4: S13 met (/summary brutas 1950, descuentos 105, anulaciones 150, devoluciones 750, neto 1095; cash Devuelto/Neto per method correct), S6 met (no-payment legacy sale shows message, no form). Harnesses 208/295/207/87/242/256 all 0 failures; 390px no overflow; live hashes unchanged. All S1-S13 pass. Advisory: legacy no-payment sale keeps pre-existing cash-history warning. Pre-existing: verify-payment-summary.ps1 aborts on obsolete hash. Slice boundary: branch holds 5 feature commits (~4270 authored lines incl. bd12bf8); delivery shape decided when publishing.
- L10: T6 (gentle-ai-worker) done: SaleService.GetReport/GetTodayReport (read-only SalesReport), /summary gross/discounts/cancellations/refunds/net (sale-date attribution; refunds by refund date; net = Total Vendido - refunds, may be negative), cash summaries Devuelto/Neto, SaleRefundability.HasRefundableMoney. RED compile; GREEN sales-refunds 208/0, sales-history 295/0, cash-history 207/0, cash-movements 87/0, cash-count 242/0, auth 256/0. Commit bafeae4. S13 recheck delegated to gentle-ai-verify.
- L9: T5 (gentle-ai-verify): S1-S12 pass (harnesses 295/183/207/87/242/256 all 0 failures; legacy fixture loads, round-trip only adds SaleRefunds/NextSaleRefundId; browser incl. closed-register refund, employee denial, 390px). S13 FAIL: /summary "Total Vendido" includes refunded sales, no refunds/net shown; cash pages do not render RefundedTotal/NetTotal. Non-blocking: legacy sale without payments shows a refund form that always fails; "Devuelto" column formatting inconsistent. Live hashes unchanged. T6 opened.
- L8: T4 (gentle-ai-worker) done: display states, status filters, refund events, refund form, CashHistory Refund outflow, docs. RED 35 CS errors vs HEAD copy; GREEN sales-history 295/0, sales-refunds 183/0, cash-history 207/0, cash-movements 87/0, cash-count 242/0, auth 256/0; build 0 errors. Notes: refund disposition defaults to Waste; per-method amounts typed manually; Cash/CashHistory pages do not render refunded/net summary (service only). Commit 10277d1. Slice boundary: 4 commits ~4066 authored lines since origin/main (incl. bd12bf8 cash history); delivery shape decided at publish time. T5 delegated to gentle-ai-verify.
- L7: T3 (gentle-ai-worker) done; pins T1. RED compile failures; GREEN verify-sales-refunds 183/0; cash-movements 87/0, cash-count 242/0, cash-history 206/0, auth-isolation 256/0; payment-summary aborts on pre-existing obsolete hash. Rules added: exact remainder on final refund, zero-total refund allowed, Cancel rejects refunded sales. Pending in T4: CashHistory.razor Refund outflow/label. Commits: 902d2e4 (T1+T3, own commit for risk item 1), f3ac356 (T2). T4 delegated (context backstop).
- L6: T2 (gentle-ai-worker) done: `Models/SaleHistory.cs`, `Services/SaleHistoryService.cs`, `Pages/SalesHistory.razor`, NavMenu, Program.cs. RED CS0246; GREEN verify-sales-history 249/0, verify-cash-history 206/0, build 0 errors. Covers S1-S3, S5, S8, S11; S4 refund states and refund events pending T4. Comprobante search not applicable (no receipt data). Not browser-rendered yet (T5).
- L5: exploration (gentle-ai-explore): cancel restores stock snapshot and does not touch cash; no history page, no refund model, no operator on sale, no stock ledger; stock snapshot is per sale (aggregated), not per line; `RequireLiveAdmin` is private in `CashRegisterService`.
