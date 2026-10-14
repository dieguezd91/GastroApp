param([string]$ScratchPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$ScratchPath) { $ScratchPath = Join-Path ([IO.Path]::GetTempPath()) ('gastro-count-' + [guid]::NewGuid().ToString('N')) }
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
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>$framework</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><ProjectReference Include="$reference" /><FrameworkReference Include="Microsoft.AspNetCore.App" /></ItemGroup>
</Project>
"@ | Set-Content (Join-Path $ScratchPath 'CountChecks.csproj') -Encoding utf8
@'
using GastroApp.Models;
using GastroApp.Services;
using Microsoft.AspNetCore.Components;
using System.Collections;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;

int checks = 0, failures = 0;
void Check(bool ok, string name) { checks++; Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}"); if (!ok) failures++; }
var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
var IOE = typeof(InvalidOperationException);
var UAE = typeof(UnauthorizedAccessException);
var STALE = typeof(CashCountReviewOutdatedException);
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
void RejectClose(CashCountRequest? request, User? actor, Type exception, string name) => Reject(() => cash.Close(request!, actor), exception, name);
bool Consistent(CashRegister register, CashCount count, DailySummary summary) =>
    count.CashRegisterId == register.Id && count.CountedAmount == register.FinalAmount && count.ExpectedAmount == register.ExpectedAmount
    && count.Difference == register.Difference && count.Difference == count.CountedAmount - count.ExpectedAmount
    && count.Lines.Sum(l => l.Subtotal) == count.CountedAmount && count.Lines.All(l => l.Subtotal == l.Denomination * l.Quantity)
    && summary.CashRegisterId == register.Id && summary.FinalCash == register.FinalAmount && summary.InitialCash == register.InitialAmount
    && summary.Difference == register.Difference && !register.IsOpen && register.CloseDate == count.CountedAt;

// ---- API surface: the unvalidated Close(decimal) path must not exist.
var closes = typeof(CashRegisterService).GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static).Where(m => m.Name == "Close").ToList();
Check(closes.Count == 1 && closes[0].GetParameters().Select(p => p.ParameterType).SequenceEqual(new[] { typeof(CashCountRequest), typeof(User) }), "only Close(CashCountRequest, User) is public; no Close(decimal)");

// ---- No session.
Reject(() => cash.GetCountReview(), IOE, "review without session");
RejectClose(Req(new CashCountReview(1, 0m, 0, 0), []), Copy(admin), IOE, "close without session");
Check(cash.GetCount(1) == null, "no count without session");

// ---- Pure preview.
var p = cash.PreviewCount([L(1000m, 3), L(0.5m, 7), L(20000m, 0)], 3600m);
Check(p.CountedAmount == 3003.5m && p.ExpectedAmount == 3600m && p.Difference == -596.5m && p.Outcome == CashCountOutcome.Shortage
    && p.Lines.Select(l => l.Subtotal).SequenceEqual(new[] { 3000m, 3.5m, 0m }), "denomination subtotals and total with decimals");
Check(p.Lines is IList { IsReadOnly: true }, "preview lines are a read-only collection");
Check(typeof(CashCountPreview).GetProperties().All(x => x.SetMethod == null), "preview properties are getter-only");
var surplus = cash.PreviewCount([L(1000m, 3), L(0.5m, 7)], 3000m);
Check(surplus.Difference == 3.5m && surplus.Outcome == CashCountOutcome.Surplus, "preview surplus");
var exact = cash.PreviewCount([L(1000m, 3), L(0.5m, 7)], 3003.5m);
Check(exact.Difference == 0m && exact.Outcome == CashCountOutcome.Exact, "preview exact");
Check(cash.PreviewCount([], 5m).CountedAmount == 0m && cash.PreviewCount([L(5m, 0), L(10m, 0)], 5m).CountedAmount == 0m, "empty and all-zero counts are allowed");
Check(cash.PreviewCount(Enumerable.Range(1, 100).Select(i => L(i, 1)).ToList(), 0m).CountedAmount == 5050m, "exactly 100 lines allowed");
Reject(() => cash.PreviewCount(null, 0m), IOE, "preview null lines");
Reject(() => cash.PreviewCount([L(0m, 1)], 0m), IOE, "preview zero denomination");
Reject(() => cash.PreviewCount([L(-5m, 1)], 0m), IOE, "preview negative denomination");
Reject(() => cash.PreviewCount([L(5m, -1)], 0m), IOE, "preview negative quantity");
Reject(() => cash.PreviewCount([L(1000m, 1), L(1000.00m, 2)], 0m), IOE, "preview duplicate 1000 vs 1000.00");
Reject(() => cash.PreviewCount(Enumerable.Range(1, 101).Select(i => L(i, 1)).ToList(), 0m), IOE, "preview more than 100 lines");
var overflowMessage = Reject(() => cash.PreviewCount([L(decimal.MaxValue, 2)], 0m), IOE, "preview subtotal overflow");
Check(overflowMessage?.Message == "El conteo supera el l\u00edmite permitido.", "overflow message in Spanish");
Reject(() => cash.PreviewCount([L(decimal.MaxValue, 1), L(1m, 1)], 0m), IOE, "preview total overflow");
Reject(() => cash.PreviewCount([L(decimal.MaxValue, 1)], -1m), IOE, "preview difference overflow");

