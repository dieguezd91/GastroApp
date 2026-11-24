param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-stockcount-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'StockCountChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using System.Collections;
using System.Globalization;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
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
storage.Ingredients = []; storage.Recipes = []; storage.Invoices = []; storage.Suppliers = [];
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
invoices.SetIngredientService(ingredients);
var counts = new StockCountService(storage, ingredients);

Ingredient NewIngredient(string name, string unit, decimal stock, decimal min, bool active = true)
{
    // New ingredients are created without stock; a fixture with stock models data stored before that rule:
    // the ingredient plus a legacy InitialStock movement written straight into the ledger.
    var i = new Ingredient { Name = name, Unit = unit, MinStock = min, IsActive = active };
    ingredients.Add(i, Copy(admin));
    if (stock != 0m)
    {
        i.CurrentStock = stock;
        storage.StockMovements.Add(new StockMovement { Id = storage.GetNextStockMovementId(), IngredientId = i.Id, Date = DateTime.Now, Type = StockMovementType.InitialStock, Quantity = stock, Unit = unit,
            PreviousStock = 0m, ResultingStock = stock, UserId = admin.Id, Username = admin.Username });
        storage.SaveToFile();
    }
    return i;
}
var harina = NewIngredient("Harina", "kg", 10m, 2m);
var huevos = NewIngredient("Huevos", "unidad", 30m, 12m);
var sal = NewIngredient("Sal", "kg", 0m, 5m);
var azucar = NewIngredient("Azucar", "kg", 5m, 0m, active: false);
var legado = NewIngredient("Legado", "kg", 0m, 0m);
legado.CurrentStock = -2m; // legacy negative balance (S10)

StockCountLineInput L(Ingredient i, decimal? counted, string? reason = null) => new() { IngredientId = i.Id, CountedStock = counted, ExpectedStock = i.CurrentStock, Reason = reason };
StockCountLineInput LE(Ingredient i, decimal? counted, decimal? expected, string? reason = null) => new() { IngredientId = i.Id, CountedStock = counted, ExpectedStock = expected, Reason = reason };
StockCountRequest Req(bool confirmed, params StockCountLineInput[] lines) => new() { Lines = lines.ToList(), Confirmed = confirmed };
string State() => JsonSerializer.Serialize(new { storage.StockCounts, storage.StockMovements, storage.Ingredients, storage.Users, storage.Sales, storage.SaleRefunds,
    storage.Invoices, storage.Recipes, storage.CashRegisters, storage.CashMovements,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
void Reject(Action action, Type exception, string name, string? contains = null)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    bool rejected = false; string message = "";
    try { action(); } catch (Exception ex) { rejected = ex.GetType() == exception && (contains == null || ex.Message.Contains(contains)); message = ex.Message; }
    Check(rejected, name + " rejected with " + exception.Name + (contains == null ? "" : " / " + contains) + (rejected ? "" : " [" + message + "]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")), name + " leaves counts, ledger, stock, counters and fixture bytes unchanged");
}
void Invalid(Action action, string name, string? contains = null) => Reject(action, typeof(InvalidOperationException), name, contains);
void Denied(Action action, string name) => Reject(action, typeof(UnauthorizedAccessException), name, "administrador");
const string Stale = "El stock cambi\u00f3 desde que se inici\u00f3 el conteo; vuelva a calcular.";

// ---- API surface and Spanish labels ----
Check(storage.StockCounts.Count == 0 && counts.GetHistory().Count == 0 && counts.GetDetail(1) == null, "fresh store has no counts");
Check(StockCountLabels.GetLabel(-0.5m) == "Faltante" && StockCountLabels.GetLabel(0.5m) == "Sobrante" && StockCountLabels.GetLabel(0m) == "Sin diferencia"
    && StockCountLabels.GetKind(-1m) == StockCountDifferenceKind.Shortage && StockCountLabels.GetKind(1m) == StockCountDifferenceKind.Surplus && StockCountLabels.GetKind(0m) == StockCountDifferenceKind.Match, "difference labels use words (S4)");

// ---- Preview (S4): expected vs counted, no mutation ----
storage.SaveToFile();
var s0 = State(); var b0 = File.ReadAllBytes("data.json"); var w0 = File.GetLastWriteTimeUtc("data.json");
var pv = counts.Preview([L(harina, 9.5m), L(huevos, 30m), L(sal, 3m), L(legado, 0m)]);
Check(pv.Lines.Count == 4 && pv.AdjustedLineCount == 3 && pv.Lines.Select(l => l.IngredientId).SequenceEqual(new[] { harina.Id, huevos.Id, sal.Id, legado.Id }), "preview keeps the requested order and counts the lines with difference");
Check(pv.Lines[0] is { IngredientName: "Harina", Unit: "kg", ExpectedStock: 10m, CountedStock: 9.5m, Difference: -0.5m, Kind: StockCountDifferenceKind.Shortage, HasNegativeStock: false }
    && pv.Lines[1] is { ExpectedStock: 30m, CountedStock: 30m, Difference: 0m, Kind: StockCountDifferenceKind.Match }
    && pv.Lines[2] is { ExpectedStock: 0m, CountedStock: 3m, Difference: 3m, Kind: StockCountDifferenceKind.Surplus }
    && pv.Lines[3] is { ExpectedStock: -2m, CountedStock: 0m, Difference: 2m, HasNegativeStock: true }, "preview shows registered, counted, difference, kind and the negative balance warning");
