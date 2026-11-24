param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-purchase-vat-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'PurchaseVatChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var root = Directory.GetCurrentDirectory();
var repoRoot = args[0];
var storage = new DataStorageService(); // Process cwd is ALWAYS the newly allocated temp directory.
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var admin = storage.Users[0]; var employee = storage.Users[1];
var staleAdmin = new User { Id = 10, Username = "fixture-admin", PasswordHash = "stale", Role = UserRole.Admin };
var harina = new Ingredient { Id = 1, Name = "Harina", Unit = "kg", IsActive = true };
var leche = new Ingredient { Id = 2, Name = "Leche", Unit = "lt", IsActive = true };
var huevo = new Ingredient { Id = 3, Name = "Huevo", Unit = "unidad", IsActive = true };
storage.Ingredients = [harina, leche, huevo]; storage.Recipes = []; storage.Invoices = []; storage.Suppliers = []; storage.Products = [];
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
invoices.SetIngredientService(ingredients);
var recipes = new RecipeService(storage, invoices);
var suppliers = new SupplierService(storage);
var business = new BusinessSettingsService(storage, recipes);
storage.SaveToFile();

var RI = TaxCondition.ResponsableInscripto; var Mono = TaxCondition.Monotributista; var Exe = TaxCondition.Exento;
var TA = InvoiceType.A; var TB = InvoiceType.B; var TC = InvoiceType.C;
const string NotAdmin = "Se requiere un usuario administrador vigente.";
const string ConfigMsg = "Configurá la condición frente al IVA del negocio en Datos fiscales antes de registrar facturas.";
string Label(TaxCondition c) => c switch { TaxCondition.ResponsableInscripto => "Responsable Inscripto", TaxCondition.Monotributista => "Monotributista", _ => "Exento" };
string State() => JsonSerializer.Serialize(new { storage.Suppliers, storage.Invoices, storage.Ingredients, storage.Recipes, storage.StockMovements, storage.BusinessSettings, storage.Users,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
Exception? Try(Action action) { try { action(); return null; } catch (Exception ex) { return ex; } }
// A call that must be rejected: exception type and message, the stored state, the counters, the passed object and data.json bytes stay identical.
void Reject(Action action, Type type, string message, string name, object? passed = null)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json"); var passedBefore = JsonSerializer.Serialize(passed);
    var ex = Try(action);
    Check(ex != null && ex.GetType() == type && ex.Message == message, $"{name} rejected with {type.Name} / {message}" + (ex != null && ex.GetType() == type && ex.Message == message ? "" : $" [{ex?.GetType().Name} {ex?.Message}]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")) && JsonSerializer.Serialize(passed) == passedBefore, $"{name} leaves objects, counters, the passed object and file bytes unchanged");
}
void Invalid(Action action, string message, string name, object? passed = null) => Reject(action, typeof(InvalidOperationException), message, name, passed);
DataStorageService Reload() => new DataStorageService();
void SetBusiness(TaxCondition c) { var ex = Try(() => business.SetTaxCondition(c, admin)); if (ex != null) Check(false, "SetTaxCondition " + c + " by admin [" + ex.Message + "]"); }

Supplier Sup(string name, string cuit, TaxCondition? c) => new() { Name = name, Cuit = cuit, TaxCondition = c };
int seq = 0;
InvoiceItem It(Ingredient i, decimal q, decimal price, decimal? rate = null, string? unit = null) => new() { IngredientId = i.Id, IngredientName = i.Name, Quantity = q, Unit = unit ?? i.Unit, UnitPrice = price, VatRate = rate };
Invoice Inv(Supplier s, InvoiceType? type, params InvoiceItem[] items) => new() { SupplierId = s.Id, InvoiceNumber = "T-" + (++seq), Type = type, Items = items.ToList() };
Invoice ValidFor(Supplier s, InvoiceType t) => Inv(s, t, It(harina, 2m, 100m, t == TA ? 21m : null));
InvoiceTax Tax(InvoiceTaxKind kind, decimal amount, string detail = "") => new() { Kind = kind, Amount = amount, Detail = detail };
void Accept(Invoice inv, string name)
{
    var count = storage.Invoices.Count; var movements = storage.StockMovements.Count; var nextBefore = storage.Invoices.Select(i => i.Id).DefaultIfEmpty(0).Max();
    var ex = Try(() => invoices.Add(inv, admin));
    Check(ex == null && storage.Invoices.Count == count + 1 && inv.Id > nextBefore && storage.Invoices.Contains(inv) && inv.Items.All(i => i.InvoiceId == inv.Id)
        && storage.StockMovements.Count == movements + inv.Items.Count && storage.StockMovements.Count(m => m.InvoiceId == inv.Id && m.Type == StockMovementType.InvoiceReceipt) == inv.Items.Count,
        name + " accepted, stored with its id and received into stock" + (ex == null ? "" : " [" + ex.Message + "]"));
}

// ---- Labels, rates and CUIT rules (FiscalRules) ----
Check(FiscalRules.Label(RI) == "Responsable Inscripto" && FiscalRules.Label(Mono) == "Monotributista" && FiscalRules.Label(Exe) == "Exento", "tax condition labels");
Check(FiscalRules.Label(InvoiceTaxKind.PercepcionIva) == "Percepción de IVA" && FiscalRules.Label(InvoiceTaxKind.PercepcionIibb) == "Percepción de IIBB"
    && FiscalRules.Label(InvoiceTaxKind.ImpuestosInternos) == "Impuestos internos" && FiscalRules.Label(InvoiceTaxKind.OtrosTributos) == "Otros tributos", "other tax labels");
Check(FiscalRules.VatRates.SequenceEqual([0m, 2.5m, 5m, 10.5m, 21m, 27m]), "VAT rates are 0, 2.5, 5, 10.5, 21 and 27 percent");
Check((int)RI == 1 && (int)Mono == 2 && (int)Exe == 3 && (int)TA == 1 && (int)TB == 2 && (int)TC == 3 && (int)InvoiceLegend.None == 0 && (int)InvoiceLegend.OperacionSujetaARetencion == 1 && (int)InvoiceLegend.PagoEnCbuInformada == 2
    && (int)InvoiceTaxKind.PercepcionIva == 1 && (int)InvoiceTaxKind.PercepcionIibb == 2 && (int)InvoiceTaxKind.ImpuestosInternos == 3 && (int)InvoiceTaxKind.OtrosTributos == 4, "enum values match the persisted contract");
