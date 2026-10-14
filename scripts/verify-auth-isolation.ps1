param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-auth-' + [guid]::NewGuid().ToString('N')) }
$ScratchPath = [IO.Path]::GetFullPath($ScratchPath)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
if (!$ScratchPath.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'ScratchPath must be under the OS temporary directory.' }
if (Test-Path $ScratchPath) { throw 'ScratchPath must be a new directory.' }
New-Item -ItemType Directory -Path $ScratchPath | Out-Null
Write-Host "Verification scratch: $ScratchPath (retained for inspection)"
$before = (& git -C $repo hash-object data.json)
$project = [xml](Get-Content (Join-Path $repo 'GastroApp.csproj') -Raw)
$framework = $project.Project.PropertyGroup.TargetFramework
$reference = [Security.SecurityElement]::Escape((Join-Path $repo 'GastroApp.csproj'))
@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>$framework</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><ProjectReference Include="$reference" /><FrameworkReference Include="Microsoft.AspNetCore.App" /></ItemGroup>
</Project>
"@ | Set-Content (Join-Path $ScratchPath 'AuthChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using System.Reflection;
using System.Text.RegularExpressions;

var repo = args[0];
int failures = 0, checks = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
string Read(string path) => File.ReadAllText(Path.Combine(repo, path));
IServiceCollection services = new ServiceCollection();
// Use the actual application's declarations without starting its host or reading live data.
foreach (Match m in Regex.Matches(Read("Program.cs"), @"builder.Services.Add(Singleton|Scoped)<(\w+)>\(\);"))
{
    var type = typeof(AuthService).Assembly.GetType("GastroApp.Services." + m.Groups[2].Value)!;
    services.Add(new ServiceDescriptor(type, type, m.Groups[1].Value == "Scoped" ? ServiceLifetime.Scoped : ServiceLifetime.Singleton));
}
Check(services.Single(d => d.ServiceType == typeof(AuthService)).Lifetime == ServiceLifetime.Scoped, "AuthService registered scoped");
Check(services.Where(d => d.ServiceType != typeof(AuthService)).All(d => d.Lifetime == ServiceLifetime.Singleton), "business registrations remain singleton");
using var provider = services.BuildServiceProvider(new ServiceProviderOptions { ValidateScopes = true, ValidateOnBuild = true });
using var one = provider.CreateScope();
using var two = provider.CreateScope();
var a = one.ServiceProvider.GetRequiredService<AuthService>();
var b = two.ServiceProvider.GetRequiredService<AuthService>();
Check(!ReferenceEquals(a, b), "independent circuit auth instances");
Check(ReferenceEquals(a, one.ServiceProvider.GetRequiredService<AuthService>()), "same circuit auth instance");
foreach (var d in services.Where(d => d.ServiceType != typeof(AuthService)))
    Check(ReferenceEquals(one.ServiceProvider.GetRequiredService(d.ServiceType), two.ServiceProvider.GetRequiredService(d.ServiceType)), "shared " + d.ServiceType.Name);