// ---- Session 1: rejections, concurrency, exact close.
cash.Open(100.25m);
var reg1 = cash.GetCurrent()!;
var rv = cash.GetCountReview();
Check(rv == new CashCountReview(reg1.Id, 100.25m, 0, 0), "review of fresh session: expected, zero movements, last ID 0");
var valid = Req(rv, [L(100m, 1), L(0.25m, 1)]);
RejectClose(null, Copy(admin), IOE, "null request");
RejectClose(Req(null!, [L(100m, 1)]), Copy(admin), IOE, "null review");
RejectClose(Req(rv, null), Copy(admin), IOE, "null lines");
RejectClose(Req(rv, [L(0m, 1)], "r"), Copy(admin), IOE, "zero denomination");
RejectClose(Req(rv, [L(-5m, 1)], "r"), Copy(admin), IOE, "negative denomination");
RejectClose(Req(rv, [L(5m, -1)], "r"), Copy(admin), IOE, "negative quantity");
RejectClose(Req(rv, [L(1000m, 1), L(1000.00m, 1)], "r"), Copy(admin), IOE, "duplicate denomination 1000 vs 1000.00");
RejectClose(Req(rv, Enumerable.Range(1, 101).Select(i => L(i, 1)).ToList(), "r"), Copy(admin), IOE, "more than 100 lines");
RejectClose(Req(rv, [L(100m, 1), L(0.25m, 1)], null, false), Copy(admin), IOE, "Confirmed=false");
RejectClose(Req(rv, [], "r"), Copy(admin), IOE, "zero count without zero confirmation (empty)");
RejectClose(Req(rv, [L(1000m, 0)], "r"), Copy(admin), IOE, "zero count without zero confirmation (zero quantities)");
RejectClose(Req(rv, [], null, true, true), Copy(admin), IOE, "zero count confirmed but no reason for difference");
RejectClose(Req(rv, [L(100m, 1)]), Copy(admin), IOE, "difference with null reason");
RejectClose(Req(rv, [L(100m, 1)], "   \t"), Copy(admin), IOE, "difference with blank reason");
RejectClose(Req(rv, [L(decimal.MaxValue, 2)], "r"), Copy(admin), IOE, "subtotal overflow on close");
RejectClose(Req(rv, [L(decimal.MaxValue, 1), L(1m, 1)], "r"), Copy(admin), IOE, "total overflow on close");
RejectClose(Req(rv with { RegisterId = 999 }, [L(100m, 1), L(0.25m, 1)]), Copy(admin), IOE, "wrong register in review");
var noReview = Reject(() => cash.Close(Req(rv with { ExpectedAmount = 1m }, [L(100m, 1), L(0.25m, 1)]), Copy(admin)), STALE, "tampered expected amount");
Check((noReview as CashCountReviewOutdatedException)?.Current == rv && noReview is InvalidOperationException, "stale exception carries fresh review and is an InvalidOperationException");
foreach (var (actor, name) in new (User?, string)[] { (null, "null actor"), (storage.Users[2], "employee"),
    (new User { Id = 99, Username = admin.Username, PasswordHash = hash, Role = UserRole.Admin }, "unknown actor"),
    (new User { Id = admin.Id, Username = "other", PasswordHash = hash, Role = UserRole.Admin }, "mismatched username"),
    (new User { Id = admin.Id, Username = admin.Username, PasswordHash = "old-hash", Role = UserRole.Admin }, "mismatched password") })
    RejectClose(valid, actor, UAE, name);
var staleActor = Copy(admin);
admin.Role = UserRole.Employee;
RejectClose(valid, staleActor, UAE, "live demotion");
admin.Role = UserRole.Admin;
admin.Username = "renamed";
RejectClose(valid, staleActor, UAE, "stale username");
admin.Username = staleActor.Username;
admin.PasswordHash = "changed";
RejectClose(valid, staleActor, UAE, "stale password");
admin.PasswordHash = hash;
storage.Users.Remove(admin);
RejectClose(valid, staleActor, UAE, "deleted actor");
storage.Users.Insert(0, admin);

