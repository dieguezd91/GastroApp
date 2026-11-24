using GastroApp.Models;
using System.Text.Json;

namespace GastroApp.Services;

public class DataStorageService
{
    public List<Product> Products { get; set; } = new();
    public List<ProductCategory> ProductCategories { get; set; } = new();
    public List<Sale> Sales { get; set; } = new();
    // Append-only refund ledger; sales themselves are never deleted or rewritten by a refund.
    public List<SaleRefund> SaleRefunds { get; private set; } = new();
    // Append-only stock ledger (M15). Only IngredientService changes it, together with CurrentStock.
    public List<StockMovement> StockMovements { get; private set; } = new();
    // Physical counts (M15). Created only by StockCountService together with their CountAdjustment movements.
    public List<StockCount> StockCounts { get; private set; } = new();
    public List<CashRegister> CashRegisters { get; private set; } = new();
    public List<CashMovement> CashMovements { get; private set; } = new();
    public List<CashCount> CashCounts { get; private set; } = new();
    public int? CurrentCashRegisterId { get; private set; }
    public CashRegister? CurrentCashRegister => CashRegisters.FirstOrDefault(r => r.Id == CurrentCashRegisterId);
    public List<DailySummary> Summaries { get; set; } = new();
    public List<User> Users { get; set; } = new();

    // Nuevas entidades
    public List<Ingredient> Ingredients { get; set; } = new();
    public List<Supplier> Suppliers { get; set; } = new();
    public List<Invoice> Invoices { get; set; } = new();
    public List<Recipe> Recipes { get; set; } = new();

    // The business's own fiscal data (one business per installation); only BusinessSettingsService changes it.
    public BusinessSettings BusinessSettings { get; private set; } = new();

    private int _nextProductId = 1;
    private int _nextProductCategoryId = 1;
    private int _nextSaleId = 1;
    private int _nextSaleRefundId = 1;
    private int _nextStockMovementId = 1;
    private int _nextStockCountId = 1;
    private int _nextCashRegisterId = 1;
    private int _nextCashMovementId = 1;
    private int _nextUserId = 1;
    private int _nextIngredientId = 1;
    private int _nextSupplierId = 1;
    private int _nextInvoiceId = 1;
    private int _nextRecipeId = 1;

    private readonly string _dataFilePath = "data.json";

    public int GetNextProductId() => _nextProductId++;
    public int GetNextProductCategoryId() => _nextProductCategoryId++;
    public int GetNextSaleId() => Allocate(ref _nextSaleId, "ventas");
    public int GetNextSaleRefundId() => Allocate(ref _nextSaleRefundId, "devoluciones");
    public int GetNextStockMovementId() => Allocate(ref _nextStockMovementId, "movimientos de stock");

    // Allocates the ID and appends the count; the caller either saves or calls DiscardStockCount.
    internal void AddStockCount(StockCount count)
    {
        count.Id = Allocate(ref _nextStockCountId, "conteos de stock");
        StockCounts.Add(count);
    }

    // Undoes AddStockCount when the count could not be completed, so a rejection leaves no trace.
    internal void DiscardStockCount(StockCount count)
    {
        if (!StockCounts.Remove(count)) return;
        if (_nextStockCountId == count.Id + 1) _nextStockCountId = count.Id;
    }

    // Fail before checkout or opening mutates state; int.MaxValue cannot be followed by a valid counter.
    private static int Allocate(ref int next, string name)
    {
        if (next <= 0 || next == int.MaxValue)
            throw new InvalidOperationException($"Se agotaron los identificadores de {name}.");
        return next++;
    }

    public void EnsureSaleCapacity() => EnsureCapacity(_nextSaleId, "ventas");
    public void EnsureCashMovementCapacity() => EnsureCapacity(_nextCashMovementId, "movimientos de caja");
    public void EnsureSaleRefundCapacity() => EnsureCapacity(_nextSaleRefundId, "devoluciones");
    // Room for `count` more ledger entries, so a batch can be rejected before anything changes.
    public void EnsureStockMovementCapacity(int count = 1)
    {
        if (_nextStockMovementId <= 0 || (long)_nextStockMovementId + count > int.MaxValue)
            throw new InvalidOperationException("Se agotaron los identificadores de movimientos de stock.");
    }
    private static void EnsureCapacity(int next, string name)
    {
        if (next <= 0 || next == int.MaxValue)
            throw new InvalidOperationException($"Se agotaron los identificadores de {name}.");
    }

    public CashRegister OpenCashRegister(decimal initialAmount)
    {
        if (initialAmount < 0m)
            throw new InvalidOperationException("El monto inicial no puede ser negativo.");
        if (CashRegisters.Any(r => r.IsOpen))
            throw new InvalidOperationException("Ya hay una caja abierta.");
        var id = Allocate(ref _nextCashRegisterId, "cajas");
        var register = new CashRegister { Id = id, OpenDate = DateTime.Now,
            InitialAmount = initialAmount, IsOpen = true };
        CashRegisters.Add(register);
        CurrentCashRegisterId = id;
        SaveToFile();
        return register;
    }