_ = counts.Preview([L(azucar, 5m)]); _ = counts.GetHistory(); _ = counts.GetDetail(1);
Check(State() == s0 && b0.SequenceEqual(File.ReadAllBytes("data.json")) && File.GetLastWriteTimeUtc("data.json") == w0 && storage.StockCounts.Count == 0, "preview and queries leave state, counters and data.json bytes/timestamp unchanged");
Invalid(() => counts.Preview(null!), "null preview", "al menos");
Invalid(() => counts.Preview([]), "empty preview", "al menos");
Invalid(() => counts.Preview([L(harina, -1m)]), "negative counted in preview", "negativo");
Invalid(() => counts.Preview([L(harina, null)]), "missing counted in preview", "stock contado");
Invalid(() => counts.Preview([L(harina, 1m), L(harina, 2m)]), "repeated ingredient in preview", "repetir");
Invalid(() => counts.Preview([L(harina, 1m), new StockCountLineInput { IngredientId = 99999, CountedStock = 1m }]), "unknown ingredient in preview", "no existe");
Invalid(() => counts.Preview([null!]), "null line in preview", "inv\u00e1lida");

// ---- Confirm: rejections leave everything unchanged ----
var good = () => Req(true, L(harina, 9m, "recuento"));
Denied(() => counts.Confirm(good(), null), "confirm with null actor");
Denied(() => counts.Confirm(good(), employee), "confirm by employee");
Denied(() => counts.Confirm(good(), new User { Id = 10, Username = "fixture-admin", PasswordHash = "old", Role = UserRole.Admin }), "confirm with stale password");
var staleAdmin = Copy(admin); admin.Role = UserRole.Employee;
Denied(() => counts.Confirm(good(), staleAdmin), "confirm by a demoted admin"); admin.Role = UserRole.Admin;
Invalid(() => counts.Confirm(null!, admin), "null request", "al menos");
Invalid(() => counts.Confirm(Req(true), admin), "no lines", "al menos");
Invalid(() => counts.Confirm(new StockCountRequest { Lines = null!, Confirmed = true }, admin), "null lines", "al menos");
Invalid(() => counts.Confirm(Req(false, L(harina, 9m, "x")), admin), "unconfirmed count", "confirmar");
Invalid(() => counts.Confirm(Req(true, L(harina, -1m, "x")), admin), "negative counted stock (S10)", "negativo");
Invalid(() => counts.Confirm(Req(true, L(harina, 9m, null)), admin), "difference without reason", "motivo");
Invalid(() => counts.Confirm(Req(true, L(harina, 9m, "  ")), admin), "difference with blank reason", "motivo");
Invalid(() => counts.Confirm(Req(true, L(huevos, 31m, "ok"), L(harina, 9m, "\t")), admin), "one line without reason rejects the whole count", "motivo");
Invalid(() => counts.Confirm(Req(true, L(harina, null, "x")), admin), "missing counted stock", "stock contado");
Invalid(() => counts.Confirm(Req(true, LE(harina, 9m, null, "x")), admin), "missing registered stock (not compared)", "comparar");
Invalid(() => counts.Confirm(Req(true, LE(harina, 9m, 11m, "x")), admin), "stale registered stock", Stale);
Invalid(() => counts.Confirm(Req(true, L(harina, 9m, "x"), L(harina, 8m, "x")), admin), "repeated ingredient", "repetir");
Invalid(() => counts.Confirm(Req(true, L(harina, 9m, "x"), new StockCountLineInput { IngredientId = 99999, CountedStock = 1m, ExpectedStock = 0m, Reason = "x" }), admin), "unknown ingredient", "no existe");
Invalid(() => counts.Confirm(Req(true, new StockCountLineInput[] { null! }), admin), "null line", "inv\u00e1lida");
Invalid(() => counts.Confirm(Req(true, L(legado, decimal.MaxValue, "x")), admin), "difference overflow", "l\u00edmite");
var countCounter = typeof(DataStorageService).GetField("_nextStockCountId", flags);
Check(countCounter != null, "count id counter exists");
var savedCountCounter = countCounter?.GetValue(storage);
foreach (var bad in new[] { int.MaxValue, 0, -1 }) { countCounter?.SetValue(storage, bad); Invalid(() => counts.Confirm(good(), admin), "confirm with count counter " + bad, "identificadores"); }
countCounter?.SetValue(storage, savedCountCounter);
var ledgerCounter = typeof(DataStorageService).GetField("_nextStockMovementId", flags)!; var savedLedgerCounter = ledgerCounter.GetValue(storage);
ledgerCounter.SetValue(storage, int.MaxValue);
Invalid(() => counts.Confirm(good(), admin), "ledger exhausted: no count record and no counter change is left behind", "identificadores");
ledgerCounter.SetValue(storage, savedLedgerCounter);
Check(storage.StockCounts.Count == 0 && harina.CurrentStock == 10m, "nothing was created by the rejected confirmations");