// Concurrency: the reviewed state must match at the moment of closing.
cash.AddManualMovement(CashMovementType.Income, 20m, "aporte", admin);
var r2 = cash.GetCountReview();
var staleIncome = Reject(() => cash.Close(valid, Copy(admin)), STALE, "manual income after review");
Check((staleIncome as CashCountReviewOutdatedException)?.Current == r2 && r2 == new CashCountReview(reg1.Id, 120.25m, 1, storage.CashMovements.Max(m => m.Id)), "stale carries fresh review (expected, count, last ID)");
cash.AddManualMovement(CashMovementType.Income, 5m, "ida", admin);
cash.AddManualMovement(CashMovementType.Expense, 5m, "vuelta", admin);
var r4 = cash.GetCountReview();
Check(r4.ExpectedAmount == r2.ExpectedAmount && r4 != r2 && r4.MovementCount == 3, "+X then -X keeps expected but changes the review token");
var stalePair = Reject(() => cash.Close(Req(r2, [L(120m, 1), L(0.25m, 1)]), Copy(admin)), STALE, "+X/-X pair after review");
Check((stalePair as CashCountReviewOutdatedException)?.Current == r4, "pair stale carries fresh review");
var product = storage.Products.First();
Sale Checkout(decimal price, params SalePayment[] payments) => new() { Items = [new SaleItem { ProductId = product.Id, ProductName = product.Name, Price = price, Quantity = 1 }], Payments = payments.ToList() };
sales.Add(Checkout(5m, new SalePayment { PaymentMethod = PaymentMethod.Transfer, Amount = 5m }));
Check(cash.GetCountReview() == r4, "noncash sale does not change the review");
sales.Add(Checkout(30m, new SalePayment { PaymentMethod = PaymentMethod.Cash, Amount = 30m, ReceivedAmount = 30m }));
var r5 = cash.GetCountReview();
Check(r5.ExpectedAmount == 150.25m && r5.MovementCount == 4, "cash sale changes the review");
var staleSale = Reject(() => cash.Close(Req(r4, [L(100m, 1), L(20m, 1), L(0.25m, 1)]), Copy(admin)), STALE, "cash sale after review");
Check((staleSale as CashCountReviewOutdatedException)?.Current == r5, "sale stale carries fresh review");
var closeAt = DateTime.Now;
var exactRequest = Req(r5, [L(100m, 1), L(50m, 1), L(0.25m, 1)], "   ");
var summary1 = cash.Close(exactRequest, Copy(admin));
var count1 = cash.GetCount(reg1.Id)!;
Check(reg1.FinalAmount == 150.25m && reg1.ExpectedAmount == 150.25m && reg1.Difference == 0m && !reg1.IsOpen, "exact close stores FinalAmount/ExpectedAmount on the register");
Check(count1 != null && Consistent(reg1, count1, summary1) && ReferenceEquals(storage.Summaries.Last(), summary1), "exact count, register and summary are consistent");
Check(count1.Reason == null && count1.UserId == 10 && count1.Username == "fixture-admin" && count1.CountedAt >= closeAt && count1.CountedAt <= DateTime.Now, "exact count: blank reason stored as null, closing admin attributed");
Check(count1.Lines.Count == 3 && count1.Lines[0].Denomination == 100m && count1.Lines[2].Subtotal == 0.25m, "stored lines keep entered order");
Check(storage.CashCounts.Count == 1 && storage.Summaries.Count == 1 && summary1.Date == DateTime.Today, "one count and one summary appended");
Reject(() => cash.GetCountReview(), IOE, "review after close");
RejectClose(exactRequest, Copy(admin), IOE, "duplicate close re-submitting the same request");
RejectClose(Req(r5, [L(1m, 1)], "x"), Copy(admin), IOE, "closed register with another request");

// ---- Session 2: surplus, two administrators.
cash.Open(50m);
var reg2 = cash.GetCurrent()!;
cash.AddManualMovement(CashMovementType.Income, 10m, "ingreso", admin);
var rvA = cash.GetCountReview();
var requestA = Req(rvA, [L(50m, 1), L(5m, 3)], "  sobrante de propina  ");
cash.AddManualMovement(CashMovementType.Income, 1m, "ingreso 2", Copy(admin2));
RejectClose(requestA, Copy(admin), STALE, "first admin's request after second admin changed the drawer");
var rvB = cash.GetCountReview();
Check(rvB.ExpectedAmount == 61m, "fresh review for surplus session");
var requestB = Req(rvB, [L(50m, 1), L(5m, 3)], "  sobrante de propina  ");
var summary2 = cash.Close(requestB, Copy(admin2));
var count2 = cash.GetCount(reg2.Id)!;
Check(reg2.FinalAmount == 65m && reg2.ExpectedAmount == 61m && reg2.Difference == 4m && count2.Difference == 4m && Consistent(reg2, count2, summary2), "surplus close: Difference = FinalAmount - ExpectedAmount, all records consistent");
Check(count2.Reason == "sobrante de propina" && count2.UserId == 11 && count2.Username == "second-admin", "surplus reason trimmed and closing admin attributed");
RejectClose(requestA, Copy(admin), IOE, "stale request from the other admin after the session closed");
Check(cash.PreviewCount([L(65m, 1)], 61m).Outcome == CashCountOutcome.Surplus, "outcome Surplus");

