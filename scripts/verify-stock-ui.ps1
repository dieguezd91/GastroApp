param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-stock-ui-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'StockUiChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using System.Globalization;
using System.Reflection;
using System.Text.Json;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var root = Directory.GetCurrentDirectory();
var repoRoot = args[0];
string Src(string path) => File.ReadAllText(Path.Combine(repoRoot, path.Replace('/', Path.DirectorySeparatorChar)));
var storage = new DataStorageService(); // Process cwd is ALWAYS the newly allocated temp directory.
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 11, Username = "second-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var admin = storage.Users[0]; var admin2 = storage.Users[1];
storage.Ingredients = []; storage.Recipes = []; storage.Invoices = []; storage.Suppliers = [new Supplier { Id = 1, Name = "Proveedor" }];
storage.Products = [new Product { Id = 1, Name = "Pizza", Price = 100m }];
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
invoices.SetIngredientService(ingredients);
var suppliers = new SupplierService(storage);
var D = DateTime.Today;

string State() => JsonSerializer.Serialize(new { storage.StockMovements, storage.Users, storage.Products, storage.Ingredients, storage.Suppliers,
    storage.Invoices, storage.Recipes, storage.Sales, storage.SaleRefunds, storage.CashRegisters, storage.CashMovements,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
// Runs an action that must throw and change nothing: objects, ledger, counters and file bytes stay identical.
void Reject(Action action, Type exception, string name, string? contains = null)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    bool rejected = false; string message = "";
    try { action(); } catch (Exception ex) { rejected = ex.GetType() == exception && (contains == null || ex.Message == contains); message = ex.Message; }
    Check(rejected, name + " rejected with " + exception.Name + (contains == null ? "" : " / " + contains) + (rejected ? "" : " [" + message + "]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")), name + " leaves objects, ledger, counters and fixture bytes unchanged");
}
void Invalid(Action action, string name, string contains) => Reject(action, typeof(InvalidOperationException), name, contains);
Ingredient Make(string name, string unit, decimal stock, decimal min = 0m, bool active = true)
{
    // New ingredients are created without stock; a fixture with stock models data stored before that rule:
    // the ingredient plus a legacy InitialStock movement written straight into the ledger.
    var i = new Ingredient { Name = name, Unit = unit, MinStock = min, IsActive = active };
    ingredients.Add(i, admin);
    if (stock != 0m)
    {
        i.CurrentStock = stock;
        storage.StockMovements.Add(new StockMovement { Id = storage.GetNextStockMovementId(), IngredientId = i.Id, Date = DateTime.Now, Type = StockMovementType.InitialStock, Quantity = stock, Unit = unit,
            PreviousStock = 0m, ResultingStock = stock, UserId = admin.Id, Username = admin.Username });
        storage.SaveToFile();
    }
    return i;
}
StockMovement[] Mv(int ingredientId) => storage.StockMovements.Where(m => m.IngredientId == ingredientId).OrderBy(m => m.Id).ToArray();
void Inject(Ingredient i, StockMovementType type, decimal quantity, DateTime date)
    => storage.StockMovements.Add(new StockMovement { Id = storage.GetNextStockMovementId(), IngredientId = i.Id, Date = date, Type = type, Quantity = quantity, Unit = i.Unit,
        PreviousStock = 0m, ResultingStock = quantity, SaleId = type == StockMovementType.SaleConsumption || type == StockMovementType.SaleCancellationReturn ? 1 : null,
        RefundId = type == StockMovementType.RefundReturn ? 1 : null });

// ---- S5: alerts and coverage (read-only query in the service) ----
var alertType = typeof(IngredientService).Assembly.GetType("GastroApp.Models.StockAlert");
Check(alertType != null && alertType.IsSealed && alertType.GetProperties().All(p => p.SetMethod == null || p.SetMethod.ReturnParameter.GetRequiredCustomModifiers().Length > 0), "StockAlert model exists and is immutable (init-only)");
Check(typeof(IngredientService).GetMethod("GetStockAlerts") != null, "IngredientService.GetStockAlerts exists");
List<dynamic> Alerts(int days = 7, DateTime? asOf = null)
{
    dynamic svc = ingredients;
    IEnumerable<object> list = svc.GetStockAlerts(days, asOf);
    return list.Cast<dynamic>().ToList();
}
string[] SafeNames() { try { return Names(Alerts()); } catch (Exception) { return ["<GetStockAlerts missing>"]; } }
string[] Names(IEnumerable<dynamic> list) => list.Select(a => (string)a.Name).ToArray();
var agotado = Make("Agotado", "kg", 0m, 5m);
var bajo = Make("Bajo", "kg", 6m, 6m);
var justo = Make("Justo", "unidad", 3m, 10m);
var corta = Make("Corta", "kg", 3m, 10m);
Make("SinMinimo", "kg", 5m, 0m); Make("Abundante", "kg", 100m, 5m); Make("Inactivo", "kg", 0m, 5m, false);
var negativo = Make("Negativo", "kg", 0m, 1m); negativo.CurrentStock = -2m; // legacy negative balance
Inject(agotado, StockMovementType.SaleConsumption, -8m, D.AddDays(-1).AddHours(12)); Inject(agotado, StockMovementType.SaleConsumption, -6m, D.AddDays(-6).AddHours(1));
Inject(bajo, StockMovementType.SaleConsumption, -9m, D.AddHours(2)); Inject(bajo, StockMovementType.SaleCancellationReturn, 2m, D.AddDays(-2));
Inject(justo, StockMovementType.SaleConsumption, -100m, D.AddDays(-7).AddHours(23));
Inject(corta, StockMovementType.SaleConsumption, -12m, D.AddDays(-3)); Inject(corta, StockMovementType.RefundReturn, 2m, D.AddDays(-3));
Inject(corta, StockMovementType.Waste, -50m, D); Inject(corta, StockMovementType.Adjustment, -50m, D); // not consumption
Inject(negativo, StockMovementType.RefundReturn, 3m, D);
storage.SaveToFile();
var stateBeforeAlerts = State(); var bytesBeforeAlerts = File.ReadAllBytes("data.json");
try
{
var alerts = Alerts();
Check(Names(alerts).SequenceEqual(["Agotado", "Negativo", "Corta", "Bajo", "Justo"]), "alerts: out of stock first, then below minimum; by coverage ascending with unknown last; inactive/ok/no-minimum excluded [" + string.Join(",", Names(alerts)) + "]");
dynamic aAgotado = alerts.First(a => a.Name == "Agotado"), aBajo = alerts.First(a => a.Name == "Bajo"), aJusto = alerts.First(a => a.Name == "Justo"),
    aCorta = alerts.First(a => a.Name == "Corta"), aNegativo = alerts.First(a => a.Name == "Negativo");
Check(aAgotado.Level.ToString() == "OutOfStock" && aBajo.Level.ToString() == "BelowMinimum" && aAgotado.IngredientId == agotado.Id && aAgotado.Unit == "kg" && aAgotado.CurrentStock == 0m && aAgotado.MinStock == 5m, "alert level, identity, unit, stock and minimum");
Check(aAgotado.RecentConsumption == 14m && aAgotado.CoverageDays == 0m && !aAgotado.IsNegative, "out of stock with recent consumption: net 14 over the 7-day window, coverage 0 days");
Check(aBajo.RecentConsumption == 7m && aBajo.CoverageDays == 6m, "below minimum: net consumption 9 - 2 = 7, daily 1, coverage 6 days (stock 6)");
Check(aCorta.RecentConsumption == 10m && aCorta.CoverageDays == 2.1m, "coverage = stock * days / net consumption (3 * 7 / 10 = 2.1); waste and adjustments are not consumption");
Check(aJusto.RecentConsumption == 0m && aJusto.CoverageDays == null, "no consumption inside the window (the 8th day back is excluded): coverage unknown");
Check(aNegativo.IsNegative && aNegativo.Level.ToString() == "OutOfStock" && aNegativo.CurrentStock == -2m && aNegativo.RecentConsumption == 0m && aNegativo.CoverageDays == null, "legacy negative balance is an out-of-stock alert flagged negative; refunds above consumption never make it negative");
var alerts14 = Alerts(14);
Check(Names(alerts14).SequenceEqual(["Agotado", "Negativo", "Justo", "Corta", "Bajo"]) && alerts14.First(a => a.Name == "Justo").CoverageDays == 0.42m && alerts14.First(a => a.Name == "Justo").RecentConsumption == 100m,
    "a longer window includes older consumption and reorders by coverage (3 * 14 / 100 = 0.42)");
var shifted = Alerts(7, D.AddDays(-7));
Check(shifted.First(a => a.Name == "Justo").RecentConsumption == 100m && shifted.First(a => a.Name == "Bajo").RecentConsumption == 0m, "asOf moves the window (calendar days, inclusive)");
Check(State() == stateBeforeAlerts && bytesBeforeAlerts.SequenceEqual(File.ReadAllBytes("data.json")), "GetStockAlerts is read-only");
Invalid(() => Alerts(0), "alerts with a zero-day window", "El per\u00edodo debe ser mayor a cero.");
Invalid(() => Alerts(-3), "alerts with a negative window", "El per\u00edodo debe ser mayor a cero.");
}
catch (Exception ex) { Check(false, "alert checks aborted: " + ex.GetType().Name + " " + ex.Message.Split((char)10)[0]); }

