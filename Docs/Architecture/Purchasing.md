# Purchase invoices and Argentine VAT (IVA)

Implements the domain side of the purchase-invoice VAT feature (S1-S7): the business tax condition, supplier fiscal data, the derived invoice type, VAT per type, other taxes, the ingredient cost policy and the persistence of all of it. Scope is purchases only; there is no electronic invoicing (ARCA). The screens (Datos fiscales, supplier form, invoice workspace and list) only use what is described here; the invoice screen is described in [Invoice screen](#invoice-screen).

> **The tax rules below must be confirmed with an accountant before being relied on.** They summarise Argentine rules as researched for this project (RG 5614/2024 for the "IVA contenido" on factura B, RG 5762/2025 for the removal of factura M from 2025-12-01) and may change.

## Ownership

| Piece | Responsibility |
|---|---|
| `Models/TaxCondition.cs`, `InvoiceType.cs`, `InvoiceLegend.cs`, `InvoiceTaxKind.cs` | Persisted enums (numeric values are part of `data.json`): `TaxCondition` 1 Responsable Inscripto, 2 Monotributista, 3 Exento; `InvoiceType` 1 A, 2 B, 3 C; `InvoiceLegend` 0 None, 1 OperacionSujetaARetencion, 2 PagoEnCbuInformada; `InvoiceTaxKind` 1 PercepcionIva, 2 PercepcionIibb, 3 ImpuestosInternos, 4 OtrosTributos. |
| `Models/FiscalRules.cs` | The only owner of the pure rules: CUIT normalisation and check digit (`TryNormalizeCuit`), the permitted VAT rates (`VatRates`), the derived type (`ExpectedInvoiceType`), the unit cost (`UnitCost`) and the Spanish labels (`Label`). |
| `Models/BusinessSettings.cs` | `{ TaxCondition? }`, the business's own condition. |
| `Models/Supplier.cs`, `Invoice.cs`, `InvoiceItem.cs`, `InvoiceTax.cs` | Fiscal fields and the computed (not persisted) totals. |
| `Services/BusinessSettingsService.cs` | Singleton. `TaxCondition` and `SetTaxCondition(condition, actor)`. |
| `Services/SupplierService.cs`, `Services/InvoiceService.cs` | Validation of every rule below, before any ID is allocated or stock is touched. |
| `DataStorageService` | `BusinessSettings` property, serialisation, load validation, `ResetAll`, seed. |

## Business tax condition (S1)

One business per installation. `BusinessSettings.TaxCondition` is `null` until an admin sets it with `BusinessSettingsService.SetTaxCondition`, which re-checks a live admin (`RequireLiveAdmin`, `UnauthorizedAccessException` `Se requiere un usuario administrador vigente.`), rejects an undefined value (`Elegí una condición frente al IVA válida.`), stores it and calls `RecipeService.RecalculateAllCosts()` (which saves), because the condition changes ingredient costs (see [Cost policy](#cost-policy-s6)). While it is `null`, `InvoiceService.Add` rejects with `Configurá la condición frente al IVA del negocio en Datos fiscales antes de registrar facturas.` `ResetAll` clears it.

## Supplier fiscal data (S2)

`Supplier.Cuit` (11 digits, stored without dashes) and `Supplier.TaxCondition`. `SupplierService.Add` / `Update` validate, in this order: name (`Ingresá un nombre para el proveedor.`), CUIT present (`Ingresá el CUIT del proveedor.`), CUIT valid (`El CUIT no es válido.`), condition defined (`Elegí la condición frente al IVA del proveedor.`), CUIT unique among the other suppliers (`Ya existe un proveedor con ese CUIT.`; editing a supplier with its own CUIT is fine). The CUIT may be typed with dashes; the check digit uses the weights 5,4,3,2,7,6,5,4,3,2 over the first ten digits, `11 − (sum mod 11)`, where 11 means 0 and 10 is invalid. Nothing else about the prefix is validated. A supplier without CUIT or condition (legacy data) has `HasFiscalData == false` and cannot be used on a new invoice (`Completá el CUIT y la condición frente al IVA del proveedor antes de registrar la factura.`) until it is completed.

## Derived invoice type (S3)

The type is derived, never chosen; the service rejects any other value (including `null`) with `Un proveedor {condición} debe emitirte factura {tipo}.`

| Supplier | Business | Expected |
|---|---|---|
| Responsable Inscripto | Responsable Inscripto or Monotributista | A |
| Responsable Inscripto | Exento | B |
| Monotributista or Exento | any | C |

Factura M is not offered. An A invoice may carry the optional `Legend`; any legend on B or C, or an undefined one, is rejected (`La leyenda solo corresponde a facturas A.`, `La leyenda de la factura no es válida.`).

## VAT per type (S4)

`InvoiceItem.VatRate` is a percentage (`21` means 21 %); the allowed values are 0, 2.5, 5, 10.5, 21 and 27.

- **A**: the typed price is **net** (sin IVA) and every item needs a rate (`Elegí una alícuota de IVA válida para cada ítem de la factura A.`). `Invoice.VatByRate` groups the items by rate (ascending) with the net and the VAT per rate; the VAT of each rate is `net × rate / 100` rounded to cents (away from zero) **per rate**, not per line (net 33,33 at 21 % → 7,00). `VatTotal` is their sum.
- **B**: the typed price is final (IVA incluido); items carry no rate (`Las facturas B no discriminan IVA por ítem.`). The invoice may record the informative `ContainedVat` (RG 5614/2024), which must be ≥ 0 and lower than the invoice total (`El IVA contenido debe ser mayor o igual a cero y menor que el total de la factura.`). It is not crédito fiscal and is not used in any cost.
- **C**: the typed price is final and no VAT field is accepted (`Las facturas C no discriminan IVA por ítem.`). `ContainedVat` on A or C is rejected (`El IVA contenido solo se informa en facturas B.`).

Computed and not persisted (`[JsonIgnore]`): `NetTotal` (items subtotal), `VatByRate`, `VatTotal` (zero unless A) and `OtherTaxesTotal`. `Total = NetTotal + VatTotal + OtherTaxesTotal`, so VAT is added only on A.

## Other taxes (S5)

`Invoice.OtherTaxes` is a list of `InvoiceTax { Kind, Detail, Amount }`: Percepción de IVA (A only), Percepción de IIBB (needs a jurisdiction in `Detail`), Impuestos internos and Otros tributos (needs a description). Rejections, in order: `El tipo de tributo no es válido.`, `El importe de cada tributo debe ser mayor a cero.`, `La percepción de IVA solo corresponde a facturas A.`, `Indicá la jurisdicción de la percepción de IIBB.`, `Describí el tributo.` `Detail` is trimmed on save. They add to `Total`.

**Limitation:** other taxes are invoice-level and are **not** allocated to any ingredient unit cost, so perceptions and internal taxes never reach recipe costs.

## Registration order

`InvoiceService.Add` checks: actor (existing rule) → business condition → supplier exists (`Seleccioná un proveedor.`) → supplier fiscal data → derived type → legend → item VAT rates → contained VAT → other taxes → the existing stock validation. Every rejection is an `InvalidOperationException` that leaves objects, ID counters and `data.json` unchanged. `InvoiceService.Update` copies `Type`, `Legend`, `ContainedVat` and `OtherTaxes` with the rest of the fields and does not validate (as before; the UI does not expose editing).

## Cost policy (S6)

`FiscalRules.UnitCost(invoice, item, business)` is the ingredient unit cost behind `InvoiceService.GetLastPriceForIngredient` and `GetPriceHistory` (and therefore `IngredientService.GetLastPrice`, recipes and the "último precio" shown on screens):

| Invoice | Business Responsable Inscripto | Any other, or not configured |
|---|---|---|
| A | net price (the IVA is crédito fiscal) | `net × (1 + rate / 100)` |
| B, C, legacy (no type) | typed price | typed price |

The cost is computed when read, so changing the business condition changes costs; `SetTaxCondition` therefore recalculates and saves the stored recipe costs. Unit conversion of the line (gr → kg) is unchanged and happens before the invoice is stored.

## Legacy invoices (S7)

Invoices stored before this change load unchanged: `Type == null`, `Legend` None, no `ContainedVat`, no other taxes, no item rate, `Total` = items. They are never reinterpreted: the price they stored is their cost and the screens show them as "Tipo no informado · precio final". Their suppliers may lack fiscal data.

## Persistence

`data.json` gains a top-level `BusinessSettings` (`{ "TaxCondition": 1 }`), `Supplier.Cuit` / `TaxCondition`, and on invoices `Type`, `Legend`, `ContainedVat`, `OtherTaxes` and on items `VatRate`. `Invoice.Total` is still written, as before. Loading never writes:

- a file without `BusinessSettings`, `Cuit`, `Type`, etc. is a legacy file (business not configured; the other fields default);
- an explicit `"BusinessSettings": null`, an undefined tax condition (for example `0` or `7`) or a malformed value throws `InvalidDataException`.
- an invoice with an explicit `"OtherTaxes": null`, an undefined `Type`, `Legend` or other-tax `Kind`, or a supplier with an undefined `TaxCondition` also throws `InvalidDataException`: loading it would break `Invoice.Total` and silently stop every later save. Legacy files that simply lack these fields load unchanged.

`ResetAll` clears the business condition (the backup keeps it). The seed creates a Responsable Inscripto supplier (CUIT 30712345671), a factura A (harina 10,5 %, the rest 21 %) and leaves the business not configured.

## Invoice screen

`Pages/Invoices.razor` owns the state and every service write; `Shared/Purchasing/InvoiceWorkspace.razor` (form) and `InvoiceList.razor` (list) only render it and raise callbacks, with the helpers in `PurchasingSupport.cs`. The page keeps calling `InvoiceService.Add(editingInvoice, AuthService.CurrentUser)` and shows every service rejection in the form error banner; every action re-checks the admin session.

- **Business not configured (S1).** The workspace shows a warning with the message `Configurá la condición frente al IVA del negocio en Datos fiscales antes de registrar facturas.` and a link to `/settings/fiscal`, no item can be added and saving is disabled.
- **Supplier and type (S3).** Suppliers without CUIT or condition are disabled options labelled `(datos fiscales incompletos)`. Choosing a supplier derives `Invoice.Type` with `FiscalRules.ExpectedInvoiceType` and shows it read-only (`Factura A`, `Factura B`, `Factura C`). If the new supplier changes the derived type, the lines, other taxes, legend and IVA contenido typed so far are removed and the form says `Se quitaron los ítems porque cambió el tipo de factura.` (a supplier with the same type keeps everything). Factura M is not offered.
- **Factura A (S4).** The price is `Precio neto por {unidad} (sin IVA)` and each line takes a rate chosen from `FiscalRules.VatRates` (21 % by default; the line keeps the rate it was added with). The line preview shows the net subtotal and the IVA at the chosen rate, the lines table shows the rate and the net subtotal, and the totals show `Neto gravado` and the IVA of each rate (rounded per rate, as `Invoice.VatByRate`). The optional legend is `Sin leyenda`, `OPERACIÓN SUJETA A RETENCIÓN` or `PAGO EN CBU INFORMADA`.
- **Factura B.** `Precio final por {unidad} (IVA incluido)`, no rate, and the optional `IVA contenido (informativo)`, parsed with `PurchasingFormat.TryParseDecimal` when saving (text that is not a number is refused with `Ingresá un IVA contenido válido.`; the range rule stays in the service). It is shown as informative and does not add to the total.
- **Factura C.** `Precio final por {unidad}` and no VAT field.
- **Other taxes (S5).** Rows of kind, detail and amount can be added and removed; `Percepción de IVA` is offered only on A, the detail is `Jurisdicción` for IIBB and `Descripción` for Otros tributos. The page only refuses an amount that is not greater than zero; the jurisdiction and description rules are the service's, so their messages appear in the form error and nothing is stored. Taxes add to the total and never to an ingredient cost.
- **List (S7, S8).** Each invoice shows a type badge; invoices without a type show `Tipo no informado · precio final` and nothing else is inferred. Factura A also shows neto, IVA and other taxes under the total and its legend and line rates; factura B shows the informative IVA contenido.

## Verification

`scripts/verify-purchase-vat.ps1` exercises every rule above through the public services (messages, unchanged state on rejection, all 9 type combinations, totals and rounding, cost matrix, recipe recalculation, legacy and corrupt files, seed, `ResetAll`). `scripts/verify-invoice-vat-ui.ps1` exercises the invoice screen through the page methods and the rendered workspace and list (gate, derived type per condition, A/B/C flows, other taxes, type change, list).
