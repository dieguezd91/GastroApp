param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-stock-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'StockChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;

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
storage.Products = [new Product { Id = 1, Name = "Pizza", Price = 100m }, new Product { Id = 2, Name = "Flan", Price = 50m },
    new Product { Id = 3, Name = "Agua", Price = 10m }];
var invoices = new InvoiceService(storage);
var ingredients = new IngredientService(storage, invoices);
invoices.SetIngredientService(ingredients);
var recipes = new RecipeService(storage, invoices);
var sales = new SaleService(storage);
sales.SetRecipeService(recipes); sales.SetIngredientService(ingredients);
var cash = new CashRegisterService(storage, sales);
var pizza = storage.Products[0]; var flan = storage.Products[1]; var agua = storage.Products[2];

SaleItem Line(Product p, int q) => new() { ProductId = p.Id, ProductName = p.Name, Price = p.Price, Quantity = q };
SalePayment CashPay(decimal a) => new() { PaymentMethod = PaymentMethod.Cash, Amount = a, ReceivedAmount = a };
Sale Simple(List<SaleItem> items, params SalePayment[] pays) => new() { Items = items, Payments = pays.ToList() };
SaleRefundLine RL(int idx, int q, RefundDisposition d = RefundDisposition.Restock) => new() { SaleItemIndex = idx, Quantity = q, Disposition = d };
SaleRefundPayment RP(PaymentMethod m, decimal a) => new() { PaymentMethod = m, Amount = a };
StockMovement[] Mv(int ingredientId) => storage.StockMovements.Where(m => m.IngredientId == ingredientId).OrderBy(m => m.Id).ToArray();
string State() => JsonSerializer.Serialize(new { storage.CurrentCashRegisterId, storage.CashRegisters, storage.CashMovements, storage.CashCounts,
    storage.Sales, storage.SaleRefunds, storage.StockMovements, storage.Users, storage.Summaries, storage.Products, storage.ProductCategories,
    storage.Ingredients, storage.Suppliers, storage.Invoices, storage.Recipes,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
void Reject(Action action, Type exception, string name, string? contains = null)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    bool rejected = false; string message = "";
    try { action(); } catch (Exception ex) { rejected = ex.GetType() == exception && (contains == null || ex.Message.Contains(contains)); message = ex.Message; }
    Check(rejected, name + " rejected with " + exception.Name + (contains == null ? "" : " / " + contains) + (rejected ? "" : " [" + message + "]"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")), name + " leaves objects, ledger, collections, counters and fixture bytes unchanged");
}
void Invalid(Action action, string name, string? contains = null) => Reject(action, typeof(InvalidOperationException), name, contains);
void Denied(Action action, string name) => Reject(action, typeof(UnauthorizedAccessException), name, "administrador");

// ---- API surface, persisted values and Spanish labels ----
Check(Enum.GetNames<StockMovementType>().SequenceEqual(new[] { "InvoiceReceipt", "SaleConsumption", "SaleCancellationReturn", "RefundReturn", "Adjustment", "Waste", "CountAdjustment", "InitialStock" })
    && (int)StockMovementType.InvoiceReceipt == 0 && (int)StockMovementType.InitialStock == 7, "movement types and their persisted numeric values");
Check(Enum.GetNames<WasteCategory>().SequenceEqual(new[] { "Vencimiento", "RoturaODerrame", "ErrorDePreparacion", "Otro" }), "waste categories");
Check(StockMovementLabels.GetLabel(StockMovementType.InvoiceReceipt) == "Ingreso por compra" && StockMovementLabels.GetLabel(StockMovementType.SaleConsumption) == "Consumo por venta"
    && StockMovementLabels.GetLabel(StockMovementType.SaleCancellationReturn) == "Reposici\u00f3n por anulaci\u00f3n" && StockMovementLabels.GetLabel(StockMovementType.RefundReturn) == "Reposici\u00f3n por devoluci\u00f3n"
    && StockMovementLabels.GetLabel(StockMovementType.Adjustment) == "Ajuste manual" && StockMovementLabels.GetLabel(StockMovementType.Waste) == "Merma"
    && StockMovementLabels.GetLabel(StockMovementType.CountAdjustment) == "Ajuste por conteo" && StockMovementLabels.GetLabel(StockMovementType.InitialStock) == "Stock inicial", "Spanish movement type labels");
Check(StockMovementLabels.GetLabel(WasteCategory.Vencimiento) == "Vencimiento" && StockMovementLabels.GetLabel(WasteCategory.RoturaODerrame) == "Rotura o derrame"
    && StockMovementLabels.GetLabel(WasteCategory.ErrorDePreparacion) == "Error de preparaci\u00f3n" && StockMovementLabels.GetLabel(WasteCategory.Otro) == "Otro", "Spanish waste category labels");
Check(typeof(IngredientService).GetMethods(flags).All(m => m.Name != "AddStock" && m.Name != "TryRemoveStock"), "AddStock/TryRemoveStock direct mutators are gone");
Check(storage.StockMovements.Count == 0, "fresh store has an empty ledger");

// ---- InitialStock on Add ----
var t0 = DateTime.Now;
var harina = new Ingredient { Name = "Harina", Unit = "kg", CurrentStock = 100m };
ingredients.Add(harina, Copy(admin));
var m0 = Mv(harina.Id).Single();
Check(harina.CurrentStock == 100m && m0.Id == 1 && m0.Type == StockMovementType.InitialStock && m0.Quantity == 100m && m0.PreviousStock == 0m && m0.ResultingStock == 100m
    && m0.Unit == "kg" && m0.UserId == 10 && m0.Username == "fixture-admin" && m0.Date >= t0 && m0.Date <= DateTime.Now && m0.Reason == null && m0.WasteCategory == null
    && m0.SaleId == null && m0.RefundId == null && m0.InvoiceId == null && m0.StockCountId == null, "Add with stock records InitialStock with previous 0, resulting, unit, actor and no links");
var huevos = new Ingredient { Name = "Huevos", Unit = "unidad", CurrentStock = 10m };
ingredients.Add(huevos, null);
Check(Mv(huevos.Id).Single() is { Type: StockMovementType.InitialStock, Quantity: 10m, UserId: null, Username: null } && huevos.CurrentStock == 10m, "Add without actor records InitialStock with null actor");
var sal = new Ingredient { Name = "Sal", Unit = "kg", CurrentStock = 0m };
ingredients.Add(sal);
Check(Mv(sal.Id).Length == 0 && !ingredients.HasMovements(sal.Id) && ingredients.HasMovements(harina.Id) && storage.StockMovements.Count == 2, "Add with zero stock records no movement");
Invalid(() => ingredients.Add(new Ingredient { Name = "Neg", Unit = "kg", CurrentStock = -1m }, admin), "negative opening stock", "negativo");
Reject(() => ingredients.Add(new Ingredient { Name = "Stale", Unit = "kg", CurrentStock = 5m }, new User { Id = 10, Username = "fixture-admin", PasswordHash = "old", Role = UserRole.Admin }),
    typeof(UnauthorizedAccessException), "stale actor on Add", "vigente");

// ---- Update no longer changes stock ----
var movementsBeforeUpdate = storage.StockMovements.Count;
ingredients.Update(new Ingredient { Id = harina.Id, Name = "Harina 000", Unit = "kg", IsActive = true, CurrentStock = 999m, MinStock = 5m });
Check(harina.CurrentStock == 100m && harina.Name == "Harina 000" && harina.MinStock == 5m && storage.StockMovements.Count == movementsBeforeUpdate, "Update keeps the stored stock, applies the other fields and records no movement");
storage.Recipes = [new Recipe { Id = 1, Name = "Pizza", Ingredients = [
        new RecipeIngredient { RecipeId = 1, IngredientId = harina.Id, Quantity = 0.5m, Unit = "kg" },
        new RecipeIngredient { RecipeId = 1, IngredientId = huevos.Id, Quantity = 2m, Unit = "unidad" }] },
    new Recipe { Id = 2, Name = "Flan", Ingredients = [new RecipeIngredient { RecipeId = 2, IngredientId = huevos.Id, Quantity = 3m, Unit = "unidad" }] }];

// ---- AdjustStock (S6) ----
var tAdjust = DateTime.Now;
var adj = ingredients.AdjustStock(harina.Id, 90m, "  conteo r\u00e1pido  ", Copy(admin));
Check(harina.CurrentStock == 90m && adj.Type == StockMovementType.Adjustment && adj.Quantity == -10m && adj.PreviousStock == 100m && adj.ResultingStock == 90m && adj.Reason == "conteo r\u00e1pido"
    && adj.Unit == "kg" && adj.UserId == 10 && adj.Username == "fixture-admin" && adj.Date >= tAdjust && adj.IngredientId == harina.Id && adj.Id == storage.StockMovements.Last().Id, "AdjustStock records the signed delta, trimmed reason, actor and balances");
var adjUp = ingredients.AdjustStock(harina.Id, 100m, "reposicion", admin2);
Check(harina.CurrentStock == 100m && adjUp.Quantity == 10m && adjUp.PreviousStock == 90m && adjUp.ResultingStock == 100m && adjUp.UserId == 11, "AdjustStock upwards by a second admin");
Check(ingredients.AdjustStock(sal.Id, 0.5m, "alta de sal", admin).PreviousStock == 0m && sal.CurrentStock == 0.5m, "AdjustStock of an ingredient without history starts from its stored stock");
adj.Reason = "tampered";
Check(storage.StockMovements.Single(m => m.Id == adj.Id).Reason == "conteo r\u00e1pido", "AdjustStock returns a detached movement");
Denied(() => ingredients.AdjustStock(harina.Id, 50m, "x", null), "adjust with null actor");
Denied(() => ingredients.AdjustStock(harina.Id, 50m, "x", employee), "adjust by employee");
Denied(() => ingredients.AdjustStock(harina.Id, 50m, "x", new User { Id = 10, Username = "fixture-admin", PasswordHash = "old", Role = UserRole.Admin }), "adjust with stale password");
var staleAdmin = Copy(admin); admin.Role = UserRole.Employee;
Denied(() => ingredients.AdjustStock(harina.Id, 50m, "x", staleAdmin), "adjust by a demoted admin"); admin.Role = UserRole.Admin;
Invalid(() => ingredients.AdjustStock(harina.Id, 50m, null, admin), "adjust without reason", "motivo");
Invalid(() => ingredients.AdjustStock(harina.Id, 50m, "  \t ", admin), "adjust with blank reason", "motivo");
Invalid(() => ingredients.AdjustStock(harina.Id, -1m, "x", admin), "adjust to a negative stock", "negativo");
Invalid(() => ingredients.AdjustStock(harina.Id, 100m, "x", admin), "no-op adjust", "igual");
Invalid(() => ingredients.AdjustStock(99999, 5m, "x", admin), "adjust of an unknown ingredient", "no existe");
var stockCounter = typeof(DataStorageService).GetField("_nextStockMovementId", flags);
Check(stockCounter != null, "ledger id counter exists");
var savedStockCounter = stockCounter?.GetValue(storage);
foreach (var bad in new[] { int.MaxValue, 0, -1 }) { stockCounter?.SetValue(storage, bad); Invalid(() => ingredients.AdjustStock(harina.Id, 50m, "x", admin), "adjust with ledger counter " + bad, "identificadores"); }
stockCounter?.SetValue(storage, savedStockCounter);

// ---- RegisterWaste (S8) ----
var w1 = ingredients.RegisterWaste(harina.Id, 5m, WasteCategory.Vencimiento, "  bolsa vencida ", admin);
Check(harina.CurrentStock == 95m && w1.Type == StockMovementType.Waste && w1.Quantity == -5m && w1.PreviousStock == 100m && w1.ResultingStock == 95m && w1.WasteCategory == WasteCategory.Vencimiento
    && w1.Reason == "bolsa vencida" && w1.UserId == 10 && w1.Unit == "kg", "RegisterWaste records a negative quantity with category, reason and actor");
var w2 = ingredients.RegisterWaste(huevos.Id, 1m, WasteCategory.RoturaODerrame, "se cayo", admin2);
Check(huevos.CurrentStock == 9m && w2.WasteCategory == WasteCategory.RoturaODerrame && w2.UserId == 11 && w2.ResultingStock == 9m, "RegisterWaste of a second ingredient and category");
var wall = new Ingredient { Name = "Azucar", Unit = "kg", CurrentStock = 2m }; ingredients.Add(wall, admin);
var wAll = ingredients.RegisterWaste(wall.Id, 2m, WasteCategory.ErrorDePreparacion, "todo", admin);
Check(wall.CurrentStock == 0m && wAll.ResultingStock == 0m && wAll.WasteCategory == WasteCategory.ErrorDePreparacion, "waste of the whole stock is allowed and leaves zero");
Invalid(() => ingredients.RegisterWaste(harina.Id, 0m, WasteCategory.Otro, "x", admin), "zero waste", "positiva");
Invalid(() => ingredients.RegisterWaste(harina.Id, -1m, WasteCategory.Otro, "x", admin), "negative waste", "positiva");
Invalid(() => ingredients.RegisterWaste(harina.Id, 95.01m, WasteCategory.Otro, "x", admin), "waste above the stock (negative stock)", "Stock insuficiente");
Invalid(() => ingredients.RegisterWaste(harina.Id, 1m, WasteCategory.Otro, " ", admin), "waste without reason", "motivo");
Invalid(() => ingredients.RegisterWaste(harina.Id, 1m, WasteCategory.Otro, null, admin), "waste with null reason", "motivo");
Invalid(() => ingredients.RegisterWaste(harina.Id, 1m, (WasteCategory)9, "x", admin), "waste with undefined category", "categor\u00eda");
Invalid(() => ingredients.RegisterWaste(99999, 1m, WasteCategory.Otro, "x", admin), "waste of an unknown ingredient", "no existe");
Denied(() => ingredients.RegisterWaste(harina.Id, 1m, WasteCategory.Otro, "x", employee), "waste by employee");
Denied(() => ingredients.RegisterWaste(harina.Id, 1m, WasteCategory.Otro, "x", null), "waste without actor");

// ---- Count adjustments (batch, StockCountId linkage) ----
Denied(() => ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 96m, Reason = "x" }], employee), "count by employee");
Invalid(() => ingredients.ApplyCountAdjustments(0, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 96m, Reason = "x" }], admin), "count with invalid id", "conteo");
Invalid(() => ingredients.ApplyCountAdjustments(7, [], admin), "empty count", "al menos");
Invalid(() => ingredients.ApplyCountAdjustments(7, null, admin), "null count", "al menos");
Invalid(() => ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 96m, Reason = " " }], admin), "count difference without reason", "motivo");
Invalid(() => ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = -1m, Reason = "x" }], admin), "negative counted stock", "negativo");
Invalid(() => ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 96m, Reason = "x" }, new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 97m, Reason = "x" }], admin), "repeated ingredient in a count", "repetir");
Invalid(() => ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = 99999, CountedStock = 1m, Reason = "x" }], admin), "unknown ingredient in a count", "no existe");
Invalid(() => ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 96m, ExpectedStock = 94m, Reason = "x" }], admin), "count over a changed registered stock", "cambi\u00f3");
Invalid(() => ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 96m, Reason = "valida" }, new StockCountAdjustment { IngredientId = huevos.Id, CountedStock = 12m, Reason = null }], admin), "count with one invalid line is all-or-nothing", "motivo");
var ledgerBeforeCount = storage.StockMovements.Count;
var noDiff = ingredients.ApplyCountAdjustments(7, [new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 95m, ExpectedStock = 95m }], admin);
Check(noDiff.Count == 0 && storage.StockMovements.Count == ledgerBeforeCount, "count without differences creates no movement");
var countMovements = ingredients.ApplyCountAdjustments(7, [
    new StockCountAdjustment { IngredientId = harina.Id, CountedStock = 96m, ExpectedStock = 95m, Reason = " conteo mensual " },
    new StockCountAdjustment { IngredientId = huevos.Id, CountedStock = 9m, ExpectedStock = 9m },
    new StockCountAdjustment { IngredientId = sal.Id, CountedStock = 0.25m, Reason = "faltante" }], Copy(admin));