// ---- S13: integrity guards ----
const string UnitMessage = "No se puede cambiar la unidad de un ingrediente con stock o movimientos.";
// S2: deletion is rejected only while a current recipe uses the ingredient, naming the recipes (sorted by name).
string RecipeBlock(params string[] names) => names.Length == 1
    ? $"No se puede eliminar: lo usa la receta {names[0]}. Quitalo de esa receta primero."
    : $"No se puede eliminar: lo usan las recetas {string.Join(", ", names)}. Quitalo de esas recetas primero.";
string Deleted(int id) => $"Ingrediente eliminado (#{id})";
var harina = Make("Harina", "kg", 100m, 10m);
var azucar = Make("Azucar", "kg", 2m); ingredients.RegisterWaste(azucar.Id, 2m, WasteCategory.Otro, "todo", admin);
var sal = Make("Sal", "kg", 0m);
Check(azucar.CurrentStock == 0m && ingredients.HasMovements(azucar.Id) && !ingredients.HasMovements(sal.Id), "guard fixture: zero stock with history vs zero stock without history");
Invalid(() => ingredients.Update(new Ingredient { Id = harina.Id, Name = "Cambio", Unit = "gr", IsActive = false, MinStock = 99m }), "unit change with stock", UnitMessage);
Invalid(() => ingredients.Update(new Ingredient { Id = azucar.Id, Name = "Cambio", Unit = "gr", IsActive = true }), "unit change with movements but zero stock", UnitMessage);
Invalid(() => ingredients.Update(new Ingredient { Id = harina.Id, Name = "Cambio", Unit = "KG", IsActive = true }), "unit change in letter case only (units are stored exactly)", UnitMessage);
ingredients.Update(new Ingredient { Id = sal.Id, Name = "Sal fina", Unit = "gr", IsActive = true, MinStock = 1m, CurrentStock = 55m });
Check(sal.Unit == "gr" && sal.Name == "Sal fina" && sal.CurrentStock == 0m && Mv(sal.Id).Length == 0, "an ingredient without stock or movements may change unit (and a caller-supplied stock is ignored)");
var ledgerBefore = storage.StockMovements.Count;
ingredients.Update(new Ingredient { Id = harina.Id, Name = "Harina 000", Unit = "kg", IsActive = false, MinStock = 20m, CurrentStock = 5m });
Check(harina.Name == "Harina 000" && harina.Unit == "kg" && !harina.IsActive && harina.MinStock == 20m && harina.CurrentStock == 100m && storage.StockMovements.Count == ledgerBefore, "PRESERVE: Update with the same unit applies name/active/minimum and never touches stock");
harina.IsActive = true;
ingredients.Update(new Ingredient { Id = 98765, Name = "Nada", Unit = "kg" });
Check(storage.Ingredients.All(i => i.Name != "Nada"), "PRESERVE: Update of an unknown ingredient stays a no-op");

