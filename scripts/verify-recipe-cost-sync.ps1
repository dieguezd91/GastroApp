param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-recipe-cost-sync-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'RecipeCostSyncChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
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
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var admin = storage.Users[0]; var employee = storage.Users[1];
storage.Ingredients = []; storage.Invoices = []; storage.Suppliers = []; storage.ProductCategories = [new ProductCategory { Id = 1, Name = "Comidas" }];
Recipe R(int id, string name, int yield, decimal total, decimal unit) => new() { Id = id, Name = name, Yield = yield, TotalCost = total, UnitCost = unit, LastCalculatedCost = unit };
storage.Recipes = [
    R(1, "Pizza", 1, 100m, 100m),
    R(2, "Flan", 1, 50.004m, 50.004m),          // sub-cent difference: not a drift
    R(3, "Torta", 1, 70m, 70m),                  // identical
    R(5, "Cafe", 5, 0m, 0m),                     // recipe exists but nothing was calculated
    R(6, "Sandwich", 1, 25m, 25m),
    R(7, "Medialunas", 12, 129m, 10.75m),        // yield 12: the unit cost is per portion
    R(8, "Dup", 1, 0m, 0m), R(9, "Dup", 1, 99m, 99m), // first match wins, as in SaleService
    R(10, "Negativa", 1, -5m, -5m),
    R(11, "Redonda", 1, 10.745m, 10.745m)];
storage.Products = [
    new Product { Id = 1, Name = "Pizza", Price = 200m, Cost = 80m, CategoryId = 1, IsActive = true },
    new Product { Id = 2, Name = "Flan", Price = 90m, Cost = 50m },
    new Product { Id = 3, Name = "Torta", Price = 140m, Cost = 70m },
    new Product { Id = 4, Name = "Agua", Price = 30m, Cost = 5m },
    new Product { Id = 5, Name = "Cafe", Price = 60m, Cost = 12m },
    new Product { Id = 6, Name = "Sandwich", Price = 100m, Cost = null, IsActive = false },
    new Product { Id = 7, Name = "Medialunas", Price = 50m, Cost = 9m },
    new Product { Id = 8, Name = "Dup", Price = 150m, Cost = 40m },
    new Product { Id = 9, Name = "pizza", Price = 200m, Cost = 80m },
    new Product { Id = 10, Name = "PIZZA", Price = 200m, Cost = 80m },
    new Product { Id = 11, Name = " Pizza ", Price = 200m, Cost = 80m },
    new Product { Id = 12, Name = "Negativa", Price = 10m, Cost = 3m },
    new Product { Id = 13, Name = "Redonda", Price = 40m, Cost = 10.74m },
    new Product { Id = 14, Name = "Otra Pizza", Price = 200m, Cost = 80m }];
storage.SaveToFile();
var products = new ProductService(storage);
Product P(int id) => storage.Products.First(p => p.Id == id);

string State() => JsonSerializer.Serialize(new { storage.Products, storage.Recipes, storage.Users, storage.ProductCategories, storage.Sales, storage.StockMovements,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
string Snapshot(Product p) => JsonSerializer.Serialize(p);
dynamic? Drift(Product p) { dynamic svc = products; return svc.GetRecipeCostDrift(p); }
string Num(decimal? value) => value?.ToString("0.####", System.Globalization.CultureInfo.InvariantCulture) ?? "";
string DriftText(Product p) { try { var d = Drift(p); return d == null ? "null" : $"{Num((decimal?)d.RecipeCost)}|{Num((decimal?)d.ProductCost)}|{d.HasDrift}"; } catch (Exception ex) { return "<" + ex.GetType().Name + ">"; } }
Exception? Sync(int id, User? actor = null)
{
    try { dynamic svc = products; svc.SyncCostFromRecipe(id, actor); return null; } catch (Exception ex) { return ex; }
}
// A sync that must be rejected: exception type/message, objects, counters and file bytes stay identical.
void RejectSync(int id, User? actor, Type exception, string name, string? message = null)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    var ex = Sync(id, actor);
    Check(ex != null && ex.GetType() == exception && (message == null || ex.Message == message), name + " rejected with " + exception.Name + (message == null ? "" : " / " + message) + (ex != null && ex.GetType() == exception ? "" : " [" + (ex?.GetType().Name ?? "no exception") + " " + ex?.Message.Split((char)10)[0] + "]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")), name + " leaves objects, counters and file bytes unchanged");
}
Product? Reload(int id)
{
    var reloaded = new DataStorageService();
    return reloaded.Products.FirstOrDefault(p => p.Id == id);
}

