param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-refunds-' + [guid]::NewGuid().ToString('N')) }
$ScratchPath = [IO.Path]::GetFullPath($ScratchPath)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (!$ScratchPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'ScratchPath must be under the OS temporary directory.' }
if (Test-Path $ScratchPath) { throw 'ScratchPath must be a new directory.' }
New-Item -ItemType Directory -Path $ScratchPath | Out-Null
Write-Host "Verification scratch: $ScratchPath (retained for inspection)"
$before = (& git -C $repo hash-object GastroApp.csproj data.json)
$project = [xml](Get-Content (Join-Path $repo 'GastroApp.csproj') -Raw)
$framework = $project.Project.PropertyGroup.TargetFramework
$reference = [Security.SecurityElement]::Escape((Join-Path $repo 'GastroApp.csproj'))
@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>$framework</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><LangVersion>12.0</LangVersion><RollForward>LatestMajor</RollForward></PropertyGroup>
  <ItemGroup><ProjectReference Include="$reference" /><FrameworkReference Include="Microsoft.AspNetCore.App" /></ItemGroup>
</Project>
"@ | Set-Content (Join-Path $ScratchPath 'RefundChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var root = Directory.GetCurrentDirectory();
var storage = new DataStorageService(); // Process cwd is ALWAYS the newly allocated temp directory.
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 11, Username = "second-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var admin = storage.Users[0]; var admin2 = storage.Users[1]; var employee = storage.Users[2];
User Copy(User user) => new() { Id = user.Id, Username = user.Username, PasswordHash = user.PasswordHash, Role = user.Role };
storage.Ingredients = [new Ingredient { Id = 1, Name = "Harina", Unit = "kg", CurrentStock = 100m },
    new Ingredient { Id = 2, Name = "Huevos", Unit = "unidad", CurrentStock = 200m }];
var harina = storage.Ingredients[0]; var huevos = storage.Ingredients[1];
storage.Products = [new Product { Id = 1, Name = "Pizza", Price = 100m }, new Product { Id = 2, Name = "Flan", Price = 50m },
    new Product { Id = 3, Name = "Agua", Price = 10m }];
storage.Recipes = [new Recipe { Id = 1, Name = "Pizza", Ingredients = [
        new RecipeIngredient { RecipeId = 1, IngredientId = 1, Quantity = 0.5m, Unit = "kg" },
        new RecipeIngredient { RecipeId = 1, IngredientId = 2, Quantity = 2m, Unit = "unidad" }] },
    new Recipe { Id = 2, Name = "Flan", Ingredients = [new RecipeIngredient { RecipeId = 2, IngredientId = 2, Quantity = 3m, Unit = "unidad" }] }];
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
var recipes = new RecipeService(storage, invoices);
var sales = new SaleService(storage);
sales.SetRecipeService(recipes); sales.SetIngredientService(ingredients);
var cash = new CashRegisterService(storage, sales);
var pizza = storage.Products[0]; var flan = storage.Products[1]; var agua = storage.Products[2];

SaleItem Line(Product p, int q, DiscountType dt = DiscountType.None, decimal dv = 0m) =>
    new() { ProductId = p.Id, ProductName = p.Name, Price = p.Price, Quantity = q, DiscountType = dt, DiscountValue = dv };
SalePayment CashPay(decimal a) => new() { PaymentMethod = PaymentMethod.Cash, Amount = a, ReceivedAmount = a };
SalePayment OtherPay(PaymentMethod m, decimal a) => new() { PaymentMethod = m, Amount = a };
Sale Make(List<SaleItem> items, DiscountType dt, decimal dv, params SalePayment[] pays) =>
    new() { Items = items, DiscountType = dt, DiscountValue = dv, Payments = pays.ToList() };
Sale Simple(List<SaleItem> items, params SalePayment[] pays) => Make(items, DiscountType.None, 0m, pays);
SaleRefundLine RL(int idx, int q, RefundDisposition d = RefundDisposition.Restock) => new() { SaleItemIndex = idx, Quantity = q, Disposition = d };
SaleRefundPayment RP(PaymentMethod m, decimal a) => new() { PaymentMethod = m, Amount = a };
SaleRefund Refund(Sale s, string? reason, SaleRefundLine[] lines, SaleRefundPayment[] pays, User? actor) => sales.Refund(s.Id, reason, lines, pays, actor);
DailySummary CloseWith(decimal amount, User actor)
{
    var review = cash.GetCountReview();
    return cash.Close(new CashCountRequest { Review = review,
        Lines = amount > 0m ? new[] { new CashCountLineInput(amount, 1) } : Array.Empty<CashCountLineInput>(),
        Reason = amount != review.ExpectedAmount ? "fixture" : null, Confirmed = true, ZeroCountConfirmed = amount == 0m }, Copy(actor));
}
string State() => JsonSerializer.Serialize(new { storage.CurrentCashRegisterId, storage.CashRegisters, storage.CashMovements, storage.CashCounts,
    storage.Sales, storage.SaleRefunds, storage.Users, storage.Summaries, storage.Products, storage.ProductCategories,
    storage.Ingredients, storage.Suppliers, storage.Invoices, storage.Recipes,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
void Reject(Action action, Type exception, string name, string? contains = null)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    bool rejected = false; string message = "";
    try { action(); } catch (Exception ex) { rejected = ex.GetType() == exception && (contains == null || ex.Message.Contains(contains)); message = ex.Message; }
    Check(rejected, name + " rejected with " + exception.Name + (contains == null ? "" : " / " + contains) + (rejected ? "" : " [" + message + "]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")), name + " leaves objects, collections, counters and fixture bytes unchanged");
}
void Invalid(Action action, string name, string? contains = null) => Reject(action, typeof(InvalidOperationException), name, contains);
void Denied(Action action, string name) => Reject(action, typeof(UnauthorizedAccessException), name, "administrador");

// ---- API surface ----
Check(typeof(CashMovementType).GetEnumNames().Contains("Refund"), "CashMovementType.Refund exists");
Check(sales.GetRefunds(9999).Count == 0 && sales.GetDisplayStatus(9999) == null && sales.GetRefundability(9999) == null, "queries on unknown sale are empty/null");
cash.Open(100m);
var register1 = cash.GetCurrent()!;