var receta = Make("EnReceta", "kg", 0m); storage.Recipes.Add(new Recipe { Id = 1, Name = "Pizza", Ingredients = [new RecipeIngredient { RecipeId = 1, IngredientId = receta.Id, Quantity = 1m, Unit = "kg" }] });
var factura = Make("EnFactura", "kg", 0m); storage.Invoices.Add(new Invoice { Id = storage.GetNextInvoiceId(), SupplierId = 1, Items = [new InvoiceItem { IngredientId = factura.Id, Quantity = 1m, Unit = "kg" }] });
var ventaAgregada = Make("EnVentaAgregada", "kg", 0m); var ventaLinea = Make("EnVentaLinea", "kg", 0m);
storage.Sales.Add(new Sale { Id = storage.GetNextSaleId(), Items = [new SaleItem { ProductId = 1, ProductName = "Pizza", Price = 1m, Quantity = 1 }], StockConsumption = [new SaleStockConsumption { IngredientId = ventaAgregada.Id, Quantity = 1m, Unit = "kg" }] });
storage.Sales.Add(new Sale { Id = storage.GetNextSaleId(), Items = [new SaleItem { ProductId = 1, ProductName = "Pizza", Price = 1m, Quantity = 1, StockConsumption = [new SaleStockConsumption { IngredientId = ventaLinea.Id, Quantity = 1m, Unit = "kg" }] }, new SaleItem { ProductId = 2, ProductName = "Legado", Price = 1m, Quantity = 1 }], StockConsumption = null });
var libre = Make("Libre", "kg", 0m);
// S2: a recipe that uses the ingredient blocks the deletion and names itself; nothing changes (objects, ledger, counters, file bytes).
Invalid(() => ingredients.Delete(receta.Id), "delete of an ingredient used by a recipe", RecipeBlock("Pizza"));
var enDos = Make("EnDosRecetas", "kg", 0m);
storage.Recipes.Add(new Recipe { Id = 3, Name = "Flan", Ingredients = [new RecipeIngredient { RecipeId = 3, IngredientId = enDos.Id, Quantity = 1m, Unit = "kg" }] });
storage.Recipes.Add(new Recipe { Id = 2, Name = "Caldo de huesos", Ingredients = [new RecipeIngredient { RecipeId = 2, IngredientId = enDos.Id, Quantity = 1m, Unit = "kg" }, new RecipeIngredient { RecipeId = 2, IngredientId = enDos.Id, Quantity = 2m, Unit = "kg" }] });
Invalid(() => ingredients.Delete(enDos.Id), "delete of an ingredient used by two recipes (listed once each, sorted by name)", RecipeBlock("Caldo de huesos", "Flan"));
Check(storage.Ingredients.Contains(receta) && storage.Ingredients.Contains(enDos), "rejected deletes keep the ingredient listed");
// S1: history alone (movements, invoice items, sale consumption snapshots) never blocks; every record stays byte-identical.
string History() => JsonSerializer.Serialize(new { storage.StockMovements, storage.Sales, storage.SaleRefunds, storage.Invoices, storage.StockCounts, storage.Recipes, storage.CashMovements });
string FileHistory() { var node = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText("data.json"))!.AsObject(); return string.Join("|", new[] { "StockMovements", "Sales", "SaleRefunds", "Invoices", "StockCounts", "Recipes", "CashMovements" }.Select(k => node[k]?.ToJsonString())); }
var deletedIds = new List<int>();
foreach (var (target, why) in new[] { (factura, "an invoice item"), (ventaAgregada, "a sale consumption snapshot"), (ventaLinea, "a sale line consumption snapshot"), (azucar, "stock movements") })
{
    storage.SaveToFile();
    var historyBefore = History(); var fileBefore = FileHistory(); var movementsOfTarget = Mv(target.Id).Length; var ledger = storage.StockMovements.Count; var targetId = target.Id; var remaining = storage.Ingredients.Count - 1;
    ingredients.Delete(targetId); deletedIds.Add(targetId);
    Check(storage.Ingredients.All(i => i.Id != targetId) && storage.Ingredients.Count == remaining && ingredients.GetById(targetId) == null, "delete of an ingredient with " + why + " succeeds");
    Check(History() == historyBefore && FileHistory() == fileBefore && storage.StockMovements.Count == ledger && Mv(targetId).Length == movementsOfTarget, "after deleting an ingredient with " + why + " movements, sales, invoices, refunds, counts and recipes are byte-identical in memory and in data.json");
}
Check(deletedIds.Count == 4 && Mv(azucar.Id).Length > 0, "deleted fixtures keep their movements");
var fresh = Make("Posterior", "kg", 0m);
Check(fresh.Id > deletedIds.Max() && Mv(fresh.Id).Length == 0 && ingredients.GetMovements(fresh.Id).Count == 0, "ids are never reused: a new ingredient does not inherit the history of a deleted one");
Check(ingredients.DisplayName(fresh.Id) == "Posterior" && ingredients.DisplayName(deletedIds[0]) == Deleted(deletedIds[0]) && IngredientService.DeletedName(7) == Deleted(7), "DisplayName: live name, else 'Ingrediente eliminado (#id)'");
var allMovements = ingredients.GetAllMovements();
Check(allMovements.Count == storage.StockMovements.Count && allMovements.Any(m => m.IngredientId == azucar.Id) && allMovements.Select(m => m.Id).SequenceEqual(allMovements.OrderByDescending(m => m.Date).ThenByDescending(m => m.Id).Select(m => m.Id)),
    "GetAllMovements lists every movement, deleted ingredients included, newest first");
Check(ingredients.GetAllMovements(new StockMovementFilter { Types = [StockMovementType.Waste] }).All(m => m.Type == StockMovementType.Waste) && ingredients.GetAllMovements(new StockMovementFilter { Types = [StockMovementType.Waste] }).Any(m => m.IngredientId == azucar.Id), "GetAllMovements honors the filter");
Check(ingredients.GetDeletedIngredientIdsWithHistory().Contains(azucar.Id) && !ingredients.GetDeletedIngredientIdsWithHistory().Contains(fresh.Id) && !ingredients.GetDeletedIngredientIdsWithHistory().Contains(98765), "ids that have movements but no ingredient are reported once, ordered");
var beforeUnknown = State(); ingredients.Delete(98765);
Check(State() == beforeUnknown, "PRESERVE: Delete of an unknown ingredient stays a no-op");

// ---- Pages: renderer-less component checks ----
var asm = typeof(IngredientService).Assembly;
var users = new UserService(storage);
AuthService NewAuth(string? username)
{
    var auth = new AuthService(users);
    if (username != null) Check(auth.Login(username, "fixture-pass"), "circuit login " + username);
    return auth;
}
object NewPage(Type type, AuthService auth, out TestNavigation nav)
{
    var page = Activator.CreateInstance(type)!; nav = new TestNavigation();
    void Inject2(string name, object value) { var p = type.GetProperty(name, flags); p?.SetValue(page, value); }
    Inject2("AuthService", auth); Inject2("Navigation", nav); Inject2("IngredientService", ingredients);
    Inject2("InvoiceService", invoices); Inject2("SupplierService", suppliers);
    return page;
}
Exception? Call(object page, string method, params object?[] arguments)
{
    try
    {
        var result = page.GetType().GetMethod(method, flags | BindingFlags.DeclaredOnly)!.Invoke(page, arguments);
        if (result is Task task) task.GetAwaiter().GetResult();
        return null;
    }
    catch (TargetInvocationException ex) { return ex.InnerException; }
}
object? Func(object page, string method, params object?[] arguments) => page.GetType().GetMethod(method, flags | BindingFlags.DeclaredOnly)!.Invoke(page, arguments);
object? Get(object page, string field) => page.GetType().GetField(field, flags)!.GetValue(page);
void Set(object page, string field, object? value) => page.GetType().GetField(field, flags)!.SetValue(page, value);
string? Str(object page, string field) => (string?)Get(page, field);