// ---- S9 service rule: read-only drift ----
Check(typeof(ProductService).GetMethod("GetRecipeCostDrift") != null && typeof(ProductService).GetMethod("SyncCostFromRecipe") != null, "ProductService.GetRecipeCostDrift and SyncCostFromRecipe exist");
var driftType = typeof(ProductService).Assembly.GetTypes().FirstOrDefault(t => t.Name == "RecipeCostDrift");
Check(driftType != null && driftType.GetProperties().All(p => p.SetMethod == null || p.SetMethod.ReturnParameter.GetRequiredCustomModifiers().Length > 0), "RecipeCostDrift result exists and is immutable (init-only)");
var stateBeforeReads = State(); var bytesBeforeReads = File.ReadAllBytes("data.json");
Check(DriftText(P(4)) == "null", "no matching recipe: no drift information");
Check(DriftText(P(5)) == "null", "recipe without calculated cost (unit cost 0): no drift information");
Check(DriftText(P(12)) == "null", "recipe with a negative unit cost: no drift information");
Check(DriftText(P(3)) == "70|70|False", "equal cost: recipe figure reported, no drift");
Check(DriftText(P(2)) == "50.004|50|False", "difference under half a cent (cents rounding): no drift");
Check(DriftText(P(13)) == "10.745|10.74|True", "10.745 rounds to 10.75 against a saved 10.74: drift at the cent boundary");
Check(DriftText(P(1)) == "100|80|True", "different cost: drift with both the recipe and the saved value");
Check(DriftText(P(6)) == "25||True", "product without saved cost and a calculated recipe: drift, saved value null");
Check(DriftText(P(7)) == "10.75|9|True", "recipe yield 12: the figure is the cost PER PORTION (unit cost), not the batch total (129)");
Check(DriftText(P(8)) == "null", "duplicate recipe names: the first match decides, as in SaleService (its cost is 0 -> none)");
Check(DriftText(P(9)) == "null" && DriftText(P(10)) == "null" && DriftText(P(11)) == "null" && DriftText(P(14)) == "null", "name match is exact and ordinal: case, surrounding spaces and prefixes do not match 'Pizza'");
Check(State() == stateBeforeReads && bytesBeforeReads.SequenceEqual(File.ReadAllBytes("data.json")), "GetRecipeCostDrift is read-only");

// ---- S9 service rule: sync ----
const string NoRecipe = "El producto no tiene una receta con costo calculado.";
const string NotAdmin = "Se requiere un usuario administrador vigente.";
RejectSync(4, admin, typeof(InvalidOperationException), "sync without a matching recipe", NoRecipe);
RejectSync(5, admin, typeof(InvalidOperationException), "sync with a recipe without calculated cost", NoRecipe);
RejectSync(9, admin, typeof(InvalidOperationException), "sync of a product whose name differs from the recipe by case", NoRecipe);
RejectSync(11, null, typeof(InvalidOperationException), "sync of a product whose name differs by surrounding spaces", NoRecipe);
RejectSync(98765, admin, typeof(InvalidOperationException), "sync of an unknown product", "El producto no existe.");
RejectSync(1, employee, typeof(UnauthorizedAccessException), "sync by an employee actor", NotAdmin);
RejectSync(1, new User { Id = 10, Username = "fixture-admin", PasswordHash = "stale", Role = UserRole.Admin }, typeof(UnauthorizedAccessException), "sync by a stale admin actor", NotAdmin);