int Remainder(string ten) { int[] w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]; int sum = 0; for (int i = 0; i < 10; i++) sum += (ten[i] - '0') * w[i]; return sum % 11; }
string? zeroCheck = null, tenCase = null; var plain = new List<string>();
for (long n = 2000000000; zeroCheck == null || tenCase == null || plain.Count < 3; n++)
{
    var t = n.ToString(); var r = Remainder(t);
    if (r == 0 && zeroCheck == null) zeroCheck = t + "0";
    if (r == 1 && tenCase == null) tenCase = t + "0";
    if (r > 1 && plain.Count < 3) plain.Add(t + (11 - r));
}
foreach (var valid in new[] { "20-12345678-6", "27-23456789-1", "30-71234567-1", "20123456786", " 20-12345678-6 ", zeroCheck! })
    Check(FiscalRules.TryNormalizeCuit(valid, out var normalized) && normalized.Length == 11 && normalized == valid.Trim().Replace("-", ""), $"valid CUIT '{valid}' normalizes to 11 digits");
foreach (var bad in new[] { "20-12345678-7", "20-12345678-0", "2012345678", "201234567866", "20-1234567a-6", "abc", "20 12345678 6", "", "   ", tenCase!, tenCase![..10] + "9" })
    Check(!FiscalRules.TryNormalizeCuit(bad, out var junk) && junk == string.Empty, $"invalid CUIT '{bad}' is rejected (check digit 10 is invalid, not 0)");
Check(!FiscalRules.TryNormalizeCuit(null, out _), "null CUIT is rejected");
var expectations = new (TaxCondition Supplier, TaxCondition Business, InvoiceType Type)[] {
    (RI, RI, TA), (RI, Mono, TA), (RI, Exe, TB), (Mono, RI, TC), (Mono, Mono, TC), (Mono, Exe, TC), (Exe, RI, TC), (Exe, Mono, TC), (Exe, Exe, TC) };
Check(expectations.All(e => FiscalRules.ExpectedInvoiceType(e.Supplier, e.Business) == e.Type), "ExpectedInvoiceType covers all 9 combinations");

// ---- S1: business settings ----
Check(business.TaxCondition == null && storage.BusinessSettings.TaxCondition == null, "the business tax condition starts not configured");
Reject(() => business.SetTaxCondition(RI, employee), typeof(UnauthorizedAccessException), NotAdmin, "SetTaxCondition by an employee");
Reject(() => business.SetTaxCondition(RI, null), typeof(UnauthorizedAccessException), NotAdmin, "SetTaxCondition without actor");
Reject(() => business.SetTaxCondition(RI, staleAdmin), typeof(UnauthorizedAccessException), NotAdmin, "SetTaxCondition by a stale admin");
Reject(() => business.SetTaxCondition((TaxCondition)0, employee), typeof(UnauthorizedAccessException), NotAdmin, "SetTaxCondition by an employee with an undefined value (identity first)");
Invalid(() => business.SetTaxCondition((TaxCondition)0, admin), "Elegí una condición frente al IVA válida.", "SetTaxCondition 0");
Invalid(() => business.SetTaxCondition((TaxCondition)9, admin), "Elegí una condición frente al IVA válida.", "SetTaxCondition 9");

// ---- S2: suppliers ----
const string C1 = "20-12345678-6", C2 = "27-23456789-1", C3 = "30-71234567-1";
void BadSupplier(Supplier s, string message, string name) => Invalid(() => suppliers.Add(s), message, "Supplier.Add " + name, s);
BadSupplier(Sup("  ", C1, RI), "Ingresá un nombre para el proveedor.", "blank name");
BadSupplier(Sup("S", "", RI), "Ingresá el CUIT del proveedor.", "empty CUIT");
BadSupplier(Sup("S", "   ", RI), "Ingresá el CUIT del proveedor.", "blank CUIT");
BadSupplier(Sup("S", null!, RI), "Ingresá el CUIT del proveedor.", "null CUIT");
BadSupplier(Sup("S", "20-12345678-5", RI), "El CUIT no es válido.", "wrong check digit");
BadSupplier(Sup("S", "2012345678", RI), "El CUIT no es válido.", "10 digits");
BadSupplier(Sup("S", "20-1234567x-6", RI), "El CUIT no es válido.", "letters");
BadSupplier(Sup("S", tenCase!, RI), "El CUIT no es válido.", "check digit 10");
BadSupplier(Sup("S", C1, null), "Elegí la condición frente al IVA del proveedor.", "no condition");
BadSupplier(Sup("S", C1, (TaxCondition)0), "Elegí la condición frente al IVA del proveedor.", "condition 0");
BadSupplier(Sup("S", C1, (TaxCondition)9), "Elegí la condición frente al IVA del proveedor.", "condition 9");
BadSupplier(Sup("S", "20-12345678-5", null), "El CUIT no es válido.", "invalid CUIT reported before the condition");
var sRI = Sup("Distribuidora RI", C1, RI);
var addEx = Try(() => suppliers.Add(sRI));
Check(addEx == null && sRI.Id > 0 && sRI.Cuit == "20123456786" && sRI.TaxCondition == RI && sRI.HasFiscalData && suppliers.GetById(sRI.Id) == sRI, "valid supplier is stored with its CUIT as 11 digits" + (addEx == null ? "" : " [" + addEx.Message + "]"));
var sMono = Sup("Mono", C2, Mono); var sExe = Sup("Exento", C3, Exe); var sCero = Sup("Cero", zeroCheck!, RI);
Check(Try(() => suppliers.Add(sMono)) == null && Try(() => suppliers.Add(sExe)) == null && Try(() => suppliers.Add(sCero)) == null && sMono.Cuit == "27234567891" && sExe.Cuit == "30712345671" && sCero.Cuit == zeroCheck, "more suppliers stored (typed with or without dashes; a check digit of 0 is valid)");
var reloaded = Reload();
var sRIFile = reloaded.Suppliers.FirstOrDefault(s => s.Id == sRI.Id);
Check(sRIFile != null && sRIFile.Cuit == "20123456786" && sRIFile.TaxCondition == RI && sRIFile.HasFiscalData && sRIFile.Name == "Distribuidora RI", "supplier CUIT and condition persist to data.json");
BadSupplier(Sup("Otro", "20123456786", Mono), "Ya existe un proveedor con ese CUIT.", "duplicate CUIT");
BadSupplier(Sup("Otro", " 20-12345678-6 ", Mono), "Ya existe un proveedor con ese CUIT.", "duplicate CUIT typed with dashes and spaces");
var temp = Sup("Temporal", plain[0], Mono); suppliers.Add(temp);
Invalid(() => suppliers.Update(new Supplier { Id = temp.Id, Name = "T", Cuit = C1, TaxCondition = Mono }), "Ya existe un proveedor con ese CUIT.", "Supplier.Update with another supplier's CUIT");
Invalid(() => suppliers.Update(new Supplier { Id = temp.Id, Name = " ", Cuit = plain[0], TaxCondition = Mono }), "Ingresá un nombre para el proveedor.", "Supplier.Update blank name");
Invalid(() => suppliers.Update(new Supplier { Id = temp.Id, Name = "T", Cuit = "", TaxCondition = Mono }), "Ingresá el CUIT del proveedor.", "Supplier.Update empty CUIT");
Invalid(() => suppliers.Update(new Supplier { Id = temp.Id, Name = "T", Cuit = "11111111111", TaxCondition = Mono }), "El CUIT no es válido.", "Supplier.Update invalid CUIT");
Invalid(() => suppliers.Update(new Supplier { Id = temp.Id, Name = "T", Cuit = plain[0], TaxCondition = null }), "Elegí la condición frente al IVA del proveedor.", "Supplier.Update without condition");
var tempEdit = new Supplier { Id = temp.Id, Name = "Temporal 2", Cuit = plain[0], TaxCondition = Exe };
var updEx = Try(() => suppliers.Update(tempEdit));
Check(updEx == null && temp.Name == "Temporal 2" && temp.TaxCondition == Exe && temp.Cuit == plain[0], "editing a supplier with its own CUIT is fine and updates name and condition" + (updEx == null ? "" : " [" + updEx.Message + "]"));
var tempEdit2 = new Supplier { Id = temp.Id, Name = "Temporal 3", Cuit = plain[1][..2] + "-" + plain[1][2..10] + "-" + plain[1][10], TaxCondition = Mono };
Check(Try(() => suppliers.Update(tempEdit2)) == null && temp.Cuit == plain[1] && temp.TaxCondition == Mono && Reload().Suppliers.First(s => s.Id == temp.Id).Cuit == plain[1], "editing a supplier changes and persists its CUIT (stored as 11 digits)");
var unknownState = State(); suppliers.Update(new Supplier { Id = 98765, Name = "Nadie", Cuit = plain[2], TaxCondition = RI });
Check(State() == unknownState, "PRESERVE: Update of an unknown supplier stays a no-op");
suppliers.Delete(temp.Id);
Check(suppliers.GetById(temp.Id) == null && Reload().Suppliers.All(s => s.Id != temp.Id), "PRESERVE: Supplier.Delete still removes and persists");
var legacyNoCuit = new Supplier { Id = storage.GetNextSupplierId(), Name = "Viejo sin CUIT", TaxCondition = RI };
var legacyNoCondition = new Supplier { Id = storage.GetNextSupplierId(), Name = "Viejo sin condición", Cuit = "20123456786" };
var legacyBlank = new Supplier { Id = storage.GetNextSupplierId(), Name = "Viejo" };
storage.Suppliers.AddRange([legacyNoCuit, legacyNoCondition, legacyBlank]);
Check(!legacyNoCuit.HasFiscalData && !legacyNoCondition.HasFiscalData && !legacyBlank.HasFiscalData && legacyBlank.Cuit == string.Empty && legacyBlank.TaxCondition == null, "a supplier missing the CUIT or the condition has no fiscal data");