// ---- Confirm: count record plus CountAdjustment movements ----
var ledgerBefore = storage.StockMovements.Count; var tConfirm = DateTime.Now;
var c1 = counts.Confirm(new StockCountRequest { Confirmed = true, Notes = "  cierre de mes  ", Lines = [
    L(harina, 9.5m, "  conteo mensual "), L(huevos, 30m, "no deberia guardarse"), L(sal, 3m, "carga pendiente")] }, Copy(admin));
Check(c1.Id == 1 && c1.Date >= tConfirm && c1.Date <= DateTime.Now && c1.UserId == 10 && c1.Username == "fixture-admin" && c1.Notes == "cierre de mes" && c1.Lines.Count == 3 && c1.AdjustedLineCount == 2, "count record: id, date, responsible, trimmed notes and adjusted lines");
Check(c1.Lines[0] is { IngredientName: "Harina", Unit: "kg", ExpectedStock: 10m, CountedStock: 9.5m, Difference: -0.5m, Reason: "conteo mensual" } && c1.Lines[0].IngredientId == harina.Id
    && c1.Lines[1] is { IngredientName: "Huevos", Unit: "unidad", ExpectedStock: 30m, CountedStock: 30m, Difference: 0m, Reason: null }
    && c1.Lines[2] is { IngredientName: "Sal", ExpectedStock: 0m, CountedStock: 3m, Difference: 3m, Reason: "carga pendiente" }, "count lines snapshot name, unit, registered, counted, difference and reason (none for a matching line)");
var m1 = storage.StockMovements.Where(m => m.StockCountId == c1.Id).OrderBy(m => m.Id).ToList();
Check(m1.Count == 2 && storage.StockMovements.Count == ledgerBefore + 2 && m1.All(m => m.Type == StockMovementType.CountAdjustment && m.UserId == 10 && m.Username == "fixture-admin" && m.SaleId == null && m.InvoiceId == null && m.RefundId == null)
    && m1[0] is { Quantity: -0.5m, PreviousStock: 10m, ResultingStock: 9.5m, Unit: "kg", Reason: "conteo mensual" } && m1[0].IngredientId == harina.Id
    && m1[1] is { Quantity: 3m, PreviousStock: 0m, ResultingStock: 3m, Reason: "carga pendiente" } && m1[1].IngredientId == sal.Id, "movements carry the count id, previous and resulting stock, reason and responsible");
Check(!storage.StockMovements.Any(m => m.StockCountId == c1.Id && m.IngredientId == huevos.Id) && harina.CurrentStock == 9.5m && huevos.CurrentStock == 30m && sal.CurrentStock == 3m, "a line without difference creates no movement and stock is applied");
Check(storage.StockCounts.Count == 1 && JsonSerializer.Serialize(storage.StockCounts[0]) == JsonSerializer.Serialize(c1), "the count is stored in DataStorageService");
c1.Lines[0].Reason = "tampered"; c1.Notes = "tampered"; c1.Lines.Clear();
Check(storage.StockCounts[0].Lines.Count == 3 && storage.StockCounts[0].Lines[0].Reason == "conteo mensual" && storage.StockCounts[0].Notes == "cierre de mes", "Confirm returns a detached copy");

var c2 = counts.Confirm(Req(true, L(harina, 9.5m), L(huevos, 30m, "  ")), admin2);
Check(c2.Id == 2 && c2.AdjustedLineCount == 0 && c2.UserId == 11 && c2.Notes == null && c2.Lines.All(l => l.Difference == 0m && l.Reason == null) && storage.StockMovements.Count == ledgerBefore + 2 && storage.StockCounts.Count == 2,
    "a count without differences is recorded (blank reason accepted) and creates no movement");
var disk = new DataStorageService();
Check(disk.StockCounts.Count == 2 && JsonSerializer.Serialize(disk.StockCounts) == JsonSerializer.Serialize(storage.StockCounts), "the zero-difference count is saved to disk");