Check(countMovements.Count == 2 && countMovements.All(m => m.Type == StockMovementType.CountAdjustment && m.StockCountId == 7 && m.UserId == 10 && m.Unit == "kg")
    && countMovements[0].IngredientId == harina.Id && countMovements[0].Quantity == 1m && countMovements[0].PreviousStock == 95m && countMovements[0].ResultingStock == 96m && countMovements[0].Reason == "conteo mensual"
    && countMovements[1].IngredientId == sal.Id && countMovements[1].Quantity == -0.25m && countMovements[1].PreviousStock == 0.5m && countMovements[1].ResultingStock == 0.25m
    && harina.CurrentStock == 96m && huevos.CurrentStock == 9m && sal.CurrentStock == 0.25m, "count batch applies only differences, linked to the count, with balances and reasons");
Check(countMovements.Select(m => m.Id).Distinct().Count() == 2 && storage.StockMovements.Count == ledgerBeforeCount + 2, "count batch movements get distinct ledger ids");

// ---- Sales: aggregated validation and atomic deduction (S9) ----
cash.Open(100m);
Check(sales.ValidateStock([Line(pizza, 3)]).IsValid && sales.ValidateStock([Line(flan, 2)]).IsValid && !sales.ValidateStock([Line(pizza, 3), Line(flan, 2)]).IsValid,
    "each line fits on its own but the aggregated requirement does not (9 eggs, 6 + 6 needed)");
