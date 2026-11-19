param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-history-' + [guid]::NewGuid().ToString('N')) }
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
"@ | Set-Content (Join-Path $ScratchPath 'HistoryChecks.csproj') -Encoding utf8
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
var hash = BCrypt.Net.BCrypt.HashPassword("fixture-pass");
storage.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 11, Username = "second-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var admin = storage.Users[0]; var admin2 = storage.Users[1];
User Copy(User user) => new() { Id = user.Id, Username = user.Username, PasswordHash = user.PasswordHash, Role = user.Role };
CashCountLineInput L(decimal denomination, int quantity) => new(denomination, quantity);
CashCountRequest Req(CashCountReview review, IReadOnlyList<CashCountLineInput>? lines, string? reason = null, bool confirmed = true, bool zero = false) =>
    new() { Review = review, Lines = lines!, Reason = reason, Confirmed = confirmed, ZeroCountConfirmed = zero };
string Json(object? value) => JsonSerializer.Serialize(value);
string State() => Json(new { storage.CurrentCashRegisterId, storage.CashRegisters, storage.CashMovements, storage.CashCounts,
    storage.Sales, storage.Users, storage.Summaries, storage.Products, storage.ProductCategories,
    storage.Ingredients, storage.Suppliers, storage.Invoices, storage.Recipes,
    Counters = typeof(DataStorageService).GetFields(flags).Where(f => f.Name.StartsWith("_next")).Select(f => new { f.Name, Value = f.GetValue(storage) }).ToArray() });
Exception? Reject(Action action, Type exception, string name)
{
    storage.SaveToFile();
    var state = State(); var bytes = File.ReadAllBytes("data.json");
    var movements = storage.CashMovements.ToArray(); var registers = storage.CashRegisters.ToArray();
    var counts = storage.CashCounts.ToArray(); var summaries = storage.Summaries.ToArray();
    Exception? caught = null;
    try { action(); } catch (Exception ex) { caught = ex; }
    Check(caught?.GetType() == exception, name + " rejected with " + exception.Name + (caught == null ? " (no exception)" : " (got " + caught.GetType().Name + ")"));
    Check(State() == state && bytes.SequenceEqual(File.ReadAllBytes("data.json")) && movements.SequenceEqual(storage.CashMovements)
        && registers.SequenceEqual(storage.CashRegisters) && counts.SequenceEqual(storage.CashCounts) && summaries.SequenceEqual(storage.Summaries),
        name + " leaves registers, movements, counts, summaries, counters and fixture bytes unchanged");
    return caught;
}
var product = storage.Products.First();
Sale Checkout(decimal price, params SalePayment[] payments) => new() { Items = [new SaleItem { ProductId = product.Id, ProductName = product.Name, Price = price, Quantity = 1 }], Payments = payments.ToList() };
SalePayment Pay(PaymentMethod method, decimal amount, decimal? received = null) => new() { PaymentMethod = method, Amount = amount, ReceivedAmount = received };
CashHistoryPage H(CashHistoryFilter? filter = null, User? actor = null) => cash.GetHistory(filter ?? new CashHistoryFilter(), actor ?? Copy(admin));
int[] Ids(CashHistoryPage page) => page.Entries.Select(e => e.Id).ToArray();
CashHistoryEntry Entry(int id) => H(new CashHistoryFilter(PageSize: 50)).Entries.Single(e => e.Id == id);
CashHistoryDetail Detail(int id) => cash.GetHistoryDetail(id, Copy(admin))!;
string Snap(CashRegisterService service, User actor) => Json(new
{
    Page = service.GetHistory(new CashHistoryFilter(PageSize: 50), actor),
    Details = Enumerable.Range(-1, 30).Select(i => service.GetHistoryDetail(i, actor)).ToArray()
});

// ---- API surface and read-model shape.
Check(typeof(CashRegisterService).GetMethod("GetHistory", new[] { typeof(CashHistoryFilter), typeof(User) })?.ReturnType == typeof(CashHistoryPage), "GetHistory(CashHistoryFilter, User) returns CashHistoryPage");
Check(typeof(CashRegisterService).GetMethod("GetHistoryDetail", new[] { typeof(int), typeof(User) })?.ReturnType == typeof(CashHistoryDetail), "GetHistoryDetail(int, User) returns CashHistoryDetail");
Check(typeof(CashRegisterService).GetMethod("GetMovements", new[] { typeof(int) })?.ReturnType == typeof(IReadOnlyList<CashMovement>), "GetMovements(int) returns IReadOnlyList<CashMovement>");
Check(typeof(CashRegisterService).GetMethod("GetPaymentSummary", new[] { typeof(int?) })?.ReturnType == typeof(CashPaymentSummary), "GetPaymentSummary(int?) returns CashPaymentSummary");
foreach (var type in new[] { typeof(CashHistoryEntry), typeof(CashHistoryPage), typeof(CashHistoryDetail) })
    Check(type.GetProperties().All(x => x.SetMethod == null) && type.GetConstructors().Length == 0 && type.IsSealed, type.Name + " is sealed, getter-only and built only by the service");
var defaults = new CashHistoryFilter();
Check(defaults.OpenedFrom == null && defaults.OpenedTo == null && defaults.Status == CashHistoryStatusFilter.All && defaults.Page == 1 && defaults.PageSize == 10, "filter defaults");
Check(Enum.GetNames<CashHistoryStatusFilter>().SequenceEqual(new[] { "All", "Open", "Closed" }), "status filter values");

// ---- No session: empty history and regressions of the current-session queries.
var empty = H();
Check(empty.TotalCount == 0 && empty.TotalPages == 0 && empty.Entries.Count == 0 && empty.Page == 1 && empty.PageSize == 10 && empty.Entries is IList { IsReadOnly: true }, "empty history: zero total, zero pages, no entries, read-only list");
Check(H(new CashHistoryFilter(Page: 7, PageSize: 1000)).Page == 1 && H(new CashHistoryFilter(Page: 7, PageSize: 1000)).PageSize == 50, "empty history clamps page to 1 and size to 50");
Check(cash.GetCurrentMovements().Count == 0 && cash.GetMovements(1).Count == 0 && cash.GetMovements(0).Count == 0, "no session: no current movements and nothing for unknown ids");
Check(cash.GetCurrentPaymentSummary().State == CashPaymentSummaryState.NoSession && cash.GetCurrentPaymentSummary().CashRegisterId == null
    && Json(cash.GetPaymentSummary(null)) == Json(cash.GetCurrentPaymentSummary()), "no session: NoSession summary, explicit null equals current");