// Simultaneous change (doc 10.6): the operator previewed, someone else moved the stock, confirm must ask for a recount.
var pending = Req(true, L(harina, 9m, "recuento"));
ingredients.AdjustStock(harina.Id, 8m, "ajuste concurrente", admin2);
Invalid(() => counts.Confirm(pending, admin), "stock changed after the preview", Stale);
var recount = counts.Preview([L(harina, 9m)]);
Check(recount.Lines[0] is { ExpectedStock: 8m, Difference: 1m }, "recounting after a stale rejection compares against the new registered stock");
var c3 = counts.Confirm(Req(true, L(harina, 9m, "recuento")), admin);
Check(c3.Id == 3 && c3.Lines[0] is { ExpectedStock: 8m, CountedStock: 9m, Difference: 1m } && storage.StockMovements.Last() is { Type: StockMovementType.CountAdjustment, StockCountId: 3, PreviousStock: 8m, ResultingStock: 9m, Quantity: 1m }, "the recount is confirmed against the current stock");

// Existing negative balance (S10): a count repairs it; it is never made negative by counting.
var c4 = counts.Confirm(Req(true, L(legado, 0m, "regularizacion"), L(azucar, 4m, "merma no registrada")), admin);
Check(c4.Id == 4 && legado.CurrentStock == 0m && azucar.CurrentStock == 4m && storage.StockMovements.Where(m => m.StockCountId == 4).OrderBy(m => m.Id).First() is { Quantity: 2m, PreviousStock: -2m, ResultingStock: 0m }
    && c4.Lines.Any(l => l.IngredientName == "Azucar" && l.Difference == -1m), "a count repairs a legacy negative balance and can include inactive ingredients");
var zeroOut = counts.Confirm(Req(true, L(harina, 0m, "estante vacio")), admin);
Check(harina.CurrentStock == 0m && zeroOut.Lines[0].CountedStock == 0m, "counting zero is allowed");

// ---- History / detail ----
storage.SaveToFile();
var s1 = State(); var b1 = File.ReadAllBytes("data.json");
var hist = counts.GetHistory();
Check(hist.Select(c => c.Id).SequenceEqual(new[] { 5, 4, 3, 2, 1 }) && hist[4].Lines.Count == 3 && counts.GetDetail(1)!.Lines[2].IngredientName == "Sal" && counts.GetDetail(99) == null && counts.GetDetail(0) == null && counts.GetDetail(-1) == null,
    "history is newest first and detail resolves by id");
hist[0].Lines.Clear(); hist[0].Notes = "tampered"; counts.GetDetail(1)!.Lines[0].Reason = "tampered"; counts.GetDetail(1)!.Lines.Clear();
Check(State() == s1 && b1.SequenceEqual(File.ReadAllBytes("data.json")), "history and detail are detached copies and never mutate");