// ---- Session 3: shortage.
cash.Open(200m);
var reg3 = cash.GetCurrent()!;
var rvC = cash.GetCountReview();
RejectClose(Req(rvC, [L(100m, 1), L(50m, 1), L(20m, 2)]), Copy(admin), IOE, "shortage without reason");
var summary3 = cash.Close(Req(rvC, [L(100m, 1), L(50m, 1), L(20m, 2)], " faltante "), Copy(admin));
var count3 = cash.GetCount(reg3.Id)!;
Check(reg3.FinalAmount == 190m && reg3.ExpectedAmount == 200m && reg3.Difference == -10m && summary3.Difference == -10m && Consistent(reg3, count3, summary3) && count3.Reason == "faltante", "shortage close and trimmed reason");

// ---- Session 4: zero count.
cash.Open(30m);
var reg4 = cash.GetCurrent()!;
var rvD = cash.GetCountReview();
RejectClose(Req(rvD, [L(1000m, 0)], "caja vac\u00eda", false, true), Copy(admin), IOE, "zero count confirmed but Confirmed=false");
RejectClose(Req(rvD, [L(1000m, 0)], "caja vac\u00eda", true, false), Copy(admin), IOE, "zero count requires ZeroCountConfirmed");
RejectClose(Req(rvD, [L(1000m, 0)], null, true, true), Copy(admin), IOE, "zero count with difference requires reason");
var summary4 = cash.Close(Req(rvD, [L(1000m, 0)], "caja vac\u00eda", true, true), Copy(admin));
var count4 = cash.GetCount(reg4.Id)!;
Check(reg4.FinalAmount == 0m && reg4.Difference == -30m && count4.CountedAmount == 0m && count4.Lines.Count == 1 && count4.Lines[0].Subtotal == 0m && Consistent(reg4, count4, summary4), "zero count with reason stored");

// ---- Session 5: difference overflow, then zero exact close.
cash.Open(0m);
var reg5 = cash.GetCurrent()!;
var injected = new CashMovement { Id = storage.GetNextCashMovementId(), CashRegisterId = reg5.Id, Date = DateTime.Now, Type = CashMovementType.Withdrawal, Amount = 1m };
storage.CashMovements.Add(injected);
var rvE = cash.GetCountReview();
Check(rvE.ExpectedAmount == -1m && rvE.LastMovementId == injected.Id, "review reflects injected movement");
RejectClose(Req(rvE, [L(decimal.MaxValue, 1)], "r"), Copy(admin), IOE, "difference overflow on close");
storage.CashMovements.Remove(injected);
var rvE2 = cash.GetCountReview();
var summary5 = cash.Close(Req(rvE2, [], null, true, true), Copy(admin));
var count5 = cash.GetCount(reg5.Id)!;
Check(count5.Lines.Count == 0 && count5.Difference == 0m && count5.Reason == null && Consistent(reg5, count5, summary5), "zero expected and zero counted closes exactly without reason");

// ---- Session 6: regressions around sales, manual movements, payment summary and detached reads.
cash.Open(10m);
var reg6 = cash.GetCurrent()!;
var mixed = Checkout(30m, new SalePayment { PaymentMethod = PaymentMethod.Cash, Amount = 10m, ReceivedAmount = 100m }, new SalePayment { PaymentMethod = PaymentMethod.DebitCard, Amount = 20m });
sales.Add(mixed);
Check(storage.CashMovements.Last().Amount == 10m && cash.GetExpectedCash(reg6.Id) == 20m, "mixed sale counts applied cash only");
sales.Add(Checkout(7m, new SalePayment { PaymentMethod = PaymentMethod.Cash, Amount = 7m, ReceivedAmount = 10m }));
Check(cash.GetExpectedCash(reg6.Id) == 27m, "cash sale counts applied cash, not tender");
var movementCount = storage.CashMovements.Count;
sales.Add(Checkout(5m, new SalePayment { PaymentMethod = PaymentMethod.Transfer, Amount = 5m }));
Check(storage.CashMovements.Count == movementCount, "noncash sale adds no movement");
cash.AddManualMovement(CashMovementType.Income, 2m, "ingreso", admin);
cash.AddManualMovement(CashMovementType.Expense, 1m, "gasto", admin);
cash.AddManualMovement(CashMovementType.Withdrawal, 1m, "retiro", admin);
Check(cash.GetExpectedCash(reg6.Id) == 27m, "manual Income/Expense/Withdrawal still work");
sales.Cancel(mixed.Id, "fixture", admin);
Check(cash.GetExpectedCash(reg6.Id) == 27m, "cancellation does not reverse money");
var paymentBefore = Json(cash.GetCurrentPaymentSummary());
var topProduct = sales.GetTopProduct(); var todayTotal = sales.GetTodayTotal(); var todayCount = sales.GetTodayCount();
var summary6 = cash.Close(Req(cash.GetCountReview(), [L(20m, 1), L(5m, 1), L(2m, 1)]), Copy(admin));
var count6 = cash.GetCount(reg6.Id)!;
Check(Consistent(reg6, count6, summary6) && reg6.Difference == 0m, "regression session closes exact");
Check(summary6.TotalSales == todayTotal && summary6.SalesCount == todayCount && summary6.TopProduct == topProduct.Name && summary6.TopProductQuantity == topProduct.Quantity
    && sales.GetTodayTotal() == todayTotal, "daily summary metrics computed as before");