// ---- S1/S3: invoice registration order ----
var unconfigured = ValidFor(sRI, TA);
Invalid(() => invoices.Add(unconfigured, admin), ConfigMsg, "invoice while the business condition is not set", unconfigured);
var unconfigured2 = Inv(new Supplier { Id = 999 }, null);
Invalid(() => invoices.Add(unconfigured2, admin), ConfigMsg, "not-configured check comes before the supplier check", unconfigured2);
Reject(() => invoices.Add(ValidFor(sRI, TA), staleAdmin), typeof(UnauthorizedAccessException), "Se requiere un usuario vigente para registrar la factura.", "invoice by a stale actor (before the configuration check)");
SetBusiness(RI);
Check(business.TaxCondition == RI && storage.BusinessSettings.TaxCondition == RI, "admin sets the business condition");
Check(File.ReadAllText("data.json").Contains("\"BusinessSettings\"") && JsonNode.Parse(File.ReadAllText("data.json"))!["BusinessSettings"]!["TaxCondition"]!.GetValue<int>() == 1 && Reload().BusinessSettings.TaxCondition == RI, "the business condition persists as top-level BusinessSettings in data.json");
var ghost = Inv(new Supplier { Id = 999 }, TA, It(harina, 1m, 1m, 21m));
Invalid(() => invoices.Add(ghost, admin), "Seleccioná un proveedor.", "invoice with an unknown supplier", ghost);
var noSupplier = Inv(new Supplier { Id = 0 }, TA, It(harina, 1m, 1m, 21m));
Invalid(() => invoices.Add(noSupplier, admin), "Seleccioná un proveedor.", "invoice without supplier", noSupplier);
foreach (var legacy in new[] { legacyNoCuit, legacyNoCondition, legacyBlank })
{
    var inv = ValidFor(legacy, TA);
    Invalid(() => invoices.Add(inv, admin), "Completá el CUIT y la condición frente al IVA del proveedor antes de registrar la factura.", "invoice with supplier '" + legacy.Name + "'", inv);
}

// ---- S3: derived invoice type, all 9 combinations x 3 submitted types ----
foreach (var biz in new[] { RI, Mono, Exe })
{
    SetBusiness(biz);
    foreach (var (sup, cond) in new[] { (sRI, RI), (sMono, Mono), (sExe, Exe) })
    {
        var expected = expectations.First(e => e.Supplier == cond && e.Business == biz).Type;
        foreach (var submitted in new[] { TA, TB, TC })
        {
            var inv = ValidFor(sup, submitted); var label = $"business {Label(biz)}, supplier {Label(cond)}, factura {submitted}";
            if (submitted == expected) Accept(inv, label);
            else Invalid(() => invoices.Add(inv, admin), $"Un proveedor {Label(cond)} debe emitirte factura {expected}.", label, inv);
        }
        var untyped = ValidFor(sup, expected); untyped.Type = null;
        Invalid(() => invoices.Add(untyped, admin), $"Un proveedor {Label(cond)} debe emitirte factura {expected}.", $"business {Label(biz)}, supplier {Label(cond)}, no type", untyped);
        var undefinedType = ValidFor(sup, expected); undefinedType.Type = (InvoiceType)9;
        Invalid(() => invoices.Add(undefinedType, admin), $"Un proveedor {Label(cond)} debe emitirte factura {expected}.", $"business {Label(biz)}, supplier {Label(cond)}, undefined type", undefinedType);
    }
}