Check(cash.GetHistoryDetail(1, Copy(admin)) == null && cash.GetHistoryDetail(0, Copy(admin)) == null, "no registers: detail is null");

// ---- Session 1: sales, manual movements, one-session history, exact close.
cash.Open(100.25m);
var reg1 = cash.GetCurrent()!;
var one = H();
Check(one.TotalCount == 1 && one.TotalPages == 1 && one.Entries.Count == 1 && one.Entries[0].Id == reg1.Id && one.Entries[0].IsOpen, "one session: one page with the open register");
sales.Add(Checkout(30m, Pay(PaymentMethod.Cash, 30m, 30m)));
sales.Add(Checkout(5m, Pay(PaymentMethod.Transfer, 5m)));
var mixed = Checkout(30m, Pay(PaymentMethod.Cash, 10m, 100m), Pay(PaymentMethod.DebitCard, 20m));
sales.Add(mixed);
cash.AddManualMovement(CashMovementType.Income, 20m, "aporte", admin);
cash.AddManualMovement(CashMovementType.Expense, 5m, "gasto", admin);
cash.AddManualMovement(CashMovementType.Withdrawal, 3m, "retiro", admin2);
var openEntry = Entry(reg1.Id);
Check(openEntry.IsOpen && openEntry.CloseDate == null && openEntry.InitialAmount == 100.25m && openEntry.ExpectedAmount == 152.25m
    && openEntry.CountedAmount == null && openEntry.Difference == null && !openEntry.HasCount && !openEntry.AmountsUnavailable,
    "open register: expected cash computed from its movements, no counted amount or difference");
Check(openEntry.ExpectedAmount == cash.GetExpectedCash(reg1.Id) && reg1.ExpectedAmount == 0m, "open expected comes from movements, not from the stored field");
var movements1 = Detail(reg1.Id).Movements;
Check(movements1.Count == 5 && movements1.All(m => m.CashRegisterId == reg1.Id)
    && movements1.Select(m => m.Type).SequenceEqual(new[] { CashMovementType.Sale, CashMovementType.Sale, CashMovementType.Income, CashMovementType.Expense, CashMovementType.Withdrawal })
    && movements1.Select(m => m.Amount).SequenceEqual(new[] { 30m, 10m, 20m, 5m, 3m })
    && movements1.Select(m => m.Id).SequenceEqual(storage.CashMovements.Where(m => m.CashRegisterId == reg1.Id).Select(m => m.Id))
    && movements1[2].Username == "fixture-admin" && movements1[4].Username == "second-admin" && movements1[0].SaleId != null, "session 1 movements: stored order, types, amounts, authors, sale link");
var pay1 = cash.GetPaymentSummary(reg1.Id);
decimal PayAmount(CashPaymentSummary s, PaymentMethod m) => s.Rows.Single(r => r.Method == m).Amount!.Value;
Check(pay1.State == CashPaymentSummaryState.Complete && pay1.CashRegisterId == reg1.Id && pay1.RegisteredTotal == 65m
    && PayAmount(pay1, PaymentMethod.Cash) == 40m && PayAmount(pay1, PaymentMethod.DebitCard) == 20m && PayAmount(pay1, PaymentMethod.Transfer) == 5m
    && pay1.Rows.Count == 6, "session 1 payments: individual and mixed receipts aggregate per method");
Check(Json(pay1) == Json(cash.GetCurrentPaymentSummary()) && Json(cash.GetCurrentMovements()) == Json(cash.GetMovements(reg1.Id)), "explicit-id queries equal the current-session ones for the current register");
var closeStart = DateTime.Now;
cash.Close(Req(cash.GetCountReview(), [L(100m, 1), L(50m, 1), L(2m, 1), L(0.25m, 1)]), Copy(admin));
var closed1 = Entry(reg1.Id);
Check(!closed1.IsOpen && closed1.CloseDate != null && closed1.CloseDate >= closeStart && closed1.InitialAmount == 100.25m && closed1.ExpectedAmount == 152.25m
    && closed1.CountedAmount == 152.25m && closed1.Difference == 0m && closed1.HasCount && !closed1.AmountsUnavailable, "exact close: stored expected, counted and zero difference");
sales.Cancel(mixed.Id, "fixture", admin);
Check(mixed.Status == SaleStatus.Cancelled && Json(cash.GetPaymentSummary(reg1.Id)) == Json(pay1) && PayAmount(cash.GetPaymentSummary(reg1.Id), PaymentMethod.DebitCard) == 20m,
    "cancelled sale receipts stay registered in the history payment summary");
Check(Entry(reg1.Id).ExpectedAmount == 152.25m, "closed register keeps its stored expected amount after cancelling a sale post-close");

// ---- Session 2: surplus, noncash only. Session 3: shortage.
cash.Open(50m);
var reg2 = cash.GetCurrent()!;
sales.Add(Checkout(40m, Pay(PaymentMethod.CreditCard, 40m)));
cash.AddManualMovement(CashMovementType.Income, 10m, "ingreso", admin2);
cash.Close(Req(cash.GetCountReview(), [L(50m, 1), L(5m, 3)], "sobrante"), Copy(admin2));
cash.Open(200m);
var reg3 = cash.GetCurrent()!;
cash.Close(Req(cash.GetCountReview(), [L(100m, 1), L(50m, 1), L(20m, 2)], "faltante"), Copy(admin));
var e2 = Entry(reg2.Id); var e3 = Entry(reg3.Id);
Check(e2.ExpectedAmount == 60m && e2.CountedAmount == 65m && e2.Difference == 5m && e2.HasCount, "surplus close shown with stored values");
Check(e3.ExpectedAmount == 200m && e3.CountedAmount == 190m && e3.Difference == -10m && e3.HasCount, "shortage close shown with stored values");
var d2 = Detail(reg2.Id);
Check(d2.Movements.Count == 1 && d2.Movements[0].Type == CashMovementType.Income && d2.Movements.All(m => m.CashRegisterId == reg2.Id), "register 2 movements exclude register 1's ledger and noncash sales add none");
Check(PayAmount(d2.PaymentSummary, PaymentMethod.CreditCard) == 40m && d2.PaymentSummary.RegisteredTotal == 40m && PayAmount(d2.PaymentSummary, PaymentMethod.Cash) == 0m, "register 2 payments exclude register 1's sales");
Check(Detail(reg3.Id).Movements.Count == 0 && Detail(reg3.Id).PaymentSummary.RegisteredTotal == 0m && Detail(reg3.Id).PaymentSummary.State == CashPaymentSummaryState.Complete, "register 3 has no movements and a complete zero summary");

