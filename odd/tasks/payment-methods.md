# Payment Methods — ODD task record

## Intent
Implement one persisted payment per positive-total sale, with explicit POS method selection; zero-total discounted sales carry no payment. Enforce payment invariants in `SaleService` before sale/stock mutation and preserve legacy JSON compatibility.

## Scope
Supported methods: Cash, DebitCard, CreditCard, Transfer, MercadoPago, Other. Payment contains method and amount; `Sale` owns a collection for future mixed payment support. No manual amount, change, partial/mixed payment behavior, fees, refunds, cancellations, or database changes.

## Tasks
1. [x] Add payment model and Sale collection; validate payment invariants before any checkout mutation.
2. [x] Add explicit POS selection for positive totals, generate exact discounted-total payment, display method; allow zero-total checkout without payment.
3. [ ] Update Sales architecture and implemented-features docs; build and exercise compatibility/validation cases. Docs updated; build remains blocked and requested runtime scenarios were not exercised.

## Routing and validation
- TDD: strict TDD explicitly disabled by user; no test project was observed in the inspected source set.
- Route: delegated direct bounded writer. Trigger: implementation spans model, service, POS, and documentation; preparation reads belong with writer.
- Allowed edit surfaces: `Models/Sale.cs`, `Services/SaleService.cs`, `Pages/Sales.razor`, `Docs/Architecture/Sales.md`, `IMPLEMENTED_FEATURES.md`.
- Validation requested: `dotnet build`; legacy JSON missing Payments; all methods; save/reload; exact discounted amount; 100% discount no payment; invalid data prevents sale/stock mutation; preserve existing POS behavior.
- Pre-existing worktree changes observed before implementation: modified `data.json` and untracked `data.manual-test.backup.json`; preserve untouched.
- Engram mirror unavailable: no memory tools are active in this session.

## Evidence
- Initial branch: `main`; HEAD `b68e3a1`.
- Existing flow: `SaleService.Add()` validates before notes normalization, assigning ID, sale insertion, stock deduction, and save. POS calls validation before `Add()`.
- Existing JSON serializer serializes/deserializes `Sales`; missing object properties use model defaults.
- `dotnet build` attempted twice; both failed with MSB3027/MSB3021 because running `GastroApp (PID 32908)` locked `bin/Debug/net7.0/GastroApp.exe`; NETSDK1138 warnings also appeared.
- Legacy load compatibility follows from the initialized empty `Payments` property, but was not runtime-tested. Method-by-method checkout, persistence/reload, discounts, zero-total, and invalid-payment/no-mutation scenarios were not exercised.
- Work-unit commit: not performed; user did not explicitly authorize commits.