    public int GetNextCashMovementId() => Allocate(ref _nextCashMovementId, "movimientos de caja");

    public decimal GetCashInflow(int registerId) => CashMovements
        .Where(m => m.CashRegisterId == registerId
            && (m.Type == CashMovementType.Sale || m.Type == CashMovementType.Income))
        .Sum(m => m.Amount);

    // Sale and Income add cash; Expense, Withdrawal and Refund take it out.
    public decimal GetExpectedCash(int registerId)
    {
        var register = CashRegisters.FirstOrDefault(r => r.Id == registerId)
            ?? throw new InvalidOperationException("La caja no existe.");
        return CashMovements.Where(m => m.CashRegisterId == registerId)
            .Aggregate(register.InitialAmount, (balance, m) => checked(balance +
                (m.Type == CashMovementType.Sale || m.Type == CashMovementType.Income
                    ? m.Amount : -m.Amount)));
    }
    // Trusted in-process boundary: revalidates identity and live Admin role against stored users.
    public User RequireLiveAdmin(User? actor)
    {
        var user = actor == null ? null : Users.FirstOrDefault(u => u.Id == actor.Id);
        if (user == null || user.Id <= 0 || string.IsNullOrWhiteSpace(user.Username)
            || string.IsNullOrWhiteSpace(user.PasswordHash) || user.Username != actor!.Username
            || user.PasswordHash != actor.PasswordHash || user.Role != UserRole.Admin
            || actor.Role != UserRole.Admin)
            throw new UnauthorizedAccessException("Se requiere un usuario administrador vigente.");
        return user;
    }

    // The stored user matching every identity field of the actor, or null (also for a blank stored username).
    internal User? FindLiveUser(User? actor)
    {
        if (actor == null) return null;
        var user = Users.FirstOrDefault(u => u.Id == actor.Id && u.Username == actor.Username
            && u.PasswordHash == actor.PasswordHash && u.Role == actor.Role);
        return user == null || string.IsNullOrWhiteSpace(user.Username) ? null : user;
    }

    public int GetNextUserId() => _nextUserId++;
    public int GetNextIngredientId() => _nextIngredientId++;
    public int GetNextSupplierId() => _nextSupplierId++;
    public int GetNextInvoiceId() => _nextInvoiceId++;
    public int GetNextRecipeId() => _nextRecipeId++;

    public DataStorageService()
    {
        // Intentar cargar datos del archivo
        LoadFromFile();

        // Si no hay datos, crear datos de ejemplo. Un sistema reiniciado (ResetAll) conserva al administrador y
        // no debe volver a sembrarse: solo se siembra cuando tampoco hay usuarios.
        if (Products.Count == 0 && Users.Count == 0)
        {
            SeedData();
            SaveToFile();
        }
    }

