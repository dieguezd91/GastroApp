param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-pos-availability-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'PosAvailabilityChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
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
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin }];
var admin = storage.Users[0];
storage.Ingredients = [
    new Ingredient { Id = 1, Name = "Harina", Unit = "kg", CurrentStock = 10m },
    new Ingredient { Id = 2, Name = "Huevos", Unit = "unidad", CurrentStock = 20m },
    new Ingredient { Id = 3, Name = "Leche", Unit = "lt", CurrentStock = 5m },
    new Ingredient { Id = 4, Name = "Sal", Unit = "gr", CurrentStock = 1000m },
    new Ingredient { Id = 5, Name = "Jugo", Unit = "ml", CurrentStock = 1000m },
    new Ingredient { Id = 6, Name = "Azucar", Unit = "kg", CurrentStock = 0m }];
var harina = storage.Ingredients[0]; var huevos = storage.Ingredients[1];
storage.Products = [
    new Product { Id = 1, Name = "Pizza", Price = 100m }, new Product { Id = 2, Name = "Flan", Price = 50m },
    new Product { Id = 3, Name = "Agua", Price = 10m }, new Product { Id = 4, Name = "Torta", Price = 70m },
    new Product { Id = 5, Name = "Cafe", Price = 30m }, new Product { Id = 6, Name = "Sazonado", Price = 20m },
    new Product { Id = 7, Name = "Licuado", Price = 40m }, new Product { Id = 8, Name = "Dulce", Price = 25m },
    new Product { Id = 9, Name = "Raro", Price = 15m }];
RecipeIngredient RI(int recipeId, int ingredientId, decimal quantity, string unit) => new() { RecipeId = recipeId, IngredientId = ingredientId, Quantity = quantity, Unit = unit };
storage.Recipes = [
    new Recipe { Id = 1, Name = "Pizza", Ingredients = [RI(1, 1, 0.5m, "kg"), RI(1, 2, 2m, "unidad")] },
    new Recipe { Id = 2, Name = "Flan", Ingredients = [RI(2, 2, 3m, "unidad")] },
    new Recipe { Id = 4, Name = "Torta", Ingredients = [RI(4, 1, 0.5m, "kg")] },
    new Recipe { Id = 5, Name = "Cafe", Ingredients = [RI(5, 3, 200m, "ml")] },
    new Recipe { Id = 6, Name = "Sazonado", Ingredients = [RI(6, 4, 0.25m, "kg")] },
    new Recipe { Id = 7, Name = "Licuado", Ingredients = [RI(7, 5, 0.3m, "lt")] },
    new Recipe { Id = 8, Name = "Dulce", Ingredients = [RI(8, 6, 1m, "kg")] },
    new Recipe { Id = 9, Name = "Raro", Ingredients = [RI(9, 1, 1m, "unidad")] }]; // incompatible unit: skipped like checkout does
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
var recipes = new RecipeService(storage, invoices);
var sales = new SaleService(storage);
sales.SetRecipeService(recipes); sales.SetIngredientService(ingredients);
var cash = new CashRegisterService(storage, sales);
Product P(string name) => storage.Products.First(p => p.Name == name);
SaleItem Line(string name, int q) { var p = P(name); return new() { ProductId = p.Id, ProductName = p.Name, Price = p.Price, Quantity = q }; }
SalePayment CashPay(decimal a) => new() { PaymentMethod = PaymentMethod.Cash, Amount = a, ReceivedAmount = a };

string State() => JsonSerializer.Serialize(new { storage.CurrentCashRegisterId, storage.CashRegisters, storage.CashMovements, storage.Sales,
    storage.Products, storage.Ingredients, storage.Recipes, storage.StockMovements,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });

// The API under test is called dynamically so a missing method fails checks instead of the whole compile (RED).
const int Missing = -999;
(int? Max, string? Ingredient, bool Reserved) Avail(List<SaleItem> cart, string product)
{
    try
    {
        dynamic a = ((dynamic)sales).GetAvailability(cart, P(product));
        return ((int?)a.MaxAdditionalUnits, (string?)a.LimitingIngredient, (bool)a.ReservedByCart);
    }
    catch (Exception) { return (Missing, "<GetAvailability missing>", false); }
}
int? MaxQty(List<SaleItem> cart, SaleItem item)
{
    try { return (int?)((dynamic)sales).GetMaxQuantity(cart, item); }
    catch (Exception) { return Missing; }
}
bool Unlimited(List<SaleItem> cart, string product) { var a = Avail(cart, product); return a.Max == null && a.Ingredient == null; }
bool Is(List<SaleItem> cart, string product, int max, string? ingredient = null)
{ var a = Avail(cart, product); return a.Max == max && (ingredient == null || a.Ingredient == ingredient); }

// ---- Surface ----
Check(typeof(SaleService).GetMethod("GetAvailability") != null, "SaleService.GetAvailability exists");
Check(typeof(SaleService).GetMethod("GetMaxQuantity") != null, "SaleService.GetMaxQuantity exists");
storage.SaveToFile();
var stateBefore = State(); var bytesBefore = File.ReadAllBytes("data.json");

// ---- Products without a matching recipe stay unlimited ----
var empty = new List<SaleItem>();
Check(Unlimited(empty, "Agua"), "no recipe: unlimited (null max, no limiting ingredient)");
Check(MaxQty([Line("Agua", 3)], Line("Agua", 3)) == null && Unlimited([Line("Agua", 500)], "Agua"), "no recipe: the cart line has no cap either");
Check(Unlimited(empty, "Raro"), "recipe whose unit is incompatible with the ingredient is skipped like checkout does: unlimited");

// ---- Enough stock: max = floor of the tightest ingredient ----
Check(Is(empty, "Pizza", 10, "Huevos"), "empty cart: Pizza max = min(10/0.5, 20/2) = 10, limited by Huevos");
Check(Is(empty, "Flan", 6, "Huevos"), "empty cart: Flan max = floor(20/3) = 6 (floor, not round)");
Check(Is(empty, "Torta", 20, "Harina"), "empty cart: Torta max = 10/0.5 = 20, limited by Harina");
Check(!Avail(empty, "Pizza").Reserved, "empty cart: nothing is reserved by the cart");

// ---- The cart reserves stock ----
var cart = new List<SaleItem> { Line("Pizza", 4) };
Check(Is(cart, "Pizza", 6, "Huevos") && Is(cart, "Flan", 4, "Huevos") && Is(cart, "Torta", 16, "Harina"),
    "cart with 4 Pizza reserves 2 kg Harina and 8 Huevos: Pizza 6, Flan 4, Torta 16 more");
Check(Avail(cart, "Pizza").Reserved && Avail(cart, "Flan").Reserved, "limited by an ingredient the cart already reserves: ReservedByCart");
Check(MaxQty(cart, cart[0]) == 10, "line cap is the line's total allowed quantity (4 in cart + 6 more = 10)");
Check(MaxQty(cart, Line("Pizza", 7)) == 10, "line cap of a candidate copy (same product, other quantity) ignores the original line's quantity");
Check(Unlimited(cart, "Agua"), "products without recipe stay unlimited while the cart reserves stock");

// ---- Products sharing an ingredient reserve from the same pool ----
var shared = new List<SaleItem> { Line("Pizza", 4), Line("Flan", 4) }; // Huevos: 8 + 12 = 20 of 20
Check(Is(shared, "Pizza", 0, "Huevos") && Is(shared, "Flan", 0, "Huevos"), "Pizza 4 + Flan 4 consume every Huevos: both blocked naming Huevos");
Check(Is(shared, "Torta", 16, "Harina"), "a product that does not use the exhausted pool (Torta: Harina, 2 kg reserved) stays available");
Check(MaxQty(shared, shared[0]) == 4 && MaxQty(shared, shared[1]) == 4, "at the cap each line may keep its quantity but not grow (4 and 4)");
var sharedFlan = new List<SaleItem> { Line("Flan", 2), Line("Pizza", 2) }; // Huevos reserved 6 + 4 = 10
Check(Is(sharedFlan, "Flan", 3, "Huevos") && Is(sharedFlan, "Pizza", 5, "Huevos"), "Flan 2 + Pizza 2 reserve 10 Huevos: Flan floor(10/3) = 3 more, Pizza 5 more");
Check(MaxQty(sharedFlan, sharedFlan[0]) == 5 && MaxQty(sharedFlan, sharedFlan[1]) == 7, "line caps take the other lines' reservation into account (Flan 2+3, Pizza 2+5)");
var harinaCart = new List<SaleItem> { Line("Pizza", 2), Line("Torta", 4) }; // Harina reserved 1 + 2 = 3 of 10
Check(Is(harinaCart, "Torta", 14, "Harina") && Is(harinaCart, "Pizza", 8, "Huevos"),
    "Pizza and Torta share Harina: 3 kg reserved, 7 kg left -> Torta 14 more; Pizza limited by Huevos (16 / 2 = 8)");

