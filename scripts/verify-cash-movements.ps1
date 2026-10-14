param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-cash-' + [guid]::NewGuid().ToString('N')) }
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
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>$framework</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><ProjectReference Include="$reference" /><FrameworkReference Include="Microsoft.AspNetCore.App" /></ItemGroup>
</Project>
"@ | Set-Content (Join-Path $ScratchPath 'CashChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Globalization;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var command = typeof(CashRegisterService).GetMethod("AddManualMovement");
var query = typeof(CashRegisterService).GetMethod("GetCurrentMovements");
Check(command != null, "manual movement command exists");
Check(query != null, "current-session snapshot query exists");
if (command == null || query == null) { Console.WriteLine($"{checks} checks, {failures} failures"); return 1; }
var storage = new DataStorageService(); // Process cwd is ALWAYS the newly allocated temp directory.
var sales = new SaleService(storage);
var cash = new CashRegisterService(storage, sales);
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 11, Username = "second-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var admin = storage.Users[0];
User Copy(User user) => new() { Id = user.Id, Username = user.Username, PasswordHash = user.PasswordHash, Role = user.Role };
DailySummary CloseWith(CashRegisterService service, decimal amount, User actor)
{
    var review = service.GetCountReview();
    return service.Close(new CashCountRequest { Review = review,
        Lines = amount > 0m ? new[] { new CashCountLineInput(amount, 1) } : Array.Empty<CashCountLineInput>(),
        Reason = amount != review.ExpectedAmount ? "fixture" : null, Confirmed = true, ZeroCountConfirmed = amount == 0m },
        new User { Id = actor.Id, Username = actor.Username, PasswordHash = actor.PasswordHash, Role = actor.Role });
}
void Add(CashMovementType type, decimal amount, string? reason, User? actor) => AddTo(cash, type, amount, reason, actor);
void AddTo(CashRegisterService target, CashMovementType type, decimal amount, string? reason, User? actor)
{
    try { command.Invoke(target, [type, amount, reason, actor]); }
    catch (TargetInvocationException ex) when (ex.InnerException != null) { System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(ex.InnerException).Throw(); }
}
IReadOnlyList<CashMovement> Movements() => (IReadOnlyList<CashMovement>)query.Invoke(cash, null)!;
string State() => JsonSerializer.Serialize(new { storage.CurrentCashRegisterId, storage.CashRegisters, storage.CashMovements,
    storage.Sales, storage.Users, storage.Summaries, storage.Products, storage.ProductCategories,
    storage.Ingredients, storage.Suppliers, storage.Invoices, storage.Recipes,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
void Reject(Action action, Type exception, string name)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    var rows = storage.CashMovements.ToArray(); var registers = storage.CashRegisters.ToArray();
    bool rejected = false;
    try { action(); } catch (Exception ex) { rejected = ex.GetType() == exception; }
    Check(rejected, name + " rejected with " + exception.Name);
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")) && rows.SequenceEqual(storage.CashMovements)
        && registers.SequenceEqual(storage.CashRegisters), name + " leaves objects, collections, counters and fixture bytes unchanged");
}
void Invalid(CashMovementType type, decimal amount, string? reason, string name) => Reject(() => Add(type, amount, reason, admin), typeof(InvalidOperationException), name);
Invalid(CashMovementType.Income, 1m, "test", "no session");
Check(Movements().Count == 0, "no session has empty projection");
cash.Open(100.25m);
foreach (var (type, amount, reason, name) in new (CashMovementType, decimal, string?, string)[] {
    (CashMovementType.Sale, 1m, "test", "automatic Sale forbidden"), ((CashMovementType)99, 1m, "test", "undefined type"),
    (CashMovementType.Income, 0m, "test", "zero"), (CashMovementType.Income, -1m, "test", "negative"),
    (CashMovementType.Withdrawal, decimal.MinValue, "test", "minimum decimal is not positive"),
    (CashMovementType.Income, 1m, null, "null reason"), (CashMovementType.Expense, 1m, "", "empty reason"),
    (CashMovementType.Withdrawal, 1m, " \t\n ", "blank reason"), (CashMovementType.Expense, 100.26m, "test", "insufficient expense"),
    (CashMovementType.Withdrawal, 100.26m, "test", "insufficient withdrawal") }) Invalid(type, amount, reason, name);
foreach (var (actor, name) in new (User?, string)[] { (null, "null actor"), (storage.Users[2], "employee"),
    (new User { Id = 99, Username = admin.Username, PasswordHash = hash, Role = UserRole.Admin }, "unknown actor"),
    (new User { Id = admin.Id, Username = "other", PasswordHash = hash, Role = UserRole.Admin }, "mismatched username"),
    (new User { Id = admin.Id, Username = admin.Username, PasswordHash = "old-hash", Role = UserRole.Admin }, "mismatched password") })
    Reject(() => Add(CashMovementType.Income, 1m, "test", actor), typeof(UnauthorizedAccessException), name);
