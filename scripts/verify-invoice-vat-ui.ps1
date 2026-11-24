param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-invoice-vat-ui-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'InvoiceVatUiChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using GastroApp.Shared.Purchasing;
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

// ---- Fixture (process cwd is ALWAYS the newly allocated temp directory) ----
var storage = new DataStorageService();
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var adminUser = storage.Users[0];
var harina = new Ingredient { Id = 1, Name = "Harina", Unit = "kg", IsActive = true };
var aceite = new Ingredient { Id = 2, Name = "Aceite", Unit = "lt", IsActive = true };
var huevo = new Ingredient { Id = 3, Name = "Huevo", Unit = "unidad", IsActive = true };
storage.Ingredients = [harina, aceite, huevo]; storage.Recipes = []; storage.Invoices = []; storage.Products = [];
var users = new UserService(storage);
var suppliers = new SupplierService(storage);
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
invoices.SetIngredientService(ingredients);
var recipes = new RecipeService(storage, invoices);
var settings = new BusinessSettingsService(storage, recipes);
var riSup = new Supplier { Id = storage.GetNextSupplierId(), Name = "Distribuidora RI", Cuit = "30712345671", TaxCondition = TaxCondition.ResponsableInscripto };
var ri2Sup = new Supplier { Id = storage.GetNextSupplierId(), Name = "Mayorista RI", Cuit = FixtureCuit(400), TaxCondition = TaxCondition.ResponsableInscripto };
var monoSup = new Supplier { Id = storage.GetNextSupplierId(), Name = "Almacen Mono", Cuit = FixtureCuit(500), TaxCondition = TaxCondition.Monotributista };
var legacySup = new Supplier { Id = storage.GetNextSupplierId(), Name = "Proveedor legado" };
storage.Suppliers = [riSup, ri2Sup, monoSup, legacySup];
storage.SaveToFile();