// ---- Unit conversion (kg<->gr, lt<->ml) ----
Check(Is(empty, "Sazonado", 4, "Sal"), "recipe in kg over an ingredient in gr: 0.25 kg = 250 gr, stock 1000 gr -> 4");
Check(Is(empty, "Cafe", 25, "Leche"), "recipe in ml over an ingredient in lt: 200 ml = 0.2 lt, stock 5 lt -> 25");
Check(Is([Line("Cafe", 10)], "Cafe", 15, "Leche"), "cart reserves in the ingredient's unit: 10 Cafe reserve 2 lt -> 15 more");
Check(Is(empty, "Licuado", 3, "Jugo"), "recipe in lt over an ingredient in ml: 0.3 lt = 300 ml, stock 1000 ml -> 3");

// ---- Zero or insufficient stock: blocked, naming the ingredient ----
Check(Is(empty, "Dulce", 0, "Azucar"), "ingredient without stock: blocked, naming Azucar");
huevos.CurrentStock = 2m;
Check(Is(empty, "Flan", 0, "Huevos") && Is(empty, "Pizza", 1, "Huevos"), "insufficient stock for one more unit (2 < 3 Huevos): Flan blocked; Pizza 1 left");
huevos.CurrentStock = -4m; // legacy negative balance
Check(Is(empty, "Flan", 0, "Huevos"), "negative legacy stock: blocked, never a negative max");
huevos.CurrentStock = 20m;
harina.IsActive = false;
Check(Is(empty, "Torta", 20, "Harina"), "the ingredient's active flag does not change availability (checkout does not look at it either)");
harina.IsActive = true;

// ---- Never diverges from checkout: max is accepted by ValidateStock and max+1 is rejected ----
List<SaleItem> WithQuantity(List<SaleItem> baseCart, string product, int total)
{
    var copy = baseCart.Select(i => new SaleItem { ProductId = i.ProductId, ProductName = i.ProductName, Price = i.Price, Quantity = i.Quantity }).ToList();
    var existing = copy.FirstOrDefault(i => i.ProductName == product);
    if (existing != null) existing.Quantity = total; else copy.Add(Line(product, total));
    return copy;
}
var carts = new List<List<SaleItem>> { empty, cart, shared, sharedFlan, harinaCart, new List<SaleItem> { Line("Cafe", 10), Line("Sazonado", 1) } };
bool consistent = true; var diverged = new List<string>();
foreach (var c in carts)
    foreach (var product in new[] { "Pizza", "Flan", "Torta", "Cafe", "Sazonado", "Licuado", "Dulce", "Agua", "Raro" })
    {
        var a = Avail(c, product);
        var current = c.FirstOrDefault(i => i.ProductName == product)?.Quantity ?? 0;
        if (a.Max == Missing) { consistent = false; diverged.Add(product + " missing API"); continue; }
        if (a.Max == null) { if (!sales.ValidateStock(WithQuantity(c, product, current + 50)).IsValid) { consistent = false; diverged.Add(product + " unlimited but rejected"); } continue; }
        var atMax = current + a.Max.Value == 0 || sales.ValidateStock(WithQuantity(c, product, current + a.Max.Value)).IsValid;
        var overMax = !sales.ValidateStock(WithQuantity(c, product, current + a.Max.Value + 1)).IsValid;
        if (!atMax || !overMax) { consistent = false; diverged.Add($"{product} max {a.Max}: atMax={atMax} overMax={overMax}"); }
    }