Invalid(() => sales.Add(Simple([Line(pizza, 3), Line(flan, 2)], CashPay(400m)), Copy(admin)), "aggregated requirement above stock", "Stock insuficiente de Huevos");
Invalid(() => sales.Add(Simple([Line(pizza, 4), Line(pizza, 1)], CashPay(500m)), Copy(admin)), "same product on two lines above aggregated stock", "Stock insuficiente de Huevos");
Invalid(() => sales.Add(Simple([Line(flan, 4)], CashPay(200m)), Copy(admin)), "single line above stock keeps its message", "Disponible: 9 unidad");
var tSale = DateTime.Now;
var s1 = Simple([Line(pizza, 2), Line(flan, 1), Line(agua, 1)], CashPay(260m));
sales.Add(s1, Copy(admin));
var s1Moves = storage.StockMovements.Where(m => m.SaleId == s1.Id).ToList();
Check(s1.Id > 0 && harina.CurrentStock == 95m && huevos.CurrentStock == 2m && s1Moves.Count == 2 && s1Moves.All(m => m.Type == StockMovementType.SaleConsumption && m.UserId == 10 && m.Username == "fixture-admin" && m.Date == s1.Date && m.Date >= tSale
    && m.RefundId == null && m.InvoiceId == null && m.Reason == null), "sale deducts and records one SaleConsumption per ingredient linked to the sale with the seller");