// ---- T1: operator recording ----
var t1Live = Make([Line(agua, 1)], DiscountType.None, 0m, CashPay(10m));
sales.Add(t1Live, Copy(admin));
Check(t1Live.CreatedByUserId == 10 && t1Live.CreatedByUsername == "fixture-admin", "T1 live seller recorded");
var t1None = Simple([Line(agua, 1)], CashPay(10m));
sales.Add(t1None);
Check(t1None.CreatedByUserId == null && t1None.CreatedByUsername == null, "T1 no seller leaves null operator");
var t1Emp = Simple([Line(agua, 1)], CashPay(10m));
sales.Add(t1Emp, Copy(employee));
Check(t1Emp.CreatedByUserId == 12 && t1Emp.CreatedByUsername == "fixture-employee", "T1 employee seller recorded");
var stale = Copy(admin); stale.PasswordHash = "old-hash";
Reject(() => sales.Add(Simple([Line(agua, 1)], CashPay(10m)), stale), typeof(UnauthorizedAccessException), "T1 stale seller password", "usuario vigente");
var unknownSeller = Copy(admin); unknownSeller.Id = 99;
Reject(() => sales.Add(Simple([Line(agua, 1)], CashPay(10m)), unknownSeller), typeof(UnauthorizedAccessException), "T1 unknown seller", "usuario vigente");
var renamedSeller = Copy(admin); renamedSeller.Username = "renamed";
Reject(() => sales.Add(Simple([Line(agua, 1)], CashPay(10m)), renamedSeller), typeof(UnauthorizedAccessException), "T1 renamed seller", "usuario vigente");
var roleSeller = Copy(admin); roleSeller.Role = UserRole.Employee;
Reject(() => sales.Add(Simple([Line(agua, 1)], CashPay(10m)), roleSeller), typeof(UnauthorizedAccessException), "T1 role mismatch seller", "usuario vigente");

// ---- per-line consumption snapshot for new sales ----
var s1 = Make([Line(pizza, 3, DiscountType.Fixed, 30m), Line(flan, 2)], DiscountType.Percentage, 10m, CashPay(200m), OtherPay(PaymentMethod.DebitCard, 133m));
sales.Add(s1, Copy(admin));

Check(s1.Total == 333m && harina.CurrentStock == 98.5m && huevos.CurrentStock == 188m, "fixture sale S1 total and stock deducted");
var aggregate = JsonSerializer.Serialize(s1.StockConsumption);
var pizzaLine = s1.Items[0].StockConsumption; var flanLine = s1.Items[1].StockConsumption;
Check(pizzaLine != null && pizzaLine.Count == 2 && pizzaLine.Single(e => e.IngredientId == 1).Quantity == 1.5m && pizzaLine.Single(e => e.IngredientId == 2).Quantity == 6m
    && flanLine != null && flanLine.Single().IngredientId == 2 && flanLine.Single().Quantity == 6m && flanLine.Single().Unit == "unidad", "per-line consumption snapshot recorded for new sale");
Check(s1.IsStockConsumptionReliable && s1.StockConsumption!.Count == 3 && s1.StockConsumption.Sum(e => e.Quantity) == pizzaLine!.Sum(e => e.Quantity) + flanLine!.Sum(e => e.Quantity), "aggregate snapshot intact and consistent with lines");
var noRecipe = Simple([Line(agua, 1)], CashPay(10m)); sales.Add(noRecipe);
Check(noRecipe.Items[0].StockConsumption != null && noRecipe.Items[0].StockConsumption!.Count == 0, "line without recipe has reliable empty snapshot");
var prefilled = Simple([Line(agua, 1)], CashPay(10m)); prefilled.Items[0].StockConsumption = [new SaleStockConsumption { IngredientId = 1, Quantity = 50m, Unit = "kg" }];
sales.Add(prefilled);
Check(prefilled.Items[0].StockConsumption!.Count == 0 && harina.CurrentStock == 98.5m, "checkout owns per-line snapshot; caller prefill discarded");

// ---- read model before any refund ----
var fresh = sales.GetRefundability(s1.Id)!;
Check(fresh.Status == SaleDisplayStatus.Collected && fresh.SaleTotal == 333m && fresh.RefundedTotal == 0m && fresh.RemainingTotal == 333m && fresh.CanRefund
    && fresh.Lines.Count == 2 && fresh.Lines[0].SoldQuantity == 3 && fresh.Lines[0].RemainingQuantity == 3 && fresh.Lines[0].CanRestock && fresh.Lines[0].ProductName == "Pizza"
    && fresh.Methods.Single(m => m.PaymentMethod == PaymentMethod.Cash).RemainingAmount == 200m, "refundability read model of untouched sale");
var preview = sales.PreviewRefund(s1.Id, [RL(0, 1)]);
Check(preview.Total == 81m && preview.Lines.Single().Amount == 81m && preview.Lines.Single().SaleItemIndex == 0, "preview prorates line and sale discounts (270*333/(3*370)=81)");
Check(sales.GetDisplayStatus(s1.Id) == SaleDisplayStatus.Collected && SaleService.GetDisplayStatusLabel(SaleDisplayStatus.Collected) == "Cobrada"
    && SaleService.GetDisplayStatusLabel(SaleDisplayStatus.Cancelled) == "Anulada" && SaleService.GetDisplayStatusLabel(SaleDisplayStatus.PartiallyRefunded) == "Parcialmente devuelta"
    && SaleService.GetDisplayStatusLabel(SaleDisplayStatus.Refunded) == "Devuelta", "derived status Cobrada and Spanish labels");

// ---- authorization (S11/L4) ----
var s5 = Simple([Line(agua, 2)], CashPay(20m)); sales.Add(s5);
var okLines = new[] { RL(0, 1) }; var okPays = new[] { RP(PaymentMethod.Cash, 10m) };
Denied(() => Refund(s5, "x", okLines, okPays, null), "null actor");
Denied(() => Refund(s5, "x", okLines, okPays, employee), "employee");
Denied(() => Refund(s5, "x", okLines, okPays, new User { Id = 99, Username = admin.Username, PasswordHash = hash, Role = UserRole.Admin }), "unknown actor");
Denied(() => Refund(s5, "x", okLines, okPays, new User { Id = admin.Id, Username = "other", PasswordHash = hash, Role = UserRole.Admin }), "mismatched username");
Denied(() => Refund(s5, "x", okLines, okPays, new User { Id = admin.Id, Username = admin.Username, PasswordHash = "old", Role = UserRole.Admin }), "mismatched password");
var staleAdmin = Copy(admin);
admin.Role = UserRole.Employee; Denied(() => Refund(s5, "x", okLines, okPays, staleAdmin), "live demotion"); admin.Role = UserRole.Admin;
admin.PasswordHash = "changed"; Denied(() => Refund(s5, "x", okLines, okPays, staleAdmin), "live password change"); admin.PasswordHash = hash;
admin.Username = "renamed"; Denied(() => Refund(s5, "x", okLines, okPays, staleAdmin), "live rename"); admin.Username = staleAdmin.Username;
storage.Users.Remove(admin); Denied(() => Refund(s5, "x", okLines, okPays, staleAdmin), "deleted admin"); storage.Users.Insert(0, admin);

