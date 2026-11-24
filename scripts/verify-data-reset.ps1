param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-data-reset-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'DataResetChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var root = Directory.GetCurrentDirectory();   // Process cwd is ALWAYS the newly allocated temp directory.
var repoRoot = args[0];
string Src(string path) => File.ReadAllText(Path.Combine(repoRoot, path.Replace('/', Path.DirectorySeparatorChar)));

// ---- PRESERVE: a directory without data.json is still seeded (fresh install) ----
var storage = new DataStorageService();
Check(storage.Products.Count == 3 && storage.Users.Count == 1 && storage.Users[0].Username == "admin" && File.Exists("data.json"), "PRESERVE: a fresh directory seeds the demo products and the default admin and saves data.json");

var users = new UserService(storage);
var categories = new ProductCategoryService(storage);
var products = new ProductService(storage);
var suppliers = new SupplierService(storage);
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
invoices.SetIngredientService(ingredients);
var recipes = new RecipeService(storage, invoices);
var sales = new SaleService(storage);
sales.SetRecipeService(recipes); sales.SetIngredientService(ingredients);
var cash = new CashRegisterService(storage, sales);
var counts = new StockCountService(storage, ingredients);
var resetService = new DataResetService(storage);

users.Add(new User { Username = "second-admin", PasswordHash = "fixture-pass", Role = UserRole.Admin });
users.Add(new User { Username = "fixture-employee", PasswordHash = "fixture-pass", Role = UserRole.Employee });
var admin = users.GetByUsername("admin")!;
var adminHash = admin.PasswordHash;
int round = 0;
string FixtureCuit(int n) { for (var k = n; ; k++) { var ten = "20" + k.ToString("D8"); int[] w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]; var sum = 0; for (var i = 0; i < 10; i++) sum += (ten[i] - (char)48) * w[i]; var check = 11 - sum % 11; if (check == 10) continue; return ten + (check == 11 ? 0 : check); } }

// Fills EVERY collection through the public services (plus the refund ledger) and leaves a register open.
void Populate()
{
    round++;
    var a = users.GetByUsername("admin")!;
    var category = new ProductCategory { Name = "Bebidas " + round }; categories.Add(category);
    var product = new Product { Name = "Café fixture " + round, Price = 150m, Cost = 50m, CategoryId = category.Id }; products.Add(product);
    // Purchase invoices need the business condition and a supplier with fiscal data (Monotributista supplier: factura C, no VAT fields).
    storage.BusinessSettings.TaxCondition = TaxCondition.ResponsableInscripto;
    var supplier = new Supplier { Name = "Proveedor " + round, Cuit = FixtureCuit(round * 100), TaxCondition = TaxCondition.Monotributista }; suppliers.Add(supplier);
    var ingredient = new Ingredient { Name = "Harina fixture " + round, Unit = "kg", MinStock = 1m }; ingredients.Add(ingredient, a);
    ingredients.AdjustStock(ingredient.Id, 10m, "fixture", a);
    invoices.Add(new Invoice { Date = DateTime.Now, SupplierId = supplier.Id, Type = InvoiceType.C, InvoiceNumber = "A-" + round,
        Items = [new InvoiceItem { IngredientId = ingredient.Id, IngredientName = ingredient.Name, Quantity = 2m, Unit = "kg", UnitPrice = 80m }] }, a);
    recipes.Add(new Recipe { Name = "Pan fixture " + round, Yield = 1,
        Ingredients = [new RecipeIngredient { IngredientId = ingredient.Id, IngredientName = ingredient.Name, Quantity = 0.5m, Unit = "kg" }] });
    counts.Confirm(new StockCountRequest { Confirmed = true, Lines = [new StockCountLineInput { IngredientId = ingredient.Id,
        CountedStock = ingredient.CurrentStock + 1m, ExpectedStock = ingredient.CurrentStock, Reason = "fixture" }] }, a);
    cash.Open(100m);
    var sale = new Sale { Items = [new SaleItem { ProductId = product.Id, ProductName = product.Name, Price = product.Price, Quantity = 1 }],
        Payments = [new SalePayment { PaymentMethod = PaymentMethod.Cash, Amount = product.Price, ReceivedAmount = product.Price }] };
    sales.Add(sale, a);
    cash.AddManualMovement(CashMovementType.Income, 10m, "fixture", a);
    storage.SaleRefunds.Add(new SaleRefund { Id = storage.GetNextSaleRefundId(), SaleId = sale.Id, Date = DateTime.Now, UserId = a.Id, Username = a.Username, Reason = "fixture",
        Lines = [new SaleRefundLine { SaleItemIndex = 0, Quantity = 1, Disposition = RefundDisposition.Waste, Amount = product.Price }],
        Payments = [new SaleRefundPayment { PaymentMethod = PaymentMethod.Cash, Amount = product.Price }], Total = product.Price });
    var review = cash.GetCountReview();
    cash.Close(new CashCountRequest { Review = review, Lines = [new CashCountLineInput(review.ExpectedAmount, 1)], Confirmed = true }, a);
    cash.Open(50m); // the current register stays open
    storage.SaveToFile();
}
Populate();