// ---- Sessions 4..24: exact closes; session 25 stays open.
for (int i = 4; i <= 24; i++)
{
    cash.Open(i);
    cash.Close(Req(cash.GetCountReview(), [L(i, 1)]), Copy(admin));
}
cash.Open(25m);
var reg25 = cash.GetCurrent()!;
cash.AddManualMovement(CashMovementType.Income, 7m, "ingreso", admin);
sales.Add(Checkout(10m, Pay(PaymentMethod.Cash, 10m, 10m)));
sales.Add(Checkout(4m, Pay(PaymentMethod.Transfer, 4m)));
cash.AddManualMovement(CashMovementType.Withdrawal, 2m, "retiro", admin);
Check(storage.CashRegisters.Count == 25 && reg25.Id == 25 && storage.CashRegisters.Count(r => r.IsOpen) == 1, "fixture has 25 sessions, the last one open");
Check(Entry(25).ExpectedAmount == 40m && Detail(25).Movements.Count == 3 && Detail(25).PaymentSummary.RegisteredTotal == 14m, "open register 25 expected cash, movements and receipts");
Check(Detail(reg1.Id).Movements.Count == 5 && Detail(reg1.Id).PaymentSummary.RegisteredTotal == 65m, "register 1 data unaffected by later sessions' sales and movements");

// Stored OpenDate is a permutation of 25 distinct days (not monotonic in Id); registers 3 and 4 tie exactly.
var d0 = new DateTime(2026, 3, 1);
foreach (var r in storage.CashRegisters)
    r.OpenDate = d0.AddDays(r.Id * 7 % 25).AddMinutes(r.Id % 2 == 0 ? 5 : 1435);
storage.CashRegisters.Single(r => r.Id == 4).OpenDate = storage.CashRegisters.Single(r => r.Id == 3).OpenDate;
DateTime OpenOf(int id) => storage.CashRegisters.Single(r => r.Id == id).OpenDate;
int[] Expected(Func<CashRegister, bool> keep) => storage.CashRegisters.Where(keep)
    .OrderByDescending(r => r.OpenDate).ThenByDescending(r => r.Id).Select(r => r.Id).ToArray();
var all = Expected(_ => true);
var full = H(new CashHistoryFilter(PageSize: 50));
Check(full.TotalCount == 25 && full.TotalPages == 1 && Ids(full).SequenceEqual(all) && Ids(full).OrderBy(x => x).SequenceEqual(Enumerable.Range(1, 25)), "history lists every register ordered by OpenDate descending");
Check(full.Entries.Zip(full.Entries.Skip(1)).All(pair => pair.First.OpenDate > pair.Second.OpenDate || (pair.First.OpenDate == pair.Second.OpenDate && pair.First.Id > pair.Second.Id)), "adjacent entries strictly descend by OpenDate then Id");
Check(Array.IndexOf(Ids(full), 4) + 1 == Array.IndexOf(Ids(full), 3) && !Ids(full).SequenceEqual(Enumerable.Range(1, 25).Reverse()), "same OpenDate ties break by Id descending and order is not simply by Id");

// ---- Pagination.
var p1 = H(); var p2 = H(new CashHistoryFilter(Page: 2)); var p3 = H(new CashHistoryFilter(Page: 3));
Check(p1.TotalCount == 25 && p1.TotalPages == 3 && p1.Page == 1 && p1.PageSize == 10 && p1.Entries.Count == 10 && p3.Entries.Count == 5, "default page size 10: 25 entries over 3 pages");
Check(Ids(p1).Concat(Ids(p2)).Concat(Ids(p3)).SequenceEqual(all), "pages concatenate to the complete ordering without gaps or repeats");
var s7 = H(new CashHistoryFilter(Page: 4, PageSize: 7));
Check(s7.TotalPages == 4 && s7.Entries.Count == 4 && Ids(s7).SequenceEqual(all.Skip(21)), "page size 7: last page holds the remainder");
Check(Ids(H(new CashHistoryFilter(Page: 0))).SequenceEqual(Ids(p1)) && H(new CashHistoryFilter(Page: 0)).Page == 1 && H(new CashHistoryFilter(Page: -3)).Page == 1, "page 0 and negative pages clamp to the first page");
Check(H(new CashHistoryFilter(Page: 99)).Page == 3 && Ids(H(new CashHistoryFilter(Page: 99))).SequenceEqual(Ids(p3)) && H(new CashHistoryFilter(Page: int.MaxValue)).Page == 3, "too-large pages clamp to the last page");
var size0 = H(new CashHistoryFilter(PageSize: 0));
Check(size0.PageSize == 1 && size0.Entries.Count == 1 && size0.TotalPages == 25 && H(new CashHistoryFilter(PageSize: -5)).PageSize == 1 && H(new CashHistoryFilter(PageSize: int.MinValue)).PageSize == 1, "page size below 1 clamps to 1");
var size1000 = H(new CashHistoryFilter(PageSize: 1000));
Check(size1000.PageSize == 50 && size1000.Entries.Count == 25 && size1000.TotalPages == 1 && H(new CashHistoryFilter(PageSize: 51)).PageSize == 50 && H(new CashHistoryFilter(PageSize: 50)).PageSize == 50 && H(new CashHistoryFilter(PageSize: int.MaxValue)).PageSize == 50, "page size above 50 clamps to 50");
Check(Ids(H(new CashHistoryFilter(PageSize: 1, Page: 25))).SequenceEqual(new[] { all[24] }), "page size 1 reaches the final register");