// ---- Persistence ----
var reload = new DataStorageService();
Check(JsonSerializer.Serialize(reload.StockCounts) == JsonSerializer.Serialize(storage.StockCounts) && JsonSerializer.Serialize(reload.StockMovements) == JsonSerializer.Serialize(storage.StockMovements), "save/reload keeps counts and ledger identical");
var reloadIngredients = new IngredientService(reload, new InvoiceService(reload));
var reloadCounts = new StockCountService(reload, reloadIngredients);
var next = reloadCounts.Confirm(Req(true, new StockCountLineInput { IngredientId = huevos.Id, CountedStock = 31m, ExpectedStock = 30m, Reason = "tras reinicio" }), reload.Users[0]);
Check(next.Id == 6 && reload.StockMovements.Last().StockCountId == 6, "reload recovers the count id counter");
storage.SaveToFile();
var savedJson = File.ReadAllText("data.json");
int dirs = 0;
DataStorageService LoadFrom(JsonObject json, out byte[] bytes)
{
    var dir = Path.Combine(root, "load-" + (++dirs)); Directory.CreateDirectory(dir);
    var file = Path.Combine(dir, "data.json");
    File.WriteAllText(file, json.ToJsonString());
    bytes = File.ReadAllBytes(file);
    Directory.SetCurrentDirectory(dir);
    try { return new DataStorageService(); } finally { Directory.SetCurrentDirectory(root); }
}
JsonObject Fresh() => JsonNode.Parse(savedJson)!.AsObject();
var legacyJson = Fresh(); legacyJson.Remove("StockCounts"); legacyJson.Remove("NextStockCountId");
var legacy = LoadFrom(legacyJson, out var legacyBytes);
Check(legacy.StockCounts.Count == 0 && legacy.StockMovements.Count == storage.StockMovements.Count && legacy.Ingredients.Count == storage.Ingredients.Count, "legacy JSON without StockCounts loads with an empty list and keeps the ledger");
Check(File.ReadAllBytes(Path.Combine(root, "load-" + dirs, "data.json")).SequenceEqual(legacyBytes), "loading never writes data.json");
var legacyCounts = new StockCountService(legacy, new IngredientService(legacy, new InvoiceService(legacy)));
var firstLegacy = legacyCounts.Confirm(Req(true, new StockCountLineInput { IngredientId = huevos.Id, CountedStock = 29m, ExpectedStock = 30m, Reason = "legacy" }), legacy.Users[0]);
Check(firstLegacy.Id == 6 && legacy.StockMovements.Last().StockCountId == 6, "legacy movements that reference count ids reserve them: the first new count does not reuse an id");
JsonNode CountNode(JsonObject j, int id) => j["StockCounts"]!.AsArray().First(n => n!["Id"]!.GetValue<int>() == id)!;
JsonNode CountMovement(JsonObject j, int countId) => j["StockMovements"]!.AsArray().First(n => n!["StockCountId"] is JsonValue v && v.GetValue<int>() == countId)!;
void BadLoad(string name, Action<JsonObject> mutate)
{
    var json = Fresh(); mutate(json);
    var ok = false;
    try { LoadFrom(json, out _); } catch (InvalidDataException) { ok = true; }
    Check(ok, "corrupt stock count rejected on load: " + name);
}
BadLoad("null list", j => j["StockCounts"] = null);
BadLoad("null entry", j => j["StockCounts"]!.AsArray().Add(null));
BadLoad("duplicate id", j => j["StockCounts"]![1]!["Id"] = j["StockCounts"]![0]!["Id"]!.GetValue<int>());
BadLoad("zero id", j => CountNode(j, 2)["Id"] = 0);
BadLoad("zero counter", j => j["NextStockCountId"] = 0);
BadLoad("user id zero", j => CountNode(j, 1)["UserId"] = 0);
BadLoad("blank username", j => CountNode(j, 1)["Username"] = " ");
BadLoad("null lines", j => CountNode(j, 1)["Lines"] = null);
BadLoad("empty lines", j => CountNode(j, 1)["Lines"] = new JsonArray());
BadLoad("null line", j => CountNode(j, 1)["Lines"]!.AsArray().Add(null));
BadLoad("repeated ingredient", j => CountNode(j, 1)["Lines"]![1]!["IngredientId"] = CountNode(j, 1)["Lines"]![0]!["IngredientId"]!.GetValue<int>());
BadLoad("ingredient id zero", j => CountNode(j, 1)["Lines"]![0]!["IngredientId"] = 0);
BadLoad("blank ingredient name", j => CountNode(j, 1)["Lines"]![0]!["IngredientName"] = "");
BadLoad("blank unit", j => CountNode(j, 1)["Lines"]![0]!["Unit"] = " ");
BadLoad("negative counted stock", j => { var l = CountNode(j, 1)["Lines"]![0]!; l["CountedStock"] = -1; l["Difference"] = -1 - l["ExpectedStock"]!.GetValue<decimal>(); });
BadLoad("difference not matching", j => CountNode(j, 1)["Lines"]![0]!["Difference"] = 7);
BadLoad("difference without reason", j => CountNode(j, 1)["Lines"]![0]!["Reason"] = null);
BadLoad("adjusted count not matching", j => CountNode(j, 1)["AdjustedLineCount"] = 3);
BadLoad("adjusted line without movement", j => { var arr = j["StockMovements"]!.AsArray(); arr.Remove(CountMovement(j, 1)); });
BadLoad("movement of another count", j => CountMovement(j, 1)["StockCountId"] = 777);
BadLoad("movement not matching the line quantity", j => { var n = CountMovement(j, 3); n["Quantity"] = 5; n["ResultingStock"] = n["PreviousStock"]!.GetValue<decimal>() + 5m; });
BadLoad("movement linked to a count without differences", j => CountMovement(j, 1)["StockCountId"] = 2);