Check(Json(cash.GetCurrentPaymentSummary()) == paymentBefore, "payment summary unchanged by close");
var snapshot = Json(count6);
count6.Lines[0].Quantity = 99; count6.Lines.Clear(); count6.Reason = "tampered"; count6.CountedAmount = 1m;
var again = cash.GetCount(reg6.Id)!;
Check(Json(again) == snapshot && !ReferenceEquals(again, storage.CashCounts.Single(c => c.CashRegisterId == reg6.Id))
    && !again.Lines.Any(l => storage.CashCounts.SelectMany(c => c.Lines).Any(s => ReferenceEquals(s, l))), "GetCount returns a detached deep copy");
Check(cash.GetCount(999) == null, "GetCount of unknown register is null");

// ---- Save / reload.
var persisted = Json(storage.CashCounts);
var reload = new DataStorageService();
var reloadCash = new CashRegisterService(reload, new SaleService(reload));
Check(storage.CashCounts.Count == 6 && Json(reload.CashCounts) == persisted, "save/reload preserves every count identically");
Check(Json(reloadCash.GetCount(reg1.Id)) == Json(cash.GetCount(reg1.Id)) && Json(reloadCash.GetCount(reg4.Id)) == Json(cash.GetCount(reg4.Id)), "GetCount works after reload");
Check(reload.Summaries.Select(s => s.CashRegisterId).SequenceEqual(storage.Summaries.Select(s => s.CashRegisterId)) && reload.Summaries.All(s => s.CashRegisterId.HasValue), "summary register IDs survive reload");
reload.LoadFromFile(); reload.LoadFromFile();
Check(reload.CashCounts.Count == 6, "repeated loads replace the collection");

// ---- Legacy and corrupted JSON.
cash.Open(1m);
var openId = cash.GetCurrent()!.Id;
var baselineJson = File.ReadAllText("data.json");
JsonObject Baseline() => JsonNode.Parse(baselineJson)!.AsObject();
DataStorageService Load(JsonObject json) { File.WriteAllText("data.json", json.ToJsonString()); return new DataStorageService(); }
void Corrupt(Action<JsonObject> edit, string name)
{
    var json = Baseline(); edit(json);
    bool failed = false;
    try { _ = Load(json); } catch (InvalidDataException) { failed = true; } catch (Exception) { }
    Check(failed, name + " fails loading with InvalidDataException");
}
JsonObject FirstCount(JsonObject json) => json["CashCounts"]!.AsArray()[0]!.AsObject();
JsonObject RegisterOf(JsonObject json, int id) => json["CashRegisters"]!.AsArray().Select(r => r!.AsObject()).Single(r => (int)r["Id"]! == id);
var noCounts = Baseline(); noCounts.Remove("CashCounts");
var legacy = Load(noCounts);
var legacyCash = new CashRegisterService(legacy, new SaleService(legacy));
Check(legacy.CashCounts.Count == 0 && legacy.CashRegisters.Count(r => !r.IsOpen) == 6 && legacyCash.GetCount(reg1.Id) == null, "legacy JSON without CashCounts loads; closed registers have no count");
var noSummaryIds = Baseline();
foreach (var s in noSummaryIds["Summaries"]!.AsArray()) s!.AsObject().Remove("CashRegisterId");
var legacySummaries = Load(noSummaryIds);
Check(legacySummaries.Summaries.Count == 6 && legacySummaries.Summaries.All(s => s.CashRegisterId == null) && legacySummaries.CashCounts.Count == 6, "legacy summaries without CashRegisterId load with null");
var oneMissing = Baseline(); oneMissing["CashCounts"]!.AsArray().RemoveAt(0);
var partial = Load(oneMissing);
var partialCash = new CashRegisterService(partial, new SaleService(partial));
Check(partial.CashCounts.Count == 5 && partialCash.GetCount(reg1.Id) == null && partialCash.GetCount(reg2.Id) != null, "closed register without a count stays valid beside counted ones");
Corrupt(j => j["CashCounts"] = null, "CashCounts null");
Corrupt(j => j["CashCounts"]!.AsArray().Add(null), "null entry");
Corrupt(j => FirstCount(j)["CashRegisterId"] = 9999, "orphan count (unknown register)");
Corrupt(j => j["CashCounts"]!.AsArray().Add(JsonNode.Parse(FirstCount(j).ToJsonString())), "duplicate register count");
Corrupt(j =>
{
    var open = JsonNode.Parse(FirstCount(j).ToJsonString())!.AsObject();
    open["CashRegisterId"] = openId;
    j["CashCounts"]!.AsArray().Add(open);
}, "count attached to an open register");
Corrupt(j => FirstCount(j)["Lines"] = null, "null Lines");
Corrupt(j => FirstCount(j)["Lines"]!.AsArray().Add(null), "null line");
Corrupt(j => FirstCount(j)["CountedAmount"] = (decimal)FirstCount(j)["CountedAmount"]! + 1m, "CountedAmount differs from line subtotals");
Corrupt(j => FirstCount(j)["Difference"] = (decimal)FirstCount(j)["Difference"]! + 1m, "Difference differs from counted - expected");
Corrupt(j => FirstCount(j)["Lines"]!.AsArray()[0]!["Subtotal"] = 1m, "line subtotal differs from denomination x quantity");
Corrupt(j => FirstCount(j)["Lines"]!.AsArray().Add(JsonNode.Parse("{\"Denomination\":0,\"Quantity\":0,\"Subtotal\":0}")), "zero denomination line");
Corrupt(j => FirstCount(j)["Lines"]!.AsArray().Add(JsonNode.Parse("{\"Denomination\":7,\"Quantity\":-1,\"Subtotal\":-7}")), "negative quantity line");
Corrupt(j =>
{
    var line = FirstCount(j)["Lines"]!.AsArray()[0]!.AsObject();
    FirstCount(j)["Lines"]!.AsArray().Add(JsonNode.Parse($"{{\"Denomination\":{line["Denomination"]!.ToJsonString()},\"Quantity\":0,\"Subtotal\":0}}"));
}, "duplicate denomination line");
Corrupt(j => FirstCount(j)["Lines"]!.AsArray().Add(JsonNode.Parse("{\"Denomination\":79228162514264337593543950335,\"Quantity\":2,\"Subtotal\":0}")), "line arithmetic overflow");
Corrupt(j => RegisterOf(j, reg1.Id)["FinalAmount"] = 1m, "register FinalAmount differs from CountedAmount");
Corrupt(j => RegisterOf(j, reg1.Id)["ExpectedAmount"] = 1m, "register ExpectedAmount differs from count");