Check(s1Moves[0] is { IngredientId: var i0, Quantity: -1m, PreviousStock: 96m, ResultingStock: 95m, Unit: "kg" } && i0 == harina.Id
    && s1Moves[1] is { IngredientId: var i1, Quantity: -7m, PreviousStock: 9m, ResultingStock: 2m, Unit: "unidad" } && i1 == huevos.Id, "movements aggregate eggs across lines (4 + 3) with previous and resulting stock");
Check(s1.IsStockConsumptionReliable && s1.StockConsumption.Count == 3 && s1.Items[0].StockConsumption!.Count == 2 && s1.Items[1].StockConsumption!.Single().Quantity == 3m && s1.Items[2].StockConsumption!.Count == 0
    && s1.StockConsumption.Where(e => e.IngredientId == huevos.Id).Sum(e => e.Quantity) == 7m, "PRESERVE: aggregate and per-line consumption snapshots keep their shape");
Check(storage.CashMovements.Count(m => m.SaleId == s1.Id && m.Type == CashMovementType.Sale && m.Amount == 260m) == 1, "PRESERVE: cash movement of the sale");
Invalid(() => sales.Add(Simple([Line(pizza, 1), Line(pizza, 1)], CashPay(200m)), Copy(admin)), "two pizza lines need 4 eggs with 2 left", "Stock insuficiente de Huevos");
Reject(() => sales.Add(Simple([Line(pizza, 1)], CashPay(100m)), new User { Id = 99, Username = "ghost", PasswordHash = hash, Role = UserRole.Admin }), typeof(UnauthorizedAccessException), "unknown seller", "usuario vigente");
var counterBeforeSale = stockCounter!.GetValue(storage);
foreach (var bad in new[] { int.MaxValue, 0 }) { stockCounter?.SetValue(storage, bad); Invalid(() => sales.Add(Simple([Line(pizza, 1)], CashPay(100m)), Copy(admin)), "sale with ledger counter " + bad, "identificadores"); }
stockCounter.SetValue(storage, counterBeforeSale);
var cashCounter = typeof(DataStorageService).GetField("_nextCashMovementId", flags)!; var savedCashCounter = cashCounter.GetValue(storage);
cashCounter.SetValue(storage, int.MaxValue);
Invalid(() => sales.Add(Simple([Line(pizza, 1)], CashPay(100m)), Copy(admin)), "sale with cash movement counter exhausted leaves stock untouched", "identificadores");
cashCounter.SetValue(storage, savedCashCounter);
var noRecipe = Simple([Line(agua, 2)], CashPay(20m)); var movementsBeforeAgua = storage.StockMovements.Count;
sales.Add(noRecipe);
Check(storage.StockMovements.Count == movementsBeforeAgua && noRecipe.IsStockConsumptionReliable && noRecipe.Items[0].StockConsumption!.Count == 0 && storage.Sales.Contains(noRecipe), "PRESERVE: a product without recipe records no movement and the sale is saved");

// ---- Cancel restores through movements ----
Invalid(() => sales.Cancel(s1.Id, " ", admin), "cancel without reason", "motivo");
Denied(() => sales.Cancel(s1.Id, "x", employee), "cancel by employee");
sales.Cancel(s1.Id, "error de carga", admin);
var cancelMoves = storage.StockMovements.Where(m => m.Type == StockMovementType.SaleCancellationReturn && m.SaleId == s1.Id).OrderBy(m => m.Id).ToList();
Check(harina.CurrentStock == 96m && huevos.CurrentStock == 9m && s1.Status == SaleStatus.Cancelled && cancelMoves.Count == 2 && cancelMoves.All(m => m.UserId == 10 && m.Reason == "error de carga" && m.RefundId == null && m.Date == s1.CancelledAt),
    "Cancel restores stock through SaleCancellationReturn movements with the cancelling admin and reason");
Check(cancelMoves[0] is { Quantity: 1m, PreviousStock: 95m, ResultingStock: 96m, Unit: "kg" } && cancelMoves[1] is { Quantity: 7m, PreviousStock: 2m, ResultingStock: 9m, Unit: "unidad" }, "cancellation movements carry previous and resulting stock");
Invalid(() => sales.Cancel(s1.Id, "otra vez", admin), "repeated cancellation", "completada");