// ---- S3: legends; S4: factura A ----
SetBusiness(RI); // supplier RI -> A; supplier Mono/Exento -> C
var legendB = Inv(sRI, TA, It(harina, 1m, 10m, 21m)); legendB.Legend = (InvoiceLegend)9;
Invalid(() => invoices.Add(legendB, admin), "La leyenda de la factura no es válida.", "undefined legend", legendB);
var legendC = ValidFor(sMono, TC); legendC.Legend = InvoiceLegend.OperacionSujetaARetencion;
Invalid(() => invoices.Add(legendC, admin), "La leyenda solo corresponde a facturas A.", "legend on a factura C", legendC);
var legendCRate = Inv(sMono, TC, It(harina, 1m, 10m, 21m)); legendCRate.Legend = InvoiceLegend.PagoEnCbuInformada;
Invalid(() => invoices.Add(legendCRate, admin), "La leyenda solo corresponde a facturas A.", "legend is checked before VAT rates", legendCRate);
foreach (var legend in new[] { InvoiceLegend.OperacionSujetaARetencion, InvoiceLegend.PagoEnCbuInformada, InvoiceLegend.None })
{ var inv = ValidFor(sRI, TA); inv.Legend = legend; Accept(inv, "factura A with legend " + legend); }
foreach (var bad in new decimal?[] { null, 20m, -1m, 21.5m, 0.21m, 100m })
{
    var inv = Inv(sRI, TA, It(harina, 1m, 10m, 21m), It(leche, 1m, 10m, bad));
    Invalid(() => invoices.Add(inv, admin), "Elegí una alícuota de IVA válida para cada ítem de la factura A.", "factura A with item rate " + (bad?.ToString() ?? "none"), inv);
}
var rateBeforeStock = Inv(sRI, TA, It(harina, 0m, 10m, null));
Invalid(() => invoices.Add(rateBeforeStock, admin), "Elegí una alícuota de IVA válida para cada ítem de la factura A.", "VAT rate is validated before the stock rules", rateBeforeStock);
var stockStillChecked = Inv(sRI, TA, It(harina, 0m, 10m, 21m));
Invalid(() => invoices.Add(stockStillChecked, admin), "La cantidad de cada ítem de la factura debe ser positiva.", "PRESERVE: valid fiscal data with quantity 0 still hits the stock rule", stockStillChecked);
foreach (var rate in FiscalRules.VatRates) Accept(Inv(sRI, TA, It(harina, 1m, 10m, rate)), "factura A with rate " + rate);
var mixed = Inv(sRI, TA, It(harina, 1m, 33.33m, 21m), It(leche, 2m, 10m, 10.5m), It(huevo, 1m, 0.05m, 10.5m), It(huevo, 1m, 0.05m, 10.5m), It(huevo, 10m, 5m, 0m));
var stockHarina = harina.CurrentStock; var stockLeche = leche.CurrentStock; var stockHuevo = huevo.CurrentStock;
Accept(mixed, "factura A with mixed rates");
Check(mixed.NetTotal == 103.43m && mixed.VatTotal == 9.11m && mixed.OtherTaxesTotal == 0m && mixed.Total == 112.54m, $"factura A totals: net 103.43 + IVA 9.11 = 112.54 [{mixed.NetTotal} {mixed.VatTotal} {mixed.Total}]");
Check(mixed.VatByRate.Select(l => (l.Rate, l.Net, l.Vat)).SequenceEqual([(0m, 50m, 0m), (10.5m, 20.10m, 2.11m), (21m, 33.33m, 7.00m)]),
    "IVA is grouped by rate ascending and rounded per rate: 33.33 at 21% -> 7.00; 20.10 at 10.5% -> 2.11 (not 2.12 per line) [" + string.Join(";", mixed.VatByRate.Select(l => $"{l.Rate}:{l.Net}:{l.Vat}")) + "]");
Check(harina.CurrentStock == stockHarina + 1m && leche.CurrentStock == stockLeche + 2m && huevo.CurrentStock == stockHuevo + 12m, "stock receipt still happens for a valid factura A (quantities as before)");
var midpoint = Inv(sRI, TA, It(harina, 1m, 0.5m, 5m)); // 0.025 -> rounds away from zero to 0.03
Accept(midpoint, "factura A with a rounding midpoint");
Check(midpoint.VatTotal == 0.03m && midpoint.Total == 0.53m, "IVA rounds half away from zero (0.025 -> 0.03)");
var noTaxA = Inv(sRI, TA, It(harina, 3m, 10m, 21m));
Accept(noTaxA, "factura A without other taxes");
Check(noTaxA.OtherTaxes.Count == 0 && noTaxA.OtherTaxesTotal == 0m && noTaxA.Total == 36.30m, "Total = net + IVA when there are no other taxes (30 + 6.30)");

// ---- S5: other taxes ----
void BadTax(Invoice inv, string message, string name) => Invalid(() => invoices.Add(inv, admin), message, name, inv);
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax((InvoiceTaxKind)0, 5m)]), "El tipo de tributo no es válido.", "tax kind 0");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax((InvoiceTaxKind)9, 5m)]), "El tipo de tributo no es válido.", "tax kind 9");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.ImpuestosInternos, 0m)]), "El importe de cada tributo debe ser mayor a cero.", "tax amount 0");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIva, 1m), Tax(InvoiceTaxKind.ImpuestosInternos, -2m)]), "El importe de cada tributo debe ser mayor a cero.", "negative tax amount in the second tax");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIibb, 5m, "  ")]), "Indicá la jurisdicción de la percepción de IIBB.", "IIBB without jurisdiction");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIibb, 5m)]), "Indicá la jurisdicción de la percepción de IIBB.", "IIBB with empty jurisdiction");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.OtrosTributos, 5m, " ")]), "Describí el tributo.", "other tax without description");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.OtrosTributos, 5m)]), "Describí el tributo.", "other tax with empty description");
SetBusiness(Exe); // supplier RI -> B
BadTax(Inv(sRI, TB, It(harina, 1m, 10m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIva, 5m)]), "La percepción de IVA solo corresponde a facturas A.", "VAT perception on a factura B");
BadTax(Inv(sMono, TC, It(harina, 1m, 10m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIva, 5m)]), "La percepción de IVA solo corresponde a facturas A.", "VAT perception on a factura C");
BadTax(Inv(sRI, TB, It(harina, 1m, 10m, 21m)), "Las facturas B no discriminan IVA por ítem.", "factura B with an item rate");
BadTax(Inv(sRI, TB, It(harina, 1m, 10m, 0m)), "Las facturas B no discriminan IVA por ítem.", "factura B with an item rate of 0");
BadTax(Inv(sRI, TB, It(harina, 1m, 10m, 21m)).With(t => t.Legend = InvoiceLegend.PagoEnCbuInformada), "La leyenda solo corresponde a facturas A.", "factura B with a legend (checked before the rates)");
BadTax(Inv(sMono, TC, It(harina, 1m, 10m, 21m)), "Las facturas C no discriminan IVA por ítem.", "factura C with an item rate");
BadTax(Inv(sMono, TC, It(harina, 1m, 10m)).With(t => t.ContainedVat = 0m), "El IVA contenido solo se informa en facturas B.", "factura C with contained VAT");
SetBusiness(RI);
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.ContainedVat = 1m), "El IVA contenido solo se informa en facturas B.", "factura A with contained VAT");
BadTax(Inv(sRI, TA, It(harina, 1m, 10m, 21m)).With(t => t.ContainedVat = 0m), "El IVA contenido solo se informa en facturas B.", "factura A with contained VAT 0");
var taxed = Inv(sRI, TA, It(harina, 1m, 33.33m, 21m), It(leche, 2m, 10m, 10.5m), It(huevo, 10m, 5m, 0m)).With(t => t.OtherTaxes = [
    Tax(InvoiceTaxKind.PercepcionIva, 5m), Tax(InvoiceTaxKind.PercepcionIibb, 3.5m, "  CABA  "), Tax(InvoiceTaxKind.ImpuestosInternos, 1m, "  "), Tax(InvoiceTaxKind.OtrosTributos, 0.5m, " Tasa municipal ")]);