// ---- Status and date filters.
Check(Ids(H(new CashHistoryFilter(Status: CashHistoryStatusFilter.Open, PageSize: 50))).SequenceEqual(new[] { 25 }), "status Open returns only the open session");
var closedOnly = H(new CashHistoryFilter(Status: CashHistoryStatusFilter.Closed, PageSize: 50));
Check(closedOnly.TotalCount == 24 && Ids(closedOnly).SequenceEqual(all.Where(id => id != 25)) && closedOnly.Entries.All(e => !e.IsOpen), "status Closed excludes the open session");
Check(H(new CashHistoryFilter(Status: CashHistoryStatusFilter.All, PageSize: 50)).TotalCount == 25, "status All returns everything");
var day5 = d0.AddDays(10); var day2 = d0.AddDays(14); var day34 = d0.AddDays(21);
Check(OpenOf(5).Date == day5 && OpenOf(2).Date == day2 && OpenOf(3).Date == day34, "fixture dates are as planned");
Check(Ids(H(new CashHistoryFilter(OpenedFrom: day5, OpenedTo: day5, PageSize: 50))).SequenceEqual(new[] { 5 }), "same-day range includes a session opened at 23:55 on that day");
Check(Ids(H(new CashHistoryFilter(OpenedFrom: day2.AddHours(12), OpenedTo: day2.AddHours(1), PageSize: 50))).SequenceEqual(new[] { 2 }), "dates compare by calendar day, so a 00:05 opening is included even with later From time and earlier To time");
Check(Ids(H(new CashHistoryFilter(OpenedFrom: day34, OpenedTo: day34, PageSize: 50))).SequenceEqual(new[] { 4, 3 }), "tied day returns both sessions, higher Id first");
Check(Ids(H(new CashHistoryFilter(OpenedFrom: day5, OpenedTo: day2, PageSize: 50))).SequenceEqual(Expected(r => r.OpenDate.Date >= day5 && r.OpenDate.Date <= day2)), "inclusive range with both ends");
Check(Ids(H(new CashHistoryFilter(OpenedFrom: day34, PageSize: 50))).SequenceEqual(Expected(r => r.OpenDate.Date >= day34)), "open-ended range with only From");
Check(Ids(H(new CashHistoryFilter(OpenedTo: day5, PageSize: 50))).SequenceEqual(Expected(r => r.OpenDate.Date <= day5)), "open-ended range with only To");
Check(H(new CashHistoryFilter(OpenedFrom: d0.AddDays(40), PageSize: 50)).TotalCount == 0 && H(new CashHistoryFilter(OpenedTo: d0.AddDays(-1))).TotalCount == 0, "ranges outside every session are empty");
var emptyFilter = H(new CashHistoryFilter(OpenedTo: d0.AddDays(-1), Page: 5, PageSize: 3));
Check(emptyFilter.TotalPages == 0 && emptyFilter.Page == 1 && emptyFilter.PageSize == 3 && emptyFilter.Entries.Count == 0, "empty result: zero pages, page clamped to 1");
Check(H(new CashHistoryFilter(Status: CashHistoryStatusFilter.Open, OpenedTo: d0.AddDays(-1))).TotalCount == 0
    && Ids(H(new CashHistoryFilter(Status: CashHistoryStatusFilter.Closed, OpenedFrom: day34, PageSize: 50))).SequenceEqual(Expected(r => !r.IsOpen && r.OpenDate.Date >= day34)), "status and dates combine");
var invalidRange = Reject(() => H(new CashHistoryFilter(OpenedFrom: day5.AddDays(1), OpenedTo: day5)), IOE, "From after To");
Check(invalidRange?.Message == "La fecha inicial no puede ser posterior a la fecha final.", "invalid range message in Spanish");
Reject(() => cash.GetHistory(null!, Copy(admin)), IOE, "null filter");

// ---- Entry values for every kind of register.
foreach (var e in full.Entries.Where(e => e.Id >= 4 && e.Id <= 24))
{
    if (!(e.InitialAmount == e.Id && e.ExpectedAmount == e.Id && e.CountedAmount == e.Id && e.Difference == 0m && e.HasCount && !e.IsOpen && !e.AmountsUnavailable && e.CloseDate != null))
        Check(false, "bulk entry " + e.Id + " mirrors its stored close");
}
Check(true, "bulk exact entries 4..24 mirror their stored closes");
var e25 = Entry(25);
Check(e25.IsOpen && e25.OpenDate == OpenOf(25) && e25.CloseDate == null && e25.ExpectedAmount == 40m && e25.CountedAmount == null && e25.Difference == null && !e25.HasCount, "open entry 25");
Check(Entry(1).OpenDate == OpenOf(1), "entry carries the stored OpenDate");

// ---- Detail: counts, linked summaries, detached copies.
var detail1 = Detail(reg1.Id);
Check(detail1.Entry.Id == reg1.Id && Json(detail1.Entry) == Json(Entry(reg1.Id)) && detail1.Count != null && detail1.Count.CashRegisterId == reg1.Id && detail1.Count.Lines.Count == 4
    && detail1.Count.CountedAmount == 152.25m && detail1.Count.Difference == 0m && detail1.Count.Lines[0].Denomination == 100m, "detail 1: entry equals the list entry and carries the stored count with lines");
Check(detail1.LinkedSummaries.Count == 1 && detail1.LinkedSummaries[0].CashRegisterId == reg1.Id && detail1.LinkedSummaries[0].FinalCash == 152.25m && detail1.LinkedSummaries[0].InitialCash == 100.25m, "detail 1: linked summary matches by register Id");
Check(Detail(reg2.Id).Count!.Reason == "sobrante" && Detail(reg3.Id).Count!.Reason == "faltante" && Detail(reg3.Id).Count!.Difference == -10m, "counts keep their stored reason and difference");
Check(Detail(25).Count == null && !Detail(25).Entry.HasCount && Detail(25).LinkedSummaries.Count == 0, "open register detail has no count and no summary");
foreach (var list in new IEnumerable[] { detail1.Movements, detail1.LinkedSummaries, detail1.PaymentSummary.Rows, detail1.PaymentSummary.Warnings, full.Entries })
    Check(list is IList { IsReadOnly: true }, "returned collection is read-only: " + list.GetType().Name);
var ledgerBefore = Json(storage.CashMovements); var summariesBefore = Json(storage.Summaries); var countsBefore = Json(storage.CashCounts);
var tamper = Detail(reg1.Id);
tamper.Movements[0].Amount = 999m; tamper.Movements[0].Reason = "tampered"; tamper.Count!.Lines.Clear(); tamper.Count.Reason = "tampered";
tamper.LinkedSummaries[0].TotalSales = 1_000_000m; tamper.LinkedSummaries[0].TopProduct = "tampered";
Check(Json(storage.CashMovements) == ledgerBefore && Json(storage.Summaries) == summariesBefore && Json(storage.CashCounts) == countsBefore, "mutating returned copies never changes storage");
Check(!storage.CashMovements.Any(m => ReferenceEquals(m, tamper.Movements[0])) && !storage.Summaries.Any(s => ReferenceEquals(s, tamper.LinkedSummaries[0]))
    && !storage.CashCounts.Any(c => ReferenceEquals(c, tamper.Count)) && !ReferenceEquals(H().Entries[0], H().Entries[0]), "returned objects are never the stored instances");