    private void SeedData()
    {
        Products.Add(new Product { Id = GetNextProductId(), Name = "Café", Price = 150, Cost = 50 });
        Products.Add(new Product { Id = GetNextProductId(), Name = "Medialunas", Price = 100, Cost = 40 });
        Products.Add(new Product { Id = GetNextProductId(), Name = "Sandwich", Price = 300, Cost = 120 });

        // Usuario admin por defecto
        Users.Add(new User
        {
            Id = GetNextUserId(),
            Username = "admin",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("admin"),
            Role = UserRole.Admin
        });

        // Seed de ingredientes
        var harinaId = GetNextIngredientId();
        var lecheId = GetNextIngredientId();
        var huevoId = GetNextIngredientId();
        var mantecaId = GetNextIngredientId();

        Ingredients.Add(new Ingredient { Id = harinaId, Name = "Harina 000", Unit = "kg", IsActive = true });
        Ingredients.Add(new Ingredient { Id = lecheId, Name = "Leche", Unit = "lt", IsActive = true });
        Ingredients.Add(new Ingredient { Id = huevoId, Name = "Huevos", Unit = "unidad", IsActive = true });
        Ingredients.Add(new Ingredient { Id = mantecaId, Name = "Manteca", Unit = "kg", IsActive = true });

        // Seed de proveedores
        var provId = GetNextSupplierId();
        Suppliers.Add(new Supplier { Id = provId, Name = "Distribuidora San Martín", Cuit = "30712345671", TaxCondition = TaxCondition.ResponsableInscripto });

        // Seed de factura con precios
        var facturaId = GetNextInvoiceId();
        Invoices.Add(new Invoice
        {
            Id = facturaId,
            Date = DateTime.Now.AddDays(-5),
            SupplierId = provId,
            InvoiceNumber = "A-0001-00001234",
            Notes = "Primera compra de ingredientes",
            Type = InvoiceType.A,
            Items = new List<InvoiceItem>
            {
                new InvoiceItem { InvoiceId = facturaId, IngredientId = harinaId, IngredientName = "Harina 000", Quantity = 10, Unit = "kg", UnitPrice = 80, VatRate = 10.5m },
                new InvoiceItem { InvoiceId = facturaId, IngredientId = lecheId, IngredientName = "Leche", Quantity = 5, Unit = "lt", UnitPrice = 120, VatRate = 21m },
                new InvoiceItem { InvoiceId = facturaId, IngredientId = huevoId, IngredientName = "Huevos", Quantity = 30, Unit = "unidad", UnitPrice = 15, VatRate = 21m },
                new InvoiceItem { InvoiceId = facturaId, IngredientId = mantecaId, IngredientName = "Manteca", Quantity = 2, Unit = "kg", UnitPrice = 350, VatRate = 21m }
            }
        });

        // Seed de receta de ejemplo
        var recetaId = GetNextRecipeId();
        Recipes.Add(new Recipe
        {
            Id = recetaId,
            Name = "Medialunas Caseras",
            Yield = 12,
            CreatedAt = DateTime.Now,
            Ingredients = new List<RecipeIngredient>
            {
                new RecipeIngredient { RecipeId = recetaId, IngredientId = harinaId, IngredientName = "Harina 000", Quantity = 0.5m, Unit = "kg", UnitPrice = 80, Subtotal = 40 },
                new RecipeIngredient { RecipeId = recetaId, IngredientId = lecheId, IngredientName = "Leche", Quantity = 0.2m, Unit = "lt", UnitPrice = 120, Subtotal = 24 },
                new RecipeIngredient { RecipeId = recetaId, IngredientId = huevoId, IngredientName = "Huevos", Quantity = 2, Unit = "unidad", UnitPrice = 15, Subtotal = 30 },
                new RecipeIngredient { RecipeId = recetaId, IngredientId = mantecaId, IngredientName = "Manteca", Quantity = 0.1m, Unit = "kg", UnitPrice = 350, Subtotal = 35 }
            },
            TotalCost = 129,
            UnitCost = 10.75m,
            CostIndicator = "green"
        });
    }

    public void SaveToFile()
    {
        try
        {
            File.WriteAllText(_dataFilePath, SerializeState(null));
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error guardando datos: {ex.Message}");
        }
    }

    // The persisted document. With keptUsers it is the state after ResetAll: every business collection empty,
    // no current register, only those users, counters unchanged. Without it, the live state.
    private string SerializeState(List<User>? keptUsers)
    {
        var cleared = keptUsers != null;
        List<T> Pick<T>(List<T> live) => cleared ? new List<T>() : live;
        var data = new
        {
            Products = Pick(Products),
            ProductCategories = Pick(ProductCategories),
            Sales = Pick(Sales),
            SaleRefunds = Pick(SaleRefunds),
            StockMovements = Pick(StockMovements),
            StockCounts = Pick(StockCounts),
            CashRegisters = Pick(CashRegisters),
            CashMovements = Pick(CashMovements),
            CashCounts = Pick(CashCounts),
            CurrentCashRegisterId = cleared ? null : CurrentCashRegisterId,
            Summaries = Pick(Summaries),
            Users = keptUsers ?? Users,
            Ingredients = Pick(Ingredients),
            Suppliers = Pick(Suppliers),
            Invoices = Pick(Invoices),
            Recipes = Pick(Recipes),
            BusinessSettings = cleared ? new BusinessSettings() : BusinessSettings,
            NextProductId = _nextProductId,
            NextProductCategoryId = _nextProductCategoryId,
            NextSaleId = _nextSaleId,
            NextSaleRefundId = _nextSaleRefundId,
            NextStockMovementId = _nextStockMovementId,
            NextStockCountId = _nextStockCountId,
            NextCashRegisterId = _nextCashRegisterId,
            NextCashMovementId = _nextCashMovementId,
            NextUserId = _nextUserId,
            NextIngredientId = _nextIngredientId,
            NextSupplierId = _nextSupplierId,
            NextInvoiceId = _nextInvoiceId,
            NextRecipeId = _nextRecipeId
        };

        return JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
    }