var RI = TaxCondition.ResponsableInscripto; var Mono = TaxCondition.Monotributista; var Exe = TaxCondition.Exento;
void Business(TaxCondition? c) { if (c == null) { storage.BusinessSettings.TaxCondition = null; storage.SaveToFile(); } else settings.SetTaxCondition(c.Value, adminUser); }
string State() => JsonSerializer.Serialize(new { storage.Suppliers, storage.BusinessSettings, storage.Users, storage.Invoices, storage.Ingredients, storage.Recipes, storage.StockMovements,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
byte[] Bytes() => File.ReadAllBytes("data.json");
bool Unchanged(string state, byte[] bytes) => State() == state && Bytes().SequenceEqual(bytes);
string M(decimal amount) => PurchasingFormat.Money(amount);

// ---- Page plumbing ----
var asm = typeof(SupplierService).Assembly;
AuthService NewAuth(string? username)
{
    var auth = new AuthService(users);
    if (username != null) Check(auth.Login(username, "fixture-pass"), "circuit login " + username);
    return auth;
}
var anon = NewAuth(null); var employee = NewAuth("fixture-employee"); var admin = NewAuth("fixture-admin");
var invoicesType = asm.GetType("GastroApp.Pages.Invoices")!;
var workspaceType = asm.GetType("GastroApp.Shared.Purchasing.InvoiceWorkspace")!;
var listType = asm.GetType("GastroApp.Shared.Purchasing.InvoiceList")!;
object NewPage(AuthService auth, out TestNavigation nav)
{
    var page = Activator.CreateInstance(invoicesType)!; nav = new TestNavigation();
    void Inject(string name, object value) { var p = invoicesType.GetProperty(name, flags); p?.SetValue(page, value); }
    Inject("AuthService", auth); Inject("Navigation", nav); Inject("SupplierService", suppliers); Inject("InvoiceService", invoices);
    Inject("IngredientService", ingredients); Inject("BusinessSettingsService", settings);
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
string? Str(object page, string field) => Get(page, field) as string;
Invoice Draft(object page) => (Invoice)Get(page, "editingInvoice")!;
decimal Rate(object page) => Get(page, "itemVatRate") is decimal d ? d : -1m;
Invoice LastInv() => storage.Invoices.LastOrDefault() ?? new Invoice { Id = -1 };
InvoiceTax FirstTax(object page) => Draft(page).OtherTaxes.FirstOrDefault() ?? new InvoiceTax();
bool Ok(Exception? ex, string what) { if (ex != null) Console.WriteLine($"  call {what} failed: {ex.GetType().Name} {ex.Message}"); return ex == null; }

object OpenForm(out TestNavigation nav, AuthService? auth = null)
{
    var page = NewPage(auth ?? admin, out nav);
    Ok(Call(page, "OnInitializedAsync"), "OnInitializedAsync"); Ok(Call(page, "ShowAddForm"), "ShowAddForm");
    return page;
}
void AddLine(object page, Ingredient ingredient, string quantity, string price)
{
    Call(page, "SelectIngredient", ingredient.Id); Call(page, "SetQuantity", quantity); Call(page, "SetUnitPrice", price); Call(page, "AddItem");
}

// Static HTML of a component, decoded so accents can be asserted. A component that cannot render yields "".
string Render(Type type, AuthService auth, Dictionary<string, object?> parameters)
{
    try
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton(auth); services.AddSingleton(suppliers); services.AddSingleton(invoices); services.AddSingleton(settings); services.AddSingleton(ingredients);
        services.AddSingleton<NavigationManager>(new TestNavigation());
        services.AddSingleton<IJSRuntime>(new StubJs());
        using var provider = services.BuildServiceProvider();
        using var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>());
        var html = renderer.Dispatcher.InvokeAsync(async () => (await renderer.RenderComponentAsync(type, ParameterView.FromDictionary(parameters))).ToHtmlString()).GetAwaiter().GetResult();
        return WebUtility.HtmlDecode(html);
    }
    catch (Exception ex) { Console.WriteLine($"  render of {type.Name} failed: {ex.GetType().Name} {ex.Message.Split('\n')[0]}"); return string.Empty; }
}
// The workspace as the page would feed it: every parameter comes from the page's own state.
string Form(object page)
{
    var canSave = (Func<bool>)Delegate.CreateDelegate(typeof(Func<bool>), page, invoicesType.GetMethod("CanSaveInvoice", flags)!);
    return Render(workspaceType, admin, new Dictionary<string, object?>
    {
        ["Invoice"] = Get(page, "editingInvoice"), ["Suppliers"] = suppliers.GetAll(), ["Ingredients"] = ingredients.GetActive(),
        ["FormError"] = Get(page, "invoiceError"), ["BuilderError"] = Get(page, "builderError"), ["TaxError"] = Get(page, "taxError"), ["TypeNotice"] = Get(page, "typeNotice"),
        ["CanSave"] = canSave, ["BusinessCondition"] = settings.TaxCondition,
        ["SelectedIngredientId"] = Get(page, "selectedIngredientId"), ["QuantityText"] = Get(page, "itemQuantityText"), ["Unit"] = Get(page, "itemUnit"), ["PriceText"] = Get(page, "itemUnitPriceText"),
        ["VatRate"] = Get(page, "itemVatRate"), ["ContainedVatText"] = Get(page, "containedVatText"),
        ["TaxKind"] = Get(page, "taxKind"), ["TaxDetail"] = Get(page, "taxDetail"), ["TaxAmountText"] = Get(page, "taxAmountText")
    });
}
int Count(string html, string text) => Regex.Matches(html, Regex.Escape(text)).Count;
string Select(string html, string id) => Regex.Match(html, "<select[^>]*id=\"" + id + "\"[^>]*>.*?</select>", RegexOptions.Singleline).Value;
bool Has(string html, string id) => html.Contains("id=\"" + id + "\"");
bool SaveDisabled(string html) => Regex.IsMatch(html, "btn--lg\"[^>]*\\bdisabled");
string Row(string html, string text) => Regex.Match(html, @"<tr[^>]*>(?:(?!</tr>).)*" + Regex.Escape(text) + @"(?:(?!</tr>).)*</tr>", RegexOptions.Singleline).Value;
InvoiceItem It(Ingredient i, decimal q, decimal price, decimal? rate = null) => new() { IngredientId = i.Id, IngredientName = i.Name, Quantity = q, Unit = i.Unit, UnitPrice = price, VatRate = rate };

const string ConfigMsg = "Configurá la condición frente al IVA del negocio en Datos fiscales antes de registrar facturas.";
const string Cleared = "Se quitaron los ítems porque cambió el tipo de factura.";

// ================= Wiring in the page and the components (source) =================
var pageSource = Src("Pages/Invoices.razor"); var workspaceSource = Src("Shared/Purchasing/InvoiceWorkspace.razor"); var listSource = Src("Shared/Purchasing/InvoiceList.razor");
Check(pageSource.Contains("@inject BusinessSettingsService BusinessSettingsService") && pageSource.Contains("FiscalRules.ExpectedInvoiceType(") && pageSource.Contains("PurchasingFormat.TryParseDecimal(containedVatText")
    && pageSource.Contains("FiscalRules.VatRates") && pageSource.Contains("InvoiceService.Add(editingInvoice, AuthService.CurrentUser)"), "page: derives the type with FiscalRules, parses IVA contenido with TryParseDecimal and saves through InvoiceService.Add with the circuit user");
foreach (var parameter in new[] { "BusinessCondition=", "TypeNotice=", "TaxError=", "VatRate=", "ContainedVatText=", "TaxKind=", "TaxDetail=", "TaxAmountText=", "SupplierIdChanged=", "OnAddTax=", "OnRemoveTax=" })
    Check(pageSource.Contains(parameter), "page passes " + parameter.TrimEnd('=') + " to the workspace");
Check(workspaceSource.Contains("href=\"/settings/fiscal\"") && workspaceSource.Contains("FiscalRules.VatRates") && workspaceSource.Contains("<Banner") && workspaceSource.Contains("<Badge"), "workspace reuses Banner and Badge, FiscalRules.VatRates and links to /settings/fiscal");

// ================= S1 gate: business not configured =================
Business(null);
{
    var page = OpenForm(out _);
    var html = Form(page);
    Check(html.Contains("Configurá la condición frente al IVA del negocio en") && html.Contains("Datos fiscales") && html.Contains("href=\"/settings/fiscal\"") && html.Contains("banner--warn"),
        "business not configured: the workspace shows the S1 message with a link to /settings/fiscal in a warn Banner");
    Check(Ok(Call(page, "SetSupplier", riSup.Id), "SetSupplier") && Draft(page).SupplierId == riSup.Id && Draft(page).Type == null, "business not configured: choosing a supplier derives no type");
    AddLine(page, harina, "2", "100");
    Check(Str(page, "builderError") == ConfigMsg && Draft(page).Items.Count == 0, "business not configured: adding an item is refused with the S1 message [" + Str(page, "builderError") + "]");
    Draft(page).Items.Add(It(harina, 2m, 100m));
    var s = State(); var b = Bytes();
    Check(!(bool)invoicesType.GetMethod("CanSaveInvoice", flags)!.Invoke(page, null)!, "business not configured: CanSaveInvoice is false");
    Check(Ok(Call(page, "SaveInvoice"), "SaveInvoice") && Unchanged(s, b) && (bool)Get(page, "showForm")!, "business not configured: SaveInvoice stores nothing and keeps the form");
    Check(SaveDisabled(Form(page)), "business not configured: the save button is disabled");
}

// ================= Supplier options and derived type (S3) =================
foreach (var (business, supplier, expected) in new[] {
    (RI, riSup, InvoiceType.A), (RI, monoSup, InvoiceType.C), (Mono, riSup, InvoiceType.A), (Mono, monoSup, InvoiceType.C), (Exe, riSup, InvoiceType.B), (Exe, monoSup, InvoiceType.C) })
{
    Business(business);
    var page = OpenForm(out _);
    var before = Form(page);
    Check(!Has(before, "invoice-type") || !before.Contains("Factura "), $"{business}: no type is shown before choosing a supplier");
    Check(Ok(Call(page, "SetSupplier", supplier.Id), "SetSupplier") && Draft(page).Type == expected && Draft(page).SupplierId == supplier.Id, $"{business} business with {supplier.TaxCondition} supplier derives factura {expected}");
    var html = Form(page);
    var typeBox = Regex.Match(html, "id=\"invoice-type\"[^>]*>(.*?)<", RegexOptions.Singleline).Groups[1].Value;
    Check(typeBox.Contains("Factura " + expected) && !Regex.IsMatch(html, "<select[^>]*id=\"invoice-type\""), $"{business}/{supplier.TaxCondition}: the type is read-only text 'Factura {expected}' [{typeBox.Trim()}]");
}
Business(RI);
{
    var html = Form(OpenForm(out _));
    var supplierSelect = Select(html, "invoice-supplier");
    Check(Regex.IsMatch(supplierSelect, "<option[^>]*\\bdisabled[^>]*>\\s*Proveedor legado \\(datos fiscales incompletos\\)\\s*</option>"), "a supplier without fiscal data is a disabled option labelled '(datos fiscales incompletos)'");
    Check(Regex.IsMatch(supplierSelect, "<option(?![^>]*\\bdisabled)[^>]*>\\s*Distribuidora RI\\s*</option>") && Regex.IsMatch(supplierSelect, "<option(?![^>]*\\bdisabled)[^>]*>\\s*Almacen Mono\\s*</option>"), "suppliers with fiscal data are enabled options");
    Check(!html.Contains("banner--warn") || !html.Contains("Configurá la condición"), "business configured: no S1 banner");
}
{
    // A stale selection of an incomplete supplier cannot be saved and derives no type.
    var page = OpenForm(out _);
    Call(page, "SetSupplier", legacySup.Id);
    Draft(page).Items.Add(It(harina, 1m, 10m));
    var s = State(); var b = Bytes();
    Check(Draft(page).Type == null && !(bool)invoicesType.GetMethod("CanSaveInvoice", flags)!.Invoke(page, null)! && Call(page, "SaveInvoice") == null && Unchanged(s, b), "an incomplete supplier derives no type and the invoice cannot be saved");
}

// ================= S4: factura A =================
Business(RI);
{
    var page = OpenForm(out _);
    Call(page, "SetSupplier", riSup.Id);
    Call(page, "SelectIngredient", harina.Id); Call(page, "SetQuantity", "3"); Call(page, "SetUnitPrice", "100");
    var html = Form(page);
    Check(html.Contains("Precio neto por kg (sin IVA)") && !html.Contains("Precio final por"), "A: the price label says 'Precio neto por kg (sin IVA)'");
    var rateSelect = Select(html, "invoice-vat-rate");
    foreach (var label in new[] { "0%", "2,5%", "5%", "10,5%", "21%", "27%" }) Check(rateSelect.Contains($">{label}</option>"), "A: the rate select offers " + label);
    Check(Count(rateSelect, "</option>") == 6 && Regex.IsMatch(rateSelect, "<option[^>]* selected[^>]*>21%</option>") && Rate(page) == 21m, "A: exactly the six rates and 21% by default");
    Check(html.Contains("Subtotal neto: " + M(300m)) && html.Contains("IVA 21%: " + M(63m)), "A: the line preview shows the net subtotal and the IVA at the chosen rate");
    Check(Has(html, "invoice-legend") && html.Contains(">Sin leyenda</option>") && html.Contains(">OPERACIÓN SUJETA A RETENCIÓN</option>") && html.Contains(">PAGO EN CBU INFORMADA</option>") && !Has(html, "invoice-contained-vat"), "A: the legend select is offered and IVA contenido is not");

    Call(page, "SetVatRate", 7m);
    Check(Rate(page) == 21m, "A: a rate outside FiscalRules.VatRates is ignored");
    Call(page, "SetQuantity", "10"); Call(page, "SetUnitPrice", "1000"); Call(page, "AddItem");
    Call(page, "SetVatRate", 10.5m);
    AddLine(page, aceite, "2", "500");
    var items = Draft(page).Items;
    Check(items.Count == 2 && items[0].VatRate == 21m && items[0].UnitPrice == 1000m && items[1].VatRate == 10.5m && items[1].Quantity == 2m, "A: each line keeps the rate chosen when it was added and the typed (net) price");
    html = Form(page);
    Check(html.Contains(">Alícuota IVA</th>") && html.Contains(">21%</td>") && html.Contains(">10,5%</td>") && html.Contains("Subtotal neto"), "A: the items table shows the rate per line and the net subtotal");
    Check(html.Contains("Neto gravado") && html.Contains(M(11000m)) && html.Contains("IVA 10,5%") && html.Contains("IVA 21%") && html.Contains(M(105m)) && html.Contains(M(2100m)), "A: totals show neto gravado and the IVA of each rate");
    Check(html.Contains(">Total factura (2 ítem(s))<") && Count(html, M(13205m)) >= 1 && html.Contains("Impacto en stock") && html.Contains("+10 kg"), "A: the total adds the IVA per rate; the stock impact column is preserved");
    Check(html.Contains("name=\"invoice-unit\"") || html.Contains("unit-static"), "PRESERVE: the poka-yoke unit control is still rendered");

    Draft(page).Legend = InvoiceLegend.OperacionSujetaARetencion; Draft(page).InvoiceNumber = "A-0001-0000123";
    var stockBefore = harina.CurrentStock;
    Check(Ok(Call(page, "SaveInvoice"), "SaveInvoice") && !(bool)Get(page, "showForm")! && Str(page, "invoiceError") == null, "A: a valid invoice saves and closes the form");
    var stored = LastInv();
    Check(stored.Type == InvoiceType.A && stored.Legend == InvoiceLegend.OperacionSujetaARetencion && stored.Items.Select(i => i.VatRate).SequenceEqual(new decimal?[] { 21m, 10.5m }) && stored.Total == 13205m
        && stored.VatByRate.Select(l => (l.Rate, l.Net, l.Vat)).SequenceEqual(new[] { (10.5m, 1000m, 105m), (21m, 10000m, 2100m) }), "A: the stored invoice has type A, the legend, the rates and the totals per rate");
    Check(harina.CurrentStock == stockBefore + 10m && new DataStorageService().Invoices.Any(i => i.InvoiceNumber == "A-0001-0000123" && i.Type == InvoiceType.A), "A: stock was received and the invoice persists in data.json");
}

// ================= S4: factura B (IVA contenido) =================
Business(Exe);
{
    var page = OpenForm(out _);
    Call(page, "SetSupplier", riSup.Id);
    Call(page, "SelectIngredient", harina.Id);
    var html = Form(page);
    Check(html.Contains("Precio final por kg (IVA incluido)") && !html.Contains("(sin IVA)") && !Has(html, "invoice-vat-rate") && !Has(html, "invoice-legend") && !html.Contains(">Alícuota IVA</th>", StringComparison.Ordinal), "B: 'Precio final por kg (IVA incluido)', no rate select and no legend");
    Check(Has(html, "invoice-contained-vat") && html.Contains("IVA contenido (informativo)"), "B: the optional IVA contenido (informativo) field is offered");
    AddLine(page, harina, "10", "100");
    Check(Draft(page).Items.Count == 1 && Draft(page).Items[0].VatRate == null, "B: the line carries no rate");

    // Rejected by the page: not a number.
    Call(page, "SetContainedVat", "abc");
    var s = State(); var b = Bytes();
    Check(Ok(Call(page, "SaveInvoice"), "SaveInvoice") && Str(page, "invoiceError") == "Ingresá un IVA contenido válido." && Unchanged(s, b) && (bool)Get(page, "showForm")!, "B: an IVA contenido that is not a number is shown in the form error and stores nothing [" + Str(page, "invoiceError") + "]");
    // Rejected by the service: not lower than the total.
    Call(page, "SetContainedVat", "1000");
    Check(Ok(Call(page, "SaveInvoice"), "SaveInvoice") && Str(page, "invoiceError") == "El IVA contenido debe ser mayor o igual a cero y menor que el total de la factura." && Unchanged(s, b), "B: the service message for an IVA contenido that is not lower than the total is shown and nothing is stored");
    Check(Form(page).Contains("El IVA contenido debe ser mayor o igual a cero"), "B: the service error is rendered in the form");
    Call(page, "SetContainedVat", "210");
    var html2 = Form(page);
    Check(html2.Contains("IVA contenido") && html2.Contains(M(210m)) && html2.Contains("informativo") && !html2.Contains("Neto gravado") && html2.Contains(">Total factura (1 ítem(s))<") && html2.Contains(M(1000m)), "B: totals show IVA contenido as informative and the total without adding it");
    Check(Ok(Call(page, "SaveInvoice"), "SaveInvoice") && !(bool)Get(page, "showForm")!, "B: the invoice saves");
    var stored = LastInv();
    Check(stored.Type == InvoiceType.B && stored.ContainedVat == 210m && stored.Total == 1000m && stored.VatByRate.Count == 0 && stored.Items.All(i => i.VatRate == null) && stored.Legend == InvoiceLegend.None, "B: the stored invoice has type B and the IVA contenido, with no rates");
}

// ================= S4: factura C =================
Business(RI);
{
    var page = OpenForm(out _);
    Call(page, "SetSupplier", monoSup.Id);
    Call(page, "SelectIngredient", harina.Id);
    var html = Form(page);
    Check(html.Contains("Precio final por kg") && !html.Contains("(IVA incluido)") && !html.Contains("(sin IVA)") && !Has(html, "invoice-vat-rate") && !Has(html, "invoice-contained-vat") && !Has(html, "invoice-legend") && !html.Contains("Alícuota IVA"), "C: 'Precio final por kg' and no VAT, IVA contenido or legend fields");
    AddLine(page, harina, "4", "50");
    Check(Ok(Call(page, "SaveInvoice"), "SaveInvoice") && !(bool)Get(page, "showForm")!, "C: the invoice saves");
    var stored = LastInv();
    Check(stored.Type == InvoiceType.C && stored.ContainedVat == null && stored.Items.All(i => i.VatRate == null) && stored.Total == 200m && stored.Legend == InvoiceLegend.None, "C: the stored invoice has type C, no VAT data and the typed total");
}

// ================= S5: other taxes =================
{
    string[] all = ["Percepción de IVA", "Percepción de IIBB", "Impuestos internos", "Otros tributos"];
    foreach (var (business, supplier, type, offersIva) in new[] { (RI, riSup, "A", true), (Exe, riSup, "B", false), (RI, monoSup, "C", false) })
    {
        Business(business);
        var page = OpenForm(out _); Call(page, "SetSupplier", supplier.Id);
        var kinds = Select(Form(page), "invoice-tax-kind");
        Check(all.Where(l => l != "Percepción de IVA").All(l => kinds.Contains($">{l}</option>")) && kinds.Contains(">Percepción de IVA</option>") == offersIva, $"{type}: the tax kind select {(offersIva ? "offers" : "does not offer")} Percepción de IVA and offers the other three");
    }

    Business(RI);
    var p = OpenForm(out _); Call(p, "SetSupplier", riSup.Id);
    AddLine(p, harina, "1", "1000");
    Call(p, "SetTaxKind", InvoiceTaxKind.PercepcionIibb);
    var html = Form(p);
    Check(html.Contains("Jurisdicción") && Has(html, "invoice-tax-amount"), "IIBB: the detail field is labelled 'Jurisdicción'");
    Call(p, "SetTaxKind", InvoiceTaxKind.OtrosTributos);
    Check(Form(p).Contains("Descripción"), "Otros tributos: the detail field is labelled 'Descripción'");

    // Invalid amounts are refused by the page.
    foreach (var amount in new[] { "", "abc", "0", "-5" })
    {
        Call(p, "SetTaxAmount", amount); Call(p, "AddTax");
        Check(Draft(p).OtherTaxes.Count == 0 && Str(p, "taxError") == "Ingresá un importe mayor a cero.", $"AddTax with amount '{amount}' is refused [{Str(p, "taxError")}]");
    }
    // Add, render and remove.
    Call(p, "SetTaxKind", InvoiceTaxKind.PercepcionIibb); Call(p, "SetTaxDetail", " Buenos Aires "); Call(p, "SetTaxAmount", "150");
    Check(Ok(Call(p, "AddTax"), "AddTax") && Draft(p).OtherTaxes.Count == 1 && Draft(p).OtherTaxes[0].Kind == InvoiceTaxKind.PercepcionIibb && Draft(p).OtherTaxes[0].Amount == 150m && Str(p, "taxError") == null
        && Str(p, "taxAmountText") == "" && Str(p, "taxDetail") == "", "AddTax adds the row and clears the tax inputs");
    html = Form(p);
    Check(html.Contains("Percepción de IIBB") && html.Contains("Buenos Aires") && html.Contains(M(150m)) && html.Contains(">Total factura (1 ítem(s))<") && html.Contains(M(1000m + 210m + 150m)), "the other tax row and its amount are listed and added to the total (A: net + IVA 21% + tax)");
    var tax = FirstTax(p);
    Check(Ok(Call(p, "RemoveTax", tax), "RemoveTax") && Draft(p).OtherTaxes.Count == 0 && !Form(p).Contains("Buenos Aires"), "RemoveTax removes the row");

    // Missing IIBB jurisdiction: the service message, nothing stored.
    Call(p, "SetTaxKind", InvoiceTaxKind.PercepcionIibb); Call(p, "SetTaxDetail", "   "); Call(p, "SetTaxAmount", "100"); Call(p, "AddTax");
    Check(Draft(p).OtherTaxes.Count == 1, "AddTax leaves the missing jurisdiction to the service");
    var s = State(); var b = Bytes();
    Check(Ok(Call(p, "SaveInvoice"), "SaveInvoice") && Str(p, "invoiceError") == "Indicá la jurisdicción de la percepción de IIBB." && Unchanged(s, b) && (bool)Get(p, "showForm")!, "IIBB without jurisdiction: the service message is shown in the form error and nothing is stored");
    Check(Form(p).Contains("Indicá la jurisdicción de la percepción de IIBB.") && Form(p).Contains("banner--danger"), "the form error is rendered in a danger Banner");
    Call(p, "RemoveTax", FirstTax(p));
    Call(p, "SetTaxKind", InvoiceTaxKind.OtrosTributos); Call(p, "SetTaxDetail", " "); Call(p, "SetTaxAmount", "10"); Call(p, "AddTax");
    Check(Ok(Call(p, "SaveInvoice"), "SaveInvoice") && Str(p, "invoiceError") == "Describí el tributo." && Unchanged(s, b), "Otros tributos without a description: 'Describí el tributo.' and nothing is stored");
    Call(p, "RemoveTax", FirstTax(p));
    Call(p, "SetTaxKind", InvoiceTaxKind.PercepcionIibb); Call(p, "SetTaxDetail", "  CABA "); Call(p, "SetTaxAmount", "100"); Call(p, "AddTax");
    Call(p, "SetTaxKind", InvoiceTaxKind.PercepcionIva); Call(p, "SetTaxDetail", ""); Call(p, "SetTaxAmount", "50"); Call(p, "AddTax");
    Check(Draft(p).OtherTaxes.Count == 2, "A: a Percepción de IVA row can be added");
    Check(Ok(Call(p, "SaveInvoice"), "SaveInvoice") && !(bool)Get(p, "showForm")!, "A with two other taxes saves");
    var stored = LastInv();
    Check(stored.OtherTaxes.Count == 2 && stored.OtherTaxes[0].Detail == "CABA" && stored.OtherTaxesTotal == 150m && stored.Total == 1000m + 210m + 150m, "the stored invoice keeps the taxes (detail trimmed) and the total includes them");

    // Percepción de IVA is refused outside factura A, also if forced.
    Business(Exe);
    var pb = OpenForm(out _); Call(pb, "SetSupplier", riSup.Id); AddLine(pb, harina, "1", "100");
    Call(pb, "SetTaxKind", InvoiceTaxKind.PercepcionIva); Call(pb, "SetTaxAmount", "5"); Call(pb, "AddTax");
    Check(Draft(pb).OtherTaxes.Count == 0 && Str(pb, "taxError") == "La percepción de IVA solo corresponde a facturas A.", "B: AddTax refuses a Percepción de IVA [" + Str(pb, "taxError") + "]");
}

// ================= S3/S4: changing the supplier changes the type =================
Business(RI);
{
    var page = OpenForm(out _);
    Call(page, "SetSupplier", riSup.Id);
    Check(Str(page, "typeNotice") == null, "choosing the first supplier shows no notice");
    AddLine(page, harina, "1", "100"); Draft(page).Legend = InvoiceLegend.PagoEnCbuInformada;
    Call(page, "SetTaxKind", InvoiceTaxKind.ImpuestosInternos); Call(page, "SetTaxAmount", "7"); Call(page, "AddTax");
    Call(page, "SetSupplier", ri2Sup.Id);
    Check(Draft(page).Type == InvoiceType.A && Draft(page).Items.Count == 1 && Draft(page).OtherTaxes.Count == 1 && Draft(page).Legend == InvoiceLegend.PagoEnCbuInformada && Str(page, "typeNotice") == null, "a supplier with the same type keeps items, taxes and legend and shows no notice");
    Call(page, "SetSupplier", monoSup.Id);
    var d = Draft(page);
    Check(d.Type == InvoiceType.C && d.Items.Count == 0 && d.OtherTaxes.Count == 0 && d.Legend == InvoiceLegend.None && d.ContainedVat == null && d.SupplierId == monoSup.Id, "a supplier that changes the type clears items, other taxes and legend");
    Check(Str(page, "typeNotice") == Cleared && Form(page).Contains(Cleared), "the L10 message is shown after the type changed [" + Str(page, "typeNotice") + "]");
    Call(page, "SetSupplier", monoSup.Id);
    Check(Ok(Call(page, "SetSupplier", ri2Sup.Id), "SetSupplier") && Str(page, "typeNotice") == null, "changing the type with nothing to clear shows no notice");

    Business(Exe);
    var pb = OpenForm(out _); Call(pb, "SetSupplier", riSup.Id); AddLine(pb, harina, "1", "100"); Call(pb, "SetContainedVat", "10");
    Call(pb, "SetSupplier", monoSup.Id);
    Check(Draft(pb).Items.Count == 0 && Str(pb, "containedVatText") == "" && Str(pb, "typeNotice") == Cleared, "B to C also clears the typed IVA contenido");
    Call(pb, "SetSupplier", riSup.Id);
    Check(Draft(pb).Type == InvoiceType.B && Str(pb, "containedVatText") == "", "going back to B starts without IVA contenido");

    // The guard of the admin applies to the new actions (PRESERVE of the existing guard).
    Business(RI);
    foreach (var (auth, who, destination) in new[] { (anon, "anonymous", "/login"), (employee, "employee", "/unauthorized") })
    {
        var page2 = NewPage(auth, out var nav);
        var s = State(); var b = Bytes();
        foreach (var (method, arg) in new (string, object?)[] { ("SetSupplier", riSup.Id), ("SetVatRate", 10.5m), ("SetContainedVat", "5"), ("SetTaxAmount", "5"), ("AddTax", null) })
        {
            nav.Destination = null;
            var args2 = arg == null ? Array.Empty<object?>() : new[] { arg };
            Check(Call(page2, method, args2) == null && nav.Destination == destination && Unchanged(s, b), $"PRESERVE: {who} calling {method} is sent to {destination} and nothing changes");
        }
    }
}

// ================= S7/S8: invoice list =================
{
    var invA = new Invoice { Id = 1, SupplierId = riSup.Id, InvoiceNumber = "A-0001-1", Type = InvoiceType.A, Legend = InvoiceLegend.OperacionSujetaARetencion,
        Items = [It(harina, 10m, 1000m, 21m), It(aceite, 2m, 500m, 10.5m)], OtherTaxes = [new InvoiceTax { Kind = InvoiceTaxKind.PercepcionIibb, Detail = "CABA", Amount = 150m }] };
    var invB = new Invoice { Id = 2, SupplierId = riSup.Id, InvoiceNumber = "B-0001-2", Type = InvoiceType.B, ContainedVat = 210m, Items = [It(harina, 10m, 100m)] };
    var invC = new Invoice { Id = 3, SupplierId = monoSup.Id, InvoiceNumber = "C-0001-3", Type = InvoiceType.C, Items = [It(harina, 4m, 50m)] };
    var legacy = new Invoice { Id = 4, SupplierId = monoSup.Id, InvoiceNumber = "L-0001-4", Items = [It(harina, 2m, 30m)] };
    var html = Render(listType, admin, new Dictionary<string, object?> { ["Invoices"] = new List<Invoice> { invA, invB, invC, legacy }, ["Suppliers"] = suppliers.GetAll() });
    Check(html.Contains(">Factura A<") && html.Contains(">Factura B<") && html.Contains(">Factura C<") && Count(html, ">Factura A<") == 1 && html.Contains("badge"), "list: every typed invoice shows its type badge");
    Check(Count(html, "Tipo no informado · precio final") == 1, "list: the legacy invoice shows 'Tipo no informado · precio final' (" + Count(html, "Tipo no informado · precio final") + ")");
    var rowA = Row(html, "A-0001-1"); var rowB = Row(html, "B-0001-2"); var rowC = Row(html, "C-0001-3"); var rowL = Row(html, "L-0001-4");
    Check(rowA != "" && rowA.Contains("Neto") && rowA.Contains(M(11000m)) && rowA.Contains("IVA") && rowA.Contains(M(2205m)) && rowA.Contains("Otros tributos") && rowA.Contains(M(150m)) && rowA.Contains(M(13355m)), "list: factura A shows neto, IVA, otros tributos and the total");
    Check(rowA.Contains("OPERACIÓN SUJETA A RETENCIÓN") && rowA.Contains("21%") && rowA.Contains("10,5%"), "list: factura A shows its legend and the rate of each line");
    Check(rowB != "" && rowB.Contains("IVA contenido") && rowB.Contains(M(210m)) && !rowB.Contains("Neto") && !rowB.Contains("Otros tributos") && rowB.Contains(M(1000m)), "list: factura B shows the informative IVA contenido and no neto breakdown");
    Check(rowC != "" && !rowC.Contains("Neto") && !rowC.Contains("IVA") && !rowC.Contains("Otros tributos") && rowC.Contains(M(200m)), "list: factura C shows its total only");
    Check(rowL != "" && rowL.Contains("Tipo no informado · precio final") && !rowL.Contains("Neto") && !rowL.Contains("IVA") && !rowL.Contains("Factura ") && rowL.Contains(M(60m)), "list: the legacy row shows only the legacy badge and its total, never reinterpreted");
    Check(html.Contains("Total factura") && html.Contains("Eliminar") && html.Contains("Ítems ingresados"), "PRESERVE: the list keeps its columns and the delete action");
    var empty = Render(listType, admin, new Dictionary<string, object?> { ["Invoices"] = new List<Invoice>(), ["Suppliers"] = new List<Supplier>() });
    Check(empty.Contains("Sin facturas registradas") && empty.Contains("Registrar factura"), "PRESERVE: the empty state is unchanged");
}

// ================= Docs =================
var doc = Src("Docs/Architecture/Purchasing.md");
Check(doc.Contains("## Invoice screen") && doc.Contains("InvoiceWorkspace") && doc.Contains("Se quitaron los ítems porque cambió el tipo de factura.") && doc.Contains("Tipo no informado · precio final") && doc.Contains("/settings/fiscal") && doc.Contains("IVA contenido") && doc.Contains("TryParseDecimal"),
    "Purchasing.md documents the invoice screen behavior");
var features = Src("IMPLEMENTED_FEATURES.md");
Check(features.Contains("Factura A") && features.Contains("IVA contenido") && features.Contains("Percepción de IIBB") && features.Contains("Tipo no informado · precio final") && features.Contains("Se quitaron los ítems porque cambió el tipo de factura.") && !features.Contains("Invoice registration against this condition is documented with the invoice screens."),
    "IMPLEMENTED_FEATURES documents invoice types, IVA and other taxes");

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
    & dotnet run --project (Join-Path $ScratchPath 'InvoiceVatUiChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Invoice VAT UI checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