// ---- Refund restock through movements ----
var s3 = Simple([Line(pizza, 2), Line(flan, 1)], CashPay(250m)); sales.Add(s3, Copy(employee));
Check(Mv(huevos.Id).Last() is { Type: StockMovementType.SaleConsumption, UserId: 12, Quantity: -7m } && harina.CurrentStock == 95m && huevos.CurrentStock == 2m, "employee sale records the employee as responsible");
Invalid(() => sales.Refund(s3.Id, " ", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin), "refund without reason", "motivo");
Invalid(() => sales.Refund(s3.Id, "x", [RL(0, 3)], [RP(PaymentMethod.Cash, 300m)], admin), "refund above sold units", "unidades");
var refund1 = sales.Refund(s3.Id, " devuelto ", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin);
var refundMoves = storage.StockMovements.Where(m => m.RefundId == refund1.Id).OrderBy(m => m.Id).ToList();
Check(refundMoves.Count == 2 && refundMoves.All(m => m.Type == StockMovementType.RefundReturn && m.SaleId == s3.Id && m.UserId == 10 && m.Reason == "devuelto" && m.Date == refund1.Date)
    && refundMoves[0] is { Quantity: 0.5m, PreviousStock: 95m, ResultingStock: 95.5m, Unit: "kg" } && refundMoves[1] is { Quantity: 2m, PreviousStock: 2m, ResultingStock: 4m, Unit: "unidad" }
    && harina.CurrentStock == 95.5m && huevos.CurrentStock == 4m, "Restock refund creates RefundReturn movements linked to sale and refund, proportional to the refunded units");
var beforeWaste = storage.StockMovements.Count;
sales.Refund(s3.Id, "merma", [RL(1, 1, RefundDisposition.Waste)], [RP(PaymentMethod.Cash, 50m)], admin);
Check(storage.StockMovements.Count == beforeWaste && huevos.CurrentStock == 4m, "Waste disposition records no stock movement");
var harinaCapacitySaved = harina.CurrentStock;
Denied(() => sales.Refund(s3.Id, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], employee), "refund by employee");
harina.CurrentStock = decimal.MaxValue - 0.1m;
Invalid(() => sales.Refund(s3.Id, "x", [RL(0, 1)], [RP(PaymentMethod.Cash, 100m)], admin), "refund restock overflow leaves the ledger untouched", "l\u00edmite");
harina.CurrentStock = harinaCapacitySaved;

// ---- Invoice receipt (S7) ----
var tInvoice = DateTime.Now;
var inv = new Invoice { SupplierId = 1, InvoiceNumber = "A-1", Items = [
    new InvoiceItem { IngredientId = harina.Id, IngredientName = "Harina", Quantity = 2m, Unit = "kg", UnitPrice = 80m },
    new InvoiceItem { IngredientId = harina.Id, IngredientName = "Harina", Quantity = 500m, Unit = "gr", UnitPrice = 0.08m },
    new InvoiceItem { IngredientId = huevos.Id, IngredientName = "Huevos", Quantity = 12m, Unit = "unidad", UnitPrice = 15m },
    new InvoiceItem { IngredientId = 99999, IngredientName = "Fantasma", Quantity = 3m, Unit = "kg", UnitPrice = 1m },
    new InvoiceItem { IngredientId = huevos.Id, IngredientName = "Huevos", Quantity = 4m, Unit = "kg", UnitPrice = 1m }] };
invoices.Add(inv, Copy(admin));
var receipts = storage.StockMovements.Where(m => m.InvoiceId == inv.Id).OrderBy(m => m.Id).ToList();
Check(inv.Id > 0 && receipts.Count == 3 && receipts.All(m => m.Type == StockMovementType.InvoiceReceipt && m.UserId == 10 && m.Username == "fixture-admin" && m.Date >= tInvoice && m.SaleId == null && m.RefundId == null)
    && receipts[0] is { Quantity: 2m, PreviousStock: 95.5m, ResultingStock: 97.5m, Unit: "kg" } && receipts[1] is { Quantity: 0.5m, PreviousStock: 97.5m, ResultingStock: 98m, Unit: "kg" }
    && receipts[2] is { Quantity: 12m, PreviousStock: 4m, ResultingStock: 16m, Unit: "unidad" } && harina.CurrentStock == 98m && huevos.CurrentStock == 16m,
    "invoice creates InvoiceReceipt movements in the ingredient unit (gr converted), linked to the invoice; unknown ingredient and incompatible unit stay skipped");
var invNoActor = new Invoice { SupplierId = 1, Items = [new InvoiceItem { IngredientId = sal.Id, Quantity = 1m, Unit = "kg", UnitPrice = 1m }] };
invoices.Add(invNoActor);
Check(Mv(sal.Id).Last() is { Type: StockMovementType.InvoiceReceipt, UserId: null, Username: null, Quantity: 1m, PreviousStock: 0.25m, ResultingStock: 1.25m } && Mv(sal.Id).Last().InvoiceId == invNoActor.Id, "invoice without actor records a null responsible");
Invalid(() => invoices.Add(new Invoice { SupplierId = 1, Items = [new InvoiceItem { IngredientId = harina.Id, Quantity = 1m, Unit = "kg" }, new InvoiceItem { IngredientId = huevos.Id, Quantity = 0m, Unit = "unidad" }] }, admin),
    "invoice with a non-positive item is rejected as a whole", "positiva");
Reject(() => invoices.Add(new Invoice { SupplierId = 1, Items = [new InvoiceItem { IngredientId = harina.Id, Quantity = 1m, Unit = "kg" }] }, new User { Id = 10, Username = "fixture-admin", PasswordHash = "old", Role = UserRole.Admin }),
    typeof(UnauthorizedAccessException), "invoice with a stale actor", "vigente");