string[] Collections = ["Products", "ProductCategories", "Sales", "SaleRefunds", "StockMovements", "StockCounts", "CashRegisters",
    "CashMovements", "CashCounts", "Summaries", "Users", "Ingredients", "Suppliers", "Invoices", "Recipes"];
JsonElement FileRoot(byte[] bytes) => JsonDocument.Parse(bytes).RootElement.Clone();
string Counters(DataStorageService? s = null) => string.Join(",", typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).OrderBy(f => f.Name).Select(f => f.Name + "=" + f.GetValue(s ?? storage)));
string State(DataStorageService? s = null) { s ??= storage; return JsonSerializer.Serialize(new { s.Products, s.ProductCategories, s.Sales, s.SaleRefunds, s.StockMovements, s.StockCounts,
    s.CashRegisters, s.CashMovements, s.CashCounts, s.CurrentCashRegisterId, s.Summaries, s.Users, s.Ingredients, s.Suppliers,
    s.Invoices, s.Recipes, Counters = Counters(s) }); }
string[] Backups() => Directory.GetFiles(root, "data.backup-*.json").Select(Path.GetFileName).ToArray()!;

var populatedBytes = File.ReadAllBytes("data.json");
var populated = FileRoot(populatedBytes);
Check(Collections.All(c => populated.GetProperty(c).GetArrayLength() > 0) && populated.GetProperty("CurrentCashRegisterId").ValueKind == JsonValueKind.Number,
    "fixture: every collection is populated and a register is current [" + string.Join(",", Collections.Where(c => populated.GetProperty(c).GetArrayLength() == 0)) + "]");
Check(Backups().Length == 0, "fixture: no backup files exist yet");

// ---- S6: rejected actors change nothing ----
void Reject(Func<object?> action, string name)
{
    var state = State(); var bytes = File.ReadAllBytes("data.json"); var backupsBefore = Backups();
    bool rejected = false; string message = "";
    try { action(); } catch (UnauthorizedAccessException ex) { rejected = true; message = ex.Message; }
    catch (Exception ex) { message = ex.GetType().Name + ": " + ex.Message; }
    Check(rejected, name + " rejected with UnauthorizedAccessException" + (rejected ? "" : " [" + message + "]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")) && Backups().SequenceEqual(backupsBefore), name + " leaves memory, data.json bytes and backups untouched");
}
var second = users.GetByUsername("second-admin")!; var employee = users.GetByUsername("fixture-employee")!;
User Clone(User u, Action<User>? change = null) { var c = new User { Id = u.Id, Username = u.Username, PasswordHash = u.PasswordHash, Role = u.Role }; change?.Invoke(c); return c; }
Reject(() => resetService.ResetAll(null), "anonymous (null actor)");
Reject(() => resetService.ResetAll(employee), "employee");
Reject(() => resetService.ResetAll(Clone(admin, u => u.Role = UserRole.Employee)), "actor claiming a role the stored user does not have");
Reject(() => resetService.ResetAll(Clone(admin, u => u.PasswordHash = second.PasswordHash)), "stale admin (changed password hash)");
Reject(() => resetService.ResetAll(Clone(admin, u => u.Username = "renamed")), "stale admin (changed username)");
Reject(() => resetService.ResetAll(Clone(admin, u => u.Id = 999)), "admin that does not exist");
admin.Role = UserRole.Employee;
Reject(() => resetService.ResetAll(Clone(admin, u => u.Role = UserRole.Admin)), "admin demoted in storage");
admin.Role = UserRole.Admin;