var pageType = asm.GetType("GastroApp.Pages.Ingredients"); var movementsType = asm.GetType("GastroApp.Pages.IngredientMovements"); var invoicesType = asm.GetType("GastroApp.Pages.Invoices");
Check(pageType != null && movementsType != null && invoicesType != null, "Ingredients, IngredientMovements and Invoices page types exist");
var uiAnon = NewAuth(null); var uiEmployee = NewAuth("fixture-employee"); var uiAdmin = NewAuth("fixture-admin"); var uiSecond = NewAuth("second-admin");
var viewIngredient = Make("Cacao", "kg", 50m, 5m);
storage.SaveToFile();
if (pageType != null)
{
    // Anonymous and employee circuits fail closed on every callback and change nothing.
    var guarded = State();
    foreach (var (auth, who, destination) in new[] { (uiAnon, "anonymous", "/login"), (uiEmployee, "employee", "/unauthorized") })
        foreach (var action in new[] { "OnInitializedAsync", "ShowAddForm", "EditIngredient", "SaveIngredient", "CancelEdit", "DeleteIngredient", "ShowStockAdjust", "SaveStockAdjustment", "CancelStockAdjustment", "ShowWaste", "SaveWaste", "CancelWaste" })
        {
            var page = NewPage(pageType, auth, out var nav);
            Set(page, "adjustIngredientId", harina.Id); Set(page, "adjustNewStock", 1m); Set(page, "adjustReason", "intento"); Set(page, "adjustConfirmed", true);
            Set(page, "wasteIngredientId", harina.Id); Set(page, "wasteQuantity", 1m); Set(page, "wasteCategory", WasteCategory.Otro); Set(page, "wasteReason", "intento"); Set(page, "wasteConfirmed", true);
            var editing = new Ingredient { Id = harina.Id, Name = "Hack", Unit = "kg", CurrentStock = 999m };
            Set(page, "editingIngredient", editing);
            var arguments = action switch { "EditIngredient" or "ShowStockAdjust" or "ShowWaste" => new object[] { harina }, "DeleteIngredient" => new object[] { libre.Id + 1 }, _ => Array.Empty<object>() };
            var ex = Call(page, action, arguments);
            Check(ex == null && nav.Destination == destination && ((System.Collections.ICollection)Get(page, "ingredients")!).Count == 0 && Get(page, "alerts") == null && Str(page, "successMessage") == null && Str(page, "formError") == null,
                who + " " + action + " navigates to " + destination + " and loads/changes nothing");
        }
    Check(State() == guarded && harina.Name == "Harina 000" && harina.CurrentStock == 100m, "anonymous and employee attempts leave storage unchanged");

    // Admin: load, list, alerts, edit form never writes stock.
    var p = NewPage(pageType, uiAdmin, out var nav1);
    Check(Call(p, "OnInitializedAsync") == null && nav1.Destination == null && ((System.Collections.ICollection)Get(p, "ingredients")!).Count == storage.Ingredients.Count
        && Get(p, "alerts") is System.Collections.IEnumerable al && al.Cast<dynamic>().Select(a => (string)a.Name).SequenceEqual(SafeNames()), "admin load lists ingredients and the stock alerts from the service");
    Check(Call(p, "EditIngredient", harina) == null && (bool)Get(p, "showForm")! && ((Ingredient)Get(p, "editingIngredient")!).Id == harina.Id, "admin opens the edit form");
    var editingCopy = (Ingredient)Get(p, "editingIngredient")!;
    editingCopy.CurrentStock = 999m; editingCopy.Name = "Harina editada"; editingCopy.MinStock = 15m;
    harina.CurrentStock = 100m; ingredients.AdjustStock(harina.Id, 90m, "concurrente", admin); // stock changed after the form was opened
    var movementsBeforeSave = storage.StockMovements.Count;
    Check(Call(p, "SaveIngredient") == null && harina.Name == "Harina editada" && harina.MinStock == 15m && harina.CurrentStock == 90m && storage.StockMovements.Count == movementsBeforeSave
        && !(bool)Get(p, "showForm")! && Str(p, "formError") == null, "edit form saves name/minimum, never writes the (stale or tampered) stock and creates no movement");
    Check(Call(p, "EditIngredient", harina) == null, "reopen the edit form");
    ((Ingredient)Get(p, "editingIngredient")!).Unit = "gr";
    var beforeUnit = State();
    Check(Call(p, "SaveIngredient") == null && Str(p, "formError") == UnitMessage && (bool)Get(p, "showForm")! && State() == beforeUnit && harina.Unit == "kg", "unit change guard is shown next to the form and keeps it open without changes");
    Check((bool)Func(p, "CanChangeUnit")! == false, "unit selector is disabled for an ingredient with stock or movements");
    Call(p, "CancelEdit");
    Check(Str(p, "formError") == null && !(bool)Get(p, "showForm")!, "cancelling the form clears its error");
    Call(p, "ShowAddForm");
    Check((bool)Func(p, "CanChangeUnit")! == true, "a new ingredient may choose its unit");
    var newIngredient = (Ingredient)Get(p, "editingIngredient")!; newIngredient.Name = "Levadura"; newIngredient.Unit = "gr";
    const string NoOpeningStock = "Un ingrediente nuevo se crea sin stock: el stock ingresa con las facturas de compra.";
    foreach (var tampered in new[] { -4m, 5m })
    {
        newIngredient.CurrentStock = tampered;
        var beforeTampered = State(); var bytesTampered = File.ReadAllBytes("data.json");
        Check(Call(p, "SaveIngredient") == null && Str(p, "formError") == NoOpeningStock && State() == beforeTampered && bytesTampered.SequenceEqual(File.ReadAllBytes("data.json")) && (bool)Get(p, "showForm")! && !storage.Ingredients.Any(i => i.Name == "Levadura"),
            "a new ingredient submitted with stock " + tampered + " is rejected with the service message in the form and changes nothing");
    }
    newIngredient.CurrentStock = 0m;
    var ledgerBeforeCreate = storage.StockMovements.Count;
    Check(Call(p, "SaveIngredient") == null && storage.Ingredients.Any(i => i.Name == "Levadura" && i.Unit == "gr" && i.CurrentStock == 0m) && storage.StockMovements.Count == ledgerBeforeCreate
        && Str(p, "formError") == null && !(bool)Get(p, "showForm")!, "a new ingredient without stock is created and records no movement");
    var blank = NewPage(pageType, uiAdmin, out _); Call(blank, "ShowAddForm"); var beforeBlank = State();
    Check(Call(blank, "SaveIngredient") == null && State() == beforeBlank && Str(blank, "formError") == "El nombre del ingrediente es obligatorio.", "blank name shows an error in the form");

    // Delete guard.
    Call(p, "OnInitializedAsync");
    var beforeDelete = State();
    Check(Call(p, "DeleteIngredient", receta.Id) == null && Str(p, "deleteError") == RecipeBlock("Pizza") && (int)Get(p, "deleteErrorId")! == receta.Id && State() == beforeDelete && storage.Ingredients.Contains(receta), "deleting an ingredient used by a recipe shows the recipe-naming message next to it and changes nothing");
    var disposable = Make("Descartable", "kg", 0m); storage.SaveToFile();
    Check(Call(p, "DeleteIngredient", disposable.Id) == null && storage.Ingredients.All(i => i.Id != disposable.Id) && Str(p, "deleteError") == null && (int)Get(p, "deleteErrorId")! == 0, "deleting an unreferenced ingredient works and clears the error");
    Check(Call(p, "DeleteIngredient", 98765) == null && Str(p, "deleteError") == null, "PRESERVE: deleting an unknown ingredient stays a no-op in the page");
    var withHistory = Make("ConHistoria", "kg", 5m); ingredients.RegisterWaste(withHistory.Id, 1m, WasteCategory.Otro, "prueba", admin); storage.SaveToFile();
    var historyId = withHistory.Id; var historyPageBefore = History(); var historyFileBefore = FileHistory();
    Check(Call(p, "DeleteIngredient", historyId) == null && storage.Ingredients.All(i => i.Id != historyId) && Str(p, "deleteError") == null && (int)Get(p, "deleteErrorId")! == 0 && History() == historyPageBefore && FileHistory() == historyFileBefore && Mv(historyId).Length == 2,
        "deleting an ingredient with history works in the page and keeps its movements, sales and invoices byte-identical");
    deletedIds.Add(historyId);
    var dialogSource = Src("Pages/Ingredients.razor");
    Check(dialogSource.Contains("desaparece del stock, de las alertas y de los selectores") && dialogSource.Contains("se conserva") && dialogSource.Contains("quitalo de la receta primero") && !dialogSource.Contains("Solo se pueden eliminar ingredientes sin movimientos"),
        "S4: the delete dialog explains that history is kept but the ingredient leaves stock, alerts and pickers, and that a recipe blocks it");

    // Adjust dialog.
    Check(Call(p, "ShowStockAdjust", harina) == null && (int)Get(p, "adjustIngredientId")! == harina.Id && Get(p, "adjustNewStock") == null && Str(p, "adjustReason") == null && !(bool)Get(p, "adjustConfirmed")!, "adjust dialog opens empty for the ingredient");
    Check(Func(p, "GetAdjustDifference") == null, "no difference is shown before a new stock is typed");
    Set(p, "adjustNewStock", 75m);
    Check((decimal?)Func(p, "GetAdjustDifference") == -15m, "the dialog shows the resulting difference (75 - 90 = -15)");
    Set(p, "adjustReason", "conteo r\u00e1pido"); var beforeAdjust = State();
    Check(Call(p, "SaveStockAdjustment") == null && Str(p, "adjustError")!.Contains("Confirm") && State() == beforeAdjust && (int)Get(p, "adjustIngredientId")! == harina.Id, "adjustment without confirmation is refused in the dialog");
    Set(p, "adjustConfirmed", true); Set(p, "adjustReason", "  ");
    Check(Call(p, "SaveStockAdjustment") == null && Str(p, "adjustError") == "Debe indicar el motivo del ajuste de stock." && State() == beforeAdjust, "mandatory reason: the service message is shown in the dialog and nothing changes");
    Set(p, "adjustReason", "conteo r\u00e1pido"); Set(p, "adjustNewStock", -1m);
    Check(Call(p, "SaveStockAdjustment") == null && Str(p, "adjustError")!.Contains("negativo") && State() == beforeAdjust, "negative target is refused (S10)");
    Set(p, "adjustNewStock", 90m);
    Check(Call(p, "SaveStockAdjustment") == null && Str(p, "adjustError")!.Contains("igual") && State() == beforeAdjust, "no-op adjustment is refused");
    Set(p, "adjustNewStock", null);
    Check(Call(p, "SaveStockAdjustment") == null && Str(p, "adjustError") == "Indique el nuevo stock." && State() == beforeAdjust, "missing new stock is refused");
    Set(p, "adjustNewStock", 75m);
    Check(Call(p, "SaveStockAdjustment") == null && harina.CurrentStock == 75m && Mv(harina.Id).Last() is { Type: StockMovementType.Adjustment, Quantity: -15m, PreviousStock: 90m, ResultingStock: 75m, Reason: "conteo r\u00e1pido", UserId: 10, Username: "fixture-admin" }
        && (int)Get(p, "adjustIngredientId")! == 0 && Str(p, "adjustError") == null && Str(p, "successMessage")!.Contains("Harina editada"), "confirmed adjustment records the movement with reason and responsible, closes the dialog and reports success");
    Check(Get(p, "adjustNewStock") == null && Str(p, "adjustReason") == null && !(bool)Get(p, "adjustConfirmed")!, "the dialog state is reset after saving");

    // Waste dialog.
    Check(Call(p, "ShowWaste", harina) == null && (int)Get(p, "wasteIngredientId")! == harina.Id && Get(p, "wasteQuantity") == null && Get(p, "wasteCategory") == null && Str(p, "successMessage") == null, "waste dialog opens empty and clears the previous success message");
    Set(p, "wasteQuantity", 5m); Set(p, "wasteReason", "bolsa vencida"); Set(p, "wasteConfirmed", true); var beforeWaste = State();
    Check(Call(p, "SaveWaste") == null && Str(p, "wasteError") == "Debe seleccionar la categor\u00eda de la merma." && State() == beforeWaste, "waste without category is refused in the dialog");
    Set(p, "wasteCategory", WasteCategory.Vencimiento); Set(p, "wasteConfirmed", false);
    Check(Call(p, "SaveWaste") == null && Str(p, "wasteError")!.Contains("Confirm") && State() == beforeWaste, "waste without confirmation is refused");
    Set(p, "wasteConfirmed", true); Set(p, "wasteQuantity", null);
    Check(Call(p, "SaveWaste") == null && Str(p, "wasteError") == "Indique la cantidad de la merma." && State() == beforeWaste, "waste without quantity is refused");
    Set(p, "wasteQuantity", 0m);
    Check(Call(p, "SaveWaste") == null && Str(p, "wasteError")!.Contains("positiva") && State() == beforeWaste, "zero waste shows the service message");
    Set(p, "wasteQuantity", 76m);
    Check(Call(p, "SaveWaste") == null && Str(p, "wasteError")!.Contains("Stock insuficiente") && State() == beforeWaste, "waste above stock shows the service message (never negative stock)");
    Set(p, "wasteQuantity", 5m); Set(p, "wasteReason", " ");
    Check(Call(p, "SaveWaste") == null && Str(p, "wasteError") == "Debe indicar el motivo de la merma." && State() == beforeWaste, "mandatory waste reason is enforced");
    Set(p, "wasteReason", "bolsa vencida");
    Check(Call(p, "SaveWaste") == null && harina.CurrentStock == 70m && Mv(harina.Id).Last() is { Type: StockMovementType.Waste, Quantity: -5m, WasteCategory: WasteCategory.Vencimiento, Reason: "bolsa vencida", UserId: 10 }
        && (int)Get(p, "wasteIngredientId")! == 0 && Str(p, "wasteError") == null && Str(p, "successMessage") != null, "confirmed waste records category, reason and responsible and closes the dialog");

    // Dialogs and form do not leak between ingredients.
    Call(p, "ShowStockAdjust", harina); Set(p, "adjustError", "viejo"); Call(p, "ShowWaste", harina);
    Check((int)Get(p, "adjustIngredientId")! == 0 && Str(p, "adjustError") == null && (int)Get(p, "wasteIngredientId")! == harina.Id, "opening the waste dialog closes the adjust dialog and its error");
    Call(p, "CancelWaste");

    // Mid-session demotion: every mutation redirects and changes nothing.
    var (sp, snav) = (NewPage(pageType, uiSecond, out var secondNav), secondNav);
    Call(sp, "OnInitializedAsync"); Call(sp, "ShowStockAdjust", harina); Set(sp, "adjustNewStock", 60m); Set(sp, "adjustReason", "x"); Set(sp, "adjustConfirmed", true);
    Set(sp, "wasteIngredientId", harina.Id); Set(sp, "wasteQuantity", 1m); Set(sp, "wasteCategory", WasteCategory.Otro); Set(sp, "wasteReason", "x"); Set(sp, "wasteConfirmed", true);
    admin2.Role = UserRole.Employee;
    var preDemotion = State();
    try
    {
        foreach (var action in new[] { "SaveStockAdjustment", "SaveWaste", "SaveIngredient", "ShowAddForm", "DeleteIngredient", "OnInitializedAsync" })
        {
            snav.Destination = null;
            var ex = Call(sp, action, action == "DeleteIngredient" ? new object[] { receta.Id } : Array.Empty<object>());
            Check(ex == null && snav.Destination == "/unauthorized" && State() == preDemotion, "demoted admin " + action + " redirects to /unauthorized and changes nothing");
        }
    }
    finally { admin2.Role = UserRole.Admin; }

    var pageSource = Src("Pages/Ingredients.razor");
    Check(!pageSource.Contains("editingIngredient.CurrentStock") && !pageSource.Contains("Stock inicial") && !pageSource.Contains("ingredient-initial") && pageSource.Contains("href=\"/invoices\"") && pageSource.Contains("facturas de compra"),
        "the form has no stock input (new or edit) and tells the Admin that stock is loaded with purchase invoices, linking to /invoices");
    Check(pageSource.Contains("Stock negativo: requiere ajuste") && pageSource.Contains("CurrentStock < 0"), "negative balances show the visible warning text (S10)");
    Check(pageSource.Contains("href=\"/ingredients/@ingredient.Id/movements\"") && pageSource.Contains("Alertas de stock") && pageSource.Contains("Sin consumo reciente"), "history link, alerts section and unknown coverage text");
    Check(pageSource.Contains("Ajustar stock") && pageSource.Contains("Registrar merma") && pageSource.Contains("Enum.GetValues<WasteCategory>()") && pageSource.Contains("StockMovementLabels.GetLabel("), "adjust and waste dialogs with category labels from StockMovementLabels");
    Check(System.Text.RegularExpressions.Regex.IsMatch(pageSource, @"AdjustStock\(adjustIngredientId, [\w.]+, adjustReason, AuthService\.CurrentUser\)") && System.Text.RegularExpressions.Regex.IsMatch(pageSource, @"RegisterWaste\(wasteIngredientId, [\w.]+, [\w.]+, wasteReason, AuthService\.CurrentUser\)") && pageSource.Contains("IngredientService.Add(editingIngredient, AuthService.CurrentUser)"),
        "the page passes the circuit user and the reason to the stock commands");
    Check(!pageSource.Contains("stockAdjustReason") && !pageSource.Contains("newStockValue"), "the temporary inline adjustment inputs are gone");
}