var stale = Copy(admin);
admin.Role = UserRole.Employee;
Reject(() => Add(CashMovementType.Income, 1m, "test", stale), typeof(UnauthorizedAccessException), "live demotion");
admin.Role = UserRole.Admin;
admin.Username = "renamed";
Reject(() => Add(CashMovementType.Income, 1m, "test", stale), typeof(UnauthorizedAccessException), "stale rename");
admin.Username = stale.Username;
admin.PasswordHash = "changed";
Reject(() => Add(CashMovementType.Income, 1m, "test", stale), typeof(UnauthorizedAccessException), "stale password");
admin.PasswordHash = hash;
storage.Users.Remove(admin);
Reject(() => Add(CashMovementType.Income, 1m, "test", stale), typeof(UnauthorizedAccessException), "deleted actor");
storage.Users.Insert(0, admin);
var beforeDate = DateTime.Now;
Add(CashMovementType.Income, 20.125m, "  aporte inicial  ", Copy(admin));
var income = storage.CashMovements.Single();
Check(income.Id == 1 && income.Date >= beforeDate && income.Date <= DateTime.Now && income.CashRegisterId == cash.GetCurrent()!.Id
    && income.UserId == admin.Id && income.Username == admin.Username && income.Reason == "aporte inicial" && income.SaleId == null, "server ID/date/session/canonical attribution and trimmed reason");
Check(cash.GetExpectedCash(income.CashRegisterId) == 120.375m && cash.GetCashInflow(income.CashRegisterId) == 20.125m, "income sign and exact decimal precision");
var history = JsonSerializer.Serialize(income);
Add(CashMovementType.Expense, 20.125m, "gasto", admin);
Check(cash.GetExpectedCash(income.CashRegisterId) == 100.25m, "expense sign");
Add(CashMovementType.Withdrawal, 100.25m, "retiro total", storage.Users[1]);
Check(cash.GetExpectedCash(income.CashRegisterId) == 0m && storage.CashMovements.Last().UserId == 11, "withdrawal exact cash cap and second actor");
Check(JsonSerializer.Serialize(income) == history && storage.CashMovements.Count == 3 && storage.CashMovements.Select(m => m.Id).SequenceEqual(new[] { 1, 2, 3 }), "append once with sequential IDs and previous row unchanged");
var projection = Movements();
Check(projection.Count == 3 && projection.All(m => !storage.CashMovements.Contains(m)), "projection copies every row");
projection[0].Amount = 999m; projection[0].Reason = "modified";
Check(JsonSerializer.Serialize(income) == history && Movements()[0].Amount == 20.125m, "mutating snapshot never changes ledger");
Check(projection is not ICollection<CashMovement> collection || collection.IsReadOnly, "projection collection is read-only");
var closed = CloseWith(cash, 0m, admin);
Check(closed.Difference == 0m && Movements().Count == 3, "closed current session can still be read");
Invalid(CashMovementType.Income, 1m, "test", "closed session");
cash.Open(1m);
Check(Movements().Count == 0, "new session projection excludes prior movements");
Add(CashMovementType.Income, 2m, "new session", admin);
Check(cash.GetExpectedCash(cash.GetCurrent()!.Id) == 3m && cash.GetExpectedCash(income.CashRegisterId) == 0m, "session formula isolation");
var current = cash.GetCurrent()!;
current.InitialAmount = decimal.MaxValue - 2m;
Invalid(CashMovementType.Income, 1m, "test", "expected balance overflow");
current.InitialAmount = 0m;
storage.CashMovements.RemoveAll(m => m.CashRegisterId == current.Id);
storage.CashMovements.Add(new CashMovement { Id = 50, CashRegisterId = current.Id, Type = CashMovementType.Income, Amount = decimal.MaxValue });
storage.CashMovements.Add(new CashMovement { Id = 51, CashRegisterId = current.Id, Type = CashMovementType.Withdrawal, Amount = decimal.MaxValue });
Invalid(CashMovementType.Income, 1m, "test", "gross inflow overflow with zero expected cash");
storage.CashMovements.RemoveAll(m => m.CashRegisterId == current.Id);
Add(CashMovementType.Income, decimal.MaxValue, "maximum decimal", admin);
Check(cash.GetExpectedCash(current.Id) == decimal.MaxValue && cash.GetCashInflow(current.Id) == decimal.MaxValue, "maximum representable expected and gross cash accepted");
Add(CashMovementType.Expense, decimal.MaxValue, "exact expense cap", admin);
Check(cash.GetExpectedCash(current.Id) == 0m, "expense at exact maximum available cash accepted");
storage.CashMovements.RemoveAll(m => m.CashRegisterId == current.Id);
current.InitialAmount = 10m;
var counter = typeof(DataStorageService).GetField("_nextCashMovementId", flags)!;
var savedCounter = counter.GetValue(storage);
foreach (var value in new[] { int.MaxValue, 0, -1 }) { counter.SetValue(storage, value); Invalid(CashMovementType.Income, 1m, "test", "counter " + value); }
counter.SetValue(storage, savedCounter);
// Mixed tender, noncash and zero totals retain their original movement semantics.
var product = storage.Products.First();
Sale Checkout(decimal price, params SalePayment[] payments) => new() { Items = [new SaleItem { ProductId = product.Id, ProductName = product.Name, Price = price, Quantity = 1 }], Payments = payments.ToList() };
var mixed = Checkout(30m, new() { PaymentMethod = PaymentMethod.Cash, Amount = 10m, ReceivedAmount = 100m }, new() { PaymentMethod = PaymentMethod.DebitCard, Amount = 20m });
var saleCount = storage.CashMovements.Count;
sales.Add(mixed);
Check(storage.CashMovements.Count == saleCount + 1 && storage.CashMovements.Last().Amount == 10m && storage.CashMovements.Last().SaleId == mixed.Id
    && cash.GetExpectedCash(current.Id) == 20m && mixed.Payments[0].Change == 90m, "mixed sale counts applied cash not tender/change");