// ---- input validation (S10) ----
Invalid(() => Refund(s5, null, okLines, okPays, admin), "null reason", "motivo");
Invalid(() => Refund(s5, "  \t ", okLines, okPays, admin), "blank reason", "motivo");
Invalid(() => sales.Refund(99999, "x", okLines, okPays, admin), "unknown sale", "no existe");
Invalid(() => Refund(s5, "x", [], okPays, admin), "empty lines");
Invalid(() => sales.Refund(s5.Id, "x", null, okPays, admin), "null lines");
Invalid(() => Refund(s5, "x", [RL(0, 0)], okPays, admin), "zero quantity");
Invalid(() => Refund(s5, "x", [RL(0, -1)], okPays, admin), "negative quantity");
Invalid(() => Refund(s5, "x", [RL(1, 1)], okPays, admin), "line index out of range");
Invalid(() => Refund(s5, "x", [RL(-1, 1)], okPays, admin), "negative line index");
Invalid(() => Refund(s5, "x", [RL(0, 1), RL(0, 1)], [RP(PaymentMethod.Cash, 20m)], admin), "repeated line index");
Invalid(() => Refund(s5, "x", [RL(0, 3)], [RP(PaymentMethod.Cash, 30m)], admin), "quantity over remaining units", "unidades");
Invalid(() => Refund(s5, "x", [RL(0, 1, (RefundDisposition)9)], okPays, admin), "undefined disposition");
Invalid(() => Refund(s5, "x", okLines, [], admin), "positive total without payments");
Invalid(() => sales.Refund(s5.Id, "x", okLines, null, admin), "null payments");
Invalid(() => Refund(s5, "x", okLines, [RP(PaymentMethod.Cash, 9.99m)], admin), "payments below total");
Invalid(() => Refund(s5, "x", okLines, [RP(PaymentMethod.Cash, 10.01m)], admin), "payments above total");
Invalid(() => Refund(s5, "x", okLines, [RP(PaymentMethod.Cash, 10m), RP(PaymentMethod.Cash, 0m)], admin), "zero payment amount");
Invalid(() => Refund(s5, "x", okLines, [RP(PaymentMethod.Cash, 15m), RP(PaymentMethod.Cash, -5m)], admin), "negative payment amount");
Invalid(() => Refund(s5, "x", okLines, [RP(PaymentMethod.Cash, 5m), RP(PaymentMethod.Cash, 5m)], admin), "repeated payment method");
Invalid(() => Refund(s5, "x", okLines, [RP((PaymentMethod)42, 10m)], admin), "undefined payment method");
Invalid(() => Refund(s5, "x", okLines, [RP(PaymentMethod.Transfer, 10m)], admin), "method not used in the sale", "cobrado");

// ---- S1 partial refunds: Restock then Waste ----
var movementsBefore = storage.CashMovements.Count; var cashBeforeR1 = cash.GetExpectedCash(register1.Id); var inflowBeforeR1 = cash.GetCashInflow(register1.Id);
var beforeDate = DateTime.Now;
var r1 = Refund(s1, "  producto devuelto  ", [RL(0, 1, RefundDisposition.Restock)], [RP(PaymentMethod.Cash, 81m)], Copy(admin));
Check(r1.Id == 1 && r1.SaleId == s1.Id && r1.Total == 81m && r1.Reason == "producto devuelto" && r1.UserId == 10 && r1.Username == "fixture-admin"
    && r1.Date >= beforeDate && r1.Date <= DateTime.Now && r1.CashRegisterId == register1.Id
    && r1.Lines.Single().Amount == 81m && r1.Lines.Single().Disposition == RefundDisposition.Restock && r1.Lines.Single().Quantity == 1
    && r1.Payments.Single().PaymentMethod == PaymentMethod.Cash && r1.Payments.Single().Amount == 81m, "partial refund persists audit, amounts and payments");
var m1 = storage.CashMovements.Last();
Check(storage.CashMovements.Count == movementsBefore + 1 && m1.Type == CashMovementType.Refund && m1.Amount == 81m && m1.SaleId == s1.Id && m1.CashRegisterId == register1.Id
    && m1.UserId == 10 && m1.Username == "fixture-admin" && m1.Reason == "producto devuelto", "cash portion booked as Refund outflow linked to sale with reason");
Check(cash.GetExpectedCash(register1.Id) == cashBeforeR1 - 81m && cash.GetCashInflow(register1.Id) == inflowBeforeR1, "Refund counts as outflow in expected cash");
Check(harina.CurrentStock == 99m && huevos.CurrentStock == 190m && JsonSerializer.Serialize(s1.StockConsumption) == aggregate && s1.Status == SaleStatus.Completed,
    "Restock returns proportional per-line stock; aggregate snapshot and sale status unchanged");
Check(sales.GetDisplayStatus(s1.Id) == SaleDisplayStatus.PartiallyRefunded && SaleService.GetDisplayStatus(s1, storage.SaleRefunds) == SaleDisplayStatus.PartiallyRefunded, "derived state Parcialmente devuelta");

var movementsAfterR1 = storage.CashMovements.Count; var stockAfterR1 = (harina.CurrentStock, huevos.CurrentStock);
var r2 = Refund(s1, "merma", [RL(0, 1, RefundDisposition.Waste)], [RP(PaymentMethod.DebitCard, 81m)], admin2);
Check(r2.Id == 2 && r2.UserId == 11 && r2.Lines.Single().Disposition == RefundDisposition.Waste && r2.CashRegisterId == register1.Id
    && storage.CashMovements.Count == movementsAfterR1 && (harina.CurrentStock, huevos.CurrentStock) == stockAfterR1, "Waste changes no stock, books no cash for card refund, keeps open register link");
var view = sales.GetRefundability(s1.Id)!;
Check(view.RefundedTotal == 162m && view.RemainingTotal == 171m && view.Lines[0].RefundedQuantity == 2 && view.Lines[0].RemainingQuantity == 1 && view.Lines[1].RemainingQuantity == 2
    && view.Methods.Single(m => m.PaymentMethod == PaymentMethod.Cash) is { PaidAmount: 200m, RefundedAmount: 81m, RemainingAmount: 119m }
    && view.Methods.Single(m => m.PaymentMethod == PaymentMethod.DebitCard) is { PaidAmount: 133m, RefundedAmount: 81m, RemainingAmount: 52m } && view.CanRefund, "refundability exposes remaining units, amount and per-method caps");
Invalid(() => Refund(s1, "x", [RL(0, 2)], [RP(PaymentMethod.Cash, 162m)], admin), "over-refund of a line", "unidades");
Invalid(() => Refund(s1, "x", [RL(0, 1)], [RP(PaymentMethod.DebitCard, 81m)], admin), "per-method cap exceeded", "cobrado");
Invalid(() => Refund(s1, "x", [RL(0, 1)], [RP(PaymentMethod.DebitCard, 52m), RP(PaymentMethod.Cash, 28.99m), RP(PaymentMethod.Transfer, 0.01m)], admin), "method not paid in sale mixed into valid split", "cobrado");
var copies = sales.GetRefunds(s1.Id);
Check(copies.Count == 2 && copies[0].Id == 1 && copies[1].Id == 2, "GetRefunds returns the sale's refunds in order");
copies[0].Reason = "tampered"; copies[0].Lines.Clear(); copies[0].Payments.Clear();
Check(storage.SaleRefunds[0].Reason == "producto devuelto" && storage.SaleRefunds[0].Lines.Count == 1 && storage.SaleRefunds[0].Payments.Count == 1, "GetRefunds returns detached copies");

// ---- final refund = exact remainder; repeated full refund and cancel-after-refund rejected ----
var cashBeforeFinal = cash.GetExpectedCash(register1.Id);
var r3 = Refund(s1, "resto", [RL(0, 1), RL(1, 2)], [RP(PaymentMethod.Cash, 119m), RP(PaymentMethod.DebitCard, 52m)], admin);
Check(r3.Total == 171m && r3.Lines.Sum(l => l.Amount) == 171m && cash.GetExpectedCash(register1.Id) == cashBeforeFinal - 119m
    && harina.CurrentStock == 99.5m && huevos.CurrentStock == 198m, "final refund takes exact remainder; Restock of both lines returns proportional stock");