// ---- History page ----
if (movementsType != null)
{
    var cacao = viewIngredient;
    for (int i = 1; i <= 22; i++) ingredients.AdjustStock(cacao.Id, 50m + i, "ajuste " + i, i % 2 == 0 ? admin : admin2);
    ingredients.RegisterWaste(cacao.Id, 3m, WasteCategory.Otro, "w1", admin); ingredients.RegisterWaste(cacao.Id, 2m, WasteCategory.RoturaODerrame, "w2", admin);
    var cm = Mv(cacao.Id);
    Check(cm.Length == 25, "history fixture: 25 movements");
    for (int k = 0; k < cm.Length; k++) cm[k].Date = new DateTime(2026, 3, 1).AddDays(k);
    cm[1].Date = new DateTime(2026, 3, 2, 23, 59, 59); cm[2].Date = new DateTime(2026, 3, 3, 0, 0, 0);
    var legacyA = Make("LegadoA", "kg", 0m); legacyA.CurrentStock = 7m;
    var legacyB = Make("LegadoB", "kg", 0m); legacyB.CurrentStock = 40m; ingredients.AdjustStock(legacyB.Id, 45m, "primer ajuste", admin);
    var vacio = Make("Vacio", "kg", 0m);
    storage.SaveToFile();
    int PageSizeValue = (int)movementsType.GetField("PageSize", flags | BindingFlags.Static)!.GetRawConstantValue()!;
    Check(PageSizeValue == 20, "history page size is 20");
    object MovePage(AuthService auth, int id, out TestNavigation nav) { var page = NewPage(movementsType, auth, out nav); movementsType.GetProperty("IngredientId", flags)!.SetValue(page, id); return page; }
    int[] RowIds(object page) => ((System.Collections.IEnumerable)Get(page, "movements")!).Cast<StockMovement>().Select(m => m.Id).ToArray();
    int[] VisibleIds(object page) => ((System.Collections.IEnumerable)Func(page, "VisibleMovements")!).Cast<StockMovement>().Select(m => m.Id).ToArray();

    var guarded = State();
    foreach (var (auth, who, destination) in new[] { (uiAnon, "anonymous", "/login"), (uiEmployee, "employee", "/unauthorized") })
        foreach (var action in new[] { "OnParametersSet", "ApplyFilters", "ClearFilters", "NextPage", "PreviousPage" })
        {
            var page = MovePage(auth, cacao.Id, out var nav);
            var ex = Call(page, action);
            Check(ex == null && nav.Destination == destination && Get(page, "ingredient") == null && RowIds(page).Length == 0 && Get(page, "legacyBalance") == null, who + " " + action + " navigates to " + destination + " and loads nothing");
        }
    Check(State() == guarded, "anonymous and employee history requests change nothing");

    var hp = MovePage(uiAdmin, cacao.Id, out var hnav);
    Check(Call(hp, "OnParametersSet") == null && hnav.Destination == null && ((Ingredient)Get(hp, "ingredient")!).Id == cacao.Id
        && RowIds(hp).SequenceEqual(ingredients.GetMovements(cacao.Id).Select(m => m.Id)) && (int)Get(hp, "pageNumber")! == 1, "admin loads the ingredient and its movements newest first");
    Check(VisibleIds(hp).Length == 20 && VisibleIds(hp).SequenceEqual(RowIds(hp).Take(20)) && (int)Func(hp, "TotalPages")! == 2, "first page shows 20 rows of 2 pages");
    Call(hp, "NextPage");
    Check((int)Get(hp, "pageNumber")! == 2 && VisibleIds(hp).SequenceEqual(RowIds(hp).Skip(20)) && VisibleIds(hp).Length == 5, "NextPage shows the remaining 5 rows");
    Call(hp, "NextPage");
    Check((int)Get(hp, "pageNumber")! == 2, "NextPage stays clamped on the last page");
    Call(hp, "PreviousPage"); Call(hp, "PreviousPage");
    Check((int)Get(hp, "pageNumber")! == 1, "PreviousPage stays clamped on the first page");
    Check(Get(hp, "legacyBalance") == null, "an ingredient whose history starts at zero has no previous balance");

    // Filters: whole days, inclusive on both ends; cause select; combination; reset.
    Set(hp, "filterFrom", new DateTime(2026, 3, 2, 18, 0, 0)); Set(hp, "filterTo", new DateTime(2026, 3, 3, 1, 0, 0));
    Check(Call(hp, "ApplyFilters") == null && RowIds(hp).SequenceEqual(new[] { cm[2].Id, cm[1].Id }) && (int)Get(hp, "pageNumber")! == 1 && Str(hp, "historyError") == null, "date range compares whole days and is inclusive on both ends");
    Set(hp, "filterFrom", new DateTime(2026, 3, 3)); Set(hp, "filterTo", new DateTime(2026, 3, 3));
    Call(hp, "ApplyFilters");
    Check(RowIds(hp).SequenceEqual(new[] { cm[2].Id }), "single-day range");
    Set(hp, "filterFrom", new DateTime(2026, 3, 10)); Set(hp, "filterTo", new DateTime(2026, 3, 2));
    Check(Call(hp, "ApplyFilters") == null && Str(hp, "historyError") == "La fecha inicial no puede ser posterior a la fecha final." && RowIds(hp).Length == 0, "inverted range shows the Spanish error and no rows");
    Check(Call(hp, "ClearFilters") == null && Str(hp, "historyError") == null && Get(hp, "filterFrom") == null && Get(hp, "filterTo") == null && Str(hp, "filterType") == "" && RowIds(hp).Length == 25, "ClearFilters restores the full history");
    Set(hp, "filterType", nameof(StockMovementType.Waste));
    Call(hp, "ApplyFilters");
    Check(RowIds(hp).SequenceEqual(new[] { cm[24].Id, cm[23].Id }), "cause filter lists only that movement type");
    Set(hp, "filterFrom", new DateTime(2026, 3, 25)); Call(hp, "ApplyFilters");
    Check(RowIds(hp).SequenceEqual(new[] { cm[24].Id }), "cause and date filters combine");
    Set(hp, "filterType", "no-such-type"); Call(hp, "ApplyFilters");
    Check(RowIds(hp).Length == 1 && Str(hp, "historyError") == null, "an unknown cause value is ignored");
    Call(hp, "ClearFilters");

    // Row formatting.
    var wasteRow = cm[23]; var adjustRow = cm[3];
    string Signed(decimal q) => q.ToString("+0.####;-0.####;0");
    Check((string)Func(hp, "SignedQuantity", wasteRow)! == Signed(wasteRow.Quantity) + " kg" && (string)Func(hp, "SignedQuantity", cm[2])! == Signed(cm[2].Quantity) + " kg" && Signed(cm[2].Quantity).StartsWith("+") && Signed(wasteRow.Quantity).StartsWith("-"), "quantity shows its sign and unit");
    Check((string)Func(hp, "ResponsibleLabel", cm[0])! == "fixture-admin" && (string)Func(hp, "ResponsibleLabel", new StockMovement { Type = StockMovementType.InvoiceReceipt })! == "Sin registro", "responsible is the username or 'Sin registro'");
    string Origin(StockMovement m) => (string)Func(hp, "OriginText", m)!; string? Href(StockMovement m) => (string?)Func(hp, "OriginHref", m);
    Check(Origin(new StockMovement { Type = StockMovementType.SaleConsumption, SaleId = 5 }) == "Venta #5" && Href(new StockMovement { Type = StockMovementType.SaleConsumption, SaleId = 5 }) == "/sales/history/5", "sale origin links to /sales/history/{id}");
    Check(Origin(new StockMovement { Type = StockMovementType.SaleCancellationReturn, SaleId = 6 }) == "Venta #6" && Href(new StockMovement { Type = StockMovementType.SaleCancellationReturn, SaleId = 6 }) == "/sales/history/6", "cancellation origin links to the sale");
    Check(Origin(new StockMovement { Type = StockMovementType.RefundReturn, SaleId = 7, RefundId = 2 }) == "Devoluci\u00f3n #2 (venta #7)" && Href(new StockMovement { Type = StockMovementType.RefundReturn, SaleId = 7, RefundId = 2 }) == "/sales/history/7", "refund origin links to its sale");
    Check(Origin(new StockMovement { Type = StockMovementType.InvoiceReceipt, InvoiceId = 3 }) == "Factura #3" && Href(new StockMovement { Type = StockMovementType.InvoiceReceipt, InvoiceId = 3 }) == "/invoices", "invoice origin links to the invoices page");
    Check(Origin(new StockMovement { Type = StockMovementType.CountAdjustment, StockCountId = 4 }) == "Conteo #4" && Href(new StockMovement { Type = StockMovementType.CountAdjustment, StockCountId = 4 }) == "/stock/count/4", "count origin links to the count page");
    Check(Origin(adjustRow) == "Manual" && Href(adjustRow) == null && Origin(wasteRow) == "Manual" && Origin(new StockMovement { Type = StockMovementType.InitialStock }) == "Alta del ingrediente", "manual and opening movements have a textual origin");

    // Previous balance without history (L2).
    var la = MovePage(uiAdmin, legacyA.Id, out _); Call(la, "OnParametersSet");
    Check((decimal?)Get(la, "legacyBalance") == 7m && RowIds(la).Length == 0, "no movements but stock: 'saldo previo sin historial' equals the stock");
    var lb = MovePage(uiAdmin, legacyB.Id, out _); Call(lb, "OnParametersSet");
    Check((decimal?)Get(lb, "legacyBalance") == 40m && RowIds(lb).Length == 1, "oldest movement with a nonzero previous stock: that previous stock is the balance without history");
    Set(lb, "filterType", nameof(StockMovementType.Waste)); Call(lb, "ApplyFilters");
    Check((decimal?)Get(lb, "legacyBalance") == 40m && RowIds(lb).Length == 0, "the previous balance does not depend on the active filters");
    var ve = MovePage(uiAdmin, vacio.Id, out _); Call(ve, "OnParametersSet");
    Check(Get(ve, "legacyBalance") == null && RowIds(ve).Length == 0, "no movements and zero stock: nothing to explain");
    var missing = MovePage(uiAdmin, 98765, out var mnav); Call(missing, "OnParametersSet");
    Check(Get(missing, "ingredient") == null && Str(missing, "notFoundMessage") == "No existe un ingrediente con el ID 98765." && mnav.Destination == null && RowIds(missing).Length == 0, "unknown ingredient shows a Spanish message");
    Check(Call(hp, "OnParametersSet") == null && Get(hp, "ingredient") != null, "parameter change reloads");

    // S3: the Movimientos tab keeps working for deleted ingredients (movements are kept, the ingredient is gone).
    var goneId = azucar.Id; var goneMovements = Mv(goneId);
    var gp = MovePage(uiAdmin, goneId, out var gnav);
    Check(Call(gp, "OnParametersSet") == null && gnav.Destination == null && Get(gp, "ingredient") == null && Str(gp, "notFoundMessage") == null && RowIds(gp).SequenceEqual(ingredients.GetMovements(goneId).Select(m => m.Id)) && RowIds(gp).Length == goneMovements.Length,
        "/ingredients/{id}/movements of a deleted ingredient lists its history, without the not-found message and without exceptions");
    Check((string)Func(gp, "IngredientName", goneMovements[0])! == Deleted(goneId) && (string)Func(gp, "DeletedTitle")! == Deleted(goneId) && (bool)Func(gp, "IsDeleted")!, "deleted ingredient: the row and the header show 'Ingrediente eliminado (#id)'");
    Set(gp, "filterType", nameof(StockMovementType.Waste));
    Check(Call(gp, "ApplyFilters") == null && RowIds(gp).Length == goneMovements.Count(m => m.Type == StockMovementType.Waste) && Str(gp, "historyError") == null, "filters keep working on the history of a deleted ingredient");
    var ap2 = (object)NewPage(movementsType, uiAdmin, out _);
    Check(Call(ap2, "OnParametersSet") == null && RowIds(ap2).Length == storage.StockMovements.Count && RowIds(ap2).Intersect(goneMovements.Select(m => m.Id)).Count() == goneMovements.Length,
        "the all-ingredients list includes the movements of deleted ingredients");
    Check(((System.Collections.IEnumerable)Get(ap2, "deletedIds")!).Cast<int>().Contains(goneId) && (string)Func(ap2, "IngredientName", goneMovements[0])! == Deleted(goneId) && (string)Func(ap2, "IngredientName", Mv(cacao.Id)[0])! == "Cacao",
        "the ingredient filter offers deleted ingredients with history and names live ones normally");
    Set(ap2, "filterType", nameof(StockMovementType.Waste));
    Check(Call(ap2, "ApplyFilters") == null && RowIds(ap2).Intersect(goneMovements.Where(m => m.Type == StockMovementType.Waste).Select(m => m.Id)).Any(), "cause filter in the all-ingredients list includes deleted ingredients");
    foreach (var (auth, destination) in new[] { (uiAnon, "/login"), (uiEmployee, "/unauthorized") })
    {
        var np = MovePage(auth, goneId, out var nnav);
        Check(Call(np, "OnParametersSet") == null && nnav.Destination == destination && RowIds(np).Length == 0, "PRESERVE: " + destination + " circuits still load nothing for a deleted ingredient id");
    }

    // Mid-session demotion.
    var dp = MovePage(uiSecond, cacao.Id, out var dnav); Call(dp, "OnParametersSet");
    var loadedBefore = Get(dp, "movements"); admin2.Role = UserRole.Employee;
    try
    {
        foreach (var action in new[] { "OnParametersSet", "ApplyFilters", "ClearFilters", "NextPage", "PreviousPage" })
        {
            dnav.Destination = null; Set(dp, "filterType", nameof(StockMovementType.Waste));
            var ex = Call(dp, action);
            Check(ex == null && dnav.Destination == "/unauthorized" && ReferenceEquals(Get(dp, "movements"), loadedBefore), "demoted admin " + action + " redirects and keeps the loaded data untouched");
        }
    }
    finally { admin2.Role = UserRole.Admin; }

    var src = Src("Pages/IngredientMovements.razor");
    Check(src.Contains("@page \"/ingredients/{IngredientId:int}/movements\"") && src.Contains("Saldo previo sin historial") && src.Contains("StockMovementLabels.GetLabel("), "history page route, previous-balance text and labels");
    Check(src.Contains("Stock negativo: requiere ajuste") && src.Contains("WasteCategory"), "history page warns about negative stock and shows the waste category");
}