harina.CurrentStock = decimal.MaxValue - 0.1m;
Invalid(() => invoices.Add(new Invoice { SupplierId = 1, Items = [new InvoiceItem { IngredientId = huevos.Id, Quantity = 1m, Unit = "unidad" }, new InvoiceItem { IngredientId = harina.Id, Quantity = 1m, Unit = "kg" }] }, admin),
    "invoice overflow of a later item leaves earlier items untouched", "l\u00edmite");
harina.CurrentStock = 98m;
var invoiceMovements = storage.StockMovements.Count(m => m.InvoiceId == inv.Id); var stockBeforeDelete = (harina.CurrentStock, huevos.CurrentStock);
invoices.Delete(inv.Id);
Check(storage.Invoices.All(i => i.Id != inv.Id) && storage.StockMovements.Count(m => m.InvoiceId == inv.Id) == invoiceMovements && (harina.CurrentStock, huevos.CurrentStock) == stockBeforeDelete, "PRESERVE: deleting an invoice keeps stock and its movements (M16 unchanged)");

// ---- Negative stock policy (S10) ----
var legacyNeg = new Ingredient { Name = "Legado", Unit = "kg", CurrentStock = 0m }; ingredients.Add(legacyNeg, admin);
legacyNeg.CurrentStock = -3m; // legacy negative balance
Invalid(() => ingredients.RegisterWaste(legacyNeg.Id, 1m, WasteCategory.Otro, "x", admin), "waste on a negative balance", "Stock insuficiente");
Invalid(() => ingredients.AdjustStock(legacyNeg.Id, -1m, "x", admin), "adjust a negative balance to a negative target", "negativo");
invoices.Add(new Invoice { SupplierId = 1, Items = [new InvoiceItem { IngredientId = legacyNeg.Id, Quantity = 1m, Unit = "kg", UnitPrice = 1m }] }, admin);
Check(Mv(legacyNeg.Id).Last() is { Type: StockMovementType.InvoiceReceipt, PreviousStock: -3m, ResultingStock: -2m } && legacyNeg.CurrentStock == -2m, "a receipt may repair a legacy negative balance without being rejected");
var legacyFix = ingredients.AdjustStock(legacyNeg.Id, 4m, "regularizacion", admin);
Check(legacyFix.Quantity == 6m && legacyFix.PreviousStock == -2m && legacyNeg.CurrentStock == 4m, "manual adjustment to a valid target repairs a negative balance");

// ---- Every movement type is present and consistent ----
var typesSeen = storage.StockMovements.Select(m => m.Type).Distinct().OrderBy(t => t).ToArray();
Check(typesSeen.SequenceEqual(Enum.GetValues<StockMovementType>()), "the fixture produced every movement type");
Check(storage.StockMovements.All(m => m.PreviousStock + m.Quantity == m.ResultingStock && m.Quantity != 0m && !string.IsNullOrWhiteSpace(m.Unit)), "every movement satisfies previous + quantity = resulting");
Check(storage.Ingredients.All(i => !storage.StockMovements.Any(m => m.IngredientId == i.Id) || Mv(i.Id).Last().ResultingStock == i.CurrentStock), "stock of each ingredient with history equals its last resulting stock");
Check(storage.StockMovements.Select(m => m.Id).SequenceEqual(Enumerable.Range(1, storage.StockMovements.Count)), "ledger ids are sequential and unique");

// ---- Queries: filters and ordering ----
var cacao = new Ingredient { Name = "Cacao", Unit = "kg", CurrentStock = 50m }; ingredients.Add(cacao, admin);
ingredients.AdjustStock(cacao.Id, 60m, "a", admin); ingredients.RegisterWaste(cacao.Id, 5m, WasteCategory.Otro, "b", admin); ingredients.RegisterWaste(cacao.Id, 1m, WasteCategory.Otro, "c", admin);
var cm = Mv(cacao.Id);
cm[0].Date = new DateTime(2026, 3, 10, 0, 0, 0); cm[1].Date = new DateTime(2026, 3, 10, 23, 59, 59);
cm[2].Date = new DateTime(2026, 3, 12, 12, 0, 0); cm[3].Date = new DateTime(2026, 3, 12, 12, 0, 0);
int[] Ids(StockMovementFilter? f) => ingredients.GetMovements(cacao.Id, f).Select(m => m.Id).ToArray();
Check(Ids(null).SequenceEqual(new[] { cm[3].Id, cm[2].Id, cm[1].Id, cm[0].Id }), "movements ordered by date descending, then id descending");
Check(Ids(new StockMovementFilter { From = new DateTime(2026, 3, 10, 18, 0, 0), To = new DateTime(2026, 3, 10, 1, 0, 0) }).SequenceEqual(new[] { cm[1].Id, cm[0].Id }), "date range compares whole days and is inclusive on both ends");
Check(Ids(new StockMovementFilter { From = new DateTime(2026, 3, 11) }).SequenceEqual(new[] { cm[3].Id, cm[2].Id }) && Ids(new StockMovementFilter { To = new DateTime(2026, 3, 11) }).SequenceEqual(new[] { cm[1].Id, cm[0].Id }), "open-ended ranges");
Check(Ids(new StockMovementFilter { From = new DateTime(2026, 3, 12), To = new DateTime(2026, 3, 10) }).Length == 0, "inverted range is empty");
Check(Ids(new StockMovementFilter { Types = [StockMovementType.Waste] }).SequenceEqual(new[] { cm[3].Id, cm[2].Id }) && Ids(new StockMovementFilter { Types = [StockMovementType.Adjustment, StockMovementType.InitialStock] }).SequenceEqual(new[] { cm[1].Id, cm[0].Id }), "type filter");
Check(Ids(new StockMovementFilter { Types = [] }).Length == 4 && Ids(new StockMovementFilter()).Length == 4, "empty type filter means every type");
Check(Ids(new StockMovementFilter { Types = [StockMovementType.Waste], To = new DateTime(2026, 3, 11) }).Length == 0, "type and date filters combine");
Check(ingredients.GetMovements(99999).Count == 0 && ingredients.GetMovements(sal.Id).All(m => m.IngredientId == sal.Id), "queries are scoped to the ingredient; unknown ingredient is empty");
var copies = ingredients.GetMovements(cacao.Id); var storedReason = cm[0].Reason; var storedQuantity = cm[0].Quantity;
copies[^1].Reason = "tampered"; copies[^1].Quantity = 12345m; copies.Clear();
Check(Mv(cacao.Id)[0].Reason == storedReason && Mv(cacao.Id)[0].Quantity == storedQuantity && Mv(cacao.Id).Length == 4, "GetMovements returns detached copies");