var othersBefore = storage.Products.Where(p => p.Id != 1).Select(Snapshot).ToArray();
var marginBefore = P(1).Margin;
var recipesBefore = JsonSerializer.Serialize(storage.Recipes);
var syncError = Sync(1, admin);
Check(syncError == null && P(1).Cost == 100m, "sync sets Cost exactly to the recipe figure [" + syncError?.Message + "]");
Check(P(1).Name == "Pizza" && P(1).Price == 200m && P(1).CategoryId == 1 && P(1).IsActive && P(1).Id == 1, "sync changes nothing but Cost on the product");
Check(storage.Products.Where(p => p.Id != 1).Select(Snapshot).SequenceEqual(othersBefore) && JsonSerializer.Serialize(storage.Recipes) == recipesBefore, "sync changes no other product and no recipe");
Check(marginBefore == 60m && P(1).Margin == 50m, "margin recomputes from the new cost (60% -> 50%)");
Check(DriftText(P(1)) == "100|100|False", "after the sync there is no drift");
var reloaded = Reload(1);
Check(reloaded != null && reloaded.Cost == 100m && reloaded.Name == "Pizza" && reloaded.Price == 200m && reloaded.CategoryId == 1, "sync persists: a fresh load of data.json has the new cost");
Check(Reload(7)!.Cost == 9m && Reload(2)!.Cost == 50m, "other products stay as saved in the file");
var cleanSync = Sync(6); // no actor: allowed (trusted in-process call), cost was null
Check(cleanSync == null && P(6).Cost == 25m && !P(6).IsActive && Reload(6)!.Cost == 25m, "sync fills a missing cost without touching IsActive; actor is optional");
Check(Sync(7, admin) == null && P(7).Cost == 10.75m && P(7).Cost != 129m && Reload(7)!.Cost == 10.75m, "sync of a yield-12 recipe stores the per-portion cost");
Check(Sync(13, admin) == null && P(13).Cost == 10.745m && DriftText(P(13)) == "10.745|10.745|False", "sync stores the unrounded recipe figure");
var again = State();
Check(Sync(1, admin) == null && P(1).Cost == 100m && State() == again, "syncing a product without drift is harmless (idempotent)");

// ---- Real pipeline: RecipeService.CalculateCosts feeds the drift ----
var invoices = new InvoiceService(storage); var ingredientService = new IngredientService(storage, invoices); invoices.SetIngredientService(ingredientService);
var recipeService = new RecipeService(storage, invoices);
foreach (var counter in new[] { "_nextProductId", "_nextRecipeId" }) typeof(DataStorageService).GetField(counter, flags)!.SetValue(storage, 100); // fixture ids are explicit; new rows must not collide
var flour = new Ingredient { Id = 901, Name = "Harina", Unit = "kg", IsActive = true }; storage.Ingredients.Add(flour);
storage.Invoices.Add(new Invoice { Id = 901, Date = DateTime.Today, Items = [new InvoiceItem { IngredientId = 901, Quantity = 10m, Unit = "kg", UnitPrice = 100m }] });
var calculated = new Recipe { Name = "Pan", Yield = 4, Ingredients = [new RecipeIngredient { IngredientId = 901, Quantity = 1m, Unit = "kg" }] };
recipeService.Add(calculated);
var pan = new Product { Name = "Pan", Price = 80m, Cost = 20m, IsActive = true }; products.Add(pan);
Check(calculated.UnitCost == 25m && DriftText(pan) == "25|20|True", "a recipe calculated by RecipeService (1 kg at $100 / 4 portions) drifts against a saved cost of 20 with figure 25");
Check(Sync(pan.Id, admin) == null && pan.Cost == 25m && Reload(pan.Id)!.Cost == 25m && pan.Margin == 68.75m, "sync from a calculated recipe persists the per-portion cost and the margin follows");
storage.Invoices.Add(new Invoice { Id = 902, Date = DateTime.Today.AddDays(1), Items = [new InvoiceItem { IngredientId = 901, Quantity = 1m, Unit = "kg", UnitPrice = 200m }] });
recipeService.RecalculateAllCosts();
Check(DriftText(pan) == "50|25|True", "after prices change and the recipe is recalculated, the product drifts again (50 vs 25)");

// ---- PRESERVE ----
Exception? Thrown(Action action) { try { action(); return null; } catch (Exception ex) { return ex; } }
products.Update(new Product { Id = 4, Name = "Agua", Price = 33m, Cost = 7m, CategoryId = 1, IsActive = false });
Check(P(4).Price == 33m && P(4).Cost == 7m && P(4).CategoryId == 1 && !P(4).IsActive && Reload(4)!.Cost == 7m, "PRESERVE: ProductService.Update still saves price, cost, category and active state");
var unknownState = State(); products.Update(new Product { Id = 98765, Name = "Nada", Price = 1m });
Check(State() == unknownState, "PRESERVE: Update of an unknown product stays a no-op");
Check(Thrown(() => products.Update(new Product { Id = 4, Name = "Agua", Price = 33m, CategoryId = 777 })) is ArgumentException, "PRESERVE: Update with a missing category still throws ArgumentException");