// ---- S7: failing backup aborts, nothing changes ----
{
    var state = State(); var bytes = File.ReadAllBytes("data.json"); bool rejected = false; string message = "";
    using (var locked = new FileStream("data.json", FileMode.Open, FileAccess.Read, FileShare.None))
    {
        try { resetService.ResetAll(admin); } catch (InvalidOperationException ex) { rejected = true; message = ex.Message; }
        catch (Exception ex) { message = ex.GetType().Name + ": " + ex.Message; }
    }
    Check(rejected, "backup that cannot be written (data.json locked) aborts with InvalidOperationException [" + message + "]");
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")) && Backups().Length == 0, "failed backup leaves memory and data.json untouched and no backup file");
}
{
    // data.json cannot be replaced (read-only): the backup succeeds, the final write fails; everything must be rolled back.
    var state = State(); var bytes = File.ReadAllBytes("data.json"); bool rejected = false; string message = "";
    File.SetAttributes("data.json", FileAttributes.ReadOnly);
    try { resetService.ResetAll(admin); } catch (InvalidOperationException ex) { rejected = true; message = ex.Message; }
    catch (Exception ex) { message = ex.GetType().Name + ": " + ex.Message; }
    finally { File.SetAttributes("data.json", FileAttributes.Normal); }
    Check(rejected, "final write that fails aborts with InvalidOperationException [" + message + "]");
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")) && Backups().Length == 0 && Directory.GetFiles(root, "*.tmp").Length == 0,
        "failed final write leaves memory and data.json untouched and no backup or temp file behind");
}

// ---- S5/S7: successful reset ----
var countersBefore = Counters();
var circuitAdmin = new AuthService(users); var circuitSecond = new AuthService(users); var circuitEmployee = new AuthService(users);
Check(circuitAdmin.Login("admin", "admin") && circuitSecond.Login("second-admin", "fixture-pass") && circuitEmployee.Login("fixture-employee", "fixture-pass"), "circuits logged in before the reset");
string backupName = resetService.ResetAll(circuitAdmin.CurrentUser);
Check(Regex.IsMatch(backupName, @"^data\.backup-\d{8}-\d{6}\.json$"), "ResetAll returns the backup file name data.backup-yyyyMMdd-HHmmss.json [" + backupName + "]");
Check(Backups().SequenceEqual([backupName]) && File.ReadAllBytes(backupName).SequenceEqual(populatedBytes), "the backup sits next to data.json with the exact previous bytes");
Check(DateTime.TryParseExact(backupName.Substring("data.backup-".Length, 15), "yyyyMMdd-HHmmss", null, System.Globalization.DateTimeStyles.None, out var stamp) && Math.Abs((DateTime.Now - stamp).TotalMinutes) < 5, "the backup name carries the current local time");
Check(storage.Products.Count == 0 && storage.ProductCategories.Count == 0 && storage.Sales.Count == 0 && storage.SaleRefunds.Count == 0 && storage.StockMovements.Count == 0
    && storage.StockCounts.Count == 0 && storage.CashRegisters.Count == 0 && storage.CashMovements.Count == 0 && storage.CashCounts.Count == 0 && storage.Summaries.Count == 0
    && storage.Ingredients.Count == 0 && storage.Suppliers.Count == 0 && storage.Invoices.Count == 0 && storage.Recipes.Count == 0, "every business collection is empty in memory");
Check(storage.CurrentCashRegisterId == null && storage.CurrentCashRegister == null && !cash.IsOpen() && cash.GetCurrent() == null, "the current register is cleared (and no register is open)");
Check(storage.Users.Count == 1 && storage.Users[0].Id == admin.Id && storage.Users[0].Username == "admin" && storage.Users[0].PasswordHash == adminHash && storage.Users[0].Role == UserRole.Admin
    && BCrypt.Net.BCrypt.Verify("admin", storage.Users[0].PasswordHash), "only the acting admin remains, with the same id, username, role and password hash");