// ---- Queries: consumption over a period (coverage) ----
var today = DateTime.Today;
var eggMoves = Mv(huevos.Id);
StockMovement Egg(StockMovementType type, int? saleId = null) => eggMoves.Where(m => m.Type == type && (saleId == null || m.SaleId == saleId)).First();
var eS1 = Egg(StockMovementType.SaleConsumption, s1.Id); var eCancel = Egg(StockMovementType.SaleCancellationReturn, s1.Id);
var eS3 = Egg(StockMovementType.SaleConsumption, s3.Id); var eRefund = Egg(StockMovementType.RefundReturn);
var s5 = Simple([Line(flan, 1)], CashPay(50m)); sales.Add(s5, Copy(admin));
var eS5 = Mv(huevos.Id).Last(m => m.SaleId == s5.Id);
eCancel.Date = today.AddDays(-6).AddHours(10); eS3.Date = today.AddDays(-3).AddHours(9); eRefund.Date = today.AddDays(-3).AddHours(15);
eS1.Date = today.AddHours(1); eS5.Date = today.AddHours(2);
Check(eS1.Quantity == -7m && eCancel.Quantity == 7m && eS3.Quantity == -7m && eRefund.Quantity == 2m && eS5.Quantity == -3m, "consumption fixture quantities");
Check(ingredients.GetConsumption(huevos.Id, today, today) == 10m, "consumption of a day sums sale consumption (7 + 3)");
Check(ingredients.GetConsumption(huevos.Id, today.AddDays(-3), today.AddDays(-3)) == 5m, "consumption nets refund returns (7 - 2)");
Check(ingredients.GetConsumption(huevos.Id, today.AddDays(-6), today.AddDays(-6)) == 0m, "consumption is never negative");
Check(ingredients.GetConsumption(huevos.Id, today.AddDays(-6), today) == 8m, "consumption over a wide period nets every sale return (-7 +7 -7 +2 -3)");
Check(ingredients.GetConsumption(huevos.Id, today.AddDays(-2), today.AddDays(-1)) == 0m && ingredients.GetConsumption(huevos.Id, today, today.AddDays(-1)) == 0m && ingredients.GetConsumption(99999, today.AddDays(-9), today) == 0m, "empty, inverted and unknown periods have no consumption");
Check(ingredients.GetConsumption(harina.Id, today.AddDays(-9), today.AddDays(9)) == 0.5m && ingredients.GetConsumption(harina.Id, today.AddDays(-9), today.AddDays(9)) == ingredients.GetMovements(harina.Id).Where(m => m.Type is StockMovementType.SaleConsumption or StockMovementType.SaleCancellationReturn or StockMovementType.RefundReturn).Sum(m => -m.Quantity),
    "waste, adjustments, counts and receipts are not consumption");

// ---- Persistence ----
storage.SaveToFile();
var savedJson = File.ReadAllText("data.json");
var reload = new DataStorageService();
Check(JsonSerializer.Serialize(reload.StockMovements) == JsonSerializer.Serialize(storage.StockMovements) && reload.StockMovements.Count == storage.StockMovements.Count
    && JsonSerializer.Serialize(reload.Ingredients) == JsonSerializer.Serialize(storage.Ingredients), "save/reload keeps the ledger and the stock identical");