// ---- /cash page callbacks (no renderer): reflection on private state, fresh scratch storage.
File.Delete("data.json");
var us = new DataStorageService();
var ucash = new CashRegisterService(us, new SaleService(us));
us.Users = [new User { Id = 10, Username = "fixture-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 11, Username = "second-admin", PasswordHash = hash, Role = UserRole.Admin },
    new User { Id = 12, Username = "fixture-employee", PasswordHash = hash, Role = UserRole.Employee }];
var uusers = new UserService(us);
AuthService Login(string name) { var auth = new AuthService(uusers); auth.Login(name, "fixture-pass"); return auth; }
var authA = Login("fixture-admin"); var authB = Login("second-admin"); var authE = Login("fixture-employee");
var pageType = typeof(GastroApp.Pages.Cash);
var rowType = pageType.GetNestedType("CountRow", flags)!;
object NewPage(AuthService auth, TestNavigation nav)
{
    var page = Activator.CreateInstance(pageType)!;
    pageType.GetProperty("AuthService", flags)!.SetValue(page, auth);
    pageType.GetProperty("Navigation", flags)!.SetValue(page, nav);
    pageType.GetProperty("CashService", flags)!.SetValue(page, ucash);
    ((Task)pageType.GetMethod("OnInitializedAsync", flags)!.Invoke(page, null)!).GetAwaiter().GetResult();
    return page;
}
object? F(object page, string name) => pageType.GetField(name, flags)!.GetValue(page);
void Set(object page, string name, object? value) => pageType.GetField(name, flags)!.SetValue(page, value);
void Call(object page, string name) => pageType.GetMethod(name, flags)!.Invoke(page, null);
void Rows(object page, params (string Denomination, string Quantity)[] rows)
{
    var list = (IList)F(page, "countRows")!;
    list.Clear();
    foreach (var (d, q) in rows)
    {
        var row = Activator.CreateInstance(rowType)!;
        rowType.GetProperty("Denomination")!.SetValue(row, d);
        rowType.GetProperty("Quantity")!.SetValue(row, q);
        list.Add(row);
    }
}
string UState() => Json(new { us.CashRegisters, us.CashMovements, us.CashCounts, us.Summaries });
string? Err(object page) => (string?)F(page, "countError");
bool Is(object page, string name) => (bool)F(page, name)!;
string sep = System.Globalization.CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator;
void NoMutation(object page, string action, string name)
{
    us.SaveToFile();
    var state = UState(); var bytes = File.ReadAllBytes("data.json");
    Call(page, action);
    Check(state == UState() && bytes.SequenceEqual(File.ReadAllBytes("data.json")), name + " leaves the stored state unchanged");
}

var navA = new TestNavigation(); var navB = new TestNavigation(); var navE = new TestNavigation();
ucash.Open(100m);
var regA = ucash.GetCurrent()!;
var pageA = NewPage(authA, navA); var pageB = NewPage(authB, navB);
Check(F(pageA, "countReview") is CashCountReview snap && snap == ucash.GetCountReview() && ((IList)F(pageA, "countRows")!).Count == 1, "page captures the review snapshot on init and starts with one empty row");
Check(F(pageB, "countReview") is CashCountReview snapB && snapB == ucash.GetCountReview(), "second circuit holds its own snapshot");

// Review step rejects bad rows without mutation.
foreach (var (rows, name) in new ((string, string)[], string)[] {
    ([("abc", "1")], "unparseable denomination"), ([("10", "")], "missing quantity"), ([("", "3")], "missing denomination"),
    ([("10", "x")], "unparseable quantity"), ([("0", "1")], "zero denomination"), ([("-5", "1")], "negative denomination"),
    ([("5", "-1")], "negative quantity"), ([("5", "1"), ("05", "2")], "duplicate denomination"),
    ([("1" + sep + "5", "1"), ("1" + sep + "50", "1")], "duplicate decimal denomination"),
    ([("79228162514264337593543950335", "2")], "subtotal overflow"), ([("10", "1"), ("", ""), ("20", "")], "partial row among blanks") })
{
    Rows(pageA, rows); Set(pageA, "countReason", "motivo");
    NoMutation(pageA, "ReviewClose", "review with " + name);
    Check(!Is(pageA, "confirmingClose") && !string.IsNullOrEmpty(Err(pageA)), "review with " + name + " shows an error and stays out of confirmation");
}
Rows(pageA, ("100", "0")); Set(pageA, "countReason", "   ");
NoMutation(pageA, "ReviewClose", "difference without reason");
Check(!Is(pageA, "confirmingClose") && !string.IsNullOrEmpty(Err(pageA)), "difference without reason blocks review");
Rows(pageA, ("100", "1")); Set(pageA, "countReason", null);
NoMutation(pageA, "ReviewClose", "exact review");
Check(Is(pageA, "confirmingClose") && Err(pageA) == null, "valid exact review enters confirmation without reason");
Call(pageA, "ResetConfirmation");
Check(!Is(pageA, "confirmingClose") && !Is(pageA, "zeroConfirmed"), "editing exits confirmation and clears the zero checkbox");
Call(pageA, "CloseCash"); // not confirmed: the page refuses to submit
Check(Is(pageA, "confirmingClose") == false && ucash.IsOpen() && us.CashCounts.Count == 0, "unconfirmed close never reaches the service");
Call(pageA, "ReviewClose");
Check(Is(pageA, "confirmingClose"), "exact review confirmed again before the concurrency checks");

// Another movement after the review: both circuits must detect it and adopt the fresh snapshot.
ucash.AddManualMovement(CashMovementType.Income, 5m, "ingreso", us.Users[0]);
NoMutation(pageA, "CloseCash", "stale confirm");
Check(us.CashCounts.Count == 0 && ucash.IsOpen() && F(pageA, "countReview") is CashCountReview fresh1 && fresh1 == ucash.GetCountReview()
    && !Is(pageA, "confirmingClose") && F(pageA, "countNotice") is string notice && notice.Contains("mientras contabas") && Err(pageA) == null,
    "stale CloseCash adopts the fresh review, exits confirmation and shows the stale message without closing");
Rows(pageB, ("100", "1")); Set(pageB, "countReason", "x");
NoMutation(pageB, "ReviewClose", "review against an old snapshot");
Check(!Is(pageB, "confirmingClose") && F(pageB, "countNotice") is string noticeB && noticeB.Contains("mientras contabas"), "stale snapshot is detected at review time");
Call(pageB, "RefreshCountReview");
Check(F(pageB, "countReview") is CashCountReview adopted && adopted == ucash.GetCountReview() && F(pageB, "countNotice") == null && !Is(pageB, "confirmingClose"), "explicit refresh adopts the fresh review");

// Zero count needs the checkbox and keeps the session open until it is set.
Rows(pageA, ("", "")); Set(pageA, "countReason", "caja vac\u00eda");
Call(pageA, "ReviewClose");
Check(Is(pageA, "confirmingClose") && Err(pageA) == null, "zero count with a reason reaches confirmation");
NoMutation(pageA, "CloseCash", "zero count without checkbox");
Check(!string.IsNullOrEmpty(Err(pageA)) && ucash.IsOpen() && us.CashCounts.Count == 0, "zero count without checkbox is rejected by the service");
Set(pageA, "zeroConfirmed", true);
Call(pageA, "CloseCash");
var zeroCount = ucash.GetCount(regA.Id);
Check(zeroCount != null && !ucash.IsOpen() && zeroCount.CountedAmount == 0m && zeroCount.Difference == -105m && zeroCount.Reason == "caja vac\u00eda"
    && zeroCount.UserId == 10 && zeroCount.Username == "fixture-admin", "zero count with checkbox closes with the clicking admin's attribution");
Check(navA.Destination == null && Err(pageA) == null && (string?)F(pageA, "closeMessage") == "Caja cerrada. Arqueo registrado."
    && F(pageA, "countReview") == null && ((IList)F(pageA, "countRows")!).Count == 1 && !Is(pageA, "confirmingClose") && !Is(pageA, "zeroConfirmed"),
    "success stays on /cash, clears the form and shows the status message");
Check(ReferenceEquals(F(pageA, "cashRegister"), us.CurrentCashRegister), "page shows the closed current session after close");

// Two admins: the second admin closes, the first admin's confirmed page is rejected.
ucash.Open(50m);
var regB = ucash.GetCurrent()!;
var pageA2 = NewPage(authA, new TestNavigation()); var pageB2 = NewPage(authB, navB = new TestNavigation());
foreach (var page in new[] { pageA2, pageB2 }) { Rows(page, ("50", "1")); Call(page, "ReviewClose"); }
Check(Is(pageA2, "confirmingClose") && Is(pageB2, "confirmingClose"), "both circuits reach confirmation");
Call(pageB2, "CloseCash");
var countB = ucash.GetCount(regB.Id);
Check(countB != null && countB.UserId == 11 && countB.Username == "second-admin" && countB.Difference == 0m && countB.Reason == null && navB.Destination == null, "exact close attributed to the clicking admin without reason");
NoMutation(pageA2, "CloseCash", "confirm after the other admin closed");
Check(!string.IsNullOrEmpty(Err(pageA2)) && us.CashCounts.Count == 2, "the other admin's confirmation is rejected with an error");

// Employee, demoted and invalidated actors are redirected without mutation.
ucash.Open(10m);
TestNavigation Nav(object page) { var nav = new TestNavigation(); pageType.GetProperty("Navigation", flags)!.SetValue(page, nav); return nav; }
var pageE = NewPage(authE, new TestNavigation());
var navE2 = Nav(pageE);
Set(pageE, "countReview", ucash.GetCountReview()); Set(pageE, "confirmingClose", true);
Rows(pageE, ("10", "1"));
NoMutation(pageE, "ReviewClose", "employee review");
Check(navE2.Destination == "/unauthorized", "employee review is redirected to /unauthorized");
navE2 = Nav(pageE);
Set(pageE, "confirmingClose", true);
NoMutation(pageE, "CloseCash", "employee close");
Check(navE2.Destination == "/unauthorized" && ucash.IsOpen(), "employee close is redirected to /unauthorized");
var pageD = NewPage(authA, new TestNavigation());
Rows(pageD, ("10", "1")); Call(pageD, "ReviewClose");
Check(Is(pageD, "confirmingClose"), "admin reaches confirmation before demotion");
us.Users[0].Role = UserRole.Employee;
var navD = Nav(pageD);
NoMutation(pageD, "CloseCash", "demoted admin close");
Check(navD.Destination == "/unauthorized" && ucash.IsOpen(), "action-time demotion is redirected without closing");
us.Users[0].Role = UserRole.Admin;
us.Users[0].PasswordHash = "changed";
navD = Nav(pageD);
NoMutation(pageD, "CloseCash", "password-invalidated close");
Check(navD.Destination == "/login" && ucash.IsOpen() && authB.IsAuthenticated, "password invalidation redirects to /login and leaves the other circuit logged in");
us.Users[0].PasswordHash = hash;
authA.Login("fixture-admin", "fixture-pass");
navD = Nav(pageD);
Rows(pageD, ("10", "1")); Call(pageD, "ReviewClose"); Call(pageD, "CloseCash");
var countC = ucash.GetCount(ucash.GetCurrent()!.Id);
Check(countC != null && countC.UserId == 10 && !ucash.IsOpen() && navD.Destination == null && us.CashCounts.Count == 3 && us.Summaries.Last().CashRegisterId == countC.CashRegisterId, "recovered admin closes normally and no navigation occurs");

var source = File.ReadAllText(Path.Combine(args[0], "Pages", "Cash.razor"));
foreach (var text in new[] { "Faltante", "Sobrante", "Exacto", "Arqueo registrado", "sin arqueo detallado", "Arqueo y cierre de caja", "Revisar cierre",
    "Confirmar cierre definitivo", "Volver a editar", "Agregar denominaci\u00f3n", "Quitar", "Actualizar saldo esperado",
    "Confirmo que el efectivo contado es cero", "Caja cerrada. Arqueo registrado.", "Ver resumen del d\u00eda", "Sin motivo (cierre exacto)",
    "overflow-x: auto", "mientras contabas" })
    Check(source.Contains(text), "page source contains: " + text);
Check(source.Contains("inputmode=\"decimal\"") && source.Contains("inputmode=\"numeric\"") && source.Contains("role=\"alert\"") && source.Contains("role=\"status\""), "page source has numeric inputmodes and alert/status roles");
Check(!System.Text.RegularExpressions.Regex.IsMatch(source, @"NavigateTo\([^;]*,\s*true\)") && !source.Contains("finalAmount"), "page never forces reload and no manual final amount remains");
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
    & dotnet run --project (Join-Path $ScratchPath 'CountChecks.csproj') -- $repo
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $after = (& git -C $repo hash-object GastroApp.csproj data.json)
    if (($before -join ',') -ne ($after -join ',')) { throw 'Live GastroApp.csproj or data.json changed.' }
    Write-Host "Live csproj/data.json unchanged: $($after -join ' / ')"
}
if ($exitCode -ne 0) { throw "Cash count checks failed (exit $exitCode). Scratch retained: $ScratchPath" }
