param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-payments-' + [guid]::NewGuid().ToString('N')) }
$ScratchPath = [IO.Path]::GetFullPath($ScratchPath)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (!$ScratchPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'ScratchPath must be under the OS temporary directory.' }
if (Test-Path $ScratchPath) { throw 'ScratchPath must be a new directory.' }
New-Item -ItemType Directory -Path $ScratchPath | Out-Null
Write-Host "Verification scratch: $ScratchPath (retained for inspection)"
$before = (& git -C $repo hash-object data.json GastroApp.csproj)
$expected = @('0f8def10c364036b406c8d225f8e5fa059b26954', '190890656d669c27c178fc53dfc526a9a184e818')
if (($before -join ',') -ne ($expected -join ',')) { throw 'Unexpected live data/project baseline.' }
$project = [xml](Get-Content (Join-Path $repo 'GastroApp.csproj') -Raw)
$framework = $project.Project.PropertyGroup.TargetFramework
$reference = [Security.SecurityElement]::Escape((Join-Path $repo 'GastroApp.csproj'))
@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>$framework</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><ProjectReference Include="$reference" /><FrameworkReference Include="Microsoft.AspNetCore.App" /></ItemGroup>
</Project>
"@ | Set-Content (Join-Path $ScratchPath 'PaymentChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Rendering;
using System.Collections;
using System.Reflection;
using System.Text.Json;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var query = typeof(CashRegisterService).GetMethod("GetCurrentPaymentSummary");
Check(query != null, "typed current-session payment summary query exists");
if (query == null) { Console.WriteLine($"{checks} checks, {failures} failures"); return 1; }
Check(query.ReturnType.Name == "CashPaymentSummary", "query returns typed summary rather than dictionary/object");
var storage = new DataStorageService(); // All storage IO is in a fresh OS-temp working directory.
var sales = new SaleService(storage);
var cash = new CashRegisterService(storage, sales);
dynamic Summary() => query.Invoke(cash, null)!;
List<dynamic> Rows(dynamic result) => ((IEnumerable)result.Rows).Cast<dynamic>().ToList();
List<dynamic> Warnings(dynamic result) => ((IEnumerable)result.Warnings).Cast<dynamic>().ToList();
decimal? Amount(dynamic result, PaymentMethod method) => (decimal?)Rows(result).Single(r => (PaymentMethod)r.Method == method).Amount;
bool Has(dynamic result, string reason, int count = 1) => Warnings(result).Any(w => w.Reason.ToString() == reason && (int)w.Count == count && !string.IsNullOrWhiteSpace((string)w.Message));
void Totals(dynamic result, decimal total, string name)
{
    Check((decimal?)result.RegisteredTotal == total && Rows(result).Count == 6 && Rows(result).Sum(r => (decimal?)r.Amount ?? 0m) == total, name);
}
void Unavailable(dynamic result, string reason, string name)
{
    Check(result.State.ToString() == "Unavailable" && (decimal?)result.RegisteredTotal == null && Rows(result).All(r => (decimal?)r.Amount == null) && Has(result, reason), name);
}
Sale Sale(decimal amount, PaymentMethod method = PaymentMethod.Cash, int? session = null) => new()
{
    Id = storage.Sales.Count + 1, CashRegisterId = session ?? storage.CurrentCashRegisterId,
    Items = [new SaleItem { ProductId = 1, ProductName = "fixture", Price = amount, Quantity = 1 }],
    Payments = amount == 0m ? [] : [new SalePayment { PaymentMethod = method, Amount = amount }]
};
void Only(params Sale[] selected) { storage.Sales = selected.ToList(); }
var result = Summary();
Check(result.State.ToString() == "NoSession" && (int?)result.CashRegisterId == null, "no session explicit state");
Totals(result, 0m, "no session six zero rows and registered zero");
cash.Open(123m);
result = Summary();
Check(result.State.ToString() == "Complete" && (int?)result.CashRegisterId == storage.CurrentCashRegisterId, "empty session complete canonical ID");
Totals(result, 0m, "empty session all six zeros excludes initial amount");
foreach (var method in Enum.GetValues<PaymentMethod>())
{
    Only(Sale(1.123456789m, method)); result = Summary();
    Totals(result, 1.123456789m, method + " exact precision registered total");
    Check(Amount(result, method) == 1.123456789m && Rows(result).Where(r => (PaymentMethod)r.Method != method).All(r => (decimal?)r.Amount == 0m), method + " independently allocated with five zero rows");
}
var discounted = Sale(12.3456789m);
discounted.Items[0].DiscountType = DiscountType.Percentage; discounted.Items[0].DiscountValue = 12.5m;
discounted.DiscountType = DiscountType.Fixed; discounted.DiscountValue = 0.01m;
discounted.Payments[0].Amount = 10.7924690375m;
Only(discounted); Totals(Summary(), 10.7924690375m, "line and whole-sale discounts preserve exact fractional precision");
Check(Summary().State.ToString() == "Complete", "discounted total allocations accepted without rounding");
var mixed = Sale(21m);
mixed.Payments = Enum.GetValues<PaymentMethod>().Select((m, i) => new SalePayment { PaymentMethod = m, Amount = i + 1m, ReceivedAmount = decimal.MinValue }).ToList();
Only(mixed); result = Summary();
Totals(result, 21m, "six-method mixed sale counts Amount only ignoring invalid historical tender");
Check(Enum.GetValues<PaymentMethod>().All(m => Amount(result, m) == (int)m + 1m), "mixed per-method totals");
mixed.Payments[0].ReceivedAmount = 100m;
Check(mixed.Payments[0].Change == 99m && Amount(Summary(), PaymentMethod.Cash) == 1m, "cash tender and change never aggregate");
mixed.Payments[0].ReceivedAmount = null;
Check(Summary().State.ToString() == "Complete", "historical missing cash tender accepted");
var firstId = storage.CurrentCashRegisterId!.Value;
var acrossDays = Sale(2m); acrossDays.Date = DateTime.Today.AddDays(-3);
Only(mixed, acrossDays);
Totals(Summary(), 23m, "session includes dates across days");
var prior = Sale(99m, session: firstId + 99); prior.Date = mixed.Date;
storage.Sales.Add(prior);
Totals(Summary(), 23m, "different session same date excluded");
var unlinked = Sale(9m); unlinked.CashRegisterId = null; unlinked.Payments = [];
storage.Sales.Add(unlinked);
result = Summary();
Check(result.State.ToString() == "Partial" && Has(result, "UnlinkedHistoricalSales") && Warnings(result).Any(w => (bool)w.IsGlobal), "unlinked historical missing payments has explicit global warning");
Totals(result, 23m, "global warning never invents attribution");
Only(unlinked); storage.Sales.Add(null!);
Check(Has(Summary(), "UnattributedInvalidSales") && Has(Summary(), "UnlinkedHistoricalSales"), "null historical record explicitly global, never silently attributed");
var otherInvalid = Sale(10m, session: firstId + 99); otherInvalid.Items = null!;
Only(otherInvalid);
Check(Summary().State.ToString() == "Complete", "malformed other-session sale excluded by identity before validation");
Only(Sale(0m));
Check(Summary().State.ToString() == "Complete", "zero-total valid sale empty allocations accepted");
Totals(Summary(), 0m, "zero-total sale contributes zero");
// Every invalid selected sale is excluded whole, even with a valid first cash allocation.
var valid = Sale(4m, PaymentMethod.Transfer);
void Invalid(Action<Sale> damage, string reason, string name)
{
    var invalid = Sale(10m);
    invalid.Payments = [new SalePayment { PaymentMethod = PaymentMethod.Cash, Amount = 4m }, new SalePayment { PaymentMethod = PaymentMethod.DebitCard, Amount = 6m }];
    damage(invalid); Only(valid, invalid); var summary = Summary();
    Check(summary.State.ToString() == "Partial" && Has(summary, reason), name + " explicit partial reason/count");
    Check((decimal?)summary.RegisteredTotal == 4m && Amount(summary, PaymentMethod.Cash) == 0m && Amount(summary, PaymentMethod.DebitCard) == 0m, name + " excludes whole sale, no partial allocation");
}
Invalid(s => s.Payments = null!, "InvalidPayments", "null collection");
Invalid(s => s.Payments[1] = null!, "InvalidPayments", "null allocation");
Invalid(s => s.Payments[1].PaymentMethod = (PaymentMethod)99, "InvalidPayments", "unknown method");
Invalid(s => s.Payments[1].PaymentMethod = PaymentMethod.Cash, "InvalidPayments", "duplicate method");
Invalid(s => s.Payments[1].Amount = 0m, "InvalidPayments", "zero allocation");
Invalid(s => s.Payments[1].Amount = -1m, "InvalidPayments", "negative allocation");
Invalid(s => s.Payments[1].Amount = 5m, "AllocationMismatch", "allocation mismatch");
Invalid(s => s.Payments = [], "MissingPayments", "positive sale missing payments");
Invalid(s => s.Items = null!, "InvalidSaleItems", "null items");
Invalid(s => s.Items = [], "InvalidSaleItems", "empty items");
Invalid(s => s.Items[0] = null!, "InvalidSaleItems", "null item");
Invalid(s => s.Items[0].Quantity = 0, "InvalidSaleItems", "zero quantity");
Invalid(s => s.Items[0].Quantity = -1, "InvalidSaleItems", "negative quantity");
Invalid(s => s.Items[0].Price = -1m, "InvalidSaleItems", "negative price");
Invalid(s => s.Items[0].DiscountType = (DiscountType)99, "InvalidSaleItems", "unknown line discount");
Invalid(s => s.Items[0].DiscountValue = 1m, "InvalidSaleItems", "invalid line discount value");
Invalid(s => { s.Items[0].DiscountType = DiscountType.Fixed; s.Items[0].DiscountValue = 11m; }, "InvalidSaleItems", "excessive fixed line discount");
Invalid(s => s.DiscountType = (DiscountType)99, "InvalidSaleItems", "unknown sale discount");
Invalid(s => s.DiscountValue = -1m, "InvalidSaleItems", "negative sale discount");
Invalid(s => { s.DiscountType = DiscountType.Fixed; s.DiscountValue = 1m; }, "AllocationMismatch", "discount changes final total");
Invalid(s => { s.DiscountType = DiscountType.Percentage; s.DiscountValue = 101m; }, "InvalidSaleItems", "invalid sale discount");
var zeroWithPayment = Sale(0m); zeroWithPayment.Payments = [new SalePayment { PaymentMethod = PaymentMethod.Cash, Amount = 1m }];
Only(zeroWithPayment); Check(Has(Summary(), "AllocationMismatch") && (decimal?)Summary().RegisteredTotal == 0m, "zero-total sale with payments excluded");
Only(Sale(1m), Sale(2m)); storage.Sales.ForEach(s => s.Payments = []);
Check(Has(Summary(), "MissingPayments", 2), "warning counts group excluded sales by reason");
var overflow = Sale(decimal.MaxValue); overflow.Items[0].Quantity = 2;
Only(valid, overflow); Unavailable(Summary(), "ArithmeticOverflow", "sale multiplication overflow explicit unavailable");
overflow = Sale(decimal.MaxValue); overflow.Items.Add(new SaleItem { ProductId = 1, Price = 1m, Quantity = 1 });
Only(valid, overflow); Unavailable(Summary(), "ArithmeticOverflow", "sale subtotal overflow explicit unavailable");
overflow = Sale(decimal.MaxValue); overflow.DiscountType = DiscountType.Percentage; overflow.DiscountValue = 100m;
Only(overflow); Unavailable(Summary(), "ArithmeticOverflow", "sale discount arithmetic overflow explicit unavailable");
overflow = Sale(decimal.MaxValue); overflow.Payments.Add(new SalePayment { PaymentMethod = PaymentMethod.Transfer, Amount = 1m });
Only(overflow); Unavailable(Summary(), "ArithmeticOverflow", "allocation sum overflow explicit unavailable");
Only(Sale(decimal.MaxValue), Sale(1m)); Unavailable(Summary(), "ArithmeticOverflow", "per-method aggregate overflow suppresses every numeric total");
Only(Sale(decimal.MaxValue), Sale(1m, PaymentMethod.Transfer)); Unavailable(Summary(), "ArithmeticOverflow", "registered total overflow across methods unavailable");
// Exercise actual checkout, cancellation, manual ledger, persistence and closed/new pointer lifecycle.
Only();
var admin = storage.Users.First(u => u.Role == UserRole.Admin);
cash.AddManualMovement(CashMovementType.Income, 20m, "fixture", admin);
cash.AddManualMovement(CashMovementType.Expense, 2m, "fixture", admin);
cash.AddManualMovement(CashMovementType.Withdrawal, 3m, "fixture", admin);
Totals(Summary(), 0m, "manual income/expense/withdrawal and initial funds excluded");
var product = storage.Products.First(p => p.IsActive);
Sale Checkout(decimal price, PaymentMethod method) => new() { Items = [new SaleItem { ProductId = product.Id, ProductName = product.Name, Price = price, Quantity = 1 }], Payments = [new SalePayment { PaymentMethod = method, Amount = price, ReceivedAmount = method == PaymentMethod.Cash ? price + 100m : null }] };
var completed = Checkout(7.12345m, PaymentMethod.Cash); sales.Add(completed);
var detached = Summary(); Totals(detached, 7.12345m, "summary refresh after new actual checkout");
sales.Cancel(completed.Id, "fixture", admin);
Check(sales.GetTodayCount() == 0 && (decimal?)Summary().RegisteredTotal == 7.12345m, "cancelled receipts retained distinct from completed-sale metrics");
sales.Add(Checkout(2m, PaymentMethod.DebitCard));
Totals(detached, 7.12345m, "old snapshot remains detached after new sale");
Totals(Summary(), 9.12345m, "new query includes new sale");
var before = JsonSerializer.Serialize(new { storage.Sales, storage.CashRegisters, storage.CashMovements, storage.Summaries });
var bytes = File.ReadAllBytes("data.json");
string Counters() => JsonSerializer.Serialize(typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }));
var counters = Counters();
result = Summary();
Check(Counters() == counters, "query changes no ID counters");
Check(before == JsonSerializer.Serialize(new { storage.Sales, storage.CashRegisters, storage.CashMovements, storage.Summaries }) && bytes.SequenceEqual(File.ReadAllBytes("data.json")), "query changes no objects or persisted bytes");
foreach (var list in new object[] { result.Rows, result.Warnings })
    Check(list is IList immutable && immutable.IsReadOnly, "result collection is read-only");