Check(Json(Detail(reg1.Id)) != Json(tamper) && Detail(reg1.Id).Movements[0].Amount == 30m, "a later query is unaffected by earlier tampering");
var getMovements = cash.GetMovements(reg1.Id);
getMovements[0].Amount = 5m;
Check(cash.GetMovements(reg1.Id)[0].Amount == 30m && cash.GetCurrentMovements().All(m => m.CashRegisterId == 25), "GetMovements and GetCurrentMovements return detached copies");

// ---- Summaries are linked by register Id only, never by date, in stored order.
var strayLegacy = new DailySummary { Date = DateTime.Today, CashRegisterId = null, TotalSales = 999m, TopProduct = "legacy" };
var secondForTwo = new DailySummary { Date = DateTime.Today, CashRegisterId = reg2.Id, TotalSales = 1m, TopProduct = "extra" };
storage.Summaries.Add(strayLegacy); storage.Summaries.Add(secondForTwo); storage.Summaries.Insert(0, new DailySummary { Date = DateTime.Today, CashRegisterId = reg2.Id, TotalSales = 2m, TopProduct = "first" });
Check(Enumerable.Range(1, 25).All(id => Detail(id).LinkedSummaries.All(s => s.TopProduct != "legacy" && s.CashRegisterId == id)), "legacy summary with null register Id and the same date is attributed to no register");
Check(Detail(reg2.Id).LinkedSummaries.Select(s => s.TopProduct).Where(t => t == "first" || t == "extra").SequenceEqual(new[] { "first", "extra" }) && Detail(reg2.Id).LinkedSummaries.Count == 3, "several summaries for one register keep stored order");
Check(Detail(reg1.Id).LinkedSummaries.Count == 1, "other registers keep exactly their own summary");
storage.Summaries.Remove(strayLegacy); storage.Summaries.Remove(secondForTwo); storage.Summaries.RemoveAt(0);
Check(Detail(reg2.Id).LinkedSummaries.Count == 1, "fixture summaries removed");

// ---- Nonexistent ids.
foreach (var id in new[] { 0, -1, 9999, int.MinValue, int.MaxValue })
    Check(cash.GetHistoryDetail(id, Copy(admin)) == null, "detail of nonexistent id " + id + " is null");

// ---- Overflow.
var injected = new CashMovement { Id = storage.GetNextCashMovementId(), CashRegisterId = 25, Date = DateTime.Now, Type = CashMovementType.Income, Amount = decimal.MaxValue };
storage.CashMovements.Add(injected);
CashHistoryEntry? overflowEntry = null; Exception? overflowEx = null;
try { overflowEntry = Entry(25); Check(Detail(25).Entry.AmountsUnavailable, "overflowing detail also flags unavailable amounts"); } catch (Exception ex) { overflowEx = ex; }
Check(overflowEx == null && overflowEntry != null && overflowEntry.ExpectedAmount == null && overflowEntry.AmountsUnavailable && overflowEntry.IsOpen && overflowEntry.CountedAmount == null && overflowEntry.Difference == null,
    "open register whose movements overflow: null expected amount, unavailable flag, no exception");
Check(H(new CashHistoryFilter(PageSize: 50)).Entries.Where(e => e.Id != 25).All(e => !e.AmountsUnavailable), "overflow in one register does not taint the others");
storage.CashMovements.Remove(injected);
Check(Entry(25).ExpectedAmount == 40m && !Entry(25).AmountsUnavailable, "entry recovers once the overflow is gone");
var stored3 = storage.CashRegisters.Single(r => r.Id == 3);
var finalBefore = stored3.FinalAmount; var expectedBefore = stored3.ExpectedAmount;
stored3.FinalAmount = decimal.MaxValue; stored3.ExpectedAmount = -1m;
CashHistoryEntry? closedOverflow = null; Exception? closedEx = null;
try { closedOverflow = Entry(3); } catch (Exception ex) { closedEx = ex; }
Check(closedEx == null && closedOverflow != null && closedOverflow.Difference == null && closedOverflow.AmountsUnavailable && closedOverflow.CountedAmount == decimal.MaxValue && closedOverflow.ExpectedAmount == -1m && !closedOverflow.IsOpen,
    "closed register whose difference overflows: null difference, unavailable flag, stored amounts kept");
stored3.FinalAmount = finalBefore; stored3.ExpectedAmount = expectedBefore;
Check(Entry(3).Difference == -10m && !Entry(3).AmountsUnavailable, "closed entry recovers after restoring the stored amounts");

// ---- Rejections for both queries.
var staleActor = Copy(admin);
var badActors = new (User?, string)[] { (null, "null actor"), (storage.Users[2], "employee"),
    (new User { Id = 99, Username = admin.Username, PasswordHash = hash, Role = UserRole.Admin }, "unknown actor"),
    (new User { Id = admin.Id, Username = "other", PasswordHash = hash, Role = UserRole.Admin }, "mismatched username"),
    (new User { Id = admin.Id, Username = admin.Username, PasswordHash = "old-hash", Role = UserRole.Admin }, "mismatched password") };
foreach (var (actor, name) in badActors)
{
    Reject(() => cash.GetHistory(new CashHistoryFilter(), actor), UAE, "history for " + name);
    Reject(() => cash.GetHistoryDetail(1, actor), UAE, "detail for " + name);
    Reject(() => cash.GetHistoryDetail(9999, actor), UAE, "detail of an unknown id for " + name + " (authorization first)");
}
Reject(() => cash.GetHistory(null!, null), UAE, "null filter with null actor (authorization first)");
Reject(() => cash.GetHistory(new CashHistoryFilter(OpenedFrom: DateTime.Today.AddDays(1), OpenedTo: DateTime.Today), storage.Users[2]), UAE, "invalid range with an employee (authorization first)");
admin.Role = UserRole.Employee;
Reject(() => cash.GetHistory(new CashHistoryFilter(), staleActor), UAE, "history after live demotion");
Reject(() => cash.GetHistoryDetail(1, staleActor), UAE, "detail after live demotion");
admin.Role = UserRole.Admin;
Check(cash.GetHistory(new CashHistoryFilter(), staleActor).TotalCount == 25 && cash.GetHistoryDetail(1, staleActor) != null, "restored admin is accepted again");
admin.PasswordHash = "changed";
Reject(() => cash.GetHistory(new CashHistoryFilter(), staleActor), UAE, "history after password change");
admin.PasswordHash = hash;
storage.Users.Remove(admin);
Reject(() => cash.GetHistoryDetail(1, staleActor), UAE, "detail after the actor was deleted");
storage.Users.Insert(0, admin);