Accept(taxed, "factura A with the four kinds of other taxes");
Check(taxed.OtherTaxes[1].Detail == "CABA" && taxed.OtherTaxes[3].Detail == "Tasa municipal" && taxed.OtherTaxes[2].Detail == string.Empty && taxed.OtherTaxes[0].Detail == string.Empty, "other tax details are trimmed");
Check(taxed.OtherTaxesTotal == 10m && taxed.NetTotal == 103.33m && taxed.VatTotal == 9.10m && taxed.Total == 122.43m, $"other taxes add to the total: 103.33 + IVA 9.10 + 10 = 122.43 [{taxed.NetTotal} {taxed.VatTotal} {taxed.OtherTaxesTotal} {taxed.Total}]");

// ---- S4: factura B / C ----
SetBusiness(Exe);
var b0 = Inv(sRI, TB, It(harina, 2m, 100m));
Accept(b0, "factura B without contained VAT");
Check(b0.VatTotal == 0m && b0.VatByRate.Count == 0 && b0.NetTotal == 200m && b0.Total == 200m && b0.ContainedVat == null, "factura B: typed price is final, no VAT breakdown, Total = items");
foreach (var bad in new decimal[] { -0.01m, 200m, 250m })
{
    var inv = Inv(sRI, TB, It(harina, 2m, 100m)).With(t => t.ContainedVat = bad);
    Invalid(() => invoices.Add(inv, admin), "El IVA contenido debe ser mayor o igual a cero y menor que el total de la factura.", "factura B with contained VAT " + bad, inv);
}
var bZero = Inv(sRI, TB, It(harina, 2m, 100m)).With(t => t.ContainedVat = 0m); Accept(bZero, "factura B with contained VAT 0");
var bTop = Inv(sRI, TB, It(harina, 2m, 100m)).With(t => t.ContainedVat = 199.99m); Accept(bTop, "factura B with contained VAT just under the total");
var bReal = Inv(sRI, TB, It(harina, 2m, 100m)).With(t => { t.ContainedVat = 34.71m; t.Legend = InvoiceLegend.None; }); Accept(bReal, "factura B with a typical contained VAT");
var bTaxes = Inv(sRI, TB, It(harina, 2m, 100m)).With(t => { t.ContainedVat = 205m; t.OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIibb, 10m, "Buenos Aires"), Tax(InvoiceTaxKind.ImpuestosInternos, 5m)]; });
Accept(bTaxes, "factura B whose contained VAT is below the total including other taxes");
Check(bTaxes.Total == 215m && bTaxes.OtherTaxesTotal == 15m && bTaxes.VatTotal == 0m, "factura B total adds IIBB perception and internal taxes (200 + 15)");
var bOver = Inv(sRI, TB, It(harina, 2m, 100m)).With(t => { t.ContainedVat = 215m; t.OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIibb, 10m, "Buenos Aires"), Tax(InvoiceTaxKind.ImpuestosInternos, 5m)]; });
Invalid(() => invoices.Add(bOver, admin), "El IVA contenido debe ser mayor o igual a cero y menor que el total de la factura.", "contained VAT equal to the total with other taxes", bOver);
var c0 = Inv(sMono, TC, It(harina, 1m, 50m)).With(t => t.OtherTaxes = [Tax(InvoiceTaxKind.OtrosTributos, 2m, "Tasa")]);
Accept(c0, "factura C with an other tax");
Check(c0.Total == 52m && c0.VatTotal == 0m && c0.VatByRate.Count == 0 && c0.Type == TC, "factura C: price is final, Total = items + other taxes");

// ---- Persistence of the new invoice shape ----
var fileNode = JsonNode.Parse(File.ReadAllText("data.json"))!;
var savedTaxed = fileNode["Invoices"]!.AsArray().First(n => n!["Id"]!.GetValue<int>() == taxed.Id)!.AsObject();
Check(savedTaxed["Type"]!.GetValue<int>() == 1 && savedTaxed["Legend"]!.GetValue<int>() == 0 && savedTaxed["OtherTaxes"]!.AsArray().Count == 4 && savedTaxed["Items"]![0]!["VatRate"]!.GetValue<decimal>() == 21m,
    "invoice persists Type, Legend, OtherTaxes and the item VatRate");
Check(!savedTaxed.ContainsKey("NetTotal") && !savedTaxed.ContainsKey("VatByRate") && !savedTaxed.ContainsKey("VatTotal") && !savedTaxed.ContainsKey("OtherTaxesTotal"), "computed totals are not persisted");
var reloadedInvoice = Reload().Invoices.First(i => i.Id == taxed.Id);
Check(reloadedInvoice.Type == TA && reloadedInvoice.OtherTaxes.Count == 4 && reloadedInvoice.OtherTaxes[1].Kind == InvoiceTaxKind.PercepcionIibb && reloadedInvoice.OtherTaxes[1].Detail == "CABA" && reloadedInvoice.Total == taxed.Total && reloadedInvoice.VatTotal == 9.10m && reloadedInvoice.Items[1].VatRate == 10.5m,
    "a factura A reloads with the same type, taxes, rates and totals");
var reloadedB = Reload().Invoices.First(i => i.Id == bReal.Id);
Check(reloadedB.Type == TB && reloadedB.ContainedVat == 34.71m && reloadedB.Items[0].VatRate == null, "a factura B reloads with its contained VAT");

// ---- Update copies the new fields ----
var updInv = new Invoice { Id = noTaxA.Id, Date = noTaxA.Date, SupplierId = noTaxA.SupplierId, InvoiceNumber = "EDITADA", Notes = "n", Items = noTaxA.Items, Type = TA, Legend = InvoiceLegend.PagoEnCbuInformada, ContainedVat = null, OtherTaxes = [Tax(InvoiceTaxKind.PercepcionIva, 7m)] };
invoices.Update(updInv);
var updReload = Reload().Invoices.First(i => i.Id == noTaxA.Id);
Check(noTaxA.InvoiceNumber == "EDITADA" && noTaxA.Legend == InvoiceLegend.PagoEnCbuInformada && noTaxA.OtherTaxes.Count == 1 && noTaxA.Type == TA && updReload.Legend == InvoiceLegend.PagoEnCbuInformada && updReload.OtherTaxes[0].Amount == 7m && updReload.InvoiceNumber == "EDITADA",
    "InvoiceService.Update copies and persists Type, Legend, ContainedVat and OtherTaxes");