Check(Rows(result).All(r => ((Type)r.GetType()).GetProperties().All(p => p.SetMethod == null)) && query.ReturnType.GetProperties().All(p => p.SetMethod == null), "summary and row properties have no setters");
var warningType = typeof(Sale).Assembly.GetType("GastroApp.Models.CashPaymentWarning")!;
Check(warningType.GetProperties().All(p => p.SetMethod == null), "warning values are immutable too");
DailySummary CloseWith(CashRegisterService service, decimal amount, User actor)
{
    var review = service.GetCountReview();
    return service.Close(new CashCountRequest { Review = review,
        Lines = amount > 0m ? new[] { new CashCountLineInput(amount, 1) } : Array.Empty<CashCountLineInput>(),
        Reason = amount != review.ExpectedAmount ? "fixture" : null, Confirmed = true, ZeroCountConfirmed = amount == 0m },
        new User { Id = actor.Id, Username = actor.Username, PasswordHash = actor.PasswordHash, Role = actor.Role });
}
CloseWith(cash, cash.GetExpectedCash(firstId), admin);
Totals(Summary(), 9.12345m, "current closed session retains receipts");
var reload = new DataStorageService(); var reloadedCash = new CashRegisterService(reload, new SaleService(reload));
Check(JsonSerializer.Serialize(query.Invoke(reloadedCash, null)) == JsonSerializer.Serialize((object)Summary()), "save/reload exact summary parity including cancelled receipts");
cash.Open(0m);
Totals(Summary(), 0m, "new canonical current pointer resets summary without old session receipts");
// Render-tree calls exercise rerender snapshot refresh without starting the application host.
var pageType = typeof(GastroApp.Pages.Cash);
var page = Activator.CreateInstance(pageType)!;
var auth = new AuthService(new UserService(storage)); auth.Login("admin", "admin");
pageType.GetProperty("CashService", flags)!.SetValue(page, cash);
pageType.GetProperty("AuthService", flags)!.SetValue(page, auth);
pageType.GetProperty("Navigation", flags)!.SetValue(page, new TestNavigation());
pageType.GetField("cashRegister", flags)!.SetValue(page, storage.CashRegisters.First());
void Render() => pageType.GetMethod("BuildRenderTree", flags)!.Invoke(page, [new RenderTreeBuilder()]);
Render();
Check(ReferenceEquals(pageType.GetField("cashRegister", flags)!.GetValue(page), cash.GetCurrent()), "rerender refreshes stale current-session header with summary");
Only(Sale(3m, PaymentMethod.Other)); Render();
Totals(Summary(), 3m, "rerender/new sale latest summary query");
var source = File.ReadAllText(Path.Combine(args[0], "Pages", "Cash.razor"));
Check(source.Contains("Cobros registrados por medio de pago") && source.Contains("RegisteredTotal") && source.Contains("paymentSummary.Rows") && source.Contains("warning.Count") && source.Contains("warning.Message"), "UI six rows total and warning reason/count from typed service result");
Check(source.Contains("canceladas") && source.Contains("ventas completadas") && source.Contains("efectivo disponible"), "UI distinguishes receipts, completed sales and available cash");
Check(!source.Contains(".Payments") && !source.Contains("ReceivedAmount") && !source.Contains(".Sum("), "UI owns no payment arithmetic or tender inputs");
Console.WriteLine($"{checks} checks, {failures} failures; fixture: {Directory.GetCurrentDirectory()}");
return failures == 0 ? 0 : 1;
sealed class TestNavigation : NavigationManager
{
    public TestNavigation() { Initialize("http://localhost/", "http://localhost/"); }
    protected override void NavigateToCore(string uri, bool forceLoad) { if (forceLoad) throw new InvalidOperationException("forced reload"); }
}
'@ | Set-Content (Join-Path $ScratchPath 'Program.cs') -Encoding utf8
$exitCode = 1
Push-Location $ScratchPath
try {
    & dotnet run --project (Join-Path $ScratchPath 'PaymentChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object data.json GastroApp.csproj)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live data.json or GastroApp.csproj changed.' }
    Write-Host "Live data.json/csproj unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Payment checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