// ---- Invoices page: service errors are shown, not thrown ----
if (invoicesType != null)
{
    var ip = NewPage(invoicesType, uiAdmin, out var inav);
    Call(ip, "OnInitializedAsync"); Call(ip, "ShowAddForm");
    var bad = new Invoice { SupplierId = 1, Items = [new InvoiceItem { IngredientId = harina.Id, Quantity = 1m, Unit = "kg" }, new InvoiceItem { IngredientId = viewIngredient.Id, Quantity = 0m, Unit = "kg" }] };
    Set(ip, "editingInvoice", bad); storage.SaveToFile(); var beforeInvoice = State();
    Check(Call(ip, "SaveInvoice") == null && State() == beforeInvoice && Str(ip, "invoiceError")!.Contains("positiva") && (bool)Get(ip, "showForm")!, "an invoice rejected by the service shows its Spanish error and keeps the form");
    var good = new Invoice { SupplierId = 1, InvoiceNumber = "A-9", Items = [new InvoiceItem { IngredientId = harina.Id, IngredientName = "Harina", Quantity = 2m, Unit = "kg", UnitPrice = 10m }] };
    Set(ip, "editingInvoice", good); var harinaBefore = harina.CurrentStock;
    Check(Call(ip, "SaveInvoice") == null && Str(ip, "invoiceError") == null && !(bool)Get(ip, "showForm")! && harina.CurrentStock == harinaBefore + 2m && Mv(harina.Id).Last() is { Type: StockMovementType.InvoiceReceipt, UserId: 10 }, "PRESERVE: a valid invoice is saved with the circuit user and closes the form");
    foreach (var (auth, destination) in new[] { (uiAnon, "/login"), (uiEmployee, "/unauthorized") })
    {
        var np = NewPage(invoicesType, auth, out var nnav); Set(np, "editingInvoice", good); var guardedInvoice = State();
        Check(Call(np, "SaveInvoice") == null && nnav.Destination == destination && State() == guardedInvoice, "PRESERVE: " + destination + " circuits cannot save invoices");
    }
    // S3: invoices keep their stored names; a draft that picked an ingredient deleted meanwhile degrades with the existing messages.
    var ghostId = deletedIds[0];
    Check(Call(ip, "ShowAddForm") == null && Call(ip, "SelectIngredient", ghostId) == null && Str(ip, "itemUnit") == "", "invoices page: picking a deleted ingredient id does not throw and offers no unit");
    Set(ip, "itemQuantityText", "1"); Set(ip, "itemUnitPriceText", "5");
    Check(Call(ip, "AddItem") == null && Str(ip, "builderError") == "El ingrediente seleccionado ya no existe." && ((Invoice)Get(ip, "editingInvoice")!).Items.Count == 0, "invoices page: adding a deleted ingredient shows 'ya no existe' and adds nothing");
    var storedNameItem = new InvoiceItem { IngredientId = ghostId, IngredientName = "Nombre guardado", Quantity = 1m, Unit = "kg", UnitPrice = 5m };
    var blankNameItem = new InvoiceItem { IngredientId = ghostId, IngredientName = "  ", Quantity = 1m, Unit = "kg", UnitPrice = 5m };
    var purchasingFormat = asm.GetType("GastroApp.Shared.Purchasing.PurchasingFormat")!;
    string? ItemName(InvoiceItem item) => (string?)purchasingFormat.GetMethod("ItemName", BindingFlags.Public | BindingFlags.Static)?.Invoke(null, new object[] { item });
    Check(ItemName(storedNameItem) == "Nombre guardado" && ItemName(blankNameItem) == Deleted(ghostId), "invoice lines of a deleted ingredient show the stored name, else 'Ingrediente eliminado (#id)'");
    decimal? lastPriceOfDeleted = -1m; Exception? lastPriceFailure = null;
    try { lastPriceOfDeleted = ingredients.GetLastPrice(ghostId); } catch (Exception ex) { lastPriceFailure = ex; }
    Check(lastPriceFailure == null && lastPriceOfDeleted == invoices.GetLastPriceForIngredient(ghostId) && lastPriceOfDeleted == 0m, "last price of a deleted ingredient comes from its kept invoice lines without throwing");
    var invoicesSource = Src("Pages/Invoices.razor");
    Check(invoicesSource.Contains("InvoiceService.Add(editingInvoice, AuthService.CurrentUser)") && invoicesSource.Contains("catch (Exception ex) when (ex is InvalidOperationException or UnauthorizedAccessException)") && invoicesSource.Contains("@invoiceError"), "Invoices page guards InvoiceService.Add and renders the error");
}