var delId = c0.Id; var stockBeforeDelete = harina.CurrentStock; invoices.Delete(delId);
Check(invoices.GetById(delId) == null && Reload().Invoices.All(i => i.Id != delId) && harina.CurrentStock == stockBeforeDelete, "PRESERVE: Invoice.Delete still removes the invoice and keeps the stock");

// ---- S6: cost policy ----
var costBiz = new TaxCondition?[] { RI, Mono, Exe, null };
// scenario: (ingredient id, label, type, rate, expected cost per business in the order RI, Mono, Exento, not configured)
var scenarios = new (int Id, string Label, InvoiceType? Type, decimal? Rate, decimal[] Cost)[] {
    (50, "A 21%", TA, 21m, [100m, 121m, 121m, 121m]), (51, "A 10.5%", TA, 10.5m, [100m, 110.5m, 110.5m, 110.5m]), (52, "A 0%", TA, 0m, [100m, 100m, 100m, 100m]),
    (53, "A without rate", TA, null, [100m, 100m, 100m, 100m]), (54, "B", TB, null, [100m, 100m, 100m, 100m]), (55, "C", TC, null, [100m, 100m, 100m, 100m]),
    (56, "legacy (no type)", null, null, [100m, 100m, 100m, 100m]) };
foreach (var sc in scenarios)
{
    storage.Ingredients.Add(new Ingredient { Id = sc.Id, Name = "Costo " + sc.Label, Unit = "kg" });
    storage.Invoices.Add(new Invoice { Id = storage.GetNextInvoiceId(), Date = new DateTime(2030, 1, 1), SupplierId = sRI.Id, Type = sc.Type, Items = [new InvoiceItem { IngredientId = sc.Id, Quantity = 1m, Unit = "kg", UnitPrice = 100m, VatRate = sc.Rate }] });
}
for (int b = 0; b < costBiz.Length; b++)
{
    storage.BusinessSettings.TaxCondition = costBiz[b];
    var bizName = costBiz[b] == null ? "not configured" : Label(costBiz[b]!.Value);
    foreach (var sc in scenarios)
    {
        var last = invoices.GetLastPriceForIngredient(sc.Id); var viaIngredients = ingredients.GetLastPrice(sc.Id); var history = invoices.GetPriceHistory(sc.Id);
        Check(last == sc.Cost[b] && viaIngredients == sc.Cost[b] && history.Count == 1 && history[0].Price == sc.Cost[b], $"cost with business {bizName}, invoice {sc.Label}: {sc.Cost[b]} [{last} / {viaIngredients} / {history.FirstOrDefault().Price}]");
    }
}
Check(invoices.GetLastPriceForIngredient(98765) == null && invoices.GetPriceHistory(98765).Count == 0, "PRESERVE: an ingredient without invoices has no price");
Check(FiscalRules.UnitCost(new Invoice { Type = TA }, new InvoiceItem { UnitPrice = 100m, VatRate = 21m }, null) == 121m && FiscalRules.UnitCost(new Invoice { Type = TA }, new InvoiceItem { UnitPrice = 100m, VatRate = 21m }, RI) == 100m
    && FiscalRules.UnitCost(new Invoice { Type = TB }, new InvoiceItem { UnitPrice = 100m, VatRate = 21m }, Mono) == 100m, "FiscalRules.UnitCost applies the policy directly");
// latest invoice wins, history is newest first and uses each invoice's own policy
storage.Ingredients.Add(new Ingredient { Id = 57, Name = "Historial", Unit = "kg" });
storage.Invoices.Add(new Invoice { Id = storage.GetNextInvoiceId(), Date = new DateTime(2030, 2, 1), SupplierId = sRI.Id, Items = [new InvoiceItem { IngredientId = 57, Quantity = 1m, Unit = "kg", UnitPrice = 100m }] });
storage.Invoices.Add(new Invoice { Id = storage.GetNextInvoiceId(), Date = new DateTime(2030, 3, 1), SupplierId = sRI.Id, Type = TA, Items = [new InvoiceItem { IngredientId = 57, Quantity = 1m, Unit = "kg", UnitPrice = 200m, VatRate = 21m }] });
storage.BusinessSettings.TaxCondition = RI;
Check(invoices.GetLastPriceForIngredient(57) == 200m && invoices.GetPriceHistory(57).Select(h => h.Price).SequenceEqual([200m, 100m]), "RI: latest cost is the net price; history is newest first");
storage.BusinessSettings.TaxCondition = Exe;
Check(invoices.GetLastPriceForIngredient(57) == 242m && invoices.GetPriceHistory(57).Select(h => h.Price).SequenceEqual([242m, 100m]) && invoices.GetPriceHistory(57).Select(h => h.Date).SequenceEqual([new DateTime(2030, 3, 1), new DateTime(2030, 2, 1)]), "Exento: latest cost is net x 1.21; the legacy invoice keeps its typed price");
storage.BusinessSettings.TaxCondition = RI; storage.SaveToFile();
// SetTaxCondition recalculates and persists recipe costs
storage.Ingredients.Add(new Ingredient { Id = 60, Name = "Costeado", Unit = "kg" });
storage.Invoices.Add(new Invoice { Id = storage.GetNextInvoiceId(), Date = new DateTime(2030, 4, 1), SupplierId = sRI.Id, Type = TA, Items = [new InvoiceItem { IngredientId = 60, Quantity = 1m, Unit = "kg", UnitPrice = 100m, VatRate = 21m }] });
var recipe = new Recipe { Name = "Receta fiscal", Yield = 2, Ingredients = [new RecipeIngredient { IngredientId = 60, Quantity = 1m, Unit = "kg" }] };
recipes.Add(recipe);
Check(recipe.TotalCost == 100m && recipe.UnitCost == 50m && recipe.Ingredients[0].UnitPrice == 100m, "a recipe costed under a Responsable Inscripto business uses the net price");
Reject(() => business.SetTaxCondition(Mono, employee), typeof(UnauthorizedAccessException), NotAdmin, "SetTaxCondition by an employee does not touch recipe costs");
Check(recipe.TotalCost == 100m && business.TaxCondition == RI, "a rejected change leaves the recipe cost and the condition as they were");
SetBusiness(Mono);
Check(recipe.TotalCost == 121m && recipe.UnitCost == 60.5m && recipe.Ingredients[0].UnitPrice == 121m && recipe.Ingredients[0].Subtotal == 121m && business.TaxCondition == Mono, "SetTaxCondition recalculates stored recipe costs (net x 1.21 for a non-RI business)");
var recipeFile = Reload(); var recipeNode = recipeFile.Recipes.First(r => r.Id == recipe.Id);
Check(recipeNode.TotalCost == 121m && recipeNode.UnitCost == 60.5m && recipeFile.BusinessSettings.TaxCondition == Mono, "the recalculated recipe cost and the condition are persisted");
SetBusiness(RI);
Check(recipe.TotalCost == 100m && Reload().Recipes.First(r => r.Id == recipe.Id).TotalCost == 100m, "switching back to Responsable Inscripto recalculates to the net price");
SetBusiness(RI);