Check(Counters() == countersBefore, "ID counters are untouched (no reuse) [" + countersBefore + "]");
var emptied = FileRoot(File.ReadAllBytes("data.json"));
Check(Collections.Where(c => c != "Users").All(c => emptied.GetProperty(c).GetArrayLength() == 0) && emptied.GetProperty("Users").GetArrayLength() == 1
    && emptied.GetProperty("CurrentCashRegisterId").ValueKind == JsonValueKind.Null, "data.json is persisted with empty collections, the single admin and no current register");
Check(emptied.GetProperty("NextSaleId").GetInt32() == populated.GetProperty("NextSaleId").GetInt32() && emptied.GetProperty("NextProductId").GetInt32() == populated.GetProperty("NextProductId").GetInt32()
    && emptied.GetProperty("NextUserId").GetInt32() == populated.GetProperty("NextUserId").GetInt32() && emptied.GetProperty("NextCashRegisterId").GetInt32() == populated.GetProperty("NextCashRegisterId").GetInt32(), "data.json keeps the running ID counters");
var stateAfter = State();
var reloaded = new DataStorageService(); // a restart: must load the empty state and must NOT reseed demo data
var reloadedState = State(reloaded);
Check(reloaded.Products.Count == 0 && reloaded.Users.Count == 1 && reloaded.Users[0].Username == "admin" && !reloaded.Ingredients.Any() && reloaded.CurrentCashRegisterId == null, "a restart loads the empty state without reseeding demo data or a second admin");
Check(reloadedState == stateAfter, "reloading data.json equals the in-memory state after the reset");

// Other circuits: removed users are logged out on their next check; the acting admin keeps working.
Check(circuitAdmin.IsAuthenticated && circuitAdmin.IsInRole(UserRole.Admin), "the acting admin's circuit stays authenticated as Admin");
Check(!circuitSecond.IsAuthenticated && circuitSecond.CurrentUser == null && !circuitEmployee.IsAuthenticated && !circuitSecond.IsInRole(UserRole.Admin), "circuits of removed users are logged out on their next check");
Reject(() => resetService.ResetAll(second), "a removed admin trying to reset again");

// New data keeps counting from the old counters.
var newProduct = new Product { Name = "Nuevo", Price = 10m }; products.Add(newProduct);
Check(newProduct.Id == int.Parse(Regex.Match(countersBefore, @"_nextProductId=(\d+)").Groups[1].Value), "the next product ID continues the old counter (" + newProduct.Id + ")");