Check(sales.GetDisplayStatus(s1.Id) == SaleDisplayStatus.Refunded && sales.GetRefundability(s1.Id)!.RemainingTotal == 0m && !sales.GetRefundability(s1.Id)!.CanRefund
    && sales.GetRefunds(s1.Id).Sum(r => r.Total) == s1.Total, "derived state Devuelta; cumulative refunds equal sale total");
Invalid(() => Refund(s1, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 81m)], admin), "repeated full refund", "unidades");
Invalid(() => sales.Cancel(s1.Id, "motivo", admin), "cancel after refund", "La venta tiene devoluciones registradas; no puede anularse.");
Check(s1.Status == SaleStatus.Completed, "refunded sale stays Completed (cancellation and refund are separate)");

// ---- rounding: cumulative refunds never differ from sale total ----
var s2 = Make([Line(agua, 3)], DiscountType.Fixed, 0.01m, CashPay(29.99m));
sales.Add(s2);
Check(s2.Total == 29.99m && sales.PreviewRefund(s2.Id, [RL(0, 1)]).Total == 10m, "rounded unit refund 9.99666 -> 10.00");
Invalid(() => Refund(s2, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 9.99m)], admin), "payments must equal the computed total exactly");
var a1 = Refund(s2, "u1", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin);
var a2 = Refund(s2, "u2", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin);
Check(a1.Total == 10m && a2.Total == 10m && sales.GetRefundability(s2.Id)!.RemainingTotal == 9.99m, "intermediate refunds are rounded to cents");
Invalid(() => Refund(s2, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin), "final unit cannot take the rounded amount instead of the remainder");
var a3 = Refund(s2, "u3", [RL(0, 1)], [RP(PaymentMethod.Cash, 9.99m)], admin);
Check(a3.Total == 9.99m && a3.Lines.Single().Amount == 9.99m && sales.GetRefunds(s2.Id).Sum(r => r.Total) == s2.Total && sales.GetDisplayStatus(s2.Id) == SaleDisplayStatus.Refunded,
    "last unit gets exact remainder so cumulative refunds equal sale total exactly");

// ---- per-method caps ----
var s3 = Simple([Line(agua, 3)], CashPay(20m), OtherPay(PaymentMethod.DebitCard, 10m)); sales.Add(s3);
Invalid(() => Refund(s3, "x", [RL(0, 2)], [RP(PaymentMethod.DebitCard, 20m)], admin), "cap by method (card 10)", "cobrado");
Invalid(() => Refund(s3, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 21m)], admin), "payments exceeding the computed total");
Invalid(() => Refund(s3, "x", [RL(0, 3)], [RP(PaymentMethod.Cash, 31m)], admin), "refund above what was paid");
Refund(s3, "mixed", [RL(0, 1)], [RP(PaymentMethod.Cash, 5m), RP(PaymentMethod.DebitCard, 5m)], admin);
var s3Methods = sales.GetRefundability(s3.Id)!.Methods;
Check(s3Methods.Single(m => m.PaymentMethod == PaymentMethod.Cash).RemainingAmount == 15m && s3Methods.Single(m => m.PaymentMethod == PaymentMethod.DebitCard).RemainingAmount == 5m, "caps shrink by previous refunds of each method");
Invalid(() => Refund(s3, "x", [RL(0, 2)], [RP(PaymentMethod.Cash, 10m), RP(PaymentMethod.DebitCard, 10m)], admin), "card cap after earlier refund", "cobrado");
Refund(s3, "resto", [RL(0, 2)], [RP(PaymentMethod.Cash, 15m), RP(PaymentMethod.DebitCard, 5m)], admin);
Check(sales.GetDisplayStatus(s3.Id) == SaleDisplayStatus.Refunded, "mixed-method refunds complete the sale");

// ---- cancelled sale, cancel unchanged ----
var s4 = Simple([Line(pizza, 1)], CashPay(100m)); sales.Add(s4);
var harinaBeforeCancel = harina.CurrentStock; var cashBeforeCancel = cash.GetExpectedCash(register1.Id); var movementsBeforeCancel = storage.CashMovements.Count;
sales.Cancel(s4.Id, "error", admin);
Check(s4.Status == SaleStatus.Cancelled && harina.CurrentStock == harinaBeforeCancel + 0.5m && cash.GetExpectedCash(register1.Id) == cashBeforeCancel && storage.CashMovements.Count == movementsBeforeCancel
    && sales.GetDisplayStatus(s4.Id) == SaleDisplayStatus.Cancelled, "PRESERVE: cancellation restores stock, never touches cash; state Anulada");
Invalid(() => Refund(s4, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin), "refund of cancelled sale");
Check(sales.GetRefundability(s4.Id)!.CanRefund == false, "cancelled sale is not refundable");
Invalid(() => sales.Cancel(s4.Id, "otra vez", admin), "repeated cancellation (S10)");
var s4b = Simple([Line(agua, 1)], CashPay(10m)); sales.Add(s4b);
sales.Cancel(s4b.Id, "sin devoluciones", admin);
Check(sales.GetRefunds(s4b.Id).Count == 0 && s4b.Status == SaleStatus.Cancelled, "cancellation of a never-refunded sale still works");

// ---- legacy / unreliable lines ----
var s6 = Simple([Line(pizza, 2), Line(agua, 1)], CashPay(210m)); sales.Add(s6);
s6.Items[0].StockConsumption = null; // legacy line without per-line snapshot
Invalid(() => Refund(s6, "x", [RL(0, 1, RefundDisposition.Restock)], [RP(PaymentMethod.Cash, 100m)], admin), "legacy line Restock", "merma");
Invalid(() => Refund(s6, "x", [RL(0, 1, RefundDisposition.Restock), RL(1, 1, RefundDisposition.Waste)], [RP(PaymentMethod.Cash, 110m)], admin), "legacy line Restock inside a mixed refund", "merma");
var harinaS6 = harina.CurrentStock;
var w6 = Refund(s6, "merma", [RL(0, 1, RefundDisposition.Waste)], [RP(PaymentMethod.Cash, 100m)], admin);
Check(w6.Lines.Single().Disposition == RefundDisposition.Waste && harina.CurrentStock == harinaS6 && sales.GetRefundability(s6.Id)!.Lines[0].CanRestock == false && sales.GetRefundability(s6.Id)!.Lines[1].CanRestock, "legacy line accepts Waste and exposes CanRestock=false");
var s7 = Simple([Line(pizza, 1)], CashPay(100m)); sales.Add(s7);
s7.IsStockConsumptionReliable = false;
Invalid(() => Refund(s7, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin), "Restock on unreliable sale", "merma");
s7.IsStockConsumptionReliable = true;
var s8 = Simple([Line(pizza, 2)], CashPay(200m)); sales.Add(s8);
var savedStock = harina.CurrentStock;
harina.CurrentStock = decimal.MaxValue - 0.1m;
Invalid(() => Refund(s8, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin), "stock overflow on Restock", "l\u00edmite");
harina.CurrentStock = savedStock;
harina.Unit = "g";
Invalid(() => Refund(s8, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin), "ingredient changed unit", "unidad");
harina.Unit = "kg";
// An ingredient deleted after the sale no longer blocks the refund: see the "ingredient deleted after the sale" section below.
var harinaBeforeS8 = harina.CurrentStock;
Refund(s8, "una unidad", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin);
Check(harina.CurrentStock == harinaBeforeS8 + 0.5m, "restock quantity is per unit snapshot * q / line quantity");