// ---- Suppliers page: service rejections are shown, not thrown ----
var asm = typeof(SupplierService).Assembly;
var pageType = asm.GetType("GastroApp.Pages.Suppliers");
Check(pageType != null, "Suppliers page type exists");
if (pageType != null)
{
    var users = new UserService(storage); var auth = new AuthService(users); Check(auth.Login("fixture-admin", "fixture-pass"), "circuit login fixture-admin");
    var page = Activator.CreateInstance(pageType)!; var nav = new TestNavigation();
    void Inject(string name, object value) { pageType.GetProperty(name, flags)?.SetValue(page, value); }
    Inject("AuthService", auth); Inject("Navigation", nav); Inject("SupplierService", suppliers); Inject("InvoiceService", invoices);
    Exception? CallPage(string method) { try { var r = pageType.GetMethod(method, flags | BindingFlags.DeclaredOnly)!.Invoke(page, []); if (r is Task t) t.GetAwaiter().GetResult(); return null; } catch (TargetInvocationException ex) { return ex.InnerException; } }
    void SetEditing(Supplier s) => pageType.GetField("editingSupplier", flags)!.SetValue(page, s);
    string FormError() => (string?)pageType.GetField("formError", flags)!.GetValue(page) ?? "";
    storage.SaveToFile(); var pageState = State(); var pageBytes = File.ReadAllBytes("data.json");
    var pageBad = new Supplier { Name = "Desde la pantalla" };
    SetEditing(pageBad);
    var pageEx = CallPage("SaveSupplier");
    Check(pageEx == null && FormError() == "Ingresá el CUIT del proveedor." && State() == pageState && pageBytes.SequenceEqual(File.ReadAllBytes("data.json")), "Suppliers page shows the service rejection in formError instead of crashing and stores nothing [" + pageEx?.Message + "]");
    SetEditing(new Supplier { Name = "Desde la pantalla", Cuit = plain[2], TaxCondition = Exe });
    pageEx = CallPage("SaveSupplier");
    Check(pageEx == null && FormError() == "" && storage.Suppliers.Any(s => s.Name == "Desde la pantalla" && s.Cuit == plain[2]), "Suppliers page saves a valid supplier and clears the error [" + pageEx?.Message + "]");
    var pageSupplier = storage.Suppliers.First(s => s.Name == "Desde la pantalla");
    SetEditing(new Supplier { Id = pageSupplier.Id, Name = "Desde la pantalla", Cuit = C1, TaxCondition = Exe });
    pageEx = CallPage("SaveSupplier");
    Check(pageEx == null && FormError() == "Ya existe un proveedor con ese CUIT." && pageSupplier.Cuit == plain[2], "Suppliers page shows an update rejection and keeps the stored supplier [" + pageEx?.Message + "]");
}

// ---- S7: legacy data.json ----
var usersJson = JsonSerializer.Serialize(storage.Users);
string InDir(string name) { var dir = Path.Combine(root, name); Directory.CreateDirectory(dir); Directory.SetCurrentDirectory(dir); return dir; }
var legacyJson = $$"""
{"Users":{{usersJson}},"Ingredients":[{"Id":1,"Name":"Harina","Unit":"kg","IsActive":true,"CurrentStock":2,"MinStock":0}],
 "Suppliers":[{"Id":1,"Name":"Proveedor viejo"}],
 "Invoices":[{"Id":1,"Date":"2025-03-01T10:00:00","SupplierId":1,"InvoiceNumber":"A-0001-1","Notes":"vieja","Items":[{"InvoiceId":1,"IngredientId":1,"IngredientName":"Harina","Quantity":2,"Unit":"kg","UnitPrice":80,"Subtotal":160}],"Total":160}],
 "Recipes":[],"NextSupplierId":2,"NextInvoiceId":2,"NextIngredientId":2}
""";
InDir("legacy"); File.WriteAllText("data.json", legacyJson);
var legacyStorage = new DataStorageService();
var oldInvoice = legacyStorage.Invoices[0]; var oldSupplier = legacyStorage.Suppliers[0];
Check(legacyStorage.Invoices.Count == 1 && oldInvoice.Type == null && oldInvoice.Legend == InvoiceLegend.None && oldInvoice.ContainedVat == null && oldInvoice.OtherTaxes.Count == 0 && oldInvoice.Items[0].VatRate == null
    && oldInvoice.Total == 160m && oldInvoice.NetTotal == 160m && oldInvoice.VatTotal == 0m && oldInvoice.VatByRate.Count == 0 && oldInvoice.InvoiceNumber == "A-0001-1" && oldInvoice.Items[0].UnitPrice == 80m, "a legacy invoice loads unchanged: no type, no VAT, Total = items");
Check(oldSupplier.Name == "Proveedor viejo" && oldSupplier.Cuit == string.Empty && oldSupplier.TaxCondition == null && !oldSupplier.HasFiscalData && legacyStorage.BusinessSettings.TaxCondition == null, "a legacy supplier loads without CUIT or condition, the business is not configured");
var legacyInvoices = new InvoiceService(legacyStorage); var legacyIngredients = new IngredientService(legacyStorage, legacyInvoices); legacyInvoices.SetIngredientService(legacyIngredients);
var legacyRecipes = new RecipeService(legacyStorage, legacyInvoices);
foreach (var biz in costBiz)
{
    legacyStorage.BusinessSettings.TaxCondition = biz;
    Check(legacyInvoices.GetLastPriceForIngredient(1) == 80m && legacyInvoices.GetPriceHistory(1)[0].Price == 80m, "legacy invoice cost is its typed price with business " + (biz?.ToString() ?? "not configured"));
}
legacyStorage.BusinessSettings.TaxCondition = Mono;
var legacyRecipe = new Recipe { Name = "Vieja", Yield = 1, Ingredients = [new RecipeIngredient { IngredientId = 1, Quantity = 2m, Unit = "kg" }] };
legacyRecipes.Add(legacyRecipe);
Check(legacyRecipe.TotalCost == 160m, "a recipe over a legacy invoice costs the typed price (never reinterpreted)");
legacyStorage.BusinessSettings.TaxCondition = null; legacyStorage.SaveToFile();
var legacyNode = JsonNode.Parse(File.ReadAllText("data.json"))!.AsObject();
var legacyInv0 = legacyNode["Invoices"]![0]!.AsObject();
Check(legacyInv0.ContainsKey("Type") && legacyInv0["Type"] == null && legacyNode.ContainsKey("BusinessSettings") && legacyNode["BusinessSettings"]!["TaxCondition"] == null, "a saved legacy invoice keeps Type null; BusinessSettings is written");
var legacyAgain = new DataStorageService();
Check(legacyAgain.Invoices[0].Type == null && legacyAgain.Invoices[0].Total == 160m && legacyAgain.Suppliers[0].Cuit == string.Empty && legacyAgain.Suppliers[0].TaxCondition == null && legacyAgain.BusinessSettings.TaxCondition == null
    && new InvoiceService(legacyAgain).GetLastPriceForIngredient(1) == 80m, "a legacy invoice survives save + reload with Type still null and cost = typed price");