var reloadIngredients = new IngredientService(reload, new InvoiceService(reload));
var reloadAdjust = reloadIngredients.AdjustStock(harina.Id, harina.CurrentStock + 1m, "tras reinicio", reload.Users[0]);
Check(reloadAdjust.Id == storage.StockMovements.Max(m => m.Id) + 1 && reloadAdjust.PreviousStock == harina.CurrentStock, "reload recovers the ledger counter");
int dirs = 0;
string LoadDir() => Path.Combine(root, "load-" + dirs);
DataStorageService LoadFrom(JsonObject json)
{
    var dir = Path.Combine(root, "load-" + (++dirs)); Directory.CreateDirectory(dir);
    File.WriteAllText(Path.Combine(dir, "data.json"), json.ToJsonString());
    Directory.SetCurrentDirectory(dir);
    try { return new DataStorageService(); } finally { Directory.SetCurrentDirectory(root); }
}
JsonObject Fresh() => JsonNode.Parse(savedJson)!.AsObject();
var legacyJson = Fresh(); legacyJson.Remove("StockMovements"); legacyJson.Remove("NextStockMovementId");
var legacyBytes = System.Text.Encoding.UTF8.GetBytes(legacyJson.ToJsonString());
var legacy = LoadFrom(legacyJson);
Check(legacy.StockMovements.Count == 0 && legacy.Ingredients.Count == storage.Ingredients.Count && legacy.Ingredients.First(i => i.Id == harina.Id).CurrentStock == harina.CurrentStock, "legacy JSON without StockMovements loads with an empty ledger and the stored stock");
Check(File.ReadAllBytes(Path.Combine(LoadDir(), "data.json")).SequenceEqual(legacyBytes), "loading never writes data.json");
var legacyIngredients = new IngredientService(legacy, new InvoiceService(legacy));
Check(!legacyIngredients.HasMovements(harina.Id) && legacyIngredients.GetMovements(harina.Id).Count == 0, "legacy stock has no history");
var firstLegacy = legacyIngredients.AdjustStock(harina.Id, harina.CurrentStock + 2m, "primer ajuste", legacy.Users[0]);
Check(firstLegacy.Id == 1 && firstLegacy.PreviousStock == harina.CurrentStock && legacy.StockMovements.Count == 1, "first movement on legacy data starts the ledger at id 1 from the stored stock");
JsonNode MvNode(JsonObject j, int type) => j["StockMovements"]!.AsArray().First(n => n!["Type"]!.GetValue<int>() == type)!;
void BadLoad(string name, Action<JsonObject> mutate)
{
    var json = Fresh(); mutate(json);
    var ok = false;
    try { LoadFrom(json); } catch (InvalidDataException) { ok = true; }
    Check(ok, "corrupt stock ledger rejected on load: " + name);
}
BadLoad("null list", j => j["StockMovements"] = null);
BadLoad("null entry", j => j["StockMovements"]!.AsArray().Add(null));
BadLoad("duplicate id", j => j["StockMovements"]![1]!["Id"] = j["StockMovements"]![0]!["Id"]!.GetValue<int>());
BadLoad("zero id", j => j["StockMovements"]![0]!["Id"] = 0);
BadLoad("zero counter", j => j["NextStockMovementId"] = 0);
BadLoad("undefined type", j => j["StockMovements"]![0]!["Type"] = 99);
BadLoad("zero quantity", j => { var n = MvNode(j, 4); n["Quantity"] = 0; n["ResultingStock"] = n["PreviousStock"]!.GetValue<decimal>(); });
BadLoad("balances not matching quantity", j => MvNode(j, 4)["ResultingStock"] = MvNode(j, 4)["ResultingStock"]!.GetValue<decimal>() + 1m);
BadLoad("consumption with positive quantity", j => { var n = MvNode(j, 1); n["Quantity"] = 5; n["ResultingStock"] = n["PreviousStock"]!.GetValue<decimal>() + 5m; });
BadLoad("receipt with negative quantity", j => { var n = MvNode(j, 0); n["Quantity"] = -5; n["ResultingStock"] = n["PreviousStock"]!.GetValue<decimal>() - 5m; });
BadLoad("blank unit", j => MvNode(j, 4)["Unit"] = " ");
BadLoad("adjustment without reason", j => MvNode(j, 4)["Reason"] = " ");
BadLoad("count adjustment without reason", j => MvNode(j, 6)["Reason"] = null);
BadLoad("waste without category", j => MvNode(j, 5)["WasteCategory"] = null);
BadLoad("waste with undefined category", j => MvNode(j, 5)["WasteCategory"] = 9);
BadLoad("category on a non-waste movement", j => MvNode(j, 4)["WasteCategory"] = 0);
BadLoad("user id without username", j => { var n = MvNode(j, 4); n["Username"] = null; });
BadLoad("username without user id", j => { var n = MvNode(j, 7); n["UserId"] = null; n["Username"] = "x"; });
BadLoad("consumption of an unknown sale", j => MvNode(j, 1)["SaleId"] = 98765);
BadLoad("cancellation return without sale", j => MvNode(j, 2)["SaleId"] = null);
BadLoad("refund return of an unknown refund", j => MvNode(j, 3)["RefundId"] = 98765);
BadLoad("refund return of another sale", j => MvNode(j, 3)["SaleId"] = MvNode(j, 1)["SaleId"]!.GetValue<int>());
BadLoad("receipt without invoice", j => MvNode(j, 0)["InvoiceId"] = null);
BadLoad("count adjustment without count", j => MvNode(j, 6)["StockCountId"] = null);
var orphan = Fresh();
var orphanIngredientId = MvNode(orphan, 0)["IngredientId"]!.GetValue<int>(); var orphanInvoiceId = MvNode(orphan, 0)["InvoiceId"]!.GetValue<int>();
var orphanIngredients = orphan["Ingredients"]!.AsArray(); orphanIngredients.Remove(orphanIngredients.First(n => n!["Id"]!.GetValue<int>() == orphanIngredientId));
var orphanInvoices = orphan["Invoices"]!.AsArray(); var gone = orphanInvoices.FirstOrDefault(n => n!["Id"]!.GetValue<int>() == orphanInvoiceId); if (gone != null) orphanInvoices.Remove(gone);
var orphanLoaded = false;
try { orphanLoaded = LoadFrom(orphan).StockMovements.Count == storage.StockMovements.Count; } catch (InvalidDataException) { }
Check(orphanLoaded, "history of a deleted ingredient or invoice does not make the file unloadable");

// ---- Pages: minimal wiring ----
var ingredientsPage = File.ReadAllText(Path.Combine(args[0], "Pages", "Ingredients.razor"));
Check(System.Text.RegularExpressions.Regex.IsMatch(ingredientsPage, @"AdjustStock\(adjustIngredientId, [\w.]+, adjustReason, AuthService\.CurrentUser\)") && ingredientsPage.Contains("IngredientService.Add(editingIngredient, AuthService.CurrentUser)"), "Ingredients page passes the current user and a reason to the stock adjustment command");
var invoicesPage = File.ReadAllText(Path.Combine(args[0], "Pages", "Invoices.razor"));
Check(invoicesPage.Contains("InvoiceService.Add(editingInvoice, AuthService.CurrentUser)"), "Invoices page passes the current user to the invoice receipt");
Console.WriteLine($"{checks} checks, {failures} failures; fixture: {root}");
return failures == 0 ? 0 : 1;
'@ | Set-Content (Join-Path $ScratchPath 'Program.cs') -Encoding utf8
$exitCode = 1
Push-Location $ScratchPath
try {
    & dotnet run --project (Join-Path $ScratchPath 'StockChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Stock checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