// ---- No mutation: a battery of history calls changes nothing.
storage.SaveToFile();
var stateBefore = State(); var bytesBefore = File.ReadAllBytes("data.json");
var currentBefore = storage.CurrentCashRegisterId; var openStates = storage.CashRegisters.Select(r => (r.Id, r.IsOpen)).ToArray();
var registerRefs = storage.CashRegisters.ToArray(); var movementRefs = storage.CashMovements.ToArray();
var fileTime = File.GetLastWriteTimeUtc("data.json");
foreach (var status in Enum.GetValues<CashHistoryStatusFilter>())
    foreach (var page in new[] { 0, 1, 2, 99 })
        _ = cash.GetHistory(new CashHistoryFilter(OpenedFrom: day5, OpenedTo: day34, Status: status, Page: page, PageSize: 7), Copy(admin));
for (int id = -1; id <= 27; id++) _ = cash.GetHistoryDetail(id, Copy(admin));
_ = cash.GetPaymentSummary(1); _ = cash.GetPaymentSummary(null); _ = cash.GetMovements(1); _ = cash.GetCurrentMovements(); _ = cash.GetCurrentPaymentSummary();
Check(State() == stateBefore && bytesBefore.SequenceEqual(File.ReadAllBytes("data.json")) && File.GetLastWriteTimeUtc("data.json") == fileTime, "history battery leaves full storage state, counters and data.json bytes/timestamp unchanged");
Check(storage.CurrentCashRegisterId == currentBefore && openStates.SequenceEqual(storage.CashRegisters.Select(r => (r.Id, r.IsOpen)))
    && registerRefs.SequenceEqual(storage.CashRegisters) && movementRefs.SequenceEqual(storage.CashMovements), "current register pointer, open flags and collections are untouched");
var oldDetail = cash.GetHistoryDetail(1, Copy(admin));
Check(oldDetail != null && !oldDetail.Entry.IsOpen && storage.CurrentCashRegisterId == 25 && cash.IsOpen() && cash.GetCurrent()!.Id == 25 && storage.CashRegisters.Single(r => r.Id == 25).IsOpen && !storage.CashRegisters.Single(r => r.Id == 1).IsOpen,
    "viewing an old closed register while another is open does not reopen, close or select anything");
Reject(() => cash.Open(1m), IOE, "opening a second register still rejected after history browsing");

// ---- Persistence: reload in the same scratch cwd and compare.
storage.SaveToFile();
var snapBefore = Snap(cash, Copy(admin));
var reload = new DataStorageService();
var reloadCash = new CashRegisterService(reload, new SaleService(reload));
var snapAfter = Snap(reloadCash, Copy(admin));
Check(reload.CashRegisters.Count == 25 && reload.CurrentCashRegisterId == 25 && snapBefore == snapAfter, "history page and every detail (ids, amounts, counts, movements, receipts, linked summaries) are identical after reload");
var reloaded = reloadCash.GetHistory(new CashHistoryFilter(PageSize: 50), Copy(admin));
Check(Ids(reloaded).SequenceEqual(all) && reloaded.Entries.Single(e => e.Id == 25).IsOpen, "ordering survives reload");