// ---- Page and seam ----
var asm = typeof(ProductService).Assembly;
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
    void Inject(string name, object value) { var p = type.GetProperty(name, flags); p?.SetValue(page, value); }
    Inject("AuthService", auth); Inject("Navigation", nav); Inject("ProductService", products); Inject("CategoryService", new ProductCategoryService(storage));
    return page;
}
Exception? Call(object page, string method, params object?[] arguments)
{
    try
    {
        var target = page.GetType().GetMethod(method, flags | BindingFlags.DeclaredOnly);
        if (target == null) return new MissingMethodException(page.GetType().Name + "." + method);
        var result = target.Invoke(page, arguments);
        if (result is Task task) task.GetAwaiter().GetResult();
        return null;
    }
    catch (TargetInvocationException ex) { return ex.InnerException; }
}
object? Get(object page, string field) => page.GetType().GetField(field, flags)!.GetValue(page);

var pageType = asm.GetType("GastroApp.Pages.Products");
Check(pageType != null, "Products page type exists");
if (pageType != null)
{
    var members = new[] { "ShowAddForm", "EditProduct", "SaveProduct", "DeleteProduct" };
    Check(members.All(m => pageType.GetMethod(m, flags | BindingFlags.DeclaredOnly) != null) && pageType.GetProperty("AuthService", flags) != null && pageType.GetProperty("Navigation", flags) != null,
        "PRESERVE: reflection-pinned members of the Products page (ShowAddForm, EditProduct, SaveProduct, DeleteProduct, AuthService, Navigation)");
    P(1).Cost = 80m; storage.Recipes.First(r => r.Name == "Pizza").UnitCost = 100m; storage.SaveToFile(); // RecalculateAllCosts above zeroed the ingredient-less fixture recipes
    var uiAnon = NewAuth(null); var uiEmployee = NewAuth("fixture-employee"); var uiAdmin = NewAuth("fixture-admin");
    var guarded = State(); var guardedBytes = File.ReadAllBytes("data.json");
    foreach (var (auth, who, destination) in new[] { (uiAnon, "anonymous", "/login"), (uiEmployee, "employee", "/unauthorized") })
    {
        var page = NewPage(pageType, auth, out var nav);
        var ex = Call(page, "SyncProductCost", P(1));
        Check(ex == null && nav.Destination == destination && State() == guarded && guardedBytes.SequenceEqual(File.ReadAllBytes("data.json")), who + " SyncProductCost navigates to " + destination + " and changes nothing [" + ex?.Message + "]");
    }
    var admin1 = NewPage(pageType, uiAdmin, out var adminNav);
    Check(Call(admin1, "OnInitializedAsync") == null, "admin page initializes");
    var noRecipe = Call(admin1, "SyncProductCost", P(4));
    Check(noRecipe == null && (string?)Get(admin1, "errorMessage") == "El producto no tiene una receta con costo calculado." && State() == guarded, "admin sync of a product without recipe cost shows the Spanish service error and changes nothing [" + noRecipe?.Message + "]");
    var okSync = Call(admin1, "SyncProductCost", P(1));
    Check(okSync == null && adminNav.Destination == null && P(1).Cost == 100m && string.IsNullOrEmpty((string?)Get(admin1, "errorMessage")) && Reload(1)!.Cost == 100m, "admin SyncProductCost updates the cost, persists it and clears the error [" + okSync?.Message + "]");
}
var catalog = Src("Pages/Products.razor");
Check(catalog.Contains("<ProductCostDrift") && catalog.Contains("RecipeCost=") && catalog.Contains("ProductService.GetRecipeCostDrift(") && catalog.Contains("ProductService.SyncCostFromRecipe(") && catalog.Contains("AuthService.CurrentUser"),
    "Products page wires the drift seam to the service rule and passes the circuit user");
var seam = Src("Shared/Catalog/ProductCostDrift.razor");
Check(seam.Contains("Sincronizar costo") && seam.Contains("nombre exacto") && seam.Contains("ProductCost") && seam.Contains("RecipeCost"), "the drift warning shows both values, the one-click 'Sincronizar costo' and the exact-name contract");

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
    & dotnet run --project (Join-Path $ScratchPath 'RecipeCostSyncChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Recipe cost sync checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
