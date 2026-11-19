param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-sales-history-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'SalesHistoryChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using System.Collections;
using Microsoft.AspNetCore.Components;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Text.Json.Nodes;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var IOE = typeof(InvalidOperationException);
var UAE = typeof(UnauthorizedAccessException);
var storage = new DataStorageService(); // Process cwd is ALWAYS the newly allocated temp directory.
var sales = new SaleService(storage);
var cash = new CashRegisterService(storage, sales);
var history = new SaleHistoryService(storage);
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 11, Username = "second-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var admin = storage.Users[0]; var admin2 = storage.Users[1]; var employee = storage.Users[2];
User Copy(User user) => new() { Id = user.Id, Username = user.Username, PasswordHash = user.PasswordHash, Role = user.Role };
string Json(object? value) => JsonSerializer.Serialize(value);
string State() => Json(new { storage.CurrentCashRegisterId, storage.CashRegisters, storage.CashMovements, storage.CashCounts,
    storage.Sales, storage.Users, storage.Summaries, storage.Products, storage.ProductCategories,
    storage.Ingredients, storage.Suppliers, storage.Invoices, storage.Recipes,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
Exception? Reject(Action action, Type exception, string name)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    Exception? caught = null;
    try { action(); } catch (Exception ex) { caught = ex; }
    Check(caught?.GetType() == exception, name + " rejected with " + exception.Name + (caught == null ? " (no exception)" : " (got " + caught.GetType().Name + ")"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")), name + " leaves sales, registers, ledger, users, counters and fixture bytes unchanged");
    return caught;
}
SaleHistoryPage H(SaleHistoryFilter? filter = null, User? actor = null) => history.GetHistory(filter ?? new SaleHistoryFilter(), actor ?? Copy(admin));
int[] Ids(SaleHistoryPage page) => page.Entries.Select(e => e.Id).ToArray();
SaleHistoryEntry Entry(int id) => H(new SaleHistoryFilter(PageSize: 50)).Entries.Single(e => e.Id == id);
SaleHistoryDetail? Detail(int id) => history.GetDetail(id, Copy(admin));
int[] Exp(Func<Sale, bool> keep) => storage.Sales.Where(keep).OrderByDescending(s => s.Date).ThenByDescending(s => s.Id).Select(s => s.Id).ToArray();
SalePayment Pay(PaymentMethod method, decimal amount, decimal? received = null) => new() { PaymentMethod = method, Amount = amount, ReceivedAmount = received };
string Snap(SaleHistoryService service, User actor) => Json(new
{
    Page = service.GetHistory(new SaleHistoryFilter(PageSize: 50), actor),
    Operators = service.GetOperators(actor),
    Details = Enumerable.Range(-1, 40).Select(i => service.GetDetail(i, actor)).ToArray()
});

// ---- API surface and read-model shape.
Check(typeof(SaleHistoryService).GetMethod("GetHistory", new[] { typeof(SaleHistoryFilter), typeof(User) })?.ReturnType == typeof(SaleHistoryPage), "GetHistory(SaleHistoryFilter, User) returns SaleHistoryPage");
Check(typeof(SaleHistoryService).GetMethod("GetDetail", new[] { typeof(int), typeof(User) })?.ReturnType == typeof(SaleHistoryDetail), "GetDetail(int, User) returns SaleHistoryDetail");
Check(typeof(SaleHistoryService).GetMethod("GetOperators", new[] { typeof(User) })?.ReturnType == typeof(IReadOnlyList<SaleHistoryOperator>), "GetOperators(User) returns IReadOnlyList<SaleHistoryOperator>");
foreach (var type in new[] { typeof(SaleHistoryEntry), typeof(SaleHistoryPage), typeof(SaleHistoryDetail), typeof(SaleHistoryLine), typeof(SaleHistoryPayment), typeof(SaleHistoryEvent), typeof(SaleHistoryOperator) })
    Check(type.GetProperties().All(x => x.SetMethod == null) && type.GetConstructors().Length == 0 && type.IsSealed, type.Name + " is sealed, getter-only and built only by the service");
var defaults = new SaleHistoryFilter();
Check(defaults.DateFrom == null && defaults.DateTo == null && defaults.SaleId == null && defaults.OperatorUserId == null && !defaults.WithoutOperator && defaults.PaymentMethod == null
    && defaults.CashRegisterId == null && defaults.Status == SaleHistoryStatusFilter.All && defaults.ProductText == null && defaults.Page == 1 && defaults.PageSize == 10, "filter defaults");
Check(Enum.GetNames<SaleHistoryStatusFilter>().SequenceEqual(new[] { "All", "Completed", "Cancelled", "PartiallyRefunded", "Refunded" }), "status filter values (Completed means display status Collected)");
Check(Enum.GetNames<SaleHistoryEventKind>().SequenceEqual(new[] { "Created", "Cancelled", "Refunded" }), "event kinds include refunds");
Check(typeof(SaleHistoryEntry).GetProperty("DisplayStatus")?.PropertyType == typeof(SaleDisplayStatus) && typeof(SaleHistoryEntry).GetProperty("RefundedTotal")?.PropertyType == typeof(decimal?)
    && typeof(SaleHistoryEvent).GetProperty("Amount")?.PropertyType == typeof(decimal?) && typeof(SaleHistoryEvent).GetProperty("RefundId")?.PropertyType == typeof(int?), "entries carry display status and refunded total; events carry amount and refund id");
Check(typeof(SaleHistoryService).GetConstructors().Single().GetParameters().Select(p => p.ParameterType).SequenceEqual(new[] { typeof(DataStorageService) }), "service is constructor-injected with DataStorageService only");

// ---- No sales: empty history.
var empty = H();
Check(empty.TotalCount == 0 && empty.TotalPages == 0 && empty.Entries.Count == 0 && empty.Page == 1 && empty.PageSize == 10 && empty.Entries is IList { IsReadOnly: true }, "empty history: zero total, zero pages, read-only list");
Check(H(new SaleHistoryFilter(Page: 7, PageSize: 1000)).Page == 1 && H(new SaleHistoryFilter(Page: 7, PageSize: 1000)).PageSize == 50, "empty history clamps page to 1 and size to 50");
Check(Detail(1) == null && history.GetOperators(Copy(admin)).Count == 0, "no sales: detail is null and there are no operators");

// ---- Fixture: 30 sales with a permutation of dates, three operator kinds, mixed payments and cancellations.
string[] names = ["Café", "Medialunas", "Sandwich", "Tostado Jamón"];
var d0 = new DateTime(2026, 3, 1);
for (int i = 1; i <= 30; i++)
{
    var items = new List<SaleItem> { new() { ProductId = 1 + i % 4, ProductName = names[i % 4], Price = 10 + i, Quantity = 1 + i % 3 } };
    if (i % 6 == 0) items.Add(new SaleItem { ProductId = 9, ProductName = "Jugo de Naranja", Price = 5, Quantity = 1 });
    var payments = i % 5 == 0 ? new List<SalePayment> { Pay(PaymentMethod.Cash, 10m, 20m), Pay(PaymentMethod.DebitCard, 20m) }
        : i % 2 == 0 ? new List<SalePayment> { Pay(PaymentMethod.Transfer, 10 + i) }
        : new List<SalePayment> { Pay(PaymentMethod.Cash, 10 + i, 10 + i) };
    var sale = new Sale
    {
        Id = storage.GetNextSaleId(), CashRegisterId = i % 5 == 0 ? null : i % 4 + 11,
        Date = d0.AddDays(i * 7 % 30).AddHours(i % 2 == 0 ? 9 : 22),
        CreatedByUserId = i % 3 == 0 ? null : i % 3 == 1 ? 10 : 12,
        CreatedByUsername = i % 3 == 0 ? null : i % 3 == 1 ? "fixture-admin" : "fixture-employee",
        Items = items, Payments = payments
    };
    if (i % 7 == 0 && i != 14)
    {
        sale.Status = SaleStatus.Cancelled; sale.CancellationReason = "motivo " + i; sale.CancelledAt = sale.Date.AddHours(1);
        sale.CancelledByUserId = 10; sale.CancelledByUsername = "fixture-admin";
    }
    if (i == 14) sale.Status = SaleStatus.Cancelled; // legacy cancellation without reason, moment or responsible user
    storage.Sales.Add(sale);
}
SaleHistoryEntry? unusedEntry = null; _ = unusedEntry;
Sale S(int id) => storage.Sales.Single(s => s.Id == id);
S(4).Date = S(3).Date; // exact tie
// Sale 30: lines with notes and discounts, a sale-level discount and a cash payment with change.
var s30 = S(30);
s30.CashRegisterId = 12; s30.CreatedByUserId = 10; s30.CreatedByUsername = "fixture-admin";
s30.Items = [new SaleItem { ProductId = 1, ProductName = "Café", Price = 100m, Quantity = 2, Notes = "sin azúcar", DiscountType = DiscountType.Percentage, DiscountValue = 10m },
    new SaleItem { ProductId = 2, ProductName = "Medialunas", Price = 50m, Quantity = 3, DiscountType = DiscountType.Fixed, DiscountValue = 20m }];
s30.DiscountType = DiscountType.Fixed; s30.DiscountValue = 15m;
s30.Payments = [Pay(PaymentMethod.Cash, 100m, 150m), Pay(PaymentMethod.DebitCard, 195m)];
Check(storage.Sales.Count == 30 && S(30).Total == 295m && S(30).Subtotal == 310m, "fixture has 30 sales and sale 30 totals 295");
var all = Exp(_ => true);

// ---- Ordering and entry values.
var full = H(new SaleHistoryFilter(PageSize: 50));
Check(full.TotalCount == 30 && full.TotalPages == 1 && Ids(full).SequenceEqual(all) && Ids(full).OrderBy(x => x).SequenceEqual(Enumerable.Range(1, 30)), "history lists every sale ordered by Date descending");
Check(full.Entries.Zip(full.Entries.Skip(1)).All(p => p.First.Date > p.Second.Date || (p.First.Date == p.Second.Date && p.First.Id > p.Second.Id)), "adjacent entries strictly descend by Date then Id");
Check(Array.IndexOf(Ids(full), 4) + 1 == Array.IndexOf(Ids(full), 3) && !Ids(full).SequenceEqual(Enumerable.Range(1, 30).Reverse()), "same Date ties break by Id descending and order is not simply by Id");
var e1 = Entry(1); var e3 = Entry(3); var e7 = Entry(7); var e14 = Entry(14); var e30 = Entry(30);
Check(e1.Date == S(1).Date && e1.CashRegisterId == 12 && e1.OperatorUserId == 10 && e1.OperatorUsername == "fixture-admin" && e1.Status == SaleStatus.Completed && e1.Total == 22m
    && e1.ProductNames.SequenceEqual(new[] { "Medialunas" }) && e1.PaymentMethods.SequenceEqual(new[] { PaymentMethod.Cash }) && e1.ItemCount == 2 && !e1.AmountsUnavailable, "entry 1 mirrors its stored sale");
Check(e3.OperatorUserId == null && e3.OperatorUsername == null && e3.CashRegisterId == 14, "legacy sale without operator keeps null operator (shown as 'Sin registro' by the page)");
Check(e7.Status == SaleStatus.Cancelled && e14.Status == SaleStatus.Cancelled && e30.Total == 295m && e30.ProductNames.SequenceEqual(new[] { "Café", "Medialunas" })
    && e30.PaymentMethods.SequenceEqual(new[] { PaymentMethod.Cash, PaymentMethod.DebitCard }) && e30.ItemCount == 5, "cancelled status, discounted total, products and payment methods in entries");
Check(Entry(5).CashRegisterId == null && Entry(5).Total == S(5).Total, "sale without register link is listed with null register");
Check(e1.DisplayStatus == SaleDisplayStatus.Collected && e1.RefundedTotal == 0m && e7.DisplayStatus == SaleDisplayStatus.Cancelled && e14.DisplayStatus == SaleDisplayStatus.Cancelled && e7.RefundedTotal == 0m
    && full.Entries.All(e => e.DisplayStatus == (e.Status == SaleStatus.Cancelled ? SaleDisplayStatus.Cancelled : SaleDisplayStatus.Collected)), "sales without refunds show Collected or Cancelled with a zero refunded total");
Check(full.Entries is IList { IsReadOnly: true } && e30.ProductNames is IList { IsReadOnly: true } && e30.PaymentMethods is IList { IsReadOnly: true }, "entry collections are read-only");

// ---- Pagination.
var p1 = H(); var p2 = H(new SaleHistoryFilter(Page: 2)); var p3 = H(new SaleHistoryFilter(Page: 3));
Check(p1.TotalCount == 30 && p1.TotalPages == 3 && p1.Page == 1 && p1.PageSize == 10 && p1.Entries.Count == 10 && p3.Entries.Count == 10, "default page size 10: 30 entries over 3 pages");
Check(Ids(p1).Concat(Ids(p2)).Concat(Ids(p3)).SequenceEqual(all), "pages concatenate to the complete ordering without gaps or repeats");
var s7 = H(new SaleHistoryFilter(Page: 5, PageSize: 7));
Check(s7.TotalPages == 5 && s7.Entries.Count == 2 && Ids(s7).SequenceEqual(all.Skip(28)), "page size 7: last page holds the remainder");
Check(Ids(H(new SaleHistoryFilter(Page: 0))).SequenceEqual(Ids(p1)) && H(new SaleHistoryFilter(Page: 0)).Page == 1 && H(new SaleHistoryFilter(Page: -3)).Page == 1, "page 0 and negative pages clamp to the first page");
Check(H(new SaleHistoryFilter(Page: 99)).Page == 3 && Ids(H(new SaleHistoryFilter(Page: 99))).SequenceEqual(Ids(p3)) && H(new SaleHistoryFilter(Page: int.MaxValue)).Page == 3, "too-large pages clamp to the last page");
var size0 = H(new SaleHistoryFilter(PageSize: 0));
Check(size0.PageSize == 1 && size0.Entries.Count == 1 && size0.TotalPages == 30 && H(new SaleHistoryFilter(PageSize: -5)).PageSize == 1 && H(new SaleHistoryFilter(PageSize: int.MinValue)).PageSize == 1, "page size below 1 clamps to 1");
Check(H(new SaleHistoryFilter(PageSize: 1000)).PageSize == 50 && H(new SaleHistoryFilter(PageSize: 51)).PageSize == 50 && H(new SaleHistoryFilter(PageSize: 50)).PageSize == 50
    && H(new SaleHistoryFilter(PageSize: int.MaxValue)).PageSize == 50 && H(new SaleHistoryFilter(PageSize: 1000)).Entries.Count == 30, "page size above 50 clamps to 50");
var emptyFilter = H(new SaleHistoryFilter(SaleId: 9999, Page: 5, PageSize: 3));
Check(emptyFilter.TotalCount == 0 && emptyFilter.TotalPages == 0 && emptyFilter.Page == 1 && emptyFilter.PageSize == 3 && emptyFilter.Entries.Count == 0, "empty result: zero pages, page clamped to 1");

// ---- Filters (S1/S2).
var day5 = d0.AddDays(5); var day21 = d0.AddDays(21);
Check(S(5).Date.Date == day5 && S(3).Date.Date == day21 && S(4).Date.Date == day21, "fixture dates are as planned");
Check(Ids(H(new SaleHistoryFilter(DateFrom: day5, DateTo: day5, PageSize: 50))).SequenceEqual(new[] { 5 }), "same-day range includes a sale registered at 22:00 on that day");
Check(Ids(H(new SaleHistoryFilter(DateFrom: day5.AddHours(23), DateTo: day5.AddHours(1), PageSize: 50))).SequenceEqual(new[] { 5 }), "dates compare by calendar day, ignoring the time of day of the bounds");
Check(Ids(H(new SaleHistoryFilter(DateFrom: day21, DateTo: day21, PageSize: 50))).SequenceEqual(new[] { 4, 3 }), "tied day returns both sales, higher Id first");
Check(Ids(H(new SaleHistoryFilter(DateFrom: day5, DateTo: day21, PageSize: 50))).SequenceEqual(Exp(s => s.Date.Date >= day5 && s.Date.Date <= day21)) && H(new SaleHistoryFilter(DateFrom: day5, DateTo: day21)).TotalCount == 18, "inclusive range with both ends (days 5..21)");
Check(Ids(H(new SaleHistoryFilter(DateFrom: day21, PageSize: 50))).SequenceEqual(Exp(s => s.Date.Date >= day21)) && Ids(H(new SaleHistoryFilter(DateTo: day5, PageSize: 50))).SequenceEqual(Exp(s => s.Date.Date <= day5)), "open-ended ranges");
Check(H(new SaleHistoryFilter(DateFrom: d0.AddDays(40))).TotalCount == 0 && H(new SaleHistoryFilter(DateTo: d0.AddDays(-1))).TotalCount == 0, "ranges outside every sale are empty");
Check(Ids(H(new SaleHistoryFilter(SaleId: 17))).SequenceEqual(new[] { 17 }) && H(new SaleHistoryFilter(SaleId: 0)).TotalCount == 0 && H(new SaleHistoryFilter(SaleId: -4)).TotalCount == 0 && H(new SaleHistoryFilter(SaleId: 31)).TotalCount == 0, "sale number filter matches exactly one id");
Check(Ids(H(new SaleHistoryFilter(OperatorUserId: 10, PageSize: 50))).SequenceEqual(Exp(s => s.CreatedByUserId == 10)) && H(new SaleHistoryFilter(OperatorUserId: 10)).TotalCount == 11
    && H(new SaleHistoryFilter(OperatorUserId: 12)).TotalCount == 10 && H(new SaleHistoryFilter(OperatorUserId: 11)).TotalCount == 0, "operator filter by user id (counts 11, 10 and 0)");
Check(Ids(H(new SaleHistoryFilter(WithoutOperator: true, PageSize: 50))).SequenceEqual(Exp(s => s.CreatedByUserId == null)) && H(new SaleHistoryFilter(WithoutOperator: true)).TotalCount == 9, "'Sin registro' filter returns only sales without operator");
Check(Ids(H(new SaleHistoryFilter(PaymentMethod: PaymentMethod.Cash, PageSize: 50))).SequenceEqual(Exp(s => s.Payments.Any(p => p.PaymentMethod == PaymentMethod.Cash)))
    && Ids(H(new SaleHistoryFilter(PaymentMethod: PaymentMethod.DebitCard, PageSize: 50))).SequenceEqual(Exp(s => s.Payments.Any(p => p.PaymentMethod == PaymentMethod.DebitCard)))
    && H(new SaleHistoryFilter(PaymentMethod: PaymentMethod.DebitCard)).TotalCount == 6 && H(new SaleHistoryFilter(PaymentMethod: PaymentMethod.MercadoPago)).TotalCount == 0, "payment method filter matches sales with any payment of that method (mixed sales count for both)");
Check(Ids(H(new SaleHistoryFilter(CashRegisterId: 12, PageSize: 50))).SequenceEqual(Exp(s => s.CashRegisterId == 12)) && H(new SaleHistoryFilter(CashRegisterId: 12)).TotalCount > 0 && H(new SaleHistoryFilter(CashRegisterId: 99)).TotalCount == 0, "cash register filter");
Check(H(new SaleHistoryFilter(Status: SaleHistoryStatusFilter.All)).TotalCount == 30 && H(new SaleHistoryFilter(Status: SaleHistoryStatusFilter.Cancelled)).TotalCount == 4 && H(new SaleHistoryFilter(Status: SaleHistoryStatusFilter.Completed)).TotalCount == 26
    && Ids(H(new SaleHistoryFilter(Status: SaleHistoryStatusFilter.Cancelled, PageSize: 50))).SequenceEqual(Exp(s => s.Status == SaleStatus.Cancelled)), "status filter: all / completed / cancelled");
Check(H(new SaleHistoryFilter(ProductText: "jamón")).TotalCount == 7 && H(new SaleHistoryFilter(ProductText: "JAMÓN")).TotalCount == 7 && H(new SaleHistoryFilter(ProductText: "  tostado  ")).TotalCount == 7
    && H(new SaleHistoryFilter(ProductText: "jamon")).TotalCount == 0 && H(new SaleHistoryFilter(ProductText: "jugo")).TotalCount == 4 && H(new SaleHistoryFilter(ProductText: "dia")).TotalCount == H(new SaleHistoryFilter(ProductText: "medial")).TotalCount
    && Ids(H(new SaleHistoryFilter(ProductText: "ostado", PageSize: 50))).SequenceEqual(Exp(s => s.Items.Any(i => i.ProductName.Contains("ostado", StringComparison.OrdinalIgnoreCase)))), "product text search is case-insensitive, trimmed and 'contains' (accents are not folded)");
Check(H(new SaleHistoryFilter(ProductText: "   ")).TotalCount == 30 && H(new SaleHistoryFilter(ProductText: "")).TotalCount == 30 && H(new SaleHistoryFilter(ProductText: "zzz")).TotalCount == 0, "blank text means no filter; unknown text is empty");
Check(Ids(H(new SaleHistoryFilter(OperatorUserId: 10, PaymentMethod: PaymentMethod.Cash, Status: SaleHistoryStatusFilter.Completed, ProductText: "café", PageSize: 50)))
    .SequenceEqual(Exp(s => s.CreatedByUserId == 10 && s.Payments.Any(p => p.PaymentMethod == PaymentMethod.Cash) && s.Status == SaleStatus.Completed && s.Items.Any(i => i.ProductName.Contains("café", StringComparison.OrdinalIgnoreCase)))), "filters combine with AND");
var combined = H(new SaleHistoryFilter(DateFrom: day5, DateTo: day21, WithoutOperator: true, Status: SaleHistoryStatusFilter.Completed, PageSize: 3, Page: 2));
var combinedAll = Exp(s => s.Date.Date >= day5 && s.Date.Date <= day21 && s.CreatedByUserId == null && s.Status == SaleStatus.Completed);
Check(combined.TotalCount == combinedAll.Length && Ids(combined).SequenceEqual(combinedAll.Skip(3).Take(3)), "filters and paging combine");
var badRange = Reject(() => H(new SaleHistoryFilter(DateFrom: day5.AddDays(1), DateTo: day5)), IOE, "From after To");
Check(badRange?.Message == "La fecha inicial no puede ser posterior a la fecha final.", "invalid range message in Spanish");
var both = Reject(() => H(new SaleHistoryFilter(OperatorUserId: 10, WithoutOperator: true)), IOE, "operator and 'Sin registro' together");
Check(both?.Message == "Elija un operador o «Sin registro», no ambos.", "operator conflict message in Spanish");
Reject(() => history.GetHistory(null!, Copy(admin)), IOE, "null filter");
var operators = history.GetOperators(Copy(admin));
Check(operators.Select(o => (o.UserId, o.Username)).SequenceEqual(new[] { (10, "fixture-admin"), (12, "fixture-employee") }) && operators is IList { IsReadOnly: true }, "operators: distinct users seen on sales, ordered by name, without 'Sin registro'");

// ---- Detail (S3).
var d30 = Detail(30)!;
Check(d30.Entry.Id == 30 && Json(d30.Entry) == Json(Entry(30)) && d30.Lines.Count == 2 && d30.Subtotal == 310m && d30.DiscountAmount == 15m && d30.Total == 295m
    && d30.SaleDiscountType == DiscountType.Fixed && d30.SaleDiscountValue == 15m, "detail 30: entry equals the list entry; subtotal, sale discount and total");
var l0 = d30.Lines[0]; var l1 = d30.Lines[1];
Check(l0.ProductId == 1 && l0.ProductName == "Café" && l0.Price == 100m && l0.Quantity == 2 && l0.Notes == "sin azúcar" && l0.DiscountType == DiscountType.Percentage && l0.DiscountValue == 10m
    && l0.GrossSubtotal == 200m && l0.DiscountAmount == 20m && l0.Subtotal == 180m, "detail line 1: notes and percentage line discount");
Check(l1.Notes == null && l1.DiscountType == DiscountType.Fixed && l1.DiscountValue == 20m && l1.GrossSubtotal == 150m && l1.DiscountAmount == 20m && l1.Subtotal == 130m, "detail line 2: fixed line discount, no notes");
Check(d30.Payments.Count == 2 && d30.Payments[0].Method == PaymentMethod.Cash && d30.Payments[0].Amount == 100m && d30.Payments[0].ReceivedAmount == 150m && d30.Payments[0].Change == 50m
    && d30.Payments[1].Method == PaymentMethod.DebitCard && d30.Payments[1].Amount == 195m && d30.Payments[1].ReceivedAmount == null && d30.Payments[1].Change == 0m, "detail payments: applied, received and change");
Check(d30.Events.Count == 1 && d30.Events[0].Kind == SaleHistoryEventKind.Created && d30.Events[0].At == S(30).Date && d30.Events[0].UserId == 10 && d30.Events[0].Username == "fixture-admin" && d30.Events[0].Reason == null, "detail events: registration by the operator at the sale date");
var d7 = Detail(7)!;
Check(d7.Events.Count == 2 && d7.Events[0].Kind == SaleHistoryEventKind.Created && d7.Events[0].UserId == 10 && d7.Events[1].Kind == SaleHistoryEventKind.Cancelled && d7.Events[1].At == S(7).CancelledAt
    && d7.Events[1].UserId == 10 && d7.Events[1].Username == "fixture-admin" && d7.Events[1].Reason == "motivo 7" && d7.Entry.Status == SaleStatus.Cancelled, "cancelled sale: registration then cancellation event with reason, moment and responsible");
var d14 = Detail(14)!;
Check(d14.Events.Count == 2 && d14.Events[1].Kind == SaleHistoryEventKind.Cancelled && d14.Events[1].At == null && d14.Events[1].Username == null && d14.Events[1].UserId == null && d14.Events[1].Reason == null, "legacy cancelled sale: cancellation event without invented data");
var d3 = Detail(3)!;
Check(d3.Entry.OperatorUserId == null && d3.Events[0].Username == null && d3.Events[0].UserId == null && d3.Entry.CashRegisterId == 14 && d3.Lines.Count == 1 && d3.Lines[0].DiscountType == DiscountType.None && d3.Lines[0].DiscountAmount == 0m, "legacy sale without operator: no invented responsible user");
Check(Detail(5)!.Entry.CashRegisterId == null && Detail(5)!.Lines.Count == 1, "sale without register link has null register in the detail");
foreach (var id in new[] { 0, -1, 31, 9999, int.MinValue, int.MaxValue }) Check(Detail(id) == null, "detail of nonexistent id " + id + " is null");
foreach (var list in new IEnumerable[] { d30.Lines, d30.Payments, d30.Events }) Check(list is IList { IsReadOnly: true }, "detail collection is read-only: " + list.GetType().Name);

// ---- Detached snapshots: later storage changes never alter earlier read models.
var snapEntry = Json(Entry(30)); var snapDetail = Json(Detail(30)); var heldDetail = Detail(30)!; var heldJson = Json(heldDetail);
s30.Items[0].Price = 1m; s30.Items[0].Notes = "cambiado"; s30.Payments[0].Amount = 1m; s30.CreatedByUsername = "renamed";
Check(Json(heldDetail) == heldJson && Json(Detail(30)) != snapDetail && Json(Entry(30)) != snapEntry, "held read models are detached copies; fresh queries see the stored changes");
s30.Items[0].Price = 100m; s30.Items[0].Notes = "sin azúcar"; s30.Payments[0].Amount = 100m; s30.CreatedByUsername = "fixture-admin";
Check(Json(Detail(30)) == snapDetail, "restoring the sale restores the detail");

// ---- Overflow.
var s2 = S(2); var priceBefore = s2.Items[0].Price;
s2.Items[0].Price = decimal.MaxValue; s2.Items[0].Quantity = 2;
SaleHistoryEntry? overflowEntry = null; SaleHistoryDetail? overflowDetail = null; Exception? overflowEx = null;
try { overflowEntry = Entry(2); overflowDetail = Detail(2); } catch (Exception ex) { overflowEx = ex; }
Check(overflowEx == null && overflowEntry != null && overflowEntry.Total == null && overflowEntry.AmountsUnavailable && overflowDetail != null && overflowDetail.Total == null
    && overflowDetail.Subtotal == null && overflowDetail.Entry.AmountsUnavailable && overflowDetail.Lines[0].GrossSubtotal == null && overflowDetail.Lines[0].Subtotal == null,
    "overflowing sale: null amounts, unavailable flag and no exception");
Check(H(new SaleHistoryFilter(PageSize: 50)).Entries.Where(e => e.Id != 2).All(e => !e.AmountsUnavailable && e.Total != null), "overflow in one sale does not taint the others");
s2.Items[0].Price = priceBefore; s2.Items[0].Quantity = 1 + 2 % 3;
Check(Entry(2).Total == S(2).Total && !Entry(2).AmountsUnavailable, "entry recovers once the overflow is gone");

// ---- Rejections for every query.
var staleActor = Copy(admin);
var badActors = new (User?, string)[] { (null, "null actor"), (employee, "employee"),
    (new User { Id = 99, Username = admin.Username, PasswordHash = hash, Role = UserRole.Admin }, "unknown actor"),
    (new User { Id = admin.Id, Username = "other", PasswordHash = hash, Role = UserRole.Admin }, "mismatched username"),
    (new User { Id = admin.Id, Username = admin.Username, PasswordHash = "old-hash", Role = UserRole.Admin }, "mismatched password"),
    (new User { Id = admin.Id, Username = admin.Username, PasswordHash = hash, Role = UserRole.Employee }, "claimed demotion") };
foreach (var (actor, name) in badActors)
{
    Reject(() => history.GetHistory(new SaleHistoryFilter(), actor), UAE, "history for " + name);
    Reject(() => history.GetDetail(1, actor), UAE, "detail for " + name);
    Reject(() => history.GetDetail(9999, actor), UAE, "detail of an unknown id for " + name + " (authorization first)");
    Reject(() => history.GetOperators(actor!), UAE, "operators for " + name);
}
Reject(() => history.GetHistory(null!, null), UAE, "null filter with null actor (authorization first)");
Reject(() => history.GetHistory(new SaleHistoryFilter(DateFrom: DateTime.Today.AddDays(1), DateTo: DateTime.Today), employee), UAE, "invalid range with an employee (authorization first)");
admin.Role = UserRole.Employee;
Reject(() => history.GetHistory(new SaleHistoryFilter(), staleActor), UAE, "history after live demotion");
Reject(() => history.GetDetail(1, staleActor), UAE, "detail after live demotion");
admin.Role = UserRole.Admin;
Check(history.GetHistory(new SaleHistoryFilter(), staleActor).TotalCount == 30 && history.GetDetail(1, staleActor) != null, "restored admin is accepted again");
admin.PasswordHash = "changed";
Reject(() => history.GetHistory(new SaleHistoryFilter(), staleActor), UAE, "history after password change");
admin.PasswordHash = hash;
storage.Users.Remove(admin);
Reject(() => history.GetDetail(1, staleActor), UAE, "detail after the actor was deleted");
storage.Users.Insert(0, admin);

// ---- No mutation: a battery of queries changes nothing.
storage.SaveToFile();
var stateBefore = State(); var bytesBefore = File.ReadAllBytes("data.json"); var fileTime = File.GetLastWriteTimeUtc("data.json");
var saleRefs = storage.Sales.ToArray(); var nextSaleBefore = typeof(DataStorageService).GetField("_nextSaleId", flags)!.GetValue(storage);
foreach (var status in Enum.GetValues<SaleHistoryStatusFilter>())
    foreach (var page in new[] { 0, 1, 2, 99 })
        _ = history.GetHistory(new SaleHistoryFilter(DateFrom: day5, DateTo: day21, Status: status, Page: page, PageSize: 7, ProductText: "a", OperatorUserId: 10), Copy(admin));
for (int id = -1; id <= 35; id++) _ = history.GetDetail(id, Copy(admin));
_ = history.GetOperators(Copy(admin));
Check(State() == stateBefore && bytesBefore.SequenceEqual(File.ReadAllBytes("data.json")) && File.GetLastWriteTimeUtc("data.json") == fileTime, "query battery leaves full storage state, counters and data.json bytes/timestamp unchanged");
Check(saleRefs.SequenceEqual(storage.Sales) && nextSaleBefore!.Equals(typeof(DataStorageService).GetField("_nextSaleId", flags)!.GetValue(storage)), "sales collection and id counter are untouched (nothing is ever deleted)");

// ---- Persistence: reload in the same scratch cwd and compare.
var snapBefore = Snap(history, Copy(admin));
var reload = new DataStorageService();
var snapAfter = Snap(new SaleHistoryService(reload), Copy(admin));
Check(reload.Sales.Count == 30 && snapBefore == snapAfter, "history page, operators and every detail are identical after reload");

// ---- Real checkout path: operator is recorded and a sale can be cancelled from the detail.
cash.Open(100m);
var product = storage.Products.First();
Sale Checkout(decimal price, params SalePayment[] payments) => new() { Items = [new SaleItem { ProductId = product.Id, ProductName = product.Name, Price = price, Quantity = 1, Notes = "  con hielo " }], Payments = payments.ToList() };
var realA = Checkout(30m, Pay(PaymentMethod.Cash, 30m, 40m)); sales.Add(realA, admin);
var realB = Checkout(20m, Pay(PaymentMethod.Transfer, 20m)); sales.Add(realB, employee);
var realC = Checkout(25m, Pay(PaymentMethod.Transfer, 25m)); sales.Add(realC, admin);
var dA = Detail(realA.Id)!;
Check(dA.Entry.OperatorUserId == 10 && dA.Entry.OperatorUsername == "fixture-admin" && dA.Events[0].Username == "fixture-admin" && dA.Lines[0].Notes == "con hielo" && dA.Payments[0].Change == 10m
    && dA.Entry.CashRegisterId == storage.CurrentCashRegisterId && dA.Entry.Status == SaleStatus.Completed, "new sale shows its operator, trimmed notes, change and register");
Check(Ids(H(new SaleHistoryFilter(CashRegisterId: storage.CurrentCashRegisterId, PageSize: 50))).SequenceEqual(new[] { realC.Id, realB.Id, realA.Id }) && H(new SaleHistoryFilter(OperatorUserId: 12, CashRegisterId: storage.CurrentCashRegisterId)).TotalCount == 1,
    "register and operator filters find the new sales (newest first)");
var all33 = Exp(_ => true);

// ---- SalesHistory page: renderer-less component checks (no browser, no host, scratch storage only).
storage.SaveToFile();
var uiType = typeof(SaleHistoryService).Assembly.GetType("GastroApp.Pages.SalesHistory");
Check(uiType != null, "SalesHistory page type exists");
if (uiType != null)
{
    var uiUsers = new UserService(storage);
    AuthService NewAuth(string? username)
    {
        var auth = new AuthService(uiUsers);
        if (username != null) Check(auth.Login(username, "fixture-pass"), "circuit login " + username);
        return auth;
    }
    (object Page, TestNavigation Nav) NewPage(AuthService auth)
    {
        var page = Activator.CreateInstance(uiType)!; var nav = new TestNavigation();
        uiType.GetProperty("AuthService", flags)!.SetValue(page, auth);
        uiType.GetProperty("Navigation", flags)!.SetValue(page, nav);
        uiType.GetProperty("HistoryService", flags)!.SetValue(page, history);
        uiType.GetProperty("SaleService", flags)!.SetValue(page, sales);
        return (page, nav);
    }
    Exception? Call(object page, string method, params object[] arguments)
    {
        try { uiType.GetMethod(method, flags | BindingFlags.DeclaredOnly)!.Invoke(page, arguments); return null; }
        catch (TargetInvocationException ex) { return ex.InnerException; }
    }
    object? Get(object page, string field) => uiType.GetField(field, flags)!.GetValue(page);
    void Set(object page, string field, object? value) => uiType.GetField(field, flags)!.SetValue(page, value);
    void SetId(object page, int? id) => uiType.GetProperty("SaleId", flags)!.SetValue(page, id);
    SaleHistoryPage? HP(object page) => (SaleHistoryPage?)Get(page, "historyPage");
    SaleHistoryDetail? DT(object page) => (SaleHistoryDetail?)Get(page, "detail");
    string? Msg(object page, string field) => (string?)Get(page, field);
    bool Flag(object page, string field) => (bool)Get(page, field)!;

    // Unauthenticated and Employee circuits fail closed on every entry point.
    var uiAnon = NewAuth(null); var uiEmployee = NewAuth("fixture-employee");
    var guardedState = State();
    foreach (var (auth, who, destination) in new[] { (uiAnon, "anonymous", "/login"), (uiEmployee, "employee", "/unauthorized") })
        foreach (var action in new[] { "OnParametersSet", "ShowDetail", "ApplyFilters", "ClearFilters", "NextPage", "PreviousPage", "CloseDetail", "StartCancel", "ConfirmCancel", "CalculateRefund", "ConfirmRefund" })
        {
            var (page, nav) = NewPage(auth);
            SetId(page, 1);
            if (action == "ConfirmCancel") { Set(page, "cancelReason", "intento"); Set(page, "cancelConfirmed", true); }
            if (action == "ConfirmRefund") { Set(page, "refundReason", "intento"); Set(page, "refundConfirmed", true); }
            var ex = Call(page, action, action == "ShowDetail" ? new object[] { 1 } : Array.Empty<object>());
            Check(ex == null && nav.Destination == destination && HP(page) == null && DT(page) == null && Msg(page, "detailMessage") == null && Msg(page, "cancelSuccess") == null && Msg(page, "refundSuccess") == null,
                who + " " + action + " navigates to " + destination + " and loads nothing");
        }
    Check(State() == guardedState, "anonymous and employee attempts (including cancellation) leave storage unchanged");

    // Admin circuit: list, detail, missing id, navigation.
    var uiAdmin = NewAuth("fixture-admin");
    var (ap, anav) = NewPage(uiAdmin);
    var loadEx = Call(ap, "OnParametersSet");
    Check(loadEx == null && anav.Destination == null && HP(ap) != null && HP(ap)!.TotalCount == storage.Sales.Count && DT(ap) == null && Msg(ap, "historyError") == null,
        "admin OnParametersSet loads the history page without navigating");
    SetId(ap, 30);
    Check(Call(ap, "OnParametersSet") == null && anav.Destination == null && DT(ap)?.Entry.Id == 30 && Msg(ap, "detailMessage") == null, "admin route with a sale id loads that detail");
    SetId(ap, 9999);
    Check(Call(ap, "OnParametersSet") == null && DT(ap) == null && Msg(ap, "detailMessage")!.Contains("No existe una venta con el ID 9999") && anav.Destination == null, "admin route with an unknown id shows the missing-sale message");
    SetId(ap, null);
    Check(Call(ap, "OnParametersSet") == null && DT(ap) == null && Msg(ap, "detailMessage") == null, "admin route without id clears the detail");
    Check(Call(ap, "ShowDetail", 7) == null && anav.Destination == "/sales/history/7", "ShowDetail navigates to /sales/history/{id} without forcing a reload");
    anav.Destination = null;
    Check(Call(ap, "CloseDetail") == null && anav.Destination == "/sales/history", "CloseDetail navigates to /sales/history without forcing a reload");

    // Filters and pagination (page size 10).
    anav.Destination = null;
    Set(ap, "filterFrom", d0.AddDays(10)); Set(ap, "filterTo", d0.AddDays(2));
    Check(Call(ap, "ApplyFilters") == null && HP(ap) == null && Msg(ap, "historyError") == "La fecha inicial no puede ser posterior a la fecha final." && anav.Destination == null, "filterFrom after filterTo shows the Spanish range error");
    Check(Call(ap, "ClearFilters") == null && Msg(ap, "historyError") == null && HP(ap)?.TotalCount == 33 && Get(ap, "filterFrom") == null, "ClearFilters recovers from the range error");
    Set(ap, "filterStatus", SaleHistoryStatusFilter.Cancelled);
    Check(Call(ap, "ApplyFilters") == null && HP(ap)!.TotalCount == 4 && HP(ap)!.Entries.All(x => x.Status == SaleStatus.Cancelled), "status filter Cancelled lists only cancelled sales");
    Call(ap, "ClearFilters");
    Set(ap, "filterOperator", "none");
    Call(ap, "ApplyFilters");
    Check(HP(ap)!.TotalCount == 9 && HP(ap)!.Entries.All(x => x.OperatorUserId == null), "operator option 'none' (Sin registro) lists sales without operator");
    Set(ap, "filterOperator", "12"); Set(ap, "filterPayment", nameof(PaymentMethod.Cash));
    Call(ap, "ApplyFilters");
    Check(Ids(HP(ap)!).SequenceEqual(Exp(s => s.CreatedByUserId == 12 && s.Payments.Any(p => p.PaymentMethod == PaymentMethod.Cash)).Take(10)), "operator id and payment method selections reach the query");
    Call(ap, "ClearFilters");
    Set(ap, "filterText", "jamón"); Set(ap, "filterSaleNumber", (int?)null); Set(ap, "filterRegister", (int?)12);
    Call(ap, "ApplyFilters");
    Check(Ids(HP(ap)!).SequenceEqual(Exp(s => s.CashRegisterId == 12 && s.Items.Any(i => i.ProductName.Contains("jamón", StringComparison.OrdinalIgnoreCase))).Take(10)), "text and register inputs reach the query");
    Call(ap, "ClearFilters");
    Set(ap, "filterSaleNumber", (int?)17);
    Call(ap, "ApplyFilters");
    Check(Ids(HP(ap)!).SequenceEqual(new[] { 17 }), "sale number input reaches the query");
    Call(ap, "ClearFilters");
    Check(HP(ap)!.Page == 1 && HP(ap)!.PageSize == 10 && HP(ap)!.TotalPages == 4 && HP(ap)!.Entries.Count == 10 && Ids(HP(ap)!).SequenceEqual(all33.Take(10)), "page 1 of 4 with ten rows");
    Call(ap, "PreviousPage");
    Check(HP(ap)!.Page == 1, "PreviousPage stays clamped on the first page");
    Call(ap, "NextPage");
    Check(HP(ap)!.Page == 2 && Ids(HP(ap)!).SequenceEqual(all33.Skip(10).Take(10)), "NextPage moves to page 2");
    Call(ap, "NextPage"); Call(ap, "NextPage");
    Check(HP(ap)!.Page == 4 && HP(ap)!.Entries.Count == 3 && Ids(HP(ap)!).SequenceEqual(all33.Skip(30)), "NextPage reaches the last page with three rows");
    Call(ap, "NextPage");
    Check(HP(ap)!.Page == 4 && Msg(ap, "historyError") == null, "NextPage stays clamped on the last page");
    Call(ap, "ApplyFilters");
    Check(HP(ap)!.Page == 1, "ApplyFilters returns to the first page");

    // Mid-session permission changes (live revalidation per interaction).
    var uiSecond = NewAuth("second-admin");
    var (sp, snav) = NewPage(uiSecond);
    SetId(sp, 1); Call(sp, "OnParametersSet");
    var listBefore = HP(sp); var detailBefore = DT(sp);
    Check(listBefore != null && detailBefore?.Entry.Id == 1 && snav.Destination == null, "second admin page loaded before the demotion");
    var preDemotion = State();
    admin2.Role = UserRole.Employee;
    try
    {
        foreach (var (action, args2) in new (string, object[])[] { ("ApplyFilters", []), ("ShowDetail", [3]), ("OnParametersSet", []), ("NextPage", []), ("CloseDetail", []), ("StartCancel", []), ("ConfirmCancel", []) })
        {
            snav.Destination = null;
            if (action == "OnParametersSet") SetId(sp, 2);
            if (action == "ConfirmCancel") { SetId(sp, 1); Set(sp, "cancelReason", "motivo"); Set(sp, "cancelConfirmed", true); }
            var ex = Call(sp, action, args2);
            Check(ex == null && snav.Destination == "/unauthorized" && ReferenceEquals(HP(sp), listBefore) && (DT(sp) == null || ReferenceEquals(DT(sp), detailBefore)),
                "demoted admin " + action + " redirects to /unauthorized without a new detail or exception");
        }
    }
    finally { admin2.Role = UserRole.Admin; }
    Check(S(1).Status == SaleStatus.Completed && S(1).CancellationReason == null, "sale 1 stays completed after the demoted admin's attempt");
    admin2.PasswordHash = "rotated-hash";
    try
    {
        SetId(sp, 3); snav.Destination = null;
        Check(Call(sp, "OnParametersSet") == null && snav.Destination == "/login" && DT(sp)?.Entry.Id != 3, "password change mid-session redirects to /login and loads no new detail");
    }
    finally { admin2.PasswordHash = hash; }

    // Cancellation from the detail: explicit confirmation, mandatory reason, live admin, repeated cancellation rejected.
    var (cp, cnav) = NewPage(NewAuth("fixture-admin"));
    SetId(cp, realA.Id); Call(cp, "OnParametersSet");
    Check(DT(cp)?.Entry.Status == SaleStatus.Completed && !Flag(cp, "cancelOpen"), "completed sale detail starts with the cancel form closed");
    Check(Call(cp, "StartCancel") == null && Flag(cp, "cancelOpen") && Msg(cp, "cancelError") == null, "StartCancel opens the cancel form");
    var uncancelled = State();
    Set(cp, "cancelReason", "Cobro duplicado"); Set(cp, "cancelConfirmed", false);
    Check(Call(cp, "ConfirmCancel") == null && Msg(cp, "cancelError") == "Debe confirmar la anulación." && Msg(cp, "cancelSuccess") == null && State() == uncancelled && realA.Status == SaleStatus.Completed, "reason without confirmation is rejected and nothing changes");
    Set(cp, "cancelReason", "   "); Set(cp, "cancelConfirmed", true);
    Check(Call(cp, "ConfirmCancel") == null && Msg(cp, "cancelError") == "Debe indicar un motivo de cancelación." && State() == uncancelled && realA.Status == SaleStatus.Completed, "confirmation without a reason is rejected and nothing changes");
    Set(cp, "cancelReason", null);
    Check(Call(cp, "ConfirmCancel") == null && Msg(cp, "cancelError") == "Debe indicar un motivo de cancelación." && State() == uncancelled, "null reason is rejected and nothing changes");
    Check(Call(cp, "AbortCancel") == null && !Flag(cp, "cancelOpen") && Msg(cp, "cancelError") == null && Msg(cp, "cancelReason") == null && !Flag(cp, "cancelConfirmed") && State() == uncancelled, "AbortCancel closes the form and clears reason, confirmation and message");
    Call(cp, "StartCancel"); Set(cp, "cancelReason", "  Cobro duplicado  "); Set(cp, "cancelConfirmed", true);
    var cancelStart = DateTime.Now;
    Check(Call(cp, "ConfirmCancel") == null && cnav.Destination == null && Msg(cp, "cancelError") == null && !string.IsNullOrWhiteSpace(Msg(cp, "cancelSuccess")), "confirmed cancellation with a reason succeeds");
    Check(realA.Status == SaleStatus.Cancelled && realA.CancellationReason == "Cobro duplicado" && realA.CancelledByUserId == 10 && realA.CancelledByUsername == "fixture-admin" && realA.CancelledAt >= cancelStart, "sale is cancelled with trimmed reason, responsible and moment");
    Check(DT(cp)?.Entry.Status == SaleStatus.Cancelled && DT(cp)!.Events.Count == 2 && DT(cp)!.Events[1].Reason == "Cobro duplicado" && DT(cp)!.Events[1].Username == "fixture-admin"
        && !Flag(cp, "cancelOpen") && Msg(cp, "cancelReason") == null && !Flag(cp, "cancelConfirmed"), "detail refreshes with the cancellation event and the form resets");
    Check(storage.Sales.Count == 33 && S(realA.Id) == realA && HP(cp)!.TotalCount == 33, "cancelled sale is kept, never deleted");
    Check(Ids(H(new SaleHistoryFilter(Status: SaleHistoryStatusFilter.Cancelled, PageSize: 50))).Contains(realA.Id), "cancelled sale appears under the cancelled filter");
    // Repeated cancellation (also from a stale page that still believed it was completed).
    var afterCancel = State(); var cancelledAt = realA.CancelledAt;
    Set(cp, "cancelReason", "otra vez"); Set(cp, "cancelConfirmed", true);
    Check(Call(cp, "ConfirmCancel") == null && Msg(cp, "cancelError") == "La venta ya no está completada." && Msg(cp, "cancelSuccess") == null && State() == afterCancel && realA.CancelledAt == cancelledAt && realA.CancellationReason == "Cobro duplicado",
        "repeated cancellation is rejected with the service message and the audit data is unchanged");
    var (stale, snavStale) = NewPage(NewAuth("fixture-admin"));
    SetId(stale, realB.Id); Call(stale, "OnParametersSet"); Call(stale, "StartCancel");
    sales.Cancel(realB.Id, "por otra sesión", Copy(admin2));
    var afterOther = State();
    Set(stale, "cancelReason", "tarde"); Set(stale, "cancelConfirmed", true);
    Check(Call(stale, "ConfirmCancel") == null && Msg(stale, "cancelError") == "La venta ya no está completada." && State() == afterOther && realB.CancelledByUsername == "second-admin" && realB.CancellationReason == "por otra sesión", "a page opened before another circuit cancelled the sale cannot overwrite that cancellation");
    // Legacy sale without a reliable stock snapshot.
    var (lp, lnav) = NewPage(NewAuth("fixture-admin"));
    SetId(lp, 5); Call(lp, "OnParametersSet"); Call(lp, "StartCancel");
    var legacyState = State();
    Set(lp, "cancelReason", "legacy"); Set(lp, "cancelConfirmed", true);
    Check(Call(lp, "ConfirmCancel") == null && Msg(lp, "cancelError") == "La venta no tiene un registro confiable de stock consumido." && State() == legacyState && S(5).Status == SaleStatus.Completed, "service rejections are shown in Spanish and leave a legacy sale untouched");
    // Unknown sale and a cancelled sale have no cancel action.
    var (up, unav) = NewPage(NewAuth("fixture-admin"));
    SetId(up, 9999); Call(up, "OnParametersSet");
    Set(up, "cancelReason", "x"); Set(up, "cancelConfirmed", true);
    Check(Call(up, "ConfirmCancel") == null && State() == legacyState && DT(up) == null, "confirming a cancellation with no loaded sale does nothing");
    // Employee page attempt on a completed sale and a mid-session demotion keep the sale intact.
    var (ep, enav) = NewPage(uiEmployee);
    SetId(ep, realC.Id); Set(ep, "cancelReason", "no autorizado"); Set(ep, "cancelConfirmed", true);
    Check(Call(ep, "ConfirmCancel") == null && enav.Destination == "/unauthorized" && realC.Status == SaleStatus.Completed && State() == legacyState, "employee cannot cancel from the detail");
    var (dp, dnav) = NewPage(NewAuth("second-admin"));
    SetId(dp, realC.Id); Call(dp, "OnParametersSet"); Call(dp, "StartCancel");
    admin2.Role = UserRole.Employee;
    try
    {
        Set(dp, "cancelReason", "ya no soy admin"); Set(dp, "cancelConfirmed", true);
        Check(Call(dp, "ConfirmCancel") == null && dnav.Destination == "/unauthorized" && realC.Status == SaleStatus.Completed && Msg(dp, "cancelSuccess") == null, "demoted admin cannot cancel from a page opened while admin");
    }
    finally { admin2.Role = UserRole.Admin; }
    // Service-level stale actor check also guards the cancellation path through the history query.
    Reject(() => history.GetDetail(realC.Id, new User { Id = 11, Username = "second-admin", PasswordHash = "old", Role = UserRole.Admin }), UAE, "stale identity opening a detail");

    // Two independent circuits over the same singleton services.
    var (aa, aanav) = NewPage(NewAuth("fixture-admin")); Call(aa, "OnParametersSet");
    var (ee, eenav) = NewPage(NewAuth("fixture-employee"));
    var adminList = HP(aa);
    Call(ee, "OnParametersSet"); Call(ee, "ApplyFilters"); Call(ee, "NextPage");
    Check(eenav.Destination == "/unauthorized" && HP(ee) == null && ReferenceEquals(HP(aa), adminList) && aanav.Destination == null, "employee denial leaves the admin circuit's page state untouched");
    var otherAdminAuth = NewAuth("fixture-admin"); otherAdminAuth.Logout();
    Call(aa, "NextPage");
    Check(!otherAdminAuth.IsAuthenticated && aanav.Destination == null && HP(aa)!.Page == 2, "logging out one circuit does not affect another circuit of the same user");
    var (a2, a2nav) = NewPage(otherAdminAuth);
    Call(a2, "ApplyFilters");
    Check(a2nav.Destination == "/login" && HP(a2) == null, "the logged-out circuit is redirected to /login");

    // Source assertions.
    string Src(string path) => File.ReadAllText(Path.Combine(args[0], path));
    var navMenu = Src("Shared/NavMenu.razor"); var linkAt = navMenu.IndexOf("href=\"sales/history\"", StringComparison.Ordinal);
    var adminIf = navMenu.LastIndexOf("@if (AuthService.IsInRole(UserRole.Admin))", Math.Max(linkAt, 0), StringComparison.Ordinal);
    Check(linkAt > 0 && adminIf >= 0 && !navMenu.Substring(adminIf, linkAt - adminIf).Contains('}') && navMenu.Contains("Historial de ventas"), "NavMenu links the sales history inside the Admin block with the Spanish label");
    Check(Regex.IsMatch(navMenu, "href=\"sales\"[^>]*Match=\"NavLinkMatch.All\""), "the Vender NavLink only matches exactly /sales, so it is not highlighted on /sales/history");
    var pageSource = Src("Pages/SalesHistory.razor");
    Check(pageSource.Contains("@page \"/sales/history\"") && pageSource.Contains("@page \"/sales/history/{SaleId:int}\""), "SalesHistory page declares both routes");
    Check(Regex.Matches(pageSource, @"HistoryService\.(\w+)").Select(m => m.Groups[1].Value).Distinct().OrderBy(x => x).SequenceEqual(new[] { "GetDetail", "GetHistory", "GetOperators" }), "page only calls the read-only history queries of the history service");
    Check(Regex.Matches(pageSource, @"\bSaleService\.(\w+)").Select(m => m.Groups[1].Value).Distinct().OrderBy(x => x).SequenceEqual(new[] { "Cancel", "GetDisplayStatusLabel", "GetRefundability", "GetRefunds", "PreviewRefund", "Refund" })
        && !pageSource.Contains("SaveToFile") && !pageSource.Contains("StorageService"), "page only mutates through SaleService.Cancel and SaleService.Refund and never touches storage");
    foreach (var label in new[] { "Cobrada", "Anulada", "Sin registro", "Historial de ventas", "Confirmo", "/cash/history/" }) Check(pageSource.Contains(label), "page contains the Spanish text '" + label + "'");
    Check(!Regex.IsMatch(pageSource, @">\s*@[\w\.]*Status\s*<"), "page never prints the internal status code");
    Check(Regex.IsMatch(pageSource, @"(?s)@code\s*\{.*EnsureAdmin"), "page revalidates the admin on every callback");

    // ---- Refunds in the history (S4, S6, S7, S9, S10, S12, S13).
    if (!cash.IsOpen()) cash.Open(100m);
    cash.AddManualMovement(CashMovementType.Income, 500m, "fondo para devoluciones", Copy(admin)); // enough cash in the drawer for the cash refunds below
    Sale NewRefundSale()
    {
        var sale = new Sale
        {
            Id = storage.GetNextSaleId(), CashRegisterId = storage.CurrentCashRegisterId, Date = DateTime.Now, CreatedByUserId = 10, CreatedByUsername = "fixture-admin",
            Items = [new SaleItem { ProductId = 1, ProductName = "Café", Price = 100m, Quantity = 2 }, new SaleItem { ProductId = 2, ProductName = "Medialunas", Price = 50m, Quantity = 2 }],
            Payments = [Pay(PaymentMethod.Transfer, 200m), Pay(PaymentMethod.Cash, 100m, 100m)]
        };
        storage.Sales.Add(sale);
        return sale;
    }
    SaleRefundLine RL(int index, int quantity, RefundDisposition disposition = RefundDisposition.Waste) => new() { SaleItemIndex = index, Quantity = quantity, Disposition = disposition };
    SaleRefundPayment RP(PaymentMethod method, decimal amount) => new() { PaymentMethod = method, Amount = amount };
    int[] ByStatus(SaleHistoryStatusFilter filter) => Ids(H(new SaleHistoryFilter(Status: filter, PageSize: 50)));
    string RState() => State() + Json(storage.SaleRefunds);

    var rs = NewRefundSale(); var rid = rs.Id;
    Check(Entry(rid).DisplayStatus == SaleDisplayStatus.Collected && Entry(rid).RefundedTotal == 0m && ByStatus(SaleHistoryStatusFilter.Completed).Contains(rid)
        && ByStatus(SaleHistoryStatusFilter.PartiallyRefunded).Length == 0 && ByStatus(SaleHistoryStatusFilter.Refunded).Length == 0, "an unrefunded sale is Collected and listed under the Completed filter");
    var r1 = sales.Refund(rid, "primera", [RL(0, 1)], [RP(PaymentMethod.Transfer, 100m)], Copy(admin));
    var partial = Entry(rid);
    Check(partial.DisplayStatus == SaleDisplayStatus.PartiallyRefunded && partial.RefundedTotal == 100m && partial.Status == SaleStatus.Completed && partial.Total == 300m
        && Detail(rid)!.Entry.DisplayStatus == SaleDisplayStatus.PartiallyRefunded && Detail(rid)!.Total == 300m, "a partial refund shows PartiallyRefunded and the refunded total without changing the sale total");
    Check(ByStatus(SaleHistoryStatusFilter.PartiallyRefunded).SequenceEqual(new[] { rid }) && ByStatus(SaleHistoryStatusFilter.Refunded).Length == 0
        && ByStatus(SaleHistoryStatusFilter.Completed).SequenceEqual(Exp(s => s.Status == SaleStatus.Completed && s.Id != rid)) && ByStatus(SaleHistoryStatusFilter.Cancelled).SequenceEqual(Exp(s => s.Status == SaleStatus.Cancelled)),
        "status filters: Completed means Collected only, PartiallyRefunded lists the partial sale, Cancelled is unchanged");
    var ev1 = Detail(rid)!.Events;
    Check(ev1.Count == 2 && ev1[0].Kind == SaleHistoryEventKind.Created && ev1[1].Kind == SaleHistoryEventKind.Refunded && ev1[1].At == r1.Date && ev1[1].UserId == 10 && ev1[1].Username == "fixture-admin"
        && ev1[1].Reason == "primera" && ev1[1].Amount == 100m && ev1[1].RefundId == r1.Id && ev1[0].Amount == null && ev1[0].RefundId == null, "refund event carries date, user, reason, amount and refund id");
    var r2 = sales.Refund(rid, "segunda", [RL(0, 1), RL(1, 2)], [RP(PaymentMethod.Transfer, 100m), RP(PaymentMethod.Cash, 100m)], Copy(admin));
    Check(Entry(rid).DisplayStatus == SaleDisplayStatus.Refunded && Entry(rid).RefundedTotal == 300m && ByStatus(SaleHistoryStatusFilter.Refunded).SequenceEqual(new[] { rid })
        && ByStatus(SaleHistoryStatusFilter.PartiallyRefunded).Length == 0 && !ByStatus(SaleHistoryStatusFilter.Completed).Contains(rid), "refunding everything shows Refunded and moves the sale to the Refunded filter");
    var ev2 = Detail(rid)!.Events;
    Check(ev2.Select(e => e.Kind).SequenceEqual(new[] { SaleHistoryEventKind.Created, SaleHistoryEventKind.Refunded, SaleHistoryEventKind.Refunded }) && ev2[1].RefundId == r1.Id && ev2[2].RefundId == r2.Id && ev2[2].Amount == 200m && ev2[2].Reason == "segunda",
        "refund events follow the creation in chronological order");
    var stored1 = storage.SaleRefunds.Single(r => r.Id == r1.Id); var date1 = stored1.Date;
    stored1.Date = r2.Date.AddMinutes(5);
    Check(Detail(rid)!.Events.Select(e => e.RefundId).SequenceEqual(new int?[] { null, r2.Id, r1.Id }), "events are ordered by date, not by refund id");
    stored1.Date = date1;
    Check(Entry(7).DisplayStatus == SaleDisplayStatus.Cancelled && ByStatus(SaleHistoryStatusFilter.Completed).All(id => S(id).Status == SaleStatus.Completed), "cancelled sales keep the Cancelled display status; Completed never lists a cancelled one");

    // The detail page: refund section and cancellation rules.
    string Str(object? o) => (string?)o ?? "";
    void SetQty(object pg, int index, int quantity, RefundDisposition disposition = RefundDisposition.Waste) { ((IDictionary)Get(pg, "refundQuantities")!)[index] = quantity; ((IDictionary)Get(pg, "refundDispositions")!)[index] = disposition; }
    void SetAmount(object pg, PaymentMethod method, decimal? amount) => ((IDictionary)Get(pg, "refundAmounts")!)[method] = amount;
    var rs2 = NewRefundSale(); var rid2 = rs2.Id;
    var (rp, rnav) = NewPage(NewAuth("fixture-admin"));
    SetId(rp, rid2); Call(rp, "OnParametersSet");
    var staleRefundPage = NewPage(NewAuth("fixture-admin")); SetId(staleRefundPage.Page, rid2); Call(staleRefundPage.Page, "OnParametersSet");
    var rb = (SaleRefundability?)Get(rp, "refundability");
    Check(DT(rp)?.Entry.DisplayStatus == SaleDisplayStatus.Collected && rb != null && rb.CanRefund && rb.Lines.Count == 2 && rb.Lines.All(l => !l.CanRestock) && rb.Methods.Count == 2
        && ((IList)Get(rp, "refunds")!).Count == 0 && Msg(rp, "refundError") == null && rnav.Destination == null, "detail loads refundability, no past refunds and an empty form");
    var untouched = RState();
    SetQty(rp, 0, 1); SetAmount(rp, PaymentMethod.Transfer, 100m); Set(rp, "refundReason", "Cliente insatisfecho"); Set(rp, "refundConfirmed", false);
    Check(Call(rp, "ConfirmRefund") == null && Msg(rp, "refundError") == "Debe confirmar la devolución." && Msg(rp, "refundSuccess") == null && RState() == untouched, "refund without confirmation is rejected and nothing changes");
    Set(rp, "refundConfirmed", true); Set(rp, "refundReason", "   ");
    Check(Call(rp, "ConfirmRefund") == null && Msg(rp, "refundError") == "Debe indicar un motivo de devolución." && RState() == untouched, "refund without a reason is rejected with the service message and nothing changes");
    Set(rp, "refundReason", "Cliente insatisfecho"); SetQty(rp, 0, 0);
    Check(Call(rp, "ConfirmRefund") == null && Msg(rp, "refundError") == "Debe indicar al menos una línea a devolver." && RState() == untouched, "refund without lines is rejected and nothing changes");
    SetQty(rp, 0, 3);
    Check(Call(rp, "CalculateRefund") == null && Msg(rp, "refundError") == "La cantidad supera las unidades pendientes de devolución de Café." && Get(rp, "refundPreviewTotal") == null && RState() == untouched, "a quantity above the remaining units is rejected by the preview");
    SetQty(rp, 0, 1);
    Check(Call(rp, "CalculateRefund") == null && Msg(rp, "refundError") == null && (decimal?)Get(rp, "refundPreviewTotal") == 100m && RState() == untouched, "'Calcular importe' shows the computed amount without mutating anything");
    SetQty(rp, 0, 1, RefundDisposition.Restock);
    Check(Call(rp, "ConfirmRefund") == null && Msg(rp, "refundError") == "La línea Café no tiene registro de consumo de stock; sólo puede devolverse como merma." && RState() == untouched, "restocking a line without consumption record is rejected and nothing changes");
    SetQty(rp, 0, 1); SetAmount(rp, PaymentMethod.Transfer, 150m);
    Check(Call(rp, "ConfirmRefund") == null && Msg(rp, "refundError") == "La suma de los importes devueltos debe ser exactamente igual al total de la devolución." && RState() == untouched, "per-method amounts that do not add up to the total are rejected");
    SetAmount(rp, PaymentMethod.Transfer, 100m);
    var movementsBefore = storage.CashMovements.Count;
    Set(rp, "refundReason", "  Cliente insatisfecho  ");
    Check(Call(rp, "ConfirmRefund") == null && Msg(rp, "refundError") == null && rnav.Destination == null, "confirmed refund with a reason succeeds");
    var stored = storage.SaleRefunds.Where(r => r.SaleId == rid2).ToList();
    Check(stored.Count == 1 && stored[0].Reason == "Cliente insatisfecho" && stored[0].Username == "fixture-admin" && stored[0].Total == 100m && stored[0].Lines.Single().Disposition == RefundDisposition.Waste
        && storage.CashMovements.Count == movementsBefore && Msg(rp, "refundSuccess") == $"Devolución #{stored[0].Id} registrada por $100.", "refund is recorded with trimmed reason, responsible and amount; a transfer refund creates no cash movement");
    Check(DT(rp)?.Entry.DisplayStatus == SaleDisplayStatus.PartiallyRefunded && DT(rp)!.Events.Count == 2 && HP(rp)!.Entries.Single(e => e.Id == rid2).DisplayStatus == SaleDisplayStatus.PartiallyRefunded
        && ((SaleRefundability)Get(rp, "refundability")!).RefundedTotal == 100m && ((IList)Get(rp, "refunds")!).Count == 1, "detail and list reload with the new refund");
    Check(!Flag(rp, "refundConfirmed") && Get(rp, "refundReason") == null && Get(rp, "refundPreviewTotal") == null && ((IDictionary)Get(rp, "refundQuantities")!).Values.Cast<int>().All(q => q == 0)
        && ((IDictionary)Get(rp, "refundAmounts")!).Values.Cast<decimal?>().All(a => a == null), "the refund form resets after a successful refund");
    // A refunded sale is not cancelled (S9).
    Check(Call(rp, "StartCancel") == null && !Flag(rp, "cancelOpen"), "a partially refunded sale offers no cancellation");
    var beforeCancelAttempt = RState();
    Set(rp, "cancelReason", "intento"); Set(rp, "cancelConfirmed", true);
    Check(Call(rp, "ConfirmCancel") == null && Msg(rp, "cancelError") == "La venta tiene devoluciones registradas; no puede anularse." && rs2.Status == SaleStatus.Completed && RState() == beforeCancelAttempt, "cancelling a refunded sale is rejected by the service and shown in Spanish");
    // Cash refund of everything that remains into the current open register.
    SetQty(rp, 0, 1); SetQty(rp, 1, 2); SetAmount(rp, PaymentMethod.Transfer, 100m); SetAmount(rp, PaymentMethod.Cash, 100m);
    Check(Call(rp, "CalculateRefund") == null && (decimal?)Get(rp, "refundPreviewTotal") == 200m, "preview of the remaining units equals the remaining refundable amount");
    Set(rp, "refundReason", "Resto"); Set(rp, "refundConfirmed", true);
    Check(Call(rp, "ConfirmRefund") == null && Msg(rp, "refundError") == null && DT(rp)?.Entry.DisplayStatus == SaleDisplayStatus.Refunded && !((SaleRefundability)Get(rp, "refundability")!).CanRefund && ((IList)Get(rp, "refunds")!).Count == 2, "refunding the rest marks the sale Refunded with no refund left to offer");
    var outflow = storage.CashMovements.Last();
    Check(storage.CashMovements.Count == movementsBefore + 1 && outflow.Type == CashMovementType.Refund && outflow.Amount == 100m && outflow.SaleId == rid2 && outflow.CashRegisterId == storage.CurrentCashRegisterId && outflow.Reason == "Resto", "the cash part of the refund is an outflow in the current open register linked to the sale");
    Check(Call(rp, "StartCancel") == null && !Flag(rp, "cancelOpen"), "a fully refunded sale offers no cancellation");
    var afterAll = RState();
    var sp2 = staleRefundPage.Page;
    SetQty(sp2, 0, 1); SetAmount(sp2, PaymentMethod.Transfer, 100m); Set(sp2, "refundReason", "tarde"); Set(sp2, "refundConfirmed", true);
    Check(Call(sp2, "ConfirmRefund") == null && Msg(sp2, "refundError") == "La cantidad supera las unidades pendientes de devolución de Café." && Msg(sp2, "refundSuccess") == null && RState() == afterAll, "a page opened before another circuit refunded the units cannot refund them again");
    // Demoted admin on an open refund form.
    var rs3 = NewRefundSale();
    var (dr, drnav) = NewPage(NewAuth("second-admin"));
    SetId(dr, rs3.Id); Call(dr, "OnParametersSet");
    SetQty(dr, 0, 1); SetAmount(dr, PaymentMethod.Transfer, 100m); Set(dr, "refundReason", "ya no soy admin"); Set(dr, "refundConfirmed", true);
    var refundsBeforeDemotion = Json(storage.SaleRefunds) + Json(storage.CashMovements);
    admin2.Role = UserRole.Employee;
    try { Check(Call(dr, "ConfirmRefund") == null && drnav.Destination == "/unauthorized" && Msg(dr, "refundSuccess") == null && Json(storage.SaleRefunds) + Json(storage.CashMovements) == refundsBeforeDemotion, "demoted admin cannot refund from a page opened while admin"); }
    finally { admin2.Role = UserRole.Admin; }
    // Source assertions for the refund UI.
    var refundSource = Src("Pages/SalesHistory.razor");
    foreach (var label in new[] { "Devoluciones", "Calcular importe", "Vuelve a stock", "Merma", "Sin registro de consumo: solo merma", "El efectivo se reintegra como egreso de la caja abierta actual", "Parcialmente devueltas", "GetDisplayStatusLabel" })
        Check(refundSource.Contains(label), "page contains '" + label + "'");
    Check(Src("Pages/CashHistory.razor").Contains("CashMovementType.Refund") && Src("Pages/CashHistory.razor").Contains("Devolución"), "cash history shows refunds as an outflow labelled Devolución");
}

// ---- Legacy data: sales saved before operators, payments or items existed.
storage.SaveToFile();
var preLegacyCount = storage.Sales.Count;
var baseline = JsonNode.Parse(File.ReadAllText("data.json"))!.AsObject();
var salesArray = baseline["Sales"]!.AsArray();
salesArray.Add(JsonNode.Parse("{\"Id\":901,\"Date\":\"2025-01-02T10:00:00\",\"Items\":[{\"ProductName\":\"Viejo\",\"Price\":5,\"Quantity\":2}]}"));
salesArray.Add(JsonNode.Parse("{\"Id\":902,\"Date\":\"2025-01-03T10:00:00\",\"Items\":null,\"Payments\":null,\"Status\":1}"));
File.WriteAllText("data.json", baseline.ToJsonString());
var legacy = new DataStorageService();
var legacyHistory = new SaleHistoryService(legacy);
var legacyAdmin = legacy.Users.Single(u => u.Id == 10);
var legacyPage = legacyHistory.GetHistory(new SaleHistoryFilter(PageSize: 50), legacyAdmin);
var l901 = legacyPage.Entries.Single(e => e.Id == 901); var l902 = legacyPage.Entries.Single(e => e.Id == 902);
Check(legacyPage.TotalCount == preLegacyCount + 2 && Ids(legacyPage).TakeLast(2).SequenceEqual(new[] { 902, 901 }), "legacy sales are listed, oldest last");
Check(l901.OperatorUserId == null && l901.OperatorUsername == null && l901.CashRegisterId == null && l901.Status == SaleStatus.Completed && l901.Total == 10m && l901.ProductNames.SequenceEqual(new[] { "Viejo" }) && l901.PaymentMethods.Count == 0, "legacy sale without operator, register or payments is browsable");
Check(l902.Status == SaleStatus.Cancelled && l902.Total == 0m && l902.ProductNames.Count == 0 && l902.PaymentMethods.Count == 0 && l902.ItemCount == 0, "legacy sale with null items and payments does not break the history");
var dl = legacyHistory.GetDetail(902, legacyAdmin)!;
Check(dl.Lines.Count == 0 && dl.Payments.Count == 0 && dl.Events.Count == 2 && dl.Events[1].Kind == SaleHistoryEventKind.Cancelled && dl.Total == 0m, "legacy detail with null collections has empty sections and invents no data");
Check(legacyHistory.GetHistory(new SaleHistoryFilter(ProductText: "viejo"), legacyAdmin).TotalCount == 1 && legacyHistory.GetHistory(new SaleHistoryFilter(PaymentMethod: PaymentMethod.Cash, WithoutOperator: true, PageSize: 50), legacyAdmin).Entries.All(e => e.Id != 902), "legacy sales take part in text and payment filters without errors");

Console.WriteLine($"{checks} checks, {failures} failures; fixture: {Directory.GetCurrentDirectory()}");
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
    & dotnet run --project (Join-Path $ScratchPath 'SalesHistoryChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Sales history checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