// ---- CashHistory page: renderer-less component checks (no browser, no host, scratch storage only).
storage.SaveToFile();
var uiState = State(); var uiBytes = File.ReadAllBytes("data.json");
var uiCurrentId = storage.CurrentCashRegisterId; var uiCurrentOpen = cash.GetCurrent()!.IsOpen; var uiIsOpen = cash.IsOpen();
var uiType = typeof(CashRegisterService).Assembly.GetType("GastroApp.Pages.CashHistory");
Check(uiType != null, "CashHistory page type exists");
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
        uiType.GetProperty("CashService", flags)!.SetValue(page, cash);
        return (page, nav);
    }
    Exception? Call(object page, string method, params object[] arguments)
    {
        try { uiType.GetMethod(method, flags | BindingFlags.DeclaredOnly)!.Invoke(page, arguments); return null; }
        catch (TargetInvocationException ex) { return ex.InnerException; }
    }
    object? Get(object page, string field) => uiType.GetField(field, flags)!.GetValue(page);
    void Set(object page, string field, object? value) => uiType.GetField(field, flags)!.SetValue(page, value);
    void SetId(object page, int? id) => uiType.GetProperty("RegisterId", flags)!.SetValue(page, id);
    CashHistoryPage? HP(object page) => (CashHistoryPage?)Get(page, "historyPage");
    CashHistoryDetail? DT(object page) => (CashHistoryDetail?)Get(page, "detail");
    string? Msg(object page, string field) => (string?)Get(page, field);

    // Unauthenticated and Employee circuits fail closed on every entry point.
    var uiAnon = NewAuth(null); var uiEmployee = NewAuth("fixture-employee");
    foreach (var (auth, who, destination) in new[] { (uiAnon, "anonymous", "/login"), (uiEmployee, "employee", "/unauthorized") })
        foreach (var action in new[] { "OnParametersSet", "ShowDetail", "ApplyFilters", "ClearFilters", "NextPage", "PreviousPage", "CloseDetail" })
        {
            var (page, nav) = NewPage(auth);
            SetId(page, 1);
            var ex = Call(page, action, action == "ShowDetail" ? new object[] { 1 } : Array.Empty<object>());
            Check(ex == null && nav.Destination == destination && HP(page) == null && DT(page) == null && Msg(page, "detailMessage") == null,
                who + " " + action + " navigates to " + destination + " and loads nothing");
        }

    // Admin circuit: list, detail, missing id, navigation.
    var uiAdmin = NewAuth("fixture-admin");
    var (ap, anav) = NewPage(uiAdmin);
    var loadEx = Call(ap, "OnParametersSet");
    Check(loadEx == null && anav.Destination == null && HP(ap) != null && HP(ap)!.TotalCount == storage.CashRegisters.Count && DT(ap) == null && Msg(ap, "historyError") == null,
        "admin OnParametersSet loads the history page without navigating");
    SetId(ap, 1);
    Check(Call(ap, "OnParametersSet") == null && anav.Destination == null && DT(ap)?.Entry.Id == 1 && !DT(ap)!.Entry.IsOpen && Msg(ap, "detailMessage") == null,
        "admin route with a closed register id loads that detail");
    SetId(ap, 25);
    Check(Call(ap, "OnParametersSet") == null && DT(ap)?.Entry.Id == 25 && DT(ap)!.Entry.IsOpen, "admin route with the open register id loads it read-only");
    SetId(ap, 9999);
    Check(Call(ap, "OnParametersSet") == null && DT(ap) == null && Msg(ap, "detailMessage")!.Contains("No existe una caja con el ID 9999") && anav.Destination == null,
        "admin route with an unknown id shows the missing-register message");
    SetId(ap, null);
    Check(Call(ap, "OnParametersSet") == null && DT(ap) == null && Msg(ap, "detailMessage") == null, "admin route without id clears the detail");
    Check(Call(ap, "ShowDetail", 7) == null && anav.Destination == "/cash/history/7", "ShowDetail navigates to /cash/history/{id} without forcing a reload");
    anav.Destination = null;
    Check(Call(ap, "CloseDetail") == null && anav.Destination == "/cash/history", "CloseDetail navigates to /cash/history without forcing a reload");

    // Filters and pagination (page size 10).
    anav.Destination = null;
    Set(ap, "filterFrom", d0.AddDays(10)); Set(ap, "filterTo", d0.AddDays(2));
    Check(Call(ap, "ApplyFilters") == null && HP(ap) == null && Msg(ap, "historyError") == "La fecha inicial no puede ser posterior a la fecha final." && anav.Destination == null,
        "filterFrom after filterTo shows the Spanish range error and clears the page");
    Check(Call(ap, "ClearFilters") == null && Msg(ap, "historyError") == null && HP(ap)?.TotalCount == 25, "ClearFilters recovers from the range error");
    Set(ap, "filterStatus", CashHistoryStatusFilter.Closed);
    Check(Call(ap, "ApplyFilters") == null && HP(ap)!.TotalCount == 24 && HP(ap)!.Entries.All(x => !x.IsOpen), "status filter Closed lists only closed registers");
    Set(ap, "filterStatus", CashHistoryStatusFilter.Open);
    Call(ap, "ApplyFilters");
    Check(HP(ap)!.TotalCount == 1 && HP(ap)!.Entries.Single().IsOpen, "status filter Open lists only the open register");
    Call(ap, "ClearFilters");
    Check(HP(ap)!.Page == 1 && HP(ap)!.PageSize == 10 && HP(ap)!.TotalPages == 3 && HP(ap)!.Entries.Count == 10 && Ids(HP(ap)!).SequenceEqual(all.Take(10)), "page 1 of 3 with ten rows");
    Call(ap, "PreviousPage");
    Check(HP(ap)!.Page == 1, "PreviousPage stays clamped on the first page");
    Call(ap, "NextPage");
    Check(HP(ap)!.Page == 2 && Ids(HP(ap)!).SequenceEqual(all.Skip(10).Take(10)), "NextPage moves to page 2");
    Call(ap, "NextPage");
    Check(HP(ap)!.Page == 3 && HP(ap)!.Entries.Count == 5 && Ids(HP(ap)!).SequenceEqual(all.Skip(20)), "NextPage reaches the last page with five rows");
    Call(ap, "NextPage");
    Check(HP(ap)!.Page == 3 && Msg(ap, "historyError") == null, "NextPage stays clamped on the last page");
    Call(ap, "PreviousPage"); Call(ap, "PreviousPage"); Call(ap, "PreviousPage");
    Check(HP(ap)!.Page == 1, "PreviousPage walks back and stays clamped on page 1");
    Call(ap, "NextPage"); Call(ap, "ApplyFilters");
    Check(HP(ap)!.Page == 1, "ApplyFilters returns to the first page");

    // Mid-session permission changes (live revalidation per interaction).
    var uiSecond = NewAuth("second-admin");
    var (sp, snav) = NewPage(uiSecond);
    SetId(sp, 1); Call(sp, "OnParametersSet");
    var listBefore = HP(sp); var detailBefore = DT(sp);
    Check(listBefore != null && detailBefore?.Entry.Id == 1 && snav.Destination == null, "second admin page loaded before the demotion");
    admin2.Role = UserRole.Employee;
    try
    {
        foreach (var (action, args2) in new (string, object[])[] { ("ApplyFilters", []), ("ShowDetail", [3]), ("OnParametersSet", []), ("NextPage", []), ("CloseDetail", []) })
        {
            snav.Destination = null;
            if (action == "OnParametersSet") SetId(sp, 2);
            var ex = Call(sp, action, args2);
            Check(ex == null && snav.Destination == "/unauthorized" && ReferenceEquals(HP(sp), listBefore) && (DT(sp) == null || ReferenceEquals(DT(sp), detailBefore)),
                "demoted admin " + action + " redirects to /unauthorized without a new detail or exception");
        }
        var (fresh, fnav) = NewPage(uiSecond);
        SetId(fresh, 1);
        Check(Call(fresh, "OnParametersSet") == null && fnav.Destination == "/unauthorized" && HP(fresh) == null && DT(fresh) == null, "demoted admin opening the page cold loads nothing");
    }
    finally { admin2.Role = UserRole.Admin; }
    snav.Destination = null; SetId(sp, 2);
    Check(Call(sp, "OnParametersSet") == null && snav.Destination == null && DT(sp)?.Entry.Id == 2, "restored admin loads detail again");
    admin2.PasswordHash = "rotated-hash";
    try
    {
        SetId(sp, 3); snav.Destination = null;
        Check(Call(sp, "OnParametersSet") == null && snav.Destination == "/login" && DT(sp)?.Entry.Id == 2, "password change mid-session redirects to /login and loads no new detail");
    }
    finally { admin2.PasswordHash = hash; }

    // Two independent circuits over the same singleton services.
    var (aa, aanav) = NewPage(NewAuth("fixture-admin")); Call(aa, "OnParametersSet");
    var (ee, eenav) = NewPage(NewAuth("fixture-employee"));
    var adminList = HP(aa);
    Call(ee, "OnParametersSet"); Call(ee, "ApplyFilters"); Call(ee, "NextPage");
    Check(eenav.Destination == "/unauthorized" && HP(ee) == null && ReferenceEquals(HP(aa), adminList) && aanav.Destination == null, "employee denial leaves the admin circuit's page state untouched");
    Call(aa, "NextPage");
    Check(HP(aa)!.Page == 2 && aanav.Destination == null, "admin circuit keeps working after the employee circuit was denied");
    var otherAdminAuth = NewAuth("fixture-admin"); otherAdminAuth.Logout();
    Call(aa, "ApplyFilters");
    Check(!otherAdminAuth.IsAuthenticated && aanav.Destination == null && HP(aa)!.Page == 1, "logging out one circuit does not affect another circuit of the same user");
    var (a2, a2nav) = NewPage(otherAdminAuth);
    Call(a2, "ApplyFilters");
    Check(a2nav.Destination == "/login" && HP(a2) == null, "the logged-out circuit is redirected to /login");

    // Nothing above may mutate storage or the current register.
    Check(State() == uiState && uiBytes.SequenceEqual(File.ReadAllBytes("data.json")), "component battery leaves the full storage snapshot and data.json bytes unchanged");
    Check(storage.CurrentCashRegisterId == uiCurrentId && cash.GetCurrent()!.IsOpen == uiCurrentOpen && cash.IsOpen() == uiIsOpen, "component battery keeps the current register id and open flag");

    // Source assertions.
    string Src(string path) => File.ReadAllText(Path.Combine(args[0], path));
    var navMenu = Src("Shared/NavMenu.razor"); var linkAt = navMenu.IndexOf("href=\"cash/history\"", StringComparison.Ordinal);
    var adminIf = navMenu.LastIndexOf("@if (AuthService.IsInRole(UserRole.Admin))", Math.Max(linkAt, 0), StringComparison.Ordinal);
    Check(linkAt > 0 && adminIf >= 0 && !navMenu.Substring(adminIf, linkAt - adminIf).Contains('}') && navMenu.Contains("Historial de cajas"), "NavMenu links the history inside the Admin block with the Spanish label");
    Check(navMenu.Contains("href=\"cash\" Match=\"NavLinkMatch.All\""), "the Caja NavLink only matches exactly /cash");
    Check(Src("Pages/Cash.razor").Contains("href=\"/cash/history\""), "Cash page links to the history");
    var historySource = Src("Pages/CashHistory.razor");
    Check(!Regex.IsMatch(historySource, @"\b(Close|Open|Cancel)\(") && !historySource.Contains("AddManualMovement") && !historySource.Contains("SaveToFile"), "CashHistory page has no mutating calls");
    Check(Regex.Matches(historySource, @"CashService\.(\w+)").Select(m => m.Groups[1].Value).Distinct().OrderBy(x => x).SequenceEqual(new[] { "GetHistory", "GetHistoryDetail" }), "CashHistory page only calls the read-only history queries of the cash service");
    Check(Regex.IsMatch(historySource, @"IsOutflow\(CashMovementType type\)\s*=>[^;]*CashMovementType\.Refund") && historySource.Contains("CashMovementType.Refund => \"Devoluci\u00f3n\""), "CashHistory treats refunds as an outflow labelled Devolucion");
    Check(historySource.Contains("@page \"/cash/history\"") && historySource.Contains("@page \"/cash/history/{RegisterId:int}\""), "CashHistory page declares both routes");
}