    // Irreversible: empties every business collection and every user except the acting admin, then persists.
    // Order: validate the live admin -> build the new document -> copy data.json to data.backup-<yyyyMMdd-HHmmss>.json
    // -> replace data.json atomically -> only then empty the memory. A failure at any step before the last leaves
    // memory and data.json as they were (and removes the backup this call created). ID counters keep running.
    // Returns the backup file name (next to data.json).
    public string ResetAll(User? actor)
    {
        var admin = RequireLiveAdmin(actor);
        var keptUsers = new List<User> { admin };
        var emptyDocument = SerializeState(keptUsers);

        var dataPath = Path.GetFullPath(_dataFilePath);
        var backupName = $"data.backup-{DateTime.Now:yyyyMMdd-HHmmss}.json";
        var backupPath = Path.Combine(Path.GetDirectoryName(dataPath)!, backupName);
        var tempPath = dataPath + ".reset.tmp";

        var backupCreated = false;
        try
        {
            try
            {
                if (File.Exists(dataPath))
                {
                    using var source = new FileStream(dataPath, FileMode.Open, FileAccess.Read, FileShare.Read);
                    using var backup = new FileStream(backupPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                    backupCreated = true;
                    source.CopyTo(backup);
                }
                else
                {
                    using var backup = new FileStream(backupPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                    backupCreated = true;
                    using var writer = new StreamWriter(backup);
                    writer.Write(SerializeState(null));
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                throw new InvalidOperationException(
                    $"No se pudo crear la copia de seguridad {backupName}; no se modificó ningún dato. {ex.Message}", ex);
            }

            try
            {
                File.WriteAllText(tempPath, emptyDocument);
                File.Move(tempPath, dataPath, overwrite: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                throw new InvalidOperationException(
                    $"No se pudo guardar el reinicio; no se modificó ningún dato. {ex.Message}", ex);
            }
        }
        catch
        {
            TryDelete(tempPath);
            if (backupCreated) TryDelete(backupPath);
            throw;
        }

        Products = new();
        ProductCategories = new();
        Sales = new();
        SaleRefunds = new();
        StockMovements = new();
        StockCounts = new();
        CashRegisters = new();
        CashMovements = new();
        CashCounts = new();
        CurrentCashRegisterId = null;
        Summaries = new();
        Users = keptUsers;
        Ingredients = new();
        Suppliers = new();
        Invoices = new();
        Recipes = new();
        BusinessSettings = new();
        return backupName;
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (Exception) { /* best effort: only files this call created */ }
    }

    private static int RecoverNext(JsonElement root, string property, IEnumerable<int> ids)
    {
        var seen = new HashSet<int>();
        foreach (var id in ids)
        {
            if (id <= 0 || !seen.Add(id))
                throw new InvalidDataException($"Identidad inválida o duplicada en {property}.");
        }
        var maximum = seen.Count == 0 ? 0 : seen.Max();
        if (maximum == int.MaxValue)
            throw new InvalidDataException($"Identificadores agotados en {property}.");
        var saved = root.TryGetProperty(property, out var element)
            ? element.GetInt32() : 1;
        if (saved <= 0 || saved == int.MaxValue)
            throw new InvalidDataException($"Contador inválido en {property}.");
        return Math.Max(saved, maximum + 1);
    }

    // Closed registers without a count are historical and valid; a count must mirror its closed register.
    private static void ValidateCashCounts(List<CashCount> counts, List<CashRegister> registers)
    {
        var seen = new HashSet<int>();
        foreach (var count in counts)
        {
            if (count == null)
                throw new InvalidDataException("CashCounts contiene un arqueo null.");
            var register = registers.FirstOrDefault(r => r.Id == count.CashRegisterId)
                ?? throw new InvalidDataException("Arqueo de una caja inexistente.");
            if (!seen.Add(count.CashRegisterId))
                throw new InvalidDataException("Hay varios arqueos para la misma caja.");
            if (register.IsOpen)
                throw new InvalidDataException("Una caja abierta no puede tener arqueo.");
            var total = CashCountCalculator.ValidateStored(count.Lines);
            if (count.CountedAmount != total || count.Difference != checked(count.CountedAmount - count.ExpectedAmount))
                throw new InvalidDataException("Los totales del arqueo no coinciden con su detalle.");
            if (register.FinalAmount != count.CountedAmount || register.ExpectedAmount != count.ExpectedAmount)
                throw new InvalidDataException("El arqueo no coincide con el cierre de su caja.");
        }
    }

    private void LoadCashState(JsonElement root)
    {
        // A canonical list, even an empty one, takes precedence over the old single object.
        var registers = root.TryGetProperty("CashRegisters", out var registersElement)
            ? JsonSerializer.Deserialize<List<CashRegister>>(registersElement.GetRawText())
                ?? throw new InvalidDataException("CashRegisters no puede ser null.")
            : new List<CashRegister>();
        if (!root.TryGetProperty("CashRegisters", out _) &&
            root.TryGetProperty("CurrentCashRegister", out var legacyElement) &&
            legacyElement.ValueKind != JsonValueKind.Null)
        {
            var legacy = JsonSerializer.Deserialize<CashRegister>(legacyElement.GetRawText())
                ?? throw new InvalidDataException("Caja histórica inválida.");
            // Legacy zero (including a missing ID) predates session identity; negative IDs remain invalid.
            if (legacy.Id == 0) legacy.Id = 1;
            registers.Add(legacy);
        }
        var movements = root.TryGetProperty("CashMovements", out var movementsElement)
            ? JsonSerializer.Deserialize<List<CashMovement>>(movementsElement.GetRawText())
                ?? throw new InvalidDataException("CashMovements no puede ser null.")
            : new List<CashMovement>();
        // A missing property is a legacy file; an explicit null is corruption.
        var counts = root.TryGetProperty("CashCounts", out var countsElement)
            ? JsonSerializer.Deserialize<List<CashCount>>(countsElement.GetRawText())
                ?? throw new InvalidDataException("CashCounts no puede ser null.")
            : new List<CashCount>();
        if (registers.Any(r => r == null))
            throw new InvalidDataException("CashRegisters contiene una caja null.");
        if (movements.Any(m => m == null))
            throw new InvalidDataException("CashMovements contiene un movimiento null.");
        var nextRegister = RecoverNext(root, "NextCashRegisterId", registers.Select(r => r.Id));
        var nextMovement = RecoverNext(root, "NextCashMovementId", movements.Select(m => m.Id));
        if (registers.Count(r => r.IsOpen) > 1)
            throw new InvalidDataException("Hay varias cajas abiertas.");
        foreach (var movement in movements)
        {
            if (!registers.Any(r => r.Id == movement.CashRegisterId) || movement.Amount <= 0m
                || !Enum.IsDefined(typeof(CashMovementType), movement.Type))
                throw new InvalidDataException("Movimiento de caja inválido o sin caja.");
        }
        int? current = null;
        if (root.TryGetProperty("CurrentCashRegisterId", out var pointer)
            && pointer.ValueKind != JsonValueKind.Null)
            current = pointer.GetInt32();
        else if (registers.Count > 0)
            current = registers.FirstOrDefault(r => r.IsOpen)?.Id
                ?? registers.OrderByDescending(r => r.OpenDate).ThenByDescending(r => r.Id).First().Id;
        if (current.HasValue && !registers.Any(r => r.Id == current.Value))
            throw new InvalidDataException("La identidad de la caja actual no existe.");
        if (registers.Any(r => r.IsOpen && r.Id != current))
            throw new InvalidDataException("La caja abierta no coincide con la caja actual.");

        ValidateCashCounts(counts, registers);

        CashRegisters = registers;
        CashMovements = movements;
        CashCounts = counts;
        CurrentCashRegisterId = current;
        _nextCashRegisterId = nextRegister;
        _nextCashMovementId = nextMovement;
    }

    // A missing list is a legacy file; an explicit null or inconsistent refund is corruption.
    private void LoadRefundState(JsonElement root)
    {
        var refunds = root.TryGetProperty("SaleRefunds", out var refundsElement)
            ? JsonSerializer.Deserialize<List<SaleRefund>>(refundsElement.GetRawText())
                ?? throw new InvalidDataException("SaleRefunds no puede ser null.")
            : new List<SaleRefund>();
        if (refunds.Any(r => r == null))
            throw new InvalidDataException("SaleRefunds contiene una devolucion null.");
        var next = RecoverNext(root, "NextSaleRefundId", refunds.Select(r => r.Id));
        ValidateRefunds(refunds);
        SaleRefunds = refunds;
        _nextSaleRefundId = next;
    }

    private void ValidateRefunds(List<SaleRefund> refunds)
    {
        var units = new Dictionary<(int SaleId, int Index), int>();
        var totals = new Dictionary<int, decimal>();
        foreach (var refund in refunds)
        {
            var sale = Sales.FirstOrDefault(s => s != null && s.Id == refund.SaleId)
                ?? throw new InvalidDataException("Devolucion de una venta inexistente.");
            if (sale.Status != SaleStatus.Completed)
                throw new InvalidDataException("Una venta con devoluciones no puede estar anulada.");
            if (refund.UserId <= 0 || string.IsNullOrWhiteSpace(refund.Username) || string.IsNullOrWhiteSpace(refund.Reason))
                throw new InvalidDataException("Devolucion sin responsable o motivo.");
            if (refund.CashRegisterId.HasValue && !CashRegisters.Any(r => r.Id == refund.CashRegisterId.Value))
                throw new InvalidDataException("Devolucion de una caja inexistente.");
            if (refund.Lines == null || refund.Lines.Count == 0 || refund.Payments == null || refund.Total < 0m)
                throw new InvalidDataException("Devolucion sin lineas o con total invalido.");

            var seenLines = new HashSet<int>();
            decimal lineTotal = 0m;
            foreach (var line in refund.Lines)
            {
                if (line == null || sale.Items == null || line.SaleItemIndex < 0 || line.SaleItemIndex >= sale.Items.Count
                    || sale.Items[line.SaleItemIndex] == null || line.Quantity <= 0 || line.Amount < 0m
                    || !Enum.IsDefined(typeof(RefundDisposition), line.Disposition) || !seenLines.Add(line.SaleItemIndex))
                    throw new InvalidDataException("Linea de devolucion invalida.");
                var key = (sale.Id, line.SaleItemIndex);
                var refunded = checked(units.GetValueOrDefault(key) + line.Quantity);
                if (refunded > sale.Items[line.SaleItemIndex].Quantity)
                    throw new InvalidDataException("La devolucion supera las unidades vendidas.");
                units[key] = refunded;
                lineTotal = checked(lineTotal + line.Amount);
            }

            var seenMethods = new HashSet<PaymentMethod>();
            decimal paymentTotal = 0m;
            foreach (var payment in refund.Payments)
            {
                if (payment == null || !Enum.IsDefined(typeof(PaymentMethod), payment.PaymentMethod)
                    || payment.Amount <= 0m || !seenMethods.Add(payment.PaymentMethod))
                    throw new InvalidDataException("Pago de devolucion invalido.");
                paymentTotal = checked(paymentTotal + payment.Amount);
            }
            if (lineTotal != refund.Total || paymentTotal != refund.Total)
                throw new InvalidDataException("Los importes de la devolucion no coinciden con su total.");
            var cumulative = checked(totals.GetValueOrDefault(sale.Id) + refund.Total);
            if (cumulative > sale.Total)
                throw new InvalidDataException("Las devoluciones superan el total de la venta.");
            totals[sale.Id] = cumulative;
        }
    }

    private void LoadRefundStateGuarded(JsonElement root)
    {
        try { LoadRefundState(root); }
        catch (Exception ex) when (ex is JsonException or FormatException or OverflowException or InvalidOperationException)
        {
            throw new InvalidDataException("Contenido de devoluciones invalido.", ex);
        }
    }

    // A missing list is a legacy file; an explicit null or inconsistent entry is corruption. Ingredients and
    // invoices may be deleted after the fact, so only the (never deleted) sale and refund links must resolve.
    private void LoadStockMovementState(JsonElement root)
    {
        var movements = root.TryGetProperty("StockMovements", out var movementsElement)
            ? JsonSerializer.Deserialize<List<StockMovement>>(movementsElement.GetRawText())
                ?? throw new InvalidDataException("StockMovements no puede ser null.")
            : new List<StockMovement>();
        if (movements.Any(m => m == null))
            throw new InvalidDataException("StockMovements contiene un movimiento null.");
        var next = RecoverNext(root, "NextStockMovementId", movements.Select(m => m.Id));
        ValidateStockMovements(movements);
        StockMovements = movements;
        _nextStockMovementId = next;
    }

    private void ValidateStockMovements(List<StockMovement> movements)
    {
        foreach (var m in movements)
        {
            if (!Enum.IsDefined(typeof(StockMovementType), m.Type) || m.IngredientId <= 0
                || m.Quantity == 0m || string.IsNullOrWhiteSpace(m.Unit))
                throw new InvalidDataException("Movimiento de stock inválido.");
            var increases = m.Type is StockMovementType.InvoiceReceipt or StockMovementType.SaleCancellationReturn
                or StockMovementType.RefundReturn or StockMovementType.InitialStock;
            var decreases = m.Type is StockMovementType.SaleConsumption or StockMovementType.Waste;
            if ((increases && m.Quantity < 0m) || (decreases && m.Quantity > 0m))
                throw new InvalidDataException("El signo del movimiento de stock no corresponde a su tipo.");
            if (checked(m.PreviousStock + m.Quantity) != m.ResultingStock)
                throw new InvalidDataException("Los saldos del movimiento de stock no coinciden con su cantidad.");
            var needsReason = m.Type is StockMovementType.Adjustment or StockMovementType.Waste
                or StockMovementType.CountAdjustment;
            if (needsReason && string.IsNullOrWhiteSpace(m.Reason))
                throw new InvalidDataException("Movimiento de stock sin motivo.");
            if (m.Type == StockMovementType.Waste
                ? !m.WasteCategory.HasValue || !Enum.IsDefined(typeof(WasteCategory), m.WasteCategory.Value)
                : m.WasteCategory.HasValue)
                throw new InvalidDataException("Categoría de merma inválida.");
            if (m.UserId.HasValue != (m.Username != null)
                || (m.UserId.HasValue && (m.UserId.Value <= 0 || string.IsNullOrWhiteSpace(m.Username))))
                throw new InvalidDataException("Movimiento de stock con responsable inválido.");
            var linked = m.Type switch
            {
                StockMovementType.SaleConsumption or StockMovementType.SaleCancellationReturn =>
                    m.SaleId.HasValue && Sales.Any(s => s != null && s.Id == m.SaleId.Value),
                StockMovementType.RefundReturn => m.SaleId.HasValue && m.RefundId.HasValue
                    && SaleRefunds.Any(r => r != null && r.Id == m.RefundId.Value && r.SaleId == m.SaleId.Value),
                StockMovementType.InvoiceReceipt => m.InvoiceId is > 0,
                StockMovementType.CountAdjustment => m.StockCountId is > 0,
                _ => true
            };
            if (!linked)
                throw new InvalidDataException("Movimiento de stock sin documento de origen válido.");
        }
    }

    private void LoadStockMovementStateGuarded(JsonElement root)
    {
        try { LoadStockMovementState(root); }
        catch (Exception ex) when (ex is JsonException or FormatException or OverflowException or InvalidOperationException)
        {
            throw new InvalidDataException("Contenido de movimientos de stock inválido.", ex);
        }
    }

    // A missing list is a legacy file; an explicit null or inconsistent count is corruption. Counts are never
    // deleted, so each line with a difference must still have its CountAdjustment movement. The reverse is not
    // required: movements may reference counts that were never persisted (ledger written before counts existed),
    // and their IDs stay reserved so a new count cannot reuse them.
    private void LoadStockCountState(JsonElement root)
    {
        var loaded = root.TryGetProperty("StockCounts", out var countsElement)
            ? JsonSerializer.Deserialize<List<StockCount>>(countsElement.GetRawText())
                ?? throw new InvalidDataException("StockCounts no puede ser null.")
            : new List<StockCount>();
        if (loaded.Any(c => c == null))
            throw new InvalidDataException("StockCounts contiene un conteo null.");
        var next = RecoverNext(root, "NextStockCountId", loaded.Select(c => c.Id));
        var referenced = StockMovements.Where(m => m.StockCountId.HasValue).Select(m => m.StockCountId!.Value).DefaultIfEmpty(0).Max();
        if (referenced == int.MaxValue)
            throw new InvalidDataException("Identificadores agotados en StockCounts.");
        ValidateStockCounts(loaded);
        StockCounts = loaded;
        _nextStockCountId = Math.Max(next, referenced + 1);
    }

    private void ValidateStockCounts(List<StockCount> loaded)
    {
        foreach (var count in loaded)
        {
            if (count.UserId <= 0 || string.IsNullOrWhiteSpace(count.Username))
                throw new InvalidDataException("Conteo de stock sin responsable.");
            if (count.Lines == null || count.Lines.Count == 0 || count.Lines.Any(l => l == null))
                throw new InvalidDataException("Conteo de stock sin líneas válidas.");
            var seen = new HashSet<int>();
            foreach (var line in count.Lines)
            {
                if (line.IngredientId <= 0 || !seen.Add(line.IngredientId) || string.IsNullOrWhiteSpace(line.IngredientName)
                    || string.IsNullOrWhiteSpace(line.Unit) || line.CountedStock < 0m
                    || checked(line.CountedStock - line.ExpectedStock) != line.Difference
                    || (line.Difference != 0m && string.IsNullOrWhiteSpace(line.Reason)))
                    throw new InvalidDataException("Línea de conteo de stock inválida.");
            }
            var adjusted = count.Lines.Where(l => l.Difference != 0m).ToList();
            if (count.AdjustedLineCount != adjusted.Count)
                throw new InvalidDataException("El conteo de stock no coincide con sus líneas ajustadas.");
            var movements = StockMovements.Where(m => m.StockCountId == count.Id).ToList();
            if (movements.Count != adjusted.Count || movements.Any(m => m.Type != StockMovementType.CountAdjustment)
                || !adjusted.All(l => movements.Any(m => m.IngredientId == l.IngredientId && m.Quantity == l.Difference
                    && m.PreviousStock == l.ExpectedStock && m.ResultingStock == l.CountedStock)))
                throw new InvalidDataException("El conteo de stock no coincide con sus movimientos.");
        }
    }

    private void LoadStockCountStateGuarded(JsonElement root)
    {
        try { LoadStockCountState(root); }
        catch (Exception ex) when (ex is JsonException or FormatException or OverflowException or InvalidOperationException)
        {
            throw new InvalidDataException("Contenido de conteos de stock inválido.", ex);
        }
    }

    // Legacy files simply lack the fiscal fields (CLR defaults). An explicit null list or an undefined enum can only come
    // from a hand-edited or corrupt file; loading it would break Invoice.Total and silently stop every later save.
    private void ValidatePurchasingFiscalData()
    {
        foreach (var supplier in Suppliers)
        {
            if (supplier != null && supplier.TaxCondition.HasValue && !Enum.IsDefined(supplier.TaxCondition.Value))
                throw new InvalidDataException("La condición frente al IVA de un proveedor no es válida.");
        }
        foreach (var invoice in Invoices)
        {
            if (invoice == null) continue;
            if (invoice.OtherTaxes == null)
                throw new InvalidDataException("Los tributos de una factura no pueden ser null.");
            if ((invoice.Type.HasValue && !Enum.IsDefined(invoice.Type.Value)) || !Enum.IsDefined(invoice.Legend)
                || invoice.OtherTaxes.Any(t => t == null || !Enum.IsDefined(t.Kind)))
                throw new InvalidDataException("Datos fiscales de factura inválidos.");
        }
    }

    // A missing property is a legacy file (not configured); an explicit null or an undefined condition is corruption.
    private void LoadBusinessSettings(JsonElement root)
    {
        if (!root.TryGetProperty("BusinessSettings", out var element))
        {
            BusinessSettings = new();
            return;
        }

        try
        {
            var settings = JsonSerializer.Deserialize<BusinessSettings>(element.GetRawText())
                ?? throw new InvalidDataException("BusinessSettings no puede ser null.");
            if (settings.TaxCondition.HasValue && !Enum.IsDefined(settings.TaxCondition.Value))
                throw new InvalidDataException("La condición frente al IVA del negocio no es válida.");
            BusinessSettings = settings;
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("Contenido de datos fiscales inválido.", ex);
        }
    }

    public void LoadFromFile()
    {
        try
        {
            if (!File.Exists(_dataFilePath))
                return;

            var json = File.ReadAllText(_dataFilePath);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.TryGetProperty("Products", out var productsElement))
            {
                Products = JsonSerializer.Deserialize<List<Product>>(productsElement.GetRawText()) ?? new();
            }

            // Los archivos anteriores no tienen categorías ni su contador.
            ProductCategories = root.TryGetProperty("ProductCategories", out var categoriesElement)
                ? JsonSerializer.Deserialize<List<ProductCategory>>(categoriesElement.GetRawText()) ?? new()
                : new();

            var minimumNextCategoryId = ProductCategories.Count == 0
                ? 1
                : ProductCategories.Max(c => c.Id) + 1;
            var savedNextCategoryId = root.TryGetProperty("NextProductCategoryId", out var nextCategoryIdElement)
                && nextCategoryIdElement.ValueKind == JsonValueKind.Number
                ? nextCategoryIdElement.GetInt32()
                : 1;
            _nextProductCategoryId = Math.Max(1, Math.Max(minimumNextCategoryId, savedNextCategoryId));

            if (root.TryGetProperty("Sales", out var salesElement))
            {
                Sales = JsonSerializer.Deserialize<List<Sale>>(salesElement.GetRawText()) ?? new();
            }

            try { LoadCashState(root); }
            catch (Exception ex) when (ex is JsonException or FormatException or OverflowException or InvalidOperationException)
            {
                throw new InvalidDataException("Identidad o contenido de caja inválido.", ex);
            }

            LoadRefundStateGuarded(root);

            if (root.TryGetProperty("Summaries", out var summariesElement))
            {
                Summaries = JsonSerializer.Deserialize<List<DailySummary>>(summariesElement.GetRawText()) ?? new();
            }

            if (root.TryGetProperty("Users", out var usersElement))
            {
                Users = JsonSerializer.Deserialize<List<User>>(usersElement.GetRawText()) ?? new();
            }

            if (root.TryGetProperty("NextProductId", out var nextProductIdElement))
            {
                _nextProductId = nextProductIdElement.GetInt32();
            }

            _nextSaleId = RecoverNext(root, "NextSaleId", Sales.Select(s => s.Id));

            if (root.TryGetProperty("NextUserId", out var nextUserIdElement))
            {
                _nextUserId = nextUserIdElement.GetInt32();
            }

            if (root.TryGetProperty("Ingredients", out var ingredientsElement))
            {
                Ingredients = JsonSerializer.Deserialize<List<Ingredient>>(ingredientsElement.GetRawText()) ?? new();
            }

            if (root.TryGetProperty("Suppliers", out var suppliersElement))
            {
                Suppliers = JsonSerializer.Deserialize<List<Supplier>>(suppliersElement.GetRawText()) ?? new();
            }

            if (root.TryGetProperty("Invoices", out var invoicesElement))
            {
                Invoices = JsonSerializer.Deserialize<List<Invoice>>(invoicesElement.GetRawText()) ?? new();
            }

            ValidatePurchasingFiscalData();

            if (root.TryGetProperty("Recipes", out var recipesElement))
            {
                Recipes = JsonSerializer.Deserialize<List<Recipe>>(recipesElement.GetRawText()) ?? new();
            }

            LoadBusinessSettings(root);

            if (root.TryGetProperty("NextIngredientId", out var nextIngredientIdElement))
            {
                _nextIngredientId = nextIngredientIdElement.GetInt32();
            }

            if (root.TryGetProperty("NextSupplierId", out var nextSupplierIdElement))
            {
                _nextSupplierId = nextSupplierIdElement.GetInt32();
            }

            if (root.TryGetProperty("NextInvoiceId", out var nextInvoiceIdElement))
            {
                _nextInvoiceId = nextInvoiceIdElement.GetInt32();
            }

            if (root.TryGetProperty("NextRecipeId", out var nextRecipeIdElement))
            {
                _nextRecipeId = nextRecipeIdElement.GetInt32();
            }

            LoadStockMovementStateGuarded(root);
            LoadStockCountStateGuarded(root);
        }
        catch (InvalidDataException)
        {
            throw; // Never quietly repair ambiguous identities or linked financial records.
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error cargando datos: {ex.Message}");
        }
    }
}