var storage = provider.GetRequiredService<DataStorageService>();
var users = provider.GetRequiredService<UserService>();
storage.Users.Clear(); // Only generated fixture state in this scratch working directory.
users.Add(new User { Username = "test-admin", PasswordHash = "test-pass", Role = UserRole.Admin });
users.Add(new User { Username = "test-employee", PasswordHash = "test-pass", Role = UserRole.Employee });
int ae = 0, be = 0;
a.OnAuthStateChanged += () => ae++;
b.OnAuthStateChanged += () => be++;
Check(a.Login("test-admin", "test-pass") && !b.IsAuthenticated && ae == 1 && be == 0, "login and event isolation");
Check(b.Login("test-employee", "test-pass") && a.IsInRole(UserRole.Admin) && b.IsInRole(UserRole.Employee), "distinct circuit roles");
a.Logout();
Check(!a.IsAuthenticated && b.IsAuthenticated && ae == 2 && be == 1, "logout and event isolation");
Check(!a.Login("test-admin", "wrong") && !a.IsAuthenticated, "invalid login fails closed");
a.Login("test-admin", "test-pass");
var admin = users.GetByUsername("test-admin")!;
// Replacing the stored object catches reference-cached identity and stale role checks.
var live = new User { Id = admin.Id, Username = admin.Username, PasswordHash = admin.PasswordHash, Role = UserRole.Employee };
storage.Users[storage.Users.IndexOf(admin)] = live;
Check(a.IsAuthenticated && !a.IsInRole(UserRole.Admin) && a.IsInRole(UserRole.Employee) && ReferenceEquals(a.CurrentUser, live), "role and actor resolve live user");
live.Role = UserRole.Admin;
Check(a.IsInRole(UserRole.Admin), "live role promotion");
live.Username = "renamed-admin";
Check(!a.IsAuthenticated && a.CurrentUser == null && !a.IsInRole(UserRole.Admin), "username change invalidates identity");
live.Username = "test-admin";
Check(!a.IsAuthenticated, "invalidated identity cannot revive");
a.Login("test-admin", "test-pass");
live.PasswordHash = BCrypt.Net.BCrypt.HashPassword("new-pass");
Check(!a.IsAuthenticated && !a.IsInRole(UserRole.Admin), "password change invalidates identity");
a.Login("test-admin", "new-pass");
users.Delete(live.Id);
Check(!a.IsAuthenticated && a.CurrentUser == null, "deleted identity fails closed");
users.Add(new User { Username = "test-admin", PasswordHash = "new-pass", Role = UserRole.Admin });
Check(!a.IsAuthenticated, "same username with new id cannot revive identity");
a.Login("test-admin", "new-pass");
var adminPages = new Dictionary<string, string[]> {
    ["Cash"] = ["OpenCash", "CloseCash", "RecordMovement"],
    ["Products"] = ["ShowAddForm", "EditProduct", "SaveProduct", "DeleteProduct"],
    ["ProductCategories"] = ["ShowAddForm", "EditCategory", "SaveCategory", "DeleteCategory"],
    ["Suppliers"] = ["ShowAddForm", "EditSupplier", "SaveSupplier", "DeleteSupplier"],
    ["Ingredients"] = ["ShowAddForm", "EditIngredient", "ShowStockAdjust", "SaveStockAdjustment", "SaveIngredient", "DeleteIngredient"],
    ["Invoices"] = ["ShowAddForm", "AddItem", "RemoveItem", "SaveInvoice", "DeleteInvoice"],
    ["Recipes"] = ["ShowAddForm", "AddIngredient", "RemoveIngredient", "SaveRecipe", "EditRecipe", "RecalculateCost", "DeleteRecipe"],
    ["Summary"] = ["CancelSelectedSale"]
};
void DeniedAction(string page, string method, AuthService auth, string destination)
{
    var type = typeof(AuthService).Assembly.GetType("GastroApp.Pages." + page)!;
    var component = Activator.CreateInstance(type)!;
    var nav = new TestNavigation();
    var flags = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
    type.GetProperty("AuthService", flags)!.SetValue(component, auth);
    type.GetProperty("Navigation", flags)!.SetValue(component, nav);
    var action = type.GetMethod(method, flags)!;
    var parameters = action.GetParameters().Select(p => p.ParameterType.IsValueType ? Activator.CreateInstance(p.ParameterType) : null).ToArray();
    try { action.Invoke(component, parameters); Check(nav.Destination == destination, page + "." + method + " denies " + destination); }
    catch (TargetInvocationException ex) { Check(false, page + "." + method + " reached unguarded code: " + ex.InnerException?.GetType().Name); }
}
foreach (var page in adminPages)
    foreach (var method in page.Value) DeniedAction(page.Key, method, b, "/unauthorized");
var currentAdmin = a.CurrentUser!;
currentAdmin.Role = UserRole.Employee;
foreach (var page in adminPages)
    foreach (var method in page.Value) DeniedAction(page.Key, method, a, "/unauthorized");
a.Logout();
foreach (var page in adminPages)
    foreach (var method in page.Value) DeniedAction(page.Key, method, a, "/login");
DeniedAction("Sales", "CompleteSale", a, "/login");
a.Login("test-admin", "new-pass");
currentAdmin.PasswordHash = BCrypt.Net.BCrypt.HashPassword("changed-pass");
foreach (var page in adminPages)
    foreach (var method in page.Value) DeniedAction(page.Key, method, a, "/login");
DeniedAction("Sales", "CompleteSale", a, "/login");
a.Login("test-admin", "changed-pass");
storage.Users.Remove(currentAdmin);
foreach (var page in adminPages)
    foreach (var method in page.Value) DeniedAction(page.Key, method, a, "/login");
DeniedAction("Sales", "CompleteSale", a, "/login");
storage.Users.Add(currentAdmin);
a.Login("test-admin", "changed-pass");
currentAdmin.Username = "renamed-admin";
foreach (var page in adminPages)
    foreach (var method in page.Value) DeniedAction(page.Key, method, a, "/login");
DeniedAction("Sales", "CompleteSale", a, "/login");
currentAdmin.Username = "test-admin";
foreach (var page in adminPages.Keys.Concat(new[] { "Login", "Index", "Sales" }))
    Check(!Regex.IsMatch(Read("Pages/" + page + ".razor"), @"NavigateTo\([^;]*,\s*true\)"), page + " circuit-preserving navigation");