// ---- Page ----
var asm = typeof(DataResetService).Assembly;
var pageType = asm.GetType("GastroApp.Pages.DataReset");
Check(pageType != null, "GastroApp.Pages.DataReset page exists");
object NewPage(AuthService auth, out TestNavigation nav)
{
    var page = Activator.CreateInstance(pageType!)!; nav = new TestNavigation();
    pageType!.GetProperty("AuthService", flags)!.SetValue(page, auth);
    pageType.GetProperty("Navigation", flags)!.SetValue(page, nav);
    pageType.GetProperty("DataResetService", flags)!.SetValue(page, resetService);
    return page;
}
Exception? Call(object page, string method)
{
    try { var result = pageType!.GetMethod(method, flags | BindingFlags.DeclaredOnly)!.Invoke(page, null); if (result is Task task) task.GetAwaiter().GetResult(); return null; }
    catch (TargetInvocationException ex) { return ex.InnerException; }
}
void Set(object page, string field, object? value) => pageType!.GetField(field, flags)!.SetValue(page, value);
object? Get(object page, string field) => pageType!.GetField(field, flags)?.GetValue(page);
bool CanReset(object page) => (bool)pageType!.GetProperty("CanReset", flags)!.GetValue(page)!;
if (pageType != null)
{
    users.Add(new User { Username = "fixture-employee", PasswordHash = "fixture-pass", Role = UserRole.Employee });
    Populate();
    Check(storage.CashRegisters.Min(r => r.Id) == int.Parse(Regex.Match(countersBefore, @"_nextCashRegisterId=(\d+)").Groups[1].Value), "the first cash register after the reset continues the old counter");
    var populatedAgain = State(); var bytesAgain = File.ReadAllBytes("data.json");
    var anon = new AuthService(users); var emp = new AuthService(users); emp.Login("fixture-employee", "fixture-pass");
    var okAdmin = new AuthService(users); okAdmin.Login("admin", "admin");
    // Employees / anonymous: guard on initialization and on the action itself, even with the confirmation forced.
    var p = NewPage(emp, out var nav); Call(p, "OnInitialized");
    Check(nav.Destination == "/unauthorized", "employee opening the page goes to /unauthorized");
    Set(p, "acknowledged", true); Set(p, "confirmation", "REINICIAR"); nav.Destination = null;
    var error = Call(p, "ResetData");
    Check(error == null && nav.Destination == "/unauthorized" && State() == populatedAgain && Backups().Length == 1, "employee forcing the confirmation is redirected and nothing changes");
    p = NewPage(anon, out nav); Call(p, "OnInitialized");
    Check(nav.Destination == "/login", "anonymous opening the page goes to /login");
    Set(p, "acknowledged", true); Set(p, "confirmation", "REINICIAR"); nav.Destination = null;
    error = Call(p, "ResetData");
    Check(error == null && nav.Destination == "/login" && State() == populatedAgain && Backups().Length == 1, "anonymous forcing the confirmation is redirected to /login and nothing changes");

    p = NewPage(okAdmin, out nav); Call(p, "OnInitialized");
    Check(nav.Destination == null, "admin can open the page");
    Check(!CanReset(p), "the button starts disabled");
    Set(p, "acknowledged", true); Set(p, "confirmation", "");
    Check(!CanReset(p), "checkbox without the word keeps it disabled");
    Set(p, "acknowledged", false); Set(p, "confirmation", "REINICIAR");
    Check(!CanReset(p), "the word without the checkbox keeps it disabled");
    Set(p, "acknowledged", true);
    foreach (var wrong in new[] { "reiniciar", "Reiniciar", "REINICIAR ", " REINICIAR", "REINICIA", "REINICIAR!", "REINICIAR\n" })
    {
        Set(p, "confirmation", wrong);
        Check(!CanReset(p), "wrong confirmation '" + wrong.Replace("\n", "\\n") + "' keeps it disabled");
    }
    Set(p, "confirmation", "REINICIAR");
    Check(CanReset(p), "checkbox + exact REINICIAR enable the button");
    // The action itself rechecks the confirmation.
    Set(p, "confirmation", "reiniciar"); error = Call(p, "ResetData");
    Check(error == null && State() == populatedAgain && Backups().Length == 1 && nav.Destination == null, "ResetData with a wrong word does nothing");
    Set(p, "confirmation", "REINICIAR"); Set(p, "acknowledged", false); error = Call(p, "ResetData");
    Check(error == null && State() == populatedAgain && Backups().Length == 1 && nav.Destination == null, "ResetData without the checkbox does nothing");

    Thread.Sleep(1200); // a different second, so the new backup name differs from the first one
    Set(p, "acknowledged", true); Set(p, "confirmation", "REINICIAR");
    error = Call(p, "ResetData");
    var pageBackup = Get(p, "backupFileName") as string;
    Check(error == null && pageBackup != null && pageBackup != backupName && File.Exists(pageBackup) && File.ReadAllBytes(pageBackup).SequenceEqual(bytesAgain), "valid confirmation resets and exposes the backup file name [" + error?.Message + "]");
    Check(storage.Products.Count == 0 && storage.Sales.Count == 0 && storage.Users.Count == 1 && storage.CurrentCashRegisterId == null && Backups().Length == 2, "page reset emptied the data and wrote a second backup");
    Check(nav.Destination == null, "the dashboard is opened when the result dialog closes, not before");
    Call(p, "GoToDashboard");
    Check(nav.Destination == "/", "closing the result goes to the dashboard");
    var page2 = NewPage(okAdmin, out var nav2);
    Call(page2, "OnInitialized");
    Check(nav2.Destination == null && okAdmin.IsAuthenticated, "the acting admin still has a valid session after the reset");
}