// ---- Docs ----
var stockDoc = File.Exists(Path.Combine(repoRoot, "Docs", "Architecture", "Stock.md")) ? Src("Docs/Architecture/Stock.md") : "";
Check(stockDoc.Contains("## Physical counts") && stockDoc.Contains("Saldo previo sin historial") && stockDoc.Contains("GetStockAlerts") && stockDoc.Contains("negative"), "Stock.md documents the ledger, alerts, negative stock policy, previous balance and a Physical counts heading");
Check(stockDoc.Contains("Ingrediente eliminado (#id)") && stockDoc.Contains("Quitalo de esa receta primero") && !stockDoc.Contains("registros asociados") && stockDoc.Contains("never reused") && stockDoc.Contains("skipped"), "S8: Stock.md documents deleting with history, the recipe block, the deleted-ingredient label and the restock skip");
var salesDoc = Src("Docs/Architecture/Sales.md");
Check(!salesDoc.Contains("still saves after each successful ingredient deduction") && salesDoc.Contains("Stock.md"), "Sales.md no longer describes TryRemoveStock and points to Stock.md");
var features = Src("IMPLEMENTED_FEATURES.md");
Check(features.Contains("Stock.md") && features.Contains("Alertas de stock") && !features.Contains("Administrators can set an ingredient's current stock directly"), "IMPLEMENTED_FEATURES.md describes the stock ledger UI");

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
    & dotnet run --project (Join-Path $ScratchPath 'StockUiChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Stock UI checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