foreach (var component in new[] { "MainLayout", "NavMenu" })
{
    var source = Read("Shared/" + component + ".razor");
    Check(source.Contains("InvokeAsync") && !source.Contains("+= StateHasChanged") && source.Contains("-= HandleAuthStateChanged") && source.Contains("IDisposable"), component + " dispatched notifications and disposal");
    Check(!Regex.IsMatch(source, @"NavigateTo\([^;]*,\s*true\)"), component + " circuit-preserving logout");
}
// A failed scope distinction would make the Employee actor below an Admin too.
if (!ReferenceEquals(a, b))
{
// Existing business rules and audit contracts, using only scratch fixture writes.
currentAdmin.Role = UserRole.Admin;
a.Login("test-admin", "changed-pass");
var cash = provider.GetRequiredService<CashRegisterService>();
var sales = provider.GetRequiredService<SaleService>();
var ingredients = provider.GetRequiredService<IngredientService>();
var recipes = provider.GetRequiredService<RecipeService>();
sales.SetIngredientService(ingredients);
sales.SetRecipeService(recipes);
cash.Open(100m);
var product = storage.Products.First();
Sale Checkout() => new Sale { Items = [new SaleItem { ProductId = product.Id, ProductName = product.Name, Price = product.Price, Quantity = 1 }], Payments = [new SalePayment { PaymentMethod = PaymentMethod.Cash, Amount = product.Price, ReceivedAmount = product.Price + 10m }] };
var sale = Checkout();
sales.Add(sale);
Check(sale.Id > 0 && sale.CashRegisterId == cash.GetCurrent()!.Id && cash.GetExpectedCash(sale.CashRegisterId!.Value) == 100m + sale.Total, "POS cash checkout and session movement");
try { sales.Cancel(sale.Id, "fixture", b.CurrentUser); Check(false, "employee cancellation denied"); } catch (UnauthorizedAccessException) { Check(sale.Status == SaleStatus.Completed, "employee cancellation denied without mutation"); }
var summaryPage = new GastroApp.Pages.Summary();
var flags = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;
var pageType = summaryPage.GetType();
pageType.GetProperty("AuthService", flags)!.SetValue(summaryPage, a);
pageType.GetProperty("Navigation", flags)!.SetValue(summaryPage, new TestNavigation());
pageType.GetProperty("SaleService", flags)!.SetValue(summaryPage, sales);
pageType.GetProperty("CashService", flags)!.SetValue(summaryPage, cash);
pageType.GetField("selectedSaleId", flags)!.SetValue(summaryPage, sale.Id);
pageType.GetField("cancellationReason", flags)!.SetValue(summaryPage, " fixture ");
pageType.GetMethod("CancelSelectedSale", flags)!.Invoke(summaryPage, null);
Check(sale.Status == SaleStatus.Cancelled && sale.CancelledByUserId == a.CurrentUser!.Id && sale.CancelledByUsername == a.CurrentUser.Username && sale.CancellationReason == "fixture", "cancellation uses validated circuit actor");
Check(cash.GetExpectedCash(sale.CashRegisterId!.Value) == 100m + sale.Total && sales.GetTodayCount() == 0, "cancellation preserves drawer and excludes daily sale");
try { sales.Cancel(sale.Id, "again", a.CurrentUser); Check(false, "repeat cancellation rejected"); } catch (InvalidOperationException) { Check(true, "repeat cancellation rejected"); }
DailySummary CloseWith(CashRegisterService service, decimal amount, User actor)
{
    var review = service.GetCountReview();
    return service.Close(new CashCountRequest { Review = review,
        Lines = amount > 0m ? new[] { new CashCountLineInput(amount, 1) } : Array.Empty<CashCountLineInput>(),
        Reason = amount != review.ExpectedAmount ? "fixture" : null, Confirmed = true, ZeroCountConfirmed = amount == 0m },
        new User { Id = actor.Id, Username = actor.Username, PasswordHash = actor.PasswordHash, Role = actor.Role });
}
var summary = CloseWith(cash, 100m + sale.Total, a.CurrentUser!);
Check(!cash.IsOpen() && summary.Difference == 0m, "cash close reconciliation");
try { sales.Add(Checkout()); Check(false, "closed-cash checkout rejected"); } catch (InvalidOperationException) { Check(true, "closed-cash checkout rejected"); }
}
else Console.WriteLine("SKIP business regression actors: circuit scope distinction failed");
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
    & dotnet run --project (Join-Path $ScratchPath 'AuthChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object data.json)
    if ($before -ne $after) { throw "Live data.json changed: $before -> $after" }
    Write-Host "Live data.json unchanged: $after"
}
if ($exitCode -ne 0) { throw "Authentication checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