// ---- Legacy data: closed registers without count or register-linked summary.
var baseline = JsonNode.Parse(File.ReadAllText("data.json"))!.AsObject();
var countArray = baseline["CashCounts"]!.AsArray();
countArray.RemoveAt(countArray.Select((n, i) => (n, i)).First(x => (int)x.n!["CashRegisterId"]! == 3).i);
foreach (var s in baseline["Summaries"]!.AsArray()) if ((int?)s!["CashRegisterId"] == 3) s.AsObject().Remove("CashRegisterId");
baseline["CashRegisters"]!.AsArray().Add(JsonNode.Parse("{\"Id\":26,\"OpenDate\":\"2025-12-31T08:00:00\",\"InitialAmount\":70,\"FinalAmount\":77,\"IsOpen\":false,\"CloseDate\":\"2025-12-31T20:00:00\",\"ExpectedAmount\":70}"));
File.WriteAllText("data.json", baseline.ToJsonString());
var legacy = new DataStorageService();
var legacyCash = new CashRegisterService(legacy, new SaleService(legacy));
var legacyAdmin = Copy(admin);
var legacyPage = legacyCash.GetHistory(new CashHistoryFilter(PageSize: 50), legacyAdmin);
var l3 = legacyPage.Entries.Single(e => e.Id == 3); var l26 = legacyPage.Entries.Single(e => e.Id == 26);
Check(legacyPage.TotalCount == 26 && legacyPage.Entries.Last().Id == 26, "legacy register is listed and, being the oldest, comes last");
Check(!l3.HasCount && !l3.IsOpen && l3.ExpectedAmount == 200m && l3.CountedAmount == 190m && l3.Difference == -10m && !l3.AmountsUnavailable, "closed register without a count shows its stored final and expected amounts");
Check(legacyCash.GetHistoryDetail(3, legacyAdmin)!.Count == null && legacyCash.GetHistoryDetail(3, legacyAdmin)!.LinkedSummaries.Count == 0, "no count is reconstructed and the same-date summary without register Id is not attributed");
var d26 = legacyCash.GetHistoryDetail(26, legacyAdmin)!;
Check(!l26.HasCount && l26.InitialAmount == 70m && l26.ExpectedAmount == 70m && l26.CountedAmount == 77m && l26.Difference == 7m && l26.CloseDate == new DateTime(2025, 12, 31, 20, 0, 0)
    && d26.Count == null && d26.LinkedSummaries.Count == 0 && d26.Movements.Count == 0 && d26.PaymentSummary.State == CashPaymentSummaryState.Complete && d26.PaymentSummary.RegisteredTotal == 0m,
    "hand-written legacy closed register is browsable with stored values and empty sections");
Check(legacy.CurrentCashRegisterId == 25 && legacyCash.GetHistoryDetail(26, legacyAdmin) != null && legacyCash.GetHistoryDetail(27, legacyAdmin) == null, "legacy lookup is by stable Id only");

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
    & dotnet run --project (Join-Path $ScratchPath 'HistoryChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Cash history checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