// ---- cash capacity and counters ----
var s9 = Simple([Line(agua, 1)], CashPay(10m)); sales.Add(s9);
var drawer = cash.GetExpectedCash(register1.Id);
cash.AddManualMovement(CashMovementType.Withdrawal, drawer - 1m, "dejar poco", admin);
Invalid(() => Refund(s9, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin), "cash refund above drawer cash", "efectivo disponible");
cash.AddManualMovement(CashMovementType.Income, 100m, "reponer", admin);
var counterField = typeof(DataStorageService).GetField("_nextSaleRefundId", flags);
Check(counterField != null, "refund id counter exists");
var savedCounter = counterField?.GetValue(storage);
foreach (var bad in new[] { int.MaxValue, 0, -1 }) { counterField?.SetValue(storage, bad); Invalid(() => Refund(s9, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin), "refund id counter " + bad, "identificadores"); }
counterField?.SetValue(storage, savedCounter);
var movementCounter = typeof(DataStorageService).GetField("_nextCashMovementId", flags)!; var savedMovementCounter = movementCounter.GetValue(storage);
movementCounter.SetValue(storage, int.MaxValue);
Invalid(() => Refund(s9, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin), "cash movement counter exhausted for a cash refund", "identificadores");
movementCounter.SetValue(storage, savedMovementCounter);

// ---- closed register / no open register / current register ----
var s10 = Simple([Line(agua, 2)], CashPay(20m)); sales.Add(s10);
var s11 = Simple([Line(agua, 2)], OtherPay(PaymentMethod.Transfer, 20m)); sales.Add(s11);
CloseWith(cash.GetExpectedCash(register1.Id), admin);
string ClosedState() => JsonSerializer.Serialize(new { Reg = storage.CashRegisters.Where(r => r.Id == register1.Id), Cnt = storage.CashCounts.Where(c => c.CashRegisterId == register1.Id), Sum = storage.Summaries.Where(s => s.CashRegisterId == register1.Id), Mov = storage.CashMovements.Where(m => m.CashRegisterId == register1.Id) });
var closedBefore = ClosedState();
Invalid(() => Refund(s10, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin), "cash refund with no open register", "caja abierta");
var nr = Refund(s11, "sin caja", [RL(0, 1, RefundDisposition.Waste)], [RP(PaymentMethod.Transfer, 10m)], admin);
Check(nr.CashRegisterId == null && storage.CashMovements.Count(m => m.Type == CashMovementType.Refund && m.SaleId == s11.Id) == 0, "non-cash refund with no open register books no register and no movement");
Check(ClosedState() == closedBefore, "closed register untouched by no-register refund");
cash.Open(50m);
var register2 = cash.GetCurrent()!;
var cr = Refund(s10, "cliente de ayer", [RL(0, 1)], [RP(PaymentMethod.Cash, 10m)], admin);
var crMovement = storage.CashMovements.Last();
Check(register2.Id != register1.Id && cr.CashRegisterId == register2.Id && crMovement.Type == CashMovementType.Refund && crMovement.CashRegisterId == register2.Id
    && crMovement.SaleId == s10.Id && s10.CashRegisterId == register1.Id && cash.GetExpectedCash(register2.Id) == 40m, "refund of a closed-register sale is an outflow in the current open register linked to the sale");
Check(ClosedState() == closedBefore, "closed register, count, summary and its movements byte-identical after a refund booked elsewhere");
var cr2 = Refund(s11, "ahora con caja", [RL(0, 1)], [RP(PaymentMethod.Transfer, 10m)], admin);
Check(cr2.CashRegisterId == register2.Id && storage.CashMovements.Count(m => m.Type == CashMovementType.Refund && m.CashRegisterId == register2.Id) == 1, "non-cash refund links the open register without a cash movement");

// ---- payment summary (S13) ----
var sum1 = cash.GetPaymentSummary(register1.Id); var sum2 = cash.GetPaymentSummary(register2.Id);
var refunds1 = storage.SaleRefunds.Where(r => r.CashRegisterId == register1.Id).SelectMany(r => r.Payments).GroupBy(p => p.PaymentMethod).ToDictionary(g => g.Key, g => g.Sum(p => p.Amount));
Check(sum1.State == CashPaymentSummaryState.Complete && sum1.RegisteredTotal == sum1.Rows.Sum(r => r.Amount!.Value)
    && sum1.Rows.All(r => r.RefundedAmount == refunds1.GetValueOrDefault(r.Method) && r.NetAmount == r.Amount - r.RefundedAmount)
    && sum1.RefundedTotal == refunds1.Values.Sum() && sum1.NetTotal == sum1.RegisteredTotal - sum1.RefundedTotal, "register summary exposes refunds per method and net");
Check(sum1.Rows.Single(r => r.Method == PaymentMethod.Cash).RefundedAmount == storage.CashMovements.Where(m => m.CashRegisterId == register1.Id && m.Type == CashMovementType.Refund).Sum(m => m.Amount),
    "summary cash refunds match Refund movements of the register");
Check(sum1.RegisteredTotal == storage.Sales.Where(s => s.CashRegisterId == register1.Id).Sum(s => s.Payments.Sum(p => p.Amount)), "registered receipts unchanged by refunds (cancelled and refunded sales retained)");
Check(sum2.RegisteredTotal == 0m && sum2.RefundedTotal == 20m && sum2.NetTotal == -20m && sum2.Rows.Single(r => r.Method == PaymentMethod.Cash).RefundedAmount == 10m
    && sum2.Rows.Single(r => r.Method == PaymentMethod.Transfer).NetAmount == -10m, "refund of an older sale reduces the current register's net");
Check(sum1.Rows.Single(r => r.Method == PaymentMethod.Transfer).RefundedAmount == 0m, "refund without a register (Transfer 10 on the closed day) is excluded from every register summary");
var noSession = cash.GetPaymentSummary(null);
Check(noSession.State == CashPaymentSummaryState.NoSession && noSession.RefundedTotal == 0m && noSession.NetTotal == 0m, "no-session summary has zero refunds");
Check(cash.GetCurrentPaymentSummary().RefundedTotal == 20m, "current summary includes refunds");