// corrupt BusinessSettings
Exception? LoadError(string dir, string body) { InDir(dir); File.WriteAllText("data.json", "{\"Users\":" + usersJson + body + "}"); return Try(() => { _ = new DataStorageService(); }); }
Check(LoadError("bs-null", ",\"BusinessSettings\":null") is InvalidDataException, "an explicit BusinessSettings null throws InvalidDataException on load");
Check(LoadError("bs-undefined", ",\"BusinessSettings\":{\"TaxCondition\":7}") is InvalidDataException, "an undefined tax condition throws InvalidDataException on load");
Check(LoadError("bs-zero", ",\"BusinessSettings\":{\"TaxCondition\":0}") is InvalidDataException, "tax condition 0 throws InvalidDataException on load");
Check(LoadError("bs-text", ",\"BusinessSettings\":\"x\"") is InvalidDataException, "a malformed BusinessSettings throws InvalidDataException on load");
Check(LoadError("bs-ok", ",\"BusinessSettings\":{\"TaxCondition\":2}") == null, "a valid BusinessSettings loads");
Check(new DataStorageService().BusinessSettings.TaxCondition == Mono, "the stored business condition is read back");
Check(LoadError("bs-missing", "") == null && new DataStorageService().BusinessSettings.TaxCondition == null, "a missing BusinessSettings means not configured");
Check(LoadError("bs-empty", ",\"BusinessSettings\":{}") == null && new DataStorageService().BusinessSettings.TaxCondition == null, "an empty BusinessSettings means not configured");
// corrupt purchasing fields (T5 blocker): a hand-edited null list or undefined enum must fail loudly, never load half-broken
string InvoiceJson(string extra) => ",\"Invoices\":[{\"Id\":1,\"SupplierId\":1,\"Items\":[{\"IngredientId\":1,\"Quantity\":1,\"Unit\":\"kg\",\"UnitPrice\":10}]" + extra + "}]";
Check(LoadError("inv-taxes-null", InvoiceJson(",\"OtherTaxes\":null")) is InvalidDataException, "an explicit invoice OtherTaxes null throws InvalidDataException on load");
Check(LoadError("inv-type-undefined", InvoiceJson(",\"Type\":9")) is InvalidDataException, "an undefined invoice type throws InvalidDataException on load");
Check(LoadError("inv-legend-undefined", InvoiceJson(",\"Type\":1,\"Legend\":9")) is InvalidDataException, "an undefined invoice legend throws InvalidDataException on load");
Check(LoadError("inv-tax-kind-undefined", InvoiceJson(",\"OtherTaxes\":[{\"Kind\":9,\"Detail\":\"\",\"Amount\":1}]")) is InvalidDataException, "an undefined other-tax kind throws InvalidDataException on load");
Check(LoadError("sup-cond-undefined", ",\"Suppliers\":[{\"Id\":1,\"Name\":\"X\",\"Cuit\":\"30712345671\",\"TaxCondition\":9}]") is InvalidDataException, "an undefined supplier tax condition throws InvalidDataException on load");
Check(LoadError("inv-valid", InvoiceJson(",\"Type\":1,\"Legend\":0,\"OtherTaxes\":[{\"Kind\":2,\"Detail\":\"CABA\",\"Amount\":1}]")) == null && new DataStorageService().Invoices[0].OtherTaxesTotal == 1m, "a valid typed invoice with other taxes loads");
Check(new Invoice { Type = InvoiceType.A, Items = [new() { Quantity = 1, UnitPrice = 0.03m, VatRate = 21 }, new() { Quantity = 1, UnitPrice = 0.03m, VatRate = 21 }, new() { Quantity = 1, UnitPrice = 0.03m, VatRate = 21 }] }.VatTotal == 0.02m, "S4 IVA is rounded per rate, not per line");

// ---- Seed ----
InDir("seed");
var seeded = new DataStorageService();
var seedSupplier = seeded.Suppliers.Single(); var seedInvoice = seeded.Invoices.Single();
Check(seedSupplier.Cuit == "30712345671" && seedSupplier.TaxCondition == RI && seedSupplier.HasFiscalData && FiscalRules.TryNormalizeCuit(seedSupplier.Cuit, out _), "seed supplier is a Responsable Inscripto with CUIT 30712345671");
Check(seedInvoice.Type == TA && seedInvoice.Items.Single(i => i.IngredientName == "Harina 000").VatRate == 10.5m && seedInvoice.Items.Where(i => i.IngredientName != "Harina 000").All(i => i.VatRate == 21m) && seeded.BusinessSettings.TaxCondition == null, "seed invoice is a factura A (harina 10.5%, the rest 21%) and the business is not configured");
var seedInvoices = new InvoiceService(seeded); var harinaSeed = seeded.Ingredients.Single(i => i.Name == "Harina 000");
Check(seedInvoices.GetLastPriceForIngredient(harinaSeed.Id) == 88.4m, "with the business not configured the seeded net price 80 costs 88.40 (net x 1.105)");
seeded.BusinessSettings.TaxCondition = RI;
Check(seedInvoices.GetLastPriceForIngredient(harinaSeed.Id) == 80m, "with a Responsable Inscripto business the seeded cost is the net 80");

// ---- ResetAll clears BusinessSettings ----
Directory.SetCurrentDirectory(root);
SetBusiness(RI);
var backup = storage.ResetAll(admin);
Check(storage.BusinessSettings.TaxCondition == null && business.TaxCondition == null && Reload().BusinessSettings.TaxCondition == null && File.Exists(backup), "ResetAll clears the business condition in memory and in data.json");
var afterReset = JsonNode.Parse(File.ReadAllText("data.json"))!.AsObject();
Check(afterReset.ContainsKey("BusinessSettings") && afterReset["BusinessSettings"]!["TaxCondition"] == null && afterReset["Suppliers"]!.AsArray().Count == 0 && afterReset["Invoices"]!.AsArray().Count == 0, "the reset document holds an empty BusinessSettings and no suppliers or invoices");
var backupNode = JsonNode.Parse(File.ReadAllText(backup))!.AsObject();
Check(backupNode["BusinessSettings"]!["TaxCondition"]!.GetValue<int>() == 1, "the backup keeps the condition that was set before the reset");

Console.WriteLine($"{checks} checks, {failures} failures; fixture: {root}");
return failures == 0 ? 0 : 1;

static class InvoiceFixtureExtensions
{
    public static Invoice With(this Invoice invoice, Action<Invoice> change) { change(invoice); return invoice; }
}

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
    & dotnet run --project (Join-Path $ScratchPath 'PurchaseVatChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Purchase VAT checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