Check(consistent, "max additional units is exactly what ValidateStock accepts (max fits, max+1 is rejected) over 6 carts x 9 products" + (consistent ? "" : " [" + string.Join("; ", diverged) + "]"));
var lineCapsOk = true;
foreach (var c in carts)
    foreach (var line in c)
    {
        var cap = MaxQty(c, line);
        if (cap == Missing) { lineCapsOk = false; continue; }
        if (cap == null) continue;
        lineCapsOk &= sales.ValidateStock(WithQuantity(c, line.ProductName, cap.Value)).IsValid && !sales.ValidateStock(WithQuantity(c, line.ProductName, cap.Value + 1)).IsValid;
    }
Check(lineCapsOk, "line cap = largest quantity ValidateStock accepts for that line (cap fits, cap+1 is rejected)");

// ---- Read-only ----
Check(State() == stateBefore && bytesBefore.SequenceEqual(File.ReadAllBytes("data.json")), "availability queries change no stock, sale, counter or file bytes");
var cartSnapshot = JsonSerializer.Serialize(cart);
_ = Avail(cart, "Pizza"); _ = MaxQty(cart, cart[0]);
Check(JsonSerializer.Serialize(cart) == cartSnapshot, "the cart passed in is not mutated");

// ---- Checkout stays the second line of defense (unchanged) ----
cash.Open(100m);
void Rejects(Sale sale, string name, string contains)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json"); var saleCount = storage.Sales.Count;
    string message = ""; bool rejected = false;
    try { sales.Add(sale, admin); } catch (InvalidOperationException ex) { rejected = ex.Message == contains; message = ex.Message; }
    var (valid, validation) = sales.ValidateSale(sale);
    Check(rejected && !valid && validation == contains, name + " rejected: " + contains + (rejected ? "" : " [" + message + "]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")) && storage.Sales.Count == saleCount, name + " leaves stock, ledger, sales, counters and file bytes unchanged");
}
Sale Checkout(List<SaleItem> items) { var total = items.Sum(i => i.Subtotal); return new Sale { Items = items, Payments = [CashPay(total)] }; }
var fullCart = new List<SaleItem> { Line("Pizza", 10) }; // the cart was filled up to the max (10, see the empty-cart check)
huevos.CurrentStock = 5m; // stock changed after the cart was filled
Rejects(Checkout(fullCart), "checkout of a cart that exceeds the stock that changed after it was filled", "Stock insuficiente de Huevos. Disponible: 5 unidad");
Check(Is(empty, "Pizza", 2, "Huevos"), "the catalog reflects the changed stock immediately (Pizza 2 left)");
huevos.CurrentStock = 20m;
Rejects(Checkout([Line("Pizza", 11)]), "checkout over the max", "Stock insuficiente de Huevos. Disponible: 20 unidad");
var good = Checkout([Line("Pizza", 10)]);
sales.Add(good, admin);
Check(good.Id > 0 && huevos.CurrentStock == 0m && harina.CurrentStock == 5m && storage.Sales.Count == 1, "checkout at the max succeeds and deducts every ingredient");
Check(Is(empty, "Pizza", 0, "Huevos") && Is(empty, "Flan", 0, "Huevos") && Is(empty, "Torta", 10, "Harina"), "after the sale the catalog is blocked on Huevos and Torta still has 10");

// ---- UI wiring (source checks) ----
var page = Src("Pages/Sales.razor");
Check(page.Contains("SaleService.GetAvailability(") && page.Contains("SaleService.GetMaxQuantity("), "Sales.razor asks SaleService for availability and the line cap");
Check(!page.Contains("=> TileAvailability.Available;") && !page.Contains("MaxQuantityOf(SaleItem item) => null;"), "Sales.razor no longer uses the no-op seams");
Check(page.Contains("IsBlocked: true"), "Sales.razor builds a blocked TileAvailability");

Console.WriteLine($"{checks} checks, {failures} failures; fixture: {root}");
return failures == 0 ? 0 : 1;
'@ | Set-Content (Join-Path $ScratchPath 'Program.cs') -Encoding utf8
$exitCode = 1
Push-Location $ScratchPath
try {
    & dotnet run --project (Join-Path $ScratchPath 'PosAvailabilityChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "POS availability checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