// ---- persistence ----
storage.SaveToFile();
var savedJson = File.ReadAllText("data.json");
var reload = new DataStorageService();
Check(JsonSerializer.Serialize(reload.SaleRefunds) == JsonSerializer.Serialize(storage.SaleRefunds) && reload.SaleRefunds.Count == storage.SaleRefunds.Count, "save/reload refunds identical");
Check(JsonSerializer.Serialize(reload.Sales.Select(s => s.Items.Select(i => i.StockConsumption))) == JsonSerializer.Serialize(storage.Sales.Select(s => s.Items.Select(i => i.StockConsumption))), "save/reload per-line snapshots (including legacy null)");
var reloadSales = new SaleService(reload);
var reloadRefund = reloadSales.Refund(s10.Id, "tras reinicio", [RL(0, 1, RefundDisposition.Waste)], [RP(PaymentMethod.Cash, 10m)], reload.Users[0]);
Check(reloadRefund.Id == storage.SaleRefunds.Max(r => r.Id) + 1 && reloadSales.GetDisplayStatus(s10.Id) == SaleDisplayStatus.Refunded && reload.CashMovements.Last().Type == CashMovementType.Refund, "reload recovers refund counter and derived state");
// A legacy file knows nothing about refunds or per-line snapshots.
int dirs = 0;
DataStorageService LoadFrom(JsonObject json)
{
    var dir = Path.Combine(root, "load-" + (++dirs)); Directory.CreateDirectory(dir);
    File.WriteAllText(Path.Combine(dir, "data.json"), json.ToJsonString());
    Directory.SetCurrentDirectory(dir);
    try { return new DataStorageService(); } finally { Directory.SetCurrentDirectory(root); }
}
JsonObject Fresh() => JsonNode.Parse(savedJson)!.AsObject();
var legacyJson = Fresh(); legacyJson.Remove("SaleRefunds"); legacyJson.Remove("NextSaleRefundId");
legacyJson.Remove("StockMovements"); legacyJson.Remove("NextStockMovementId"); // a legacy file has neither refunds nor the ledger that links to them
foreach (var sale in legacyJson["Sales"]!.AsArray())
{
    sale!.AsObject().Remove("CreatedByUserId"); sale.AsObject().Remove("CreatedByUsername");
    foreach (var item in sale["Items"]!.AsArray()) item!.AsObject().Remove("StockConsumption");
}
legacyJson["Sales"]!.AsArray().First(s => s!["Id"]!.GetValue<int>() == s5.Id)!["Payments"] = new JsonArray(); // legacy sale without payments
var legacyOriginalSales = JsonNode.Parse(legacyJson["Sales"]!.ToJsonString())!;
var legacyStorage = LoadFrom(legacyJson);
var legacyDir = Path.Combine(root, "load-" + dirs);
var legacySales = new SaleService(legacyStorage);
Check(legacyStorage.SaleRefunds.Count == 0 && legacyStorage.Sales.Count == storage.Sales.Count && legacyStorage.Sales.All(s => s.Items.All(i => i.StockConsumption == null))
    && legacySales.GetDisplayStatus(s1.Id) == SaleDisplayStatus.Collected && legacySales.GetRefundability(s1.Id)!.Lines.All(l => !l.CanRestock), "legacy JSON without refunds or line snapshots loads; sales show Cobrada and cannot Restock");
// ---- T6 regression: legacy data keeps loading, rejecting restock and saving original fields ----
Check(legacyStorage.Sales.All(s => s.CreatedByUserId == null && s.CreatedByUsername == null), "legacy sales without CreatedBy* load with null operator");
var legacyView = legacySales.GetRefundability(s1.Id)!;
Check(legacyView.Lines.All(l => !l.CanRestock) && legacyView.Status == SaleDisplayStatus.Collected, "legacy lines without per-line snapshot expose CanRestock=false");
var legacyRestock = false; var legacyMessage = "";
try { legacySales.Refund(s1.Id, "x", [RL(0, 1, RefundDisposition.Restock)], [RP(PaymentMethod.Cash, 81m)], legacyStorage.Users[0]); }
catch (InvalidOperationException ex) { legacyRestock = ex.Message.Contains("s\u00f3lo puede devolverse como merma"); legacyMessage = ex.Message; }
Check(legacyRestock && legacyStorage.SaleRefunds.Count == 0, "legacy Restock refund rejected with 's\u00f3lo puede devolverse como merma' and nothing recorded [" + legacyMessage + "]");
Directory.SetCurrentDirectory(legacyDir);
try { legacyStorage.SaveToFile(); } finally { Directory.SetCurrentDirectory(root); }
bool Preserves(JsonNode? original, JsonNode? saved) => original switch
{
    null => saved == null,
    JsonObject o => saved is JsonObject so && o.All(p => so.ContainsKey(p.Key) && Preserves(p.Value, so[p.Key])),
    JsonArray a => saved is JsonArray sa && sa.Count == a.Count && a.Select((n, i) => Preserves(n, sa[i])).All(ok => ok),
    _ => saved != null && original.ToJsonString() == saved.ToJsonString()
};
var resaved = JsonNode.Parse(File.ReadAllText(Path.Combine(legacyDir, "data.json")))!;
Check(Preserves(legacyOriginalSales, resaved["Sales"]), "saving a legacy-loaded store keeps every original sale field");
var noPay = legacySales.GetRefundability(s5.Id)!;
Check(noPay.RemainingTotal == 20m && noPay.Methods.Count == 0 && noPay.Lines[0].RemainingQuantity == 2 && !noPay.CanRefund && !noPay.HasRefundableMoney,
    "legacy sale without payments: CanRefund false (remaining total > 0, no method with remaining amount)");
Check(legacySales.GetRefundability(s1.Id)!.CanRefund && legacySales.GetRefundability(s1.Id)!.HasRefundableMoney, "legacy sale with payments stays refundable");
void BadLoad(string name, Action<JsonObject> mutate)
{
    var json = Fresh(); mutate(json);
    var ok = false;
    try { LoadFrom(json); } catch (InvalidDataException) { ok = true; }
    Check(ok, "corrupt refund data rejected on load: " + name);
}
BadLoad("null list", j => j["SaleRefunds"] = null);
BadLoad("unknown sale", j => j["SaleRefunds"]![0]!["SaleId"] = 98765);
BadLoad("duplicate refund id", j => j["SaleRefunds"]![1]!["Id"] = j["SaleRefunds"]![0]!["Id"]!.GetValue<int>());
BadLoad("zero refund id", j => j["SaleRefunds"]![0]!["Id"] = 0);
BadLoad("line quantity above sold units", j => j["SaleRefunds"]![0]!["Lines"]![0]!["Quantity"] = 999);
BadLoad("line index out of range", j => j["SaleRefunds"]![0]!["Lines"]![0]!["SaleItemIndex"] = 50);
BadLoad("blank reason", j => j["SaleRefunds"]![0]!["Reason"] = "  ");
BadLoad("payments not matching total", j => j["SaleRefunds"]![0]!["Total"] = 999m);
BadLoad("unknown register", j => j["SaleRefunds"]![0]!["CashRegisterId"] = 777);
BadLoad("refunded sale marked cancelled", j => j["Sales"]!.AsArray().First(s => s!["Id"]!.GetValue<int>() == s1.Id)!["Status"] = 1);
BadLoad("cumulative refunds above sale total", j =>
{
    var copy = JsonNode.Parse(j["SaleRefunds"]![0]!.ToJsonString())!;
    copy["Id"] = 5000; copy["SaleId"] = s1.Id; // first refund of S1 is repeated on top of its complete refunds
    j["SaleRefunds"]!.AsArray().Add(copy);
});