Check(Movements().Last().Type == CashMovementType.Sale && Movements().Last().UserId == null && Movements().Last().Reason == null, "automatic Sale included with legacy nullable audit");
sales.Add(Checkout(5m, new SalePayment { PaymentMethod = PaymentMethod.Transfer, Amount = 5m }));
sales.Add(Checkout(0m));
Check(storage.CashMovements.Count == saleCount + 1 && storage.Sales.All(s => s.CashRegisterId == current.Id), "noncash and zero sale session links without movements");
sales.Cancel(mixed.Id, "fixture", admin);
Check(cash.GetExpectedCash(current.Id) == 20m && storage.CashMovements.Count == saleCount + 1 && mixed.Status == SaleStatus.Cancelled, "cancellation never reverses money");
Add(CashMovementType.Expense, 3m, "gasto", admin);
var summary = CloseWith(cash, 16m, admin);
Check(summary.Difference == -1m && current.ExpectedAmount == 17m, "close difference includes manual and automatic movements");
// Reload preserves nullable legacy fields, attribution and ID recovery.
var persisted = JsonSerializer.Serialize(storage.CashMovements);
var reload = new DataStorageService();
Check(JsonSerializer.Serialize(reload.CashMovements) == persisted, "save/reload ledger audit and exact decimals");
var reloadedCash = new CashRegisterService(reload, new SaleService(reload));
reloadedCash.Open(0m);
AddTo(reloadedCash, CashMovementType.Income, 1m, "reload", reload.Users[0]);
Check(reload.CashMovements.Last().Id == storage.CashMovements.Max(m => m.Id) + 1 && reload.CashMovements.Last().UserId == 10, "save/reload next ID and actor");
var json = JsonNode.Parse(File.ReadAllText("data.json"))!.AsObject();
json.Remove("CashRegisters"); json.Remove("CurrentCashRegisterId"); json.Remove("NextCashRegisterId"); json.Remove("NextCashMovementId"); json.Remove("CashMovements"); json.Remove("CashCounts");
json["CurrentCashRegister"] = JsonSerializer.SerializeToNode(new CashRegister { Id = 0, InitialAmount = 4m, IsOpen = true, OpenDate = DateTime.Now });
File.WriteAllText("data.json", json.ToJsonString());
var legacy = new DataStorageService();
var legacyCash = new CashRegisterService(legacy, new SaleService(legacy));
AddTo(legacyCash, CashMovementType.Income, 2m, "legacy", legacy.Users[0]);
Check(legacy.CurrentCashRegister!.Id == 1 && legacy.CashMovements.Single().Id == 1 && legacyCash.GetExpectedCash(1) == 6m, "legacy single-register JSON supports manual command without inferred movements");
// Invoke real UI callbacks without a renderer; assertion observes authorization and mutation, not browser appearance.
var users = new UserService(legacy);
var a = new AuthService(users); var b = new AuthService(users);
a.Login("fixture-admin", "fixture-pass"); b.Login("second-admin", "fixture-pass");
var pageType = typeof(GastroApp.Pages.Cash);
var action = pageType.GetMethod("RecordMovement", flags);
Check(action != null, "manual UI action exists");
if (action != null)
{
    object Page(AuthService auth, TestNavigation nav, string amount = "1")
    {
        var page = Activator.CreateInstance(pageType)!;
        pageType.GetProperty("AuthService", flags)!.SetValue(page, auth);
        pageType.GetProperty("Navigation", flags)!.SetValue(page, nav);
        pageType.GetProperty("CashService", flags)!.SetValue(page, legacyCash);
        pageType.GetField("movementAmount", flags)!.SetValue(page, amount);
        pageType.GetField("movementReason", flags)!.SetValue(page, "  UI fixture  ");
        return page;
    }
    void Click(object page) => action.Invoke(page, null);
    var nav = new TestNavigation();
    var firstPage = Page(a, nav); var secondPage = Page(b, new TestNavigation());
    Click(firstPage); Click(secondPage);
    Check(legacy.CashMovements.TakeLast(2).Select(m => m.UserId).SequenceEqual(new int?[] { 10, 11 }), "two UI circuits attribute fresh actor independently");
    Check(pageType.GetField("movementMessage", flags)!.GetValue(firstPage) is string message && message.Length > 0
        && ReferenceEquals(pageType.GetField("cashRegister", flags)!.GetValue(firstPage), legacy.CurrentCashRegister), "UI success confirmation and immediate current session refresh");
    var count = legacy.CashMovements.Count;
    foreach (var raw in new[] { "", "bad", "999999999999999999999999999999999", "-1", "0" }) Click(Page(a, nav, raw));
    Check(legacy.CashMovements.Count == count, "UI invalid raw amount never submits old decimal");
    var blankReasonPage = Page(a, nav);
    pageType.GetField("movementReason", flags)!.SetValue(blankReasonPage, "   ");
    Click(blankReasonPage);
    Check(legacy.CashMovements.Count == count && pageType.GetField("cashError", flags)!.GetValue(blankReasonPage) is string reasonError && reasonError.Length > 0,
        "UI blank reason reports service validation without mutation");
    var closedPage = Page(a, nav);
    CloseWith(legacyCash, legacyCash.GetExpectedCash(legacy.CurrentCashRegister!.Id), legacy.Users[0]);
    Click(closedPage);
    Check(legacy.CashMovements.Count == count && pageType.GetField("cashError", flags)!.GetValue(closedPage) is string sessionError && sessionError.Length > 0,
        "UI click after session closes reports error without mutation");
    legacyCash.Open(0m);
    legacy.Users[0].Role = UserRole.Employee; Click(Page(a, nav));
    Check(nav.Destination == "/unauthorized" && legacy.CashMovements.Count == count, "UI action-time demotion denies mutation");
    legacy.Users[0].Role = UserRole.Admin;
    legacy.Users[0].PasswordHash = "changed"; Click(Page(a, nav));
    Check(nav.Destination == "/login" && legacy.CashMovements.Count == count && b.IsAuthenticated, "UI password invalidation and other circuit isolation");
    legacy.Users[0].PasswordHash = hash; a.Login("fixture-admin", "fixture-pass");
    legacy.Users[0].Username = "renamed"; Click(Page(a, nav));
    Check(nav.Destination == "/login" && legacy.CashMovements.Count == count, "UI username invalidation denies mutation");
}
var source = File.ReadAllText(Path.Combine(args[0], "Pages", "Cash.razor"));
Check(source.Contains("GetCurrentMovements") && source.Contains("Venta") && source.Contains("Sin responsable registrado") && source.Contains("Sin motivo registrado"), "UI current-session Sale and nullable legacy audit fallbacks");
Check(!System.Text.RegularExpressions.Regex.IsMatch(source, @"NavigateTo\([^;]*,\s*true\)"), "cash navigation never forces reload");
Console.WriteLine($"{checks} checks, {failures} failures; fixture: {Directory.GetCurrentDirectory()}");
return failures == 0 ? 0 : 1;

sealed class TestNavigation : NavigationManager
{
    public string? Destination { get; private set; }
    public TestNavigation() { Initialize("http://localhost/", "http://localhost/"); }
    protected override void NavigateToCore(string uri, bool forceLoad) { if (forceLoad) throw new InvalidOperationException("forced reload"); Destination = uri; }
}
'@ | Set-Content (Join-Path $ScratchPath 'Program.cs') -Encoding utf8
$exitCode = 1
Push-Location $ScratchPath
try {
    & dotnet run --project (Join-Path $ScratchPath 'CashChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Cash checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