// ---- Wiring, UI and docs ----
string page = File.Exists(Path.Combine(repoRoot, "Pages", "DataReset.razor")) ? Src("Pages/DataReset.razor") : "";
Check(page.Contains("@page \"/settings/reset\"") && page.Contains("<PageTitle>Reiniciar datos</PageTitle>") && page.Contains("REINICIAR") && page.Contains("disabled=\"@(!CanReset)\"")
    && page.Contains("<Banner") && page.Contains("<ModalDialog") && page.Contains("<Toast") && page.Contains("btn--danger") && page.Contains("backupFileName"), "page: route, title, REINICIAR, disabled button, Banner, ModalDialog, Toast and danger styling");
foreach (var what in new[] { "productos", "categorías", "ventas", "devoluciones", "movimientos de stock", "conteos de stock", "cajas", "movimientos de caja", "arqueos", "resúmenes diarios", "ingredientes", "proveedores", "facturas", "recetas" })
    Check(page.Contains(what, StringComparison.OrdinalIgnoreCase), "page lists what is deleted: " + what);
Check(page.Contains("contraseña") && page.Contains("irreversible") && page.Contains("copia de seguridad") && page.Contains("identificadores"), "page explains what is kept, that it is irreversible, the backup and the counters");
var program = Src("Program.cs");
Check(program.Contains("builder.Services.AddSingleton<DataResetService>();"), "Program.cs registers DataResetService as a singleton");
var nav3 = Src("Shared/NavMenu.razor");
var adminAt = nav3.IndexOf("@if (AuthService.IsInRole(UserRole.Admin))", nav3.IndexOf("sidebar__footer", StringComparison.Ordinal), StringComparison.Ordinal);
var resetAt = nav3.IndexOf("href=\"settings/reset\"", StringComparison.Ordinal);
Check(resetAt > 0 && adminAt > 0 && adminAt < resetAt && !nav3.Substring(adminAt, resetAt - adminAt).Contains('}') && nav3.Contains("Reiniciar datos") && nav3.Contains("nav-link--danger"), "NavMenu: discreet admin-only danger entry 'Reiniciar datos' in the sidebar footer");
Check(nav3.Contains("href=\"ingredients\"") && nav3.Contains("href=\"cash/history\"") && nav3.Contains("href=\"cash\" Match=\"NavLinkMatch.All\"") && nav3.Contains("href=\"sales\" Match=\"NavLinkMatch.All\"") && !nav3.Contains("href=\"stock/count\""), "PRESERVE: existing NavMenu entries are unchanged");
var host = Src("Pages/_Host.cshtml");
Check(host.Contains("css/views/settings.css") && File.Exists(Path.Combine(repoRoot, "wwwroot", "css", "views", "settings.css")), "settings.css is linked from _Host.cshtml");
var gitignore = Src(".gitignore");
Check(gitignore.Split('\n').Any(l => l.Trim() == "data.backup-*.json"), ".gitignore lists data.backup-*.json");
var ignored = new System.Diagnostics.Process();
ignored.StartInfo = new System.Diagnostics.ProcessStartInfo("git", $"-C \"{repoRoot}\" check-ignore -q data.backup-20260101-120000.json") { UseShellExecute = false, CreateNoWindow = true };
ignored.Start(); ignored.WaitForExit();
Check(ignored.ExitCode == 0, "git ignores data.backup-<timestamp>.json");
var docPath = Path.Combine(repoRoot, "Docs", "Architecture", "DataReset.md");
var doc = File.Exists(docPath) ? File.ReadAllText(docPath) : "";
Check(doc.Contains("data.backup-") && doc.Contains("REINICIAR") && doc.Contains("ResetAll") && doc.Contains("counters"), "DataReset.md documents the backup, the confirmation, ResetAll and the counters");
var readme = Src("README.md");
Check(readme.Contains("Reiniciar datos") && readme.Contains("DataReset.md"), "README mentions Reiniciar datos and links the document");
var auth = Src("scripts/verify-auth-isolation.ps1");
Check(auth.Contains("[\"DataReset\"]"), "verify-auth-isolation.ps1 covers the DataReset page");

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
    & dotnet run --project (Join-Path $ScratchPath 'DataResetChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Data reset checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