// ---- Page /stock/count: renderer-less callbacks ----
storage.SaveToFile();
var uiUsers = new UserService(storage);
AuthService NewAuth(string? username)
{
    var auth = new AuthService(uiUsers);
    if (username != null) Check(auth.Login(username, "fixture-pass"), "circuit login " + username);
    return auth;
}
var pageType = typeof(StockCountService).Assembly.GetType("GastroApp.Pages.StockCount");
Check(pageType != null, "StockCount page type exists");
if (pageType != null)
{
    var rowType = pageType.GetNestedType("CountRow", flags)!;
    (object Page, TestNavigation Nav) NewPage(AuthService auth)
    {
        var page = Activator.CreateInstance(pageType)!; var nav = new TestNavigation();
        pageType.GetProperty("AuthService", flags)!.SetValue(page, auth);
        pageType.GetProperty("Navigation", flags)!.SetValue(page, nav);
        pageType.GetProperty("StockCountService", flags)!.SetValue(page, counts);
        pageType.GetProperty("IngredientService", flags)!.SetValue(page, ingredients);
        return (page, nav);
    }
    Exception? Call(object page, string method, params object[] arguments)
    {
        try { pageType.GetMethod(method, flags | BindingFlags.DeclaredOnly)!.Invoke(page, arguments); return null; }
        catch (TargetInvocationException ex) { return ex.InnerException; }
    }
    object? Get(object page, string field) => pageType.GetField(field, flags)!.GetValue(page);
    void Set(object page, string field, object? value) => pageType.GetField(field, flags)!.SetValue(page, value);
    void SetId(object page, int? id) => pageType.GetProperty("CountId", flags)!.SetValue(page, id);
    string? Msg(object page, string field) => (string?)Get(page, field);
    IList Rows(object page) => (IList)Get(page, "rows")!;
    object RowOf(object page, Ingredient i) => Rows(page).Cast<object>().First(r => (int)rowType.GetProperty("Id")!.GetValue(r)! == i.Id);
    bool Selected(object page, Ingredient i) => (bool)rowType.GetProperty("Selected")!.GetValue(RowOf(page, i))!;
    int SelectedCount(object page) => Rows(page).Cast<object>().Count(r => (bool)rowType.GetProperty("Selected")!.GetValue(r)!);
    void Pick(object page, Ingredient i, string counted) { var r = RowOf(page, i); rowType.GetProperty("Selected")!.SetValue(r, true); rowType.GetProperty("Counted")!.SetValue(r, counted); }
    StockCountPreview? PV(object page) => (StockCountPreview?)Get(page, "preview");
    Dictionary<int, string> Reasons(object page) => (Dictionary<int, string>)Get(page, "reasons")!;
    void Init(object page) { var failure = Call(page, "OnParametersSet"); if (failure != null) Console.WriteLine("init failed: " + failure.Message); }

    // Unauthenticated and Employee circuits fail closed on every entry point.
    var uiState = State(); var uiBytes = File.ReadAllBytes("data.json");
    var uiAnon = NewAuth(null); var uiEmployee = NewAuth("fixture-employee");
    foreach (var (auth, who, destination) in new[] { (uiAnon, "anonymous", "/login"), (uiEmployee, "employee", "/unauthorized") })
        foreach (var action in new[] { "OnParametersSet", "Compare", "Confirm", "SelectAllActive", "SelectVisible", "ClearSelection", "Invalidate", "ShowDetail", "CloseDetail" })
        {
            var (page, pnav) = NewPage(auth);
            SetId(page, 1);
            var failure = Call(page, action, action == "ShowDetail" ? new object[] { 1 } : Array.Empty<object>());
            Check(failure == null && pnav.Destination == destination && Rows(page).Count == 0 && Get(page, "history") == null && Get(page, "detail") == null && PV(page) == null,
                who + " " + action + " navigates to " + destination + " and loads nothing");
        }
    Check(State() == uiState && uiBytes.SequenceEqual(File.ReadAllBytes("data.json")), "unauthorized callbacks do not touch storage");

    // Admin: list, selection helpers.
    var uiAdmin = NewAuth("fixture-admin");
    var (ap, anav) = NewPage(uiAdmin);
    Init(ap);
    Check(anav.Destination == null && Rows(ap).Count == storage.Ingredients.Count && ((IReadOnlyList<StockCount>)Get(ap, "history")!).Count == storage.StockCounts.Count && Get(ap, "detail") == null && SelectedCount(ap) == 0, "admin loads ingredients and the count history without selecting anything");
    Call(ap, "SelectAllActive");
    Check(SelectedCount(ap) == storage.Ingredients.Count(i => i.IsActive) && !Selected(ap, azucar) && Selected(ap, harina), "select all active skips inactive ingredients");
    Call(ap, "ClearSelection");
    Check(SelectedCount(ap) == 0, "clear selection");
    Set(ap, "nameFilter", "har"); Call(ap, "SelectVisible");
    Check(SelectedCount(ap) == 1 && Selected(ap, harina), "filter by name then select visible");
    Call(ap, "ClearSelection"); Set(ap, "nameFilter", ""); Set(ap, "onlyLowStock", true); Call(ap, "SelectVisible");
    var lowIds = storage.Ingredients.Where(i => i.CurrentStock <= i.MinStock).Select(i => i.Id).ToHashSet();
    Check(lowIds.Count > 0 && SelectedCount(ap) == lowIds.Count && Rows(ap).Cast<object>().All(r => (bool)rowType.GetProperty("Selected")!.GetValue(r)! == lowIds.Contains((int)rowType.GetProperty("Id")!.GetValue(r)!)), "only low stock then select visible");
    Call(ap, "ClearSelection"); Set(ap, "onlyLowStock", false);

    // Compare validations: nothing mutates, no preview.
    storage.SaveToFile(); var cmpState = State(); var cmpBytes = File.ReadAllBytes("data.json");
    Check(Call(ap, "Compare") == null && PV(ap) == null && Msg(ap, "errorMessage")!.Contains("Seleccione"), "compare without selection shows an error");
    Pick(ap, harina, "");
    Check(Call(ap, "Compare") == null && PV(ap) == null && Msg(ap, "errorMessage")!.Contains("Harina"), "compare with a blank counted quantity names the ingredient");
    Pick(ap, harina, "abc");
    Check(Call(ap, "Compare") == null && PV(ap) == null && Msg(ap, "errorMessage")!.Contains("Harina"), "compare with a non numeric quantity is rejected");
    Pick(ap, harina, "-1");
    Check(Call(ap, "Compare") == null && PV(ap) == null && Msg(ap, "errorMessage")!.Contains("negativo"), "compare with a negative quantity is rejected (S10)");
    Check(State() == cmpState && cmpBytes.SequenceEqual(File.ReadAllBytes("data.json")), "failed comparisons mutate nothing");

    // Compare / Confirm flow.
    var harinaBefore = harina.CurrentStock; var huevosBefore = huevos.CurrentStock;
    Pick(ap, harina, "2.5"); Pick(ap, huevos, huevosBefore.ToString(CultureInfo.InvariantCulture));
    Check(Call(ap, "Compare") == null && Msg(ap, "errorMessage") == null && PV(ap) is { } p1 && p1.Lines.Count == 2 && p1.Lines.Single(l => l.IngredientId == harina.Id) is { ExpectedStock: var ex1, CountedStock: 2.5m, Kind: StockCountDifferenceKind.Surplus } && ex1 == harinaBefore
        && p1.Lines.Single(l => l.IngredientId == huevos.Id).Kind == StockCountDifferenceKind.Match && Reasons(ap).ContainsKey(harina.Id), "compare shows registered vs counted with kinds and a reason slot per line");
    Check(State() == cmpState, "compare is read-only");
    Set(ap, "confirmChecked", true);
    storage.SaveToFile(); var noReasonState = State(); var noReasonBytes = File.ReadAllBytes("data.json");
    Check(Call(ap, "Confirm") == null && Msg(ap, "errorMessage")!.Contains("motivo") && State() == noReasonState && noReasonBytes.SequenceEqual(File.ReadAllBytes("data.json")) && anav.Destination == null, "confirm without the reason of a difference is rejected and nothing changes");
    Reasons(ap)[harina.Id] = "faltante en estante";
    Set(ap, "confirmChecked", false);
    Check(Call(ap, "Confirm") == null && Msg(ap, "errorMessage")!.Contains("confirm") && State() == noReasonState && anav.Destination == null, "confirm without the confirmation checkbox is rejected and nothing changes");
    // Editing a counted quantity after comparing requires comparing again.
    Set(ap, "confirmChecked", true);
    rowType.GetProperty("Counted")!.SetValue(RowOf(ap, harina), "1");
    Check(Call(ap, "Confirm") == null && Msg(ap, "errorMessage")!.Contains("comparar") && State() == noReasonState && PV(ap) == null, "changing a quantity after comparing forces a new comparison");
    rowType.GetProperty("Counted")!.SetValue(RowOf(ap, harina), "2.5");
    Check(Call(ap, "Compare") == null && PV(ap) != null && Call(ap, "Invalidate") == null && PV(ap) == null && !(bool)Get(ap, "confirmChecked")!, "invalidate drops the comparison and the confirmation");
    Call(ap, "Compare"); Reasons(ap)[harina.Id] = "faltante en estante"; Set(ap, "confirmChecked", true); Set(ap, "notes", "  conteo de prueba ");
    // A demoted admin is rejected on the circuit before anything reaches the service.
    admin.Role = UserRole.Employee;
    storage.SaveToFile(); var demotedState = State();
    Check(Call(ap, "Confirm") == null && anav.Destination == "/unauthorized" && State() == demotedState, "confirm by a demoted admin navigates to /unauthorized and mutates nothing");
    admin.Role = UserRole.Admin; anav.Destination = null;
    var countsBefore = storage.StockCounts.Count;
    Check(Call(ap, "Confirm") == null && Msg(ap, "errorMessage") == null && storage.StockCounts.Count == countsBefore + 1 && harina.CurrentStock == 2.5m && huevos.CurrentStock == huevosBefore, "confirm applies the count");
    var newCount = storage.StockCounts.Last();
    Check(anav.Destination == "/stock/count/" + newCount.Id && newCount.Notes == "conteo de prueba" && newCount.UserId == 10 && newCount.AdjustedLineCount == 1 && newCount.Lines.Count == 2
        && storage.StockMovements.Last() is { Type: StockMovementType.CountAdjustment, Reason: "faltante en estante" } lm && lm.StockCountId == newCount.Id
        && PV(ap) == null && SelectedCount(ap) == 0 && Msg(ap, "successMessage") != null, "success navigates to the detail, clears the form and records the count");
    Check(((IReadOnlyList<StockCount>)Get(ap, "history")!).Count == storage.StockCounts.Count && ((decimal)rowType.GetProperty("Stock")!.GetValue(RowOf(ap, harina))!) == 2.5m, "success refreshes the history and the registered stock");

    // Stale confirm: the registered stock moves between compare and confirm.
    Pick(ap, harina, "3"); Call(ap, "Compare");
    Reasons(ap)[harina.Id] = "sobrante"; Set(ap, "confirmChecked", true);
    ingredients.AdjustStock(harina.Id, 2m, "otro operador", admin2);
    storage.SaveToFile(); var staleState = State();
    Check(Call(ap, "Confirm") == null && Msg(ap, "errorMessage") == Stale && PV(ap) == null && State() == staleState && anav.Destination == "/stock/count/" + newCount.Id, "stale confirm shows the recount message, drops the comparison and mutates nothing");

    // Detail route.
    SetId(ap, newCount.Id);
    Check(Call(ap, "OnParametersSet") == null && ((StockCount?)Get(ap, "detail"))?.Id == newCount.Id && Msg(ap, "detailMessage") == null, "detail route loads the count");
    SetId(ap, 9999);
    Check(Call(ap, "OnParametersSet") == null && Get(ap, "detail") == null && Msg(ap, "detailMessage")!.Contains("No existe un conteo con el ID 9999"), "unknown detail id shows the missing-count message");
    SetId(ap, null); anav.Destination = null;
    Check(Call(ap, "OnParametersSet") == null && Get(ap, "detail") == null && Msg(ap, "detailMessage") == null, "list route clears the detail");
    Check(Call(ap, "ShowDetail", 2) == null && anav.Destination == "/stock/count/2" && Call(ap, "CloseDetail") == null && anav.Destination == "/stock/count", "show and close detail navigate without forcing a reload");

    // Source wiring.
    string Src(string path) => File.ReadAllText(Path.Combine(args[0], path.Replace('/', Path.DirectorySeparatorChar)));
    var pageSource = Src("Pages/StockCount.razor"); var navSource = Src("Shared/NavMenu.razor"); var program = Src("Program.cs");
    Check(pageSource.Contains("@page \"/stock/count\"") && pageSource.Contains("@page \"/stock/count/{CountId:int}\""), "page routes");
    Check(pageSource.Contains("/ingredients/") && pageSource.Contains("/movements") && pageSource.Contains("StockCountLabels.GetLabel(line.Difference)") && pageSource.Contains("StockCountLabels.GetLabel(line.Kind)") && !pageSource.Contains("forceLoad"), "page links to the movements of each ingredient, labels differences with words and never forces a reload");
    // The menu has one admin-only entry to /ingredients ("Ingredientes y stock"); the count is its "Conteo f\u00edsico" tab.
    var linkAt = navSource.IndexOf("href=\"ingredients\"", StringComparison.Ordinal);
    var logoutAt = navSource.IndexOf("sidebar__footer", StringComparison.Ordinal);
    var inventorySource = Src("Shared/Inventory/InventoryView.razor"); var inventorySupport = Src("Shared/Inventory/InventorySupport.cs");
    Check(linkAt > 0 && linkAt < logoutAt && navSource.Contains("Ingredientes y stock") && navSource.LastIndexOf("IsInRole(UserRole.Admin)", linkAt, StringComparison.Ordinal) > 0
        && navSource.IndexOf("href=\"stock/count\"", StringComparison.Ordinal) < 0, "NavMenu has the admin-only Ingredientes y stock entry to /ingredients (no separate count link)");
    Check(pageSource.Contains("InventoryTab.Count") && inventorySource.Contains("Conteo f\u00edsico") && inventorySupport.Contains("CountRoute = \"/stock/count\"") && inventorySupport.Contains("InventoryTab.Count => CountRoute"),
        "/stock/count opens the Conteo f\u00edsico tab of the inventory view");
    Check(program.Contains("AddSingleton<StockCountService>()"), "StockCountService is registered as a singleton");
}

Console.WriteLine($"{checks} checks, {failures} failures; fixture: {root}");
return failures == 0 ? 0 : 1;

sealed class TestNavigation : NavigationManager
{
    public string? Destination { get; set; }
    public TestNavigation() { Initialize("http://localhost/", "http://localhost/"); }
    protected override void NavigateToCore(string uri, bool forceLoad) { if (forceLoad) throw new InvalidOperationException("forced reload"); Destination = uri; }
}
'@ | Set-Content (Join-Path $ScratchPath 'Program.cs') -Encoding utf8
$exitCode = 1
Push-Location $ScratchPath
try {
    & dotnet run --project (Join-Path $ScratchPath 'StockCountChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Stock count checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