// ---- T6 / S13: gross, discounts, cancellations, refunds and net; closed-register cash refund ----
(DataStorageService St, SaleService Sales, CashRegisterService Cash, User Admin) NewStack(string name)
{
    var dir = Path.Combine(root, name); Directory.CreateDirectory(dir);
    Directory.SetCurrentDirectory(dir);
    var st = new DataStorageService();
    st.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin }];
    st.Products = [new Product { Id = 1, Name = "Cafe", Price = 20m }, new Product { Id = 2, Name = "Menu", Price = 150m }];
    var sv = new SaleService(st); var cs = new CashRegisterService(st, sv);
    cs.Open(100m);
    return (st, sv, cs, st.Users[0]);
}
try
{
    var t6 = NewStack("t6-report");
    var cafe = t6.St.Products[0];
    var saleA = Simple([Line(cafe, 5)], CashPay(100m)); t6.Sales.Add(saleA, Copy(t6.Admin));
    var beforeRefundReport = t6.Sales.GetTodayReport();
    Check(beforeRefundReport.GrossSales == 100m && beforeRefundReport.RefundedTotal == 0m && beforeRefundReport.NetTotal == 100m, "S13 report before refunds: gross 100, refunds 0, net 100");
    t6.Sales.Refund(saleA.Id, "devolucion parcial", [RL(0, 2, RefundDisposition.Waste)], [RP(PaymentMethod.Cash, 40m)], t6.Admin);
    var rep = t6.Sales.GetTodayReport();
    Check(rep.GrossSales == 100m && rep.Discounts == 0m && rep.SoldTotal == 100m && rep.CancelledTotal == 0m && rep.RefundedTotal == 40m && rep.RefundCount == 1 && rep.NetTotal == 60m,
        "S13 sale 100, refund 40: gross 100, refunds 40, net 60");
    var saleB = Simple([Line(cafe, 2, DiscountType.Percentage, 10m)], CashPay(36m)); t6.Sales.Add(saleB, Copy(t6.Admin));
    var saleC = Simple([Line(cafe, 1)], CashPay(20m)); t6.Sales.Add(saleC, Copy(t6.Admin));
    t6.Sales.Cancel(saleC.Id, "error", t6.Admin);
    var before6 = JsonSerializer.Serialize(new { t6.St.Sales, t6.St.SaleRefunds, t6.St.Summaries, t6.St.CashMovements });
    var rep2 = t6.Sales.GetTodayReport();
    Check(rep2.GrossSales == 140m && rep2.Discounts == 4m && rep2.SoldTotal == 136m && rep2.SalesCount == 2 && rep2.CancelledTotal == 20m && rep2.CancelledCount == 1
        && rep2.RefundedTotal == 40m && rep2.NetTotal == 96m, "S13 report separates gross 140, discounts 4, sold 136, cancelled 20, refunds 40, net 96");
    Check(t6.Sales.GetTodayTotal() == 136m && t6.Sales.GetTodayCount() == 2, "PRESERVE: Total Vendido (completed, after discounts) and count keep their meaning");
    Check(JsonSerializer.Serialize(new { t6.St.Sales, t6.St.SaleRefunds, t6.St.Summaries, t6.St.CashMovements }) == before6, "report is read-only");
    saleA.Date = DateTime.Today.AddDays(-1);
    var rep3 = t6.Sales.GetTodayReport();
    Check(rep3.GrossSales == 40m && rep3.RefundedTotal == 40m && rep3.NetTotal == -4m, "refunds count by refund date, sales by sale date");
    saleA.Date = DateTime.Now;
    var yesterday = t6.Sales.GetReport(DateTime.Today.AddDays(-1));
    Check(yesterday.GrossSales == 0m && yesterday.RefundedTotal == 0m && yesterday.NetTotal == 0m && yesterday.CancelledTotal == 0m, "report of another day is empty");

    var t6c = NewStack("t6-closed");
    var menu = t6c.St.Products[1];
    var big = Simple([Line(menu, 1)], CashPay(150m)); t6c.Sales.Add(big, Copy(t6c.Admin));
    var review6 = t6c.Cash.GetCountReview();
    t6c.Cash.Close(new CashCountRequest { Review = review6, Lines = new[] { new CashCountLineInput(50m, 5) }, Confirmed = true }, Copy(t6c.Admin));
    var closedId = t6c.St.CashRegisters.Single().Id;
    string Closed6() => JsonSerializer.Serialize(new { Reg = t6c.St.CashRegisters.Where(r => r.Id == closedId), Cnt = t6c.St.CashCounts.Where(c => c.CashRegisterId == closedId),
        Sum = t6c.St.Summaries.Where(s => s.CashRegisterId == closedId), Mov = t6c.St.CashMovements.Where(m => m.CashRegisterId == closedId) });
    var closedBefore6 = Closed6();
    var closed6 = t6c.St.CashRegisters.Single();
    Check(!closed6.IsOpen && closed6.FinalAmount == 250m && closed6.ExpectedAmount == 250m, "closed fixture register: expected 250 counted 250");
    t6c.Cash.Open(500m);
    var open6 = t6c.Cash.GetCurrent()!;
    var closedRefund = t6c.Sales.Refund(big.Id, "cliente de ayer", [RL(0, 1, RefundDisposition.Waste)], [RP(PaymentMethod.Cash, 150m)], t6c.Admin);
    var mv = t6c.St.CashMovements.Last();
    Check(mv.Type == CashMovementType.Refund && mv.Amount == 150m && mv.CashRegisterId == open6.Id && mv.SaleId == big.Id && closedRefund.CashRegisterId == open6.Id
        && t6c.Cash.GetExpectedCash(open6.Id) == 350m, "closed-register sale cash refund 150 is a Refund movement in the open register");
    var closedAfter = t6c.St.CashRegisters.Single(r => r.Id == closedId);
    Check(closedAfter.FinalAmount == 250m && closedAfter.ExpectedAmount == 250m && t6c.St.CashCounts.Single(c => c.CashRegisterId == closedId).CountedAmount == 250m && Closed6() == closedBefore6,
        "closed register FinalAmount, ExpectedAmount and CashCount unchanged by the refund");
    var closedPay = t6c.Cash.GetPaymentSummary(closedId); var openPay = t6c.Cash.GetPaymentSummary(open6.Id);
    Check(closedPay.RegisteredTotal == 150m && closedPay.RefundedTotal == 0m && openPay.RefundedTotal == 150m && openPay.NetTotal == -150m, "payment summaries: receipts stay in the closed register, refund nets the open one");
}
finally { Directory.SetCurrentDirectory(root); }

