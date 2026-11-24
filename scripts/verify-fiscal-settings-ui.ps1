param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-fiscal-ui-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'FiscalSettingsUiChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.JSInterop;
using System.Net;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var repoRoot = args[0];
string Src(string path) => File.ReadAllText(Path.Combine(repoRoot, path.Replace('/', Path.DirectorySeparatorChar)));
string FixtureCuit(int n) { for (var k = n; ; k++) { var ten = "20" + k.ToString("D8"); int[] w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]; var sum = 0; for (var i = 0; i < 10; i++) sum += (ten[i] - (char)48) * w[i]; var check = 11 - sum % 11; if (check == 10) continue; return ten + (check == 11 ? 0 : check); } }
string Dashed(string c) => c[..2] + "-" + c[2..10] + "-" + c[10..];

// ---- Fixture (process cwd is ALWAYS the newly allocated temp directory) ----
var storage = new DataStorageService();
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
storage.Ingredients = []; storage.Recipes = []; storage.Invoices = []; storage.Suppliers = [];
var users = new UserService(storage);
var suppliers = new SupplierService(storage);
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
invoices.SetIngredientService(ingredients);
var recipes = new RecipeService(storage, invoices);
var settings = new BusinessSettingsService(storage, recipes);
// Legacy supplier (no fiscal data), a half-completed one (CUIT but no condition) and a complete one.
var legacy = new Supplier { Id = storage.GetNextSupplierId(), Name = "Proveedor legado" };
var halfDone = new Supplier { Id = storage.GetNextSupplierId(), Name = "Proveedor sin condicion", Cuit = FixtureCuit(300) };
var complete = new Supplier { Id = storage.GetNextSupplierId(), Name = "Proveedor completo", Cuit = "30712345671", TaxCondition = TaxCondition.ResponsableInscripto };
storage.Suppliers = [legacy, halfDone, complete];
storage.SaveToFile();
Check(storage.BusinessSettings.TaxCondition == null, "fixture: the business condition starts unset");

string State() => JsonSerializer.Serialize(new { storage.Suppliers, storage.BusinessSettings, storage.Users, storage.Invoices, storage.Recipes,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
byte[] Bytes() => File.ReadAllBytes("data.json");
bool Unchanged(string state, byte[] bytes) => State() == state && Bytes().SequenceEqual(bytes);

// ---- Page plumbing ----
var asm = typeof(SupplierService).Assembly;
AuthService NewAuth(string? username)
{
    var auth = new AuthService(users);
    if (username != null) Check(auth.Login(username, "fixture-pass"), "circuit login " + username);
    return auth;
}
var anon = NewAuth(null); var employee = NewAuth("fixture-employee"); var admin = NewAuth("fixture-admin");
object NewPage(Type type, AuthService auth, out TestNavigation nav)
{
    var page = Activator.CreateInstance(type)!; nav = new TestNavigation();
    void Inject(string name, object value) { var p = type.GetProperty(name, flags); p?.SetValue(page, value); }
    Inject("AuthService", auth); Inject("Navigation", nav); Inject("SupplierService", suppliers); Inject("InvoiceService", invoices);
    Inject("BusinessSettingsService", settings);
    return page;
}
Exception? Call(object page, string method, params object?[] arguments)
{
    try
    {
        var m = page.GetType().GetMethod(method, flags | BindingFlags.DeclaredOnly);
        if (m == null) return new MissingMethodException(method);
        var result = m.Invoke(page, arguments);
        if (result is Task task) task.GetAwaiter().GetResult();
        return null;
    }
    catch (TargetInvocationException ex) { return ex.InnerException; }
}
object? Get(object page, string field) => page.GetType().GetField(field, flags)?.GetValue(page);
void Set(object page, string field, object? value) => page.GetType().GetField(field, flags)!.SetValue(page, value);
string? Str(object page, string field) => Get(page, field) as string;

// Static HTML of a component, decoded so accents can be asserted.
string Render(Type type, AuthService auth, Dictionary<string, object?>? parameters = null)
{
    var services = new ServiceCollection();
    services.AddLogging();
    services.AddSingleton(auth); services.AddSingleton(suppliers); services.AddSingleton(invoices); services.AddSingleton(settings);
    services.AddSingleton<NavigationManager>(new TestNavigation());
    services.AddSingleton<IJSRuntime>(new StubJs());
    using var provider = services.BuildServiceProvider();
    using var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>());
    var html = renderer.Dispatcher.InvokeAsync(async () => (await renderer.RenderComponentAsync(type, ParameterView.FromDictionary(parameters ?? new Dictionary<string, object?>()))).ToHtmlString()).GetAwaiter().GetResult();
    return WebUtility.HtmlDecode(html);
}
int Count(string html, string text) => Regex.Matches(html, Regex.Escape(text)).Count;

// ================= S1: Datos fiscales page =================
var fiscalType = asm.GetType("GastroApp.Pages.FiscalSettings");
Check(fiscalType != null, "GastroApp.Pages.FiscalSettings page exists");
const string Saved = "Condición frente al IVA guardada. Se recalcularon los costos de las recetas.";
if (fiscalType != null)
{
    var fiscalSource = Src("Pages/FiscalSettings.razor");
    Check(fiscalSource.Contains("@page \"/settings/fiscal\"") && fiscalSource.Contains("<PageTitle>Datos fiscales</PageTitle>"), "page: route /settings/fiscal and title Datos fiscales");
    Check(fiscalSource.Contains("SetTaxCondition(") && fiscalSource.Contains("AuthService.CurrentUser") && fiscalSource.Contains("UnauthorizedAccessException") && fiscalSource.Contains("InvalidOperationException")
        && fiscalSource.Contains("Variant=\"danger\"") && fiscalSource.Contains("@errorMessage"), "page: saves through the service with the live actor and shows service errors in a danger Banner");

    // Guards: anonymous -> /login, employee -> /unauthorized, on initialization and on the action itself.
    var guarded = State(); var guardedBytes = Bytes();
    foreach (var (auth, who, destination) in new[] { (anon, "anonymous", "/login"), (employee, "employee", "/unauthorized") })
    {
        var page = NewPage(fiscalType, auth, out var nav);
        var ex = Call(page, "OnInitialized");
        Check(ex == null && nav.Destination == destination && Get(page, "selectedCondition") == null, who + " opening the page goes to " + destination + " and loads nothing");
        Set(page, "selectedCondition", (TaxCondition?)TaxCondition.Exento); nav.Destination = null;
        ex = Call(page, "SaveCondition");
        Check(ex == null && nav.Destination == destination && Str(page, "successMessage") == null && Unchanged(guarded, guardedBytes), who + " forcing a selection is redirected to " + destination + " and nothing changes");
        var html = Render(fiscalType, auth);
        Check(!html.Contains("Responsable Inscripto") && !html.Contains("Sin configurar"), who + " sees no fiscal data in the rendered page");
    }

    // Admin: the empty state, then save.
    var p = NewPage(fiscalType, admin, out var navAdmin);
    Check(Call(p, "OnInitialized") == null && navAdmin.Destination == null && Get(p, "selectedCondition") == null, "admin opens the page with no selection while the condition is unset");
    var emptyHtml = Render(fiscalType, admin);
    Check(emptyHtml.Contains("Datos fiscales") && emptyHtml.Contains("Sin configurar"), "unset condition is shown as 'Sin configurar'");
    foreach (var c in Enum.GetValues<TaxCondition>())
        Check(emptyHtml.Contains($">{FiscalRules.Label(c)}</option>"), "the select offers the option " + FiscalRules.Label(c));
    Check(Count(emptyHtml, "</option>") == 4 && emptyHtml.Contains(">Seleccionar...</option>"), "the select offers 'Seleccionar...' plus exactly the three conditions");
    Check(emptyHtml.Contains("factura A") && emptyHtml.Contains("crédito fiscal") && emptyHtml.Contains("neto") && emptyHtml.Contains("Monotributista") && emptyHtml.Contains("factura B") && emptyHtml.Contains("IVA incluido")
        && emptyHtml.Contains("contador"), "help explains each condition for purchases and suggests confirming with an accountant");

    // A save without a selection is rejected by the page and changes nothing.
    var s0 = State(); var b0 = Bytes();
    var err = Call(p, "SaveCondition");
    Check(err == null && !string.IsNullOrEmpty(Str(p, "errorMessage")) && Str(p, "successMessage") == null && Unchanged(s0, b0), "saving without a selection shows an error and changes nothing");

    // Service rejection: an undefined value.
    Set(p, "selectedCondition", (TaxCondition?)(TaxCondition)99);
    err = Call(p, "SaveCondition");
    Check(err == null && Str(p, "errorMessage") == "Elegí una condición frente al IVA válida." && Str(p, "successMessage") == null && Unchanged(s0, b0),
        "service rejection is shown in the page and changes nothing [" + Str(p, "errorMessage") + "]");

    // Admin save persists, shows the message and recalculates (service contract).
    Set(p, "selectedCondition", (TaxCondition?)TaxCondition.Monotributista);
    err = Call(p, "SaveCondition");
    Check(err == null && storage.BusinessSettings.TaxCondition == TaxCondition.Monotributista && settings.TaxCondition == TaxCondition.Monotributista, "admin save stores the condition");
    Check(Str(p, "successMessage") == Saved && string.IsNullOrEmpty(Str(p, "errorMessage")) && navAdmin.Destination == null, "admin save shows the success message and no error [" + Str(p, "successMessage") + "]");
    var reloaded = new DataStorageService();
    Check(reloaded.BusinessSettings.TaxCondition == TaxCondition.Monotributista, "the condition survives a restart (data.json)");
    var page2 = NewPage(fiscalType, admin, out _);
    Call(page2, "OnInitialized");
    Check((TaxCondition?)Get(page2, "selectedCondition") == TaxCondition.Monotributista, "reopening the page preselects the stored condition");
    var setHtml = Render(fiscalType, admin);
    Check(!setHtml.Contains("Sin configurar") && Count(setHtml, "Monotributista") >= 2, "the current condition replaces 'Sin configurar' in the page");

    // A second change and a failed save keep the previous value.
    Set(p, "selectedCondition", (TaxCondition?)TaxCondition.Exento); Call(p, "SaveCondition");
    Check(storage.BusinessSettings.TaxCondition == TaxCondition.Exento && Str(p, "successMessage") == Saved, "admin can change the condition again");
    var s1 = State(); var b1 = Bytes();
    Set(p, "selectedCondition", (TaxCondition?)(TaxCondition)0); Call(p, "SaveCondition");
    Check(storage.BusinessSettings.TaxCondition == TaxCondition.Exento && Str(p, "successMessage") == null && !string.IsNullOrEmpty(Str(p, "errorMessage")) && Unchanged(s1, b1), "a rejected save keeps the stored condition and clears the previous success message");

    // Stale admin: the circuit is logged out before the action runs.
    var stale = NewAuth("fixture-admin"); var staleStored = storage.Users.First(u => u.Id == 10);
    var staleHash = staleStored.PasswordHash; staleStored.PasswordHash = BCrypt.Net.BCrypt.HashPassword("changed");
    var sp = NewPage(fiscalType, stale, out var staleNav);
    Set(sp, "selectedCondition", (TaxCondition?)TaxCondition.ResponsableInscripto);
    var s2 = State(); var b2 = Bytes();
    Check(Call(sp, "SaveCondition") == null && staleNav.Destination == "/login" && Unchanged(s2, b2), "a stale admin session is sent to /login and nothing changes");
    staleStored.PasswordHash = staleHash;
}
else
{
    Check(false, "(skipped) Datos fiscales page checks need the page");
}
storage.BusinessSettings.TaxCondition = null; storage.SaveToFile();

// ================= S2: suppliers page =================
var suppliersType = asm.GetType("GastroApp.Pages.Suppliers")!;
var suppliersSource = Src("Pages/Suppliers.razor");
Check(suppliersSource.Contains("for=\"supplier-cuit\"") && suppliersSource.Contains("placeholder=\"Ej: 30-71234567-1\"") && suppliersSource.Contains("@bind=\"editingSupplier.Cuit\"") && suppliersSource.Contains("CUIT <span class=\"field__req\""),
    "form: required CUIT input with the example placeholder");
Check(suppliersSource.Contains("Condición frente al IVA <span class=\"field__req\"") && suppliersSource.Contains("@bind=\"editingSupplier.TaxCondition\"") && suppliersSource.Contains("<option value=\"\">Seleccionar...</option>"),
    "form: required 'Condición frente al IVA' select with 'Seleccionar...' first");
{
    var sAdmin = NewPage(suppliersType, admin, out var navS);
    Call(sAdmin, "OnInitializedAsync");
    // The dialog body only renders while open, so the form markup is checked in the source.
    var selectAt = suppliersSource.IndexOf("id=\"supplier-tax-condition\"", StringComparison.Ordinal);
    var selectPart = selectAt < 0 ? "" : suppliersSource.Substring(selectAt, Math.Min(500, suppliersSource.Length - selectAt));
    Check(selectPart.IndexOf("Seleccionar...", StringComparison.Ordinal) is var first and >= 0 && selectPart.IndexOf("Enum.GetValues<TaxCondition>()", StringComparison.Ordinal) > first && selectPart.Contains("FiscalRules.Label(condition)"),
        "form: the condition select lists 'Seleccionar...' first, then the three FiscalRules labels");

    // Create through the page.
    Call(sAdmin, "ShowAddForm");
    var created = new Supplier { Name = "Nuevo", Cuit = "30-71234567-1", TaxCondition = TaxCondition.Monotributista };
    Set(sAdmin, "editingSupplier", created);
    storage.Suppliers = [legacy, halfDone]; storage.SaveToFile();
    var err = Call(sAdmin, "SaveSupplier");
    var stored = storage.Suppliers.SingleOrDefault(s => s.Cuit == "30712345671");
    Check(err == null && stored != null && stored.TaxCondition == TaxCondition.Monotributista && stored.Id > 0 && Str(sAdmin, "formError") == "", "creating a supplier through the page stores the CUIT without dashes and the condition");
    Check(new DataStorageService().Suppliers.Any(s => s.Cuit == "30712345671" && s.TaxCondition == TaxCondition.Monotributista), "the created supplier is in data.json with its fiscal data");

    // Invalid inputs show the service message in formError and store nothing.
    void Rejected(string name, string cuit, TaxCondition? condition, string message, int id = 0, string supplierName = "Otro")
    {
        var s = State(); var b = Bytes(); var count = storage.Suppliers.Count;
        var page = NewPage(suppliersType, admin, out var nav);
        Set(page, "editingSupplier", new Supplier { Id = id, Name = supplierName, Cuit = cuit, TaxCondition = condition });
        var ex = Call(page, "SaveSupplier");
        Check(ex == null && Str(page, "formError") == message && storage.Suppliers.Count == count && Unchanged(s, b) && nav.Destination == null, name + " shows '" + message + "' in formError and stores nothing [" + Str(page, "formError") + (ex != null ? " " + ex.GetType().Name : "") + "]");
    }
    Rejected("invalid check digit", "30-71234567-2", TaxCondition.Exento, "El CUIT no es válido.");
    Rejected("too short CUIT", "123", TaxCondition.Exento, "El CUIT no es válido.");
    Rejected("missing CUIT", "", TaxCondition.Exento, "Ingresá el CUIT del proveedor.");
    Rejected("missing condition", FixtureCuit(500), null, "Elegí la condición frente al IVA del proveedor.");
    Rejected("duplicate CUIT typed with dashes", "30-71234567-1", TaxCondition.Exento, "Ya existe un proveedor con ese CUIT.");
    // PRESERVE: the page's own name check still runs first.
    {
        var s = State(); var b = Bytes();
        var page = NewPage(suppliersType, admin, out _);
        Set(page, "editingSupplier", new Supplier { Name = " ", Cuit = FixtureCuit(500), TaxCondition = TaxCondition.Exento });
        Check(Call(page, "SaveSupplier") == null && Str(page, "formError") == "Ingresá un nombre para el proveedor." && Unchanged(s, b), "PRESERVE: an empty name is still rejected with its own message");
    }

    // Edit copies the fiscal data and updates it.
    var editPage = NewPage(suppliersType, admin, out _);
    Call(editPage, "EditSupplier", stored!);
    var form = (Supplier?)Get(editPage, "editingSupplier");
    Check(form != null && !ReferenceEquals(form, stored) && form.Id == stored!.Id && form.Name == stored.Name && form.Cuit == stored.Cuit && form.TaxCondition == stored.TaxCondition, "editing copies name, CUIT and condition into the form");
    form!.Cuit = Dashed(stored!.Cuit); form.TaxCondition = TaxCondition.Exento; form.Name = "Nuevo editado";
    var editErr = Call(editPage, "SaveSupplier");
    Check(editErr == null && stored.Name == "Nuevo editado" && stored.Cuit == "30712345671" && stored.TaxCondition == TaxCondition.Exento && Str(editPage, "formError") == "", "saving an edit keeps its own CUIT (stored as 11 digits) and updates the condition");

    // Legacy supplier completed through the edit form.
    var legacyPage = NewPage(suppliersType, admin, out _);
    Call(legacyPage, "EditSupplier", legacy);
    var legacyForm = (Supplier)Get(legacyPage, "editingSupplier")!;
    Check(legacyForm.Cuit == "" && legacyForm.TaxCondition == null, "editing a legacy supplier opens an empty CUIT and no condition");
    legacyForm.Cuit = FixtureCuit(700); legacyForm.TaxCondition = TaxCondition.ResponsableInscripto;
    Check(Call(legacyPage, "SaveSupplier") == null && legacy.HasFiscalData && legacy.Cuit == FixtureCuit(700) && legacy.TaxCondition == TaxCondition.ResponsableInscripto, "completing a legacy supplier through the page stores its fiscal data");
    Rejected("editing with the CUIT of another supplier", stored.Cuit, TaxCondition.Exento, "Ya existe un proveedor con ese CUIT.", id: halfDone.Id, supplierName: halfDone.Name);

    // Guards (PRESERVE): employee and anonymous cannot save.
    foreach (var (auth, who, destination) in new[] { (anon, "anonymous", "/login"), (employee, "employee", "/unauthorized") })
    {
        var s = State(); var b = Bytes();
        var page = NewPage(suppliersType, auth, out var nav);
        Set(page, "editingSupplier", new Supplier { Name = "Intruso", Cuit = FixtureCuit(900), TaxCondition = TaxCondition.Exento });
        Check(Call(page, "SaveSupplier") == null && nav.Destination == destination && Unchanged(s, b), "PRESERVE: " + who + " cannot save a supplier (" + destination + ")");
    }
    // PRESERVE: delete still works.
    var toDelete = storage.Suppliers.First(x => x.Id == halfDone.Id);
    var delPage = NewPage(suppliersType, admin, out _);
    Check(Call(delPage, "DeleteSupplier", toDelete.Id) == null && storage.Suppliers.All(x => x.Id != toDelete.Id), "PRESERVE: deleting a supplier still works");
}

// ================= S2/S8: supplier list =================
var listType = asm.GetType("GastroApp.Shared.Purchasing.SupplierList")!;
var cuitComplete = "30712345671"; var cuitHalf = FixtureCuit(300);
var listSuppliers = new List<Supplier> {
    new() { Id = 1, Name = "Proveedor legado" },
    new() { Id = 2, Name = "Proveedor sin condicion", Cuit = cuitHalf },
    new() { Id = 3, Name = "Proveedor completo", Cuit = cuitComplete, TaxCondition = TaxCondition.ResponsableInscripto },
    new() { Id = 4, Name = "Proveedor mono", Cuit = FixtureCuit(800), TaxCondition = TaxCondition.Monotributista }
};
var listHtml = Render(listType, admin, new Dictionary<string, object?> { ["Suppliers"] = listSuppliers, ["Invoices"] = new List<Invoice>() });
Check(listHtml.Contains(">CUIT</th>") && listHtml.Contains(">Condición</th>"), "list has the CUIT and Condición columns");
Check(listHtml.Contains(Dashed(cuitComplete)) && listHtml.Contains(Dashed(cuitHalf)) && listHtml.Contains(Dashed(FixtureCuit(800))) && !listHtml.Contains(cuitComplete), "list shows CUITs formatted XX-XXXXXXXX-X");
Check(listHtml.Contains(">Responsable Inscripto<") && listHtml.Contains(">Monotributista<"), "list shows the condition labels");
Check(Count(listHtml, "Datos fiscales incompletos") == 2, "the incomplete-data badge appears for the legacy supplier and the one without condition only (" + Count(listHtml, "Datos fiscales incompletos") + ")");
Check(listHtml.Contains("badge--warn"), "the incomplete-data badge is a warn Badge");
var legacyRow = Regex.Match(listHtml, @"<tr[^>]*>(?:(?!</tr>).)*Proveedor legado(?:(?!</tr>).)*</tr>", RegexOptions.Singleline).Value;
Check(legacyRow.Contains("Datos fiscales incompletos") && Count(legacyRow, "—") >= 2, "the legacy supplier's row shows the badge and '—' for CUIT and condition");
var completeRow = Regex.Match(listHtml, @"<tr[^>]*>(?:(?!</tr>).)*Proveedor completo(?:(?!</tr>).)*</tr>", RegexOptions.Singleline).Value;
Check(completeRow != "" && !completeRow.Contains("Datos fiscales incompletos") && !completeRow.Contains("—"), "a complete supplier's row has no badge and no '—'");
Check(listHtml.Contains("nombre, CUIT y condición frente al IVA") && listHtml.Contains("tipo de factura") && !listHtml.Contains("únicamente su nombre") && !listHtml.Contains("quedan para iteraciones futuras"), "the 'Modelo actual' banner describes name, CUIT, condition and the derived invoice type");
Check(listHtml.Contains("Editar") && listHtml.Contains("Eliminar") && listHtml.Contains("Facturas registradas"), "PRESERVE: the list keeps its edit/delete actions and the invoice count column");
var emptyList = Render(listType, admin, new Dictionary<string, object?> { ["Suppliers"] = new List<Supplier>(), ["Invoices"] = new List<Invoice>() });
Check(emptyList.Contains("No hay proveedores") && emptyList.Contains("Crear proveedor"), "PRESERVE: the empty state is unchanged");

// ================= Navigation =================
var navType = asm.GetType("GastroApp.Shared.NavMenu")!;
var navAdminHtml = Render(navType, admin);
var navEmployeeHtml = Render(navType, employee);
Check(navAdminHtml.Contains("href=\"settings/fiscal\"") && navAdminHtml.Contains("Datos fiscales"), "admin NavMenu links to settings/fiscal as 'Datos fiscales'");
Check(navAdminHtml.Contains("href=\"settings/reset\"") && navAdminHtml.Contains("Reiniciar datos"), "PRESERVE: admin NavMenu keeps the Reiniciar datos link");
Check(!navEmployeeHtml.Contains("settings/fiscal") && !navEmployeeHtml.Contains("Datos fiscales") && !navEmployeeHtml.Contains("settings/reset"), "employee NavMenu has neither admin link");
var navSource = Src("Shared/NavMenu.razor");
var zoneAt = navSource.IndexOf("sidebar__admin-zone", StringComparison.Ordinal);
var fiscalAt = navSource.IndexOf("href=\"settings/fiscal\"", StringComparison.Ordinal);
var resetAt = navSource.IndexOf("href=\"settings/reset\"", StringComparison.Ordinal);
Check(zoneAt > 0 && fiscalAt > zoneAt && resetAt > zoneAt && Math.Abs(fiscalAt - resetAt) < 400, "the fiscal link sits in the admin zone next to the reset link");

// ================= Docs =================
var features = Src("IMPLEMENTED_FEATURES.md");
Check(features.Contains("/settings/fiscal") && features.Contains("Datos fiscales") && features.Contains("CUIT") && features.Contains("BusinessSettingsService"), "IMPLEMENTED_FEATURES documents the fiscal data screen, the supplier CUIT/condition and the service");
Check(!features.Contains("The current supplier model is intentionally small"), "IMPLEMENTED_FEATURES no longer says the supplier model only stores a name");

Console.WriteLine($"{checks} checks, {failures} failures; fixture: {Directory.GetCurrentDirectory()}");
return failures == 0 ? 0 : 1;

sealed class TestNavigation : NavigationManager
{
    public string? Destination { get; set; }
    public TestNavigation() { Initialize("http://localhost/", "http://localhost/"); }
    protected override void NavigateToCore(string uri, bool forceLoad) { if (forceLoad) throw new InvalidOperationException("forced reload"); Destination = uri; }
}

sealed class StubJs : IJSRuntime
{
    public ValueTask<TValue> InvokeAsync<TValue>(string identifier, object?[]? args) => default;
    public ValueTask<TValue> InvokeAsync<TValue>(string identifier, CancellationToken cancellationToken, object?[]? args) => default;
}
'@ | Set-Content (Join-Path $ScratchPath 'Program.cs') -Encoding utf8
$exitCode = 1
Push-Location $ScratchPath
try {
    & dotnet run --project (Join-Path $ScratchPath 'FiscalSettingsUiChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Fiscal settings UI checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