// ---- S3: an ingredient deleted after the sale (history is kept, the ingredient is gone) ----
// Decision: restocking a line returns only what still exists. The entry of a deleted ingredient is skipped and records
// nothing (there is no stock to restore and no movement to attach to a missing ingredient); the refund or cancellation
// itself, its money and the other ingredients are unaffected. A changed unit still rejects (unchanged behavior).
try
{
    var dir = Path.Combine(root, "ingdel"); Directory.CreateDirectory(dir); Directory.SetCurrentDirectory(dir);
    var st = new DataStorageService();
    st.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin }];
    var dAdmin = st.Users[0];
    st.Ingredients = [new Ingredient { Id = 1, Name = "Harina", Unit = "kg", CurrentStock = 100m }, new Ingredient { Id = 2, Name = "Huevos", Unit = "unidad", CurrentStock = 200m }];
    st.Products = [new Product { Id = 1, Name = "Pizza", Price = 100m }];
    st.Recipes = [new Recipe { Id = 1, Name = "Pizza", Ingredients = [
        new RecipeIngredient { RecipeId = 1, IngredientId = 1, Quantity = 0.5m, Unit = "kg" },
        new RecipeIngredient { RecipeId = 1, IngredientId = 2, Quantity = 2m, Unit = "unidad" }] }];
    var dInvoices = new InvoiceService(st); var dIngredients = new IngredientService(st, dInvoices); var dRecipes = new RecipeService(st, dInvoices);
    var dSales = new SaleService(st); dSales.SetRecipeService(dRecipes); dSales.SetIngredientService(dIngredients);
    var dCash = new CashRegisterService(st, dSales); dCash.Open(100m);
    var dPizza = st.Products[0];
    var d1 = Simple([Line(dPizza, 2)], CashPay(200m)); dSales.Add(d1);
    var d2 = Simple([Line(dPizza, 1)], CashPay(100m)); dSales.Add(d2);
    var d3 = Simple([Line(dPizza, 1)], CashPay(100m)); dSales.Add(d3);
    string MovesOf(int id) => JsonSerializer.Serialize(st.StockMovements.Where(m => m.IngredientId == id));
    var harinaMoves = MovesOf(1); var huevosStock = st.Ingredients[1].CurrentStock; var movementTotal = st.StockMovements.Count;
    st.Recipes[0].Ingredients.RemoveAll(i => i.IngredientId == 1);   // a recipe uses it => deletion would be rejected
    dIngredients.Delete(1);
    Check(st.Ingredients.All(i => i.Id != 1) && MovesOf(1) == harinaMoves && st.StockMovements.Count == movementTotal, "ingredient deleted after the sale: its movements stay untouched");

    var refund1 = dSales.Refund(d1.Id, "devuelto", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], dAdmin);
    var added = st.StockMovements.Skip(movementTotal).ToList();
    Check(refund1.Lines.Single().Disposition == RefundDisposition.Restock && st.SaleRefunds.Count == 1 && st.CashMovements.Any(m => m.Type == CashMovementType.Refund && m.Amount == 100m),
        "Restock refund of a line whose ingredient was deleted is accepted: refund and cash recorded");
    Check(added.Count == 1 && added[0].IngredientId == 2 && added[0].Type == StockMovementType.RefundReturn && added[0].Quantity == 2m && added[0].RefundId == refund1.Id && st.Ingredients[0].CurrentStock == huevosStock + 2m && MovesOf(1) == harinaMoves,
        "the deleted ingredient is skipped (no movement, no stock); the remaining ingredient is restocked in proportion");
    var beforeCancel = st.StockMovements.Count; var huevosBeforeCancel = st.Ingredients[0].CurrentStock;
    dSales.Cancel(d2.Id, "error", dAdmin);
    var cancelAdded = st.StockMovements.Skip(beforeCancel).ToList();
    Check(d2.Status == SaleStatus.Cancelled && cancelAdded.Count == 1 && cancelAdded[0].IngredientId == 2 && cancelAdded[0].Type == StockMovementType.SaleCancellationReturn && st.Ingredients[0].CurrentStock == huevosBeforeCancel + 2m && MovesOf(1) == harinaMoves,
        "cancelling a sale with a deleted ingredient is accepted: the sale is voided, the existing ingredient is restored, the deleted one is skipped");
    st.Recipes[0].Ingredients.RemoveAll(i => i.IngredientId == 2); dIngredients.Delete(2);
    var beforeEmpty = st.StockMovements.Count;
    var refund3 = dSales.Refund(d3.Id, "devuelto", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], dAdmin);
    Check(st.StockMovements.Count == beforeEmpty && st.SaleRefunds.Count == 2 && refund3.Total == 100m, "when every ingredient of the line is deleted the refund is recorded with no stock movement");
    var d4 = Simple([Line(dPizza, 1)], CashPay(100m)); dSales.Add(d4);
    Check(d4.StockConsumption != null && d4.StockConsumption.Count == 0 && st.StockMovements.Count == beforeEmpty, "PRESERVE: a new sale of a product whose recipe lost its ingredients consumes nothing");
    var d5 = Simple([Line(dPizza, 1)], CashPay(100m)); dSales.Add(d5);
    dSales.Cancel(d5.Id, "sin consumo", dAdmin);
    Check(d5.Status == SaleStatus.Cancelled && st.StockMovements.Count == beforeEmpty, "cancelling a sale that consumed nothing records no movement");
}
finally { Directory.SetCurrentDirectory(root); }

// ---- UI label ----
var cashPage = File.ReadAllText(Path.Combine(args[0], "Pages", "Cash.razor"));
Check(cashPage.Contains("CashMovementType.Refund => \"Devoluci\u00f3n\""), "Cash page labels Refund movements as Devolucion");
Check(System.Text.RegularExpressions.Regex.IsMatch(cashPage, @"CashMovementType\.Refund\s*\?\s*""[^""]"""), "Cash page shows Refund movements as outflows");
var summaryPage = File.ReadAllText(Path.Combine(args[0], "Pages", "Summary.razor"));
foreach (var label in new[] { "Ventas brutas", "Descuentos", "Anulaciones", "Devoluciones", "Importe neto" })
    Check(summaryPage.Contains(label), "Summary page renders label: " + label);
var cashHistoryPage = File.ReadAllText(Path.Combine(args[0], "Pages", "CashHistory.razor"));
foreach (var (pageName, text) in new[] { ("Cash", cashPage), ("CashHistory", cashHistoryPage) })
    Check(text.Contains("Cobros registrados") && text.Contains("Devuelto") && text.Contains("Neto") && text.Contains("RefundedAmount") && text.Contains("NetAmount")
        && text.Contains("RefundedTotal") && text.Contains("NetTotal"), pageName + " page keeps Cobros registrados and renders Devuelto/Neto per method and totals");
var historyPage = File.ReadAllText(Path.Combine(args[0], "Pages", "SalesHistory.razor"));
Check(historyPage.Contains("La venta no tiene pagos registrados; no puede devolverse."), "Sales history explains a sale without payments cannot be refunded");
Console.WriteLine($"{checks} checks, {failures} failures; fixture: {root}");
return failures == 0 ? 0 : 1;
'@ | Set-Content (Join-Path $ScratchPath 'Program.cs') -Encoding utf8
$exitCode = 1
Push-Location $ScratchPath
try {
    & dotnet run --project (Join-Path $ScratchPath 'RefundChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Refund checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
