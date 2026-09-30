using GastroApp.Models;
using System.Text.Json;

namespace GastroApp.Services;

public class DataStorageService
{
    public List<Product> Products { get; set; } = new();
    public List<ProductCategory> ProductCategories { get; set; } = new();
    public List<Sale> Sales { get; set; } = new();
    public List<CashRegister> CashRegisters { get; private set; } = new();
    public List<CashMovement> CashMovements { get; private set; } = new();
    public int? CurrentCashRegisterId { get; private set; }
    public CashRegister? CurrentCashRegister => CashRegisters.FirstOrDefault(r => r.Id == CurrentCashRegisterId);
    public List<DailySummary> Summaries { get; set; } = new();
    public List<User> Users { get; set; } = new();

    // Nuevas entidades
    public List<Ingredient> Ingredients { get; set; } = new();
    public List<Supplier> Suppliers { get; set; } = new();
    public List<Invoice> Invoices { get; set; } = new();
    public List<Recipe> Recipes { get; set; } = new();

    private int _nextProductId = 1;
    private int _nextProductCategoryId = 1;
    private int _nextSaleId = 1;
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

    // Fail before checkout or opening mutates state; int.MaxValue cannot be followed by a valid counter.
    private static int Allocate(ref int next, string name)
    {
        if (next <= 0 || next == int.MaxValue)
            throw new InvalidOperationException($"Se agotaron los identificadores de {name}.");
        return next++;
    }

    public void EnsureSaleCapacity() => EnsureCapacity(_nextSaleId, "ventas");
    public void EnsureCashMovementCapacity() => EnsureCapacity(_nextCashMovementId, "movimientos de caja");
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

    public decimal GetExpectedCash(int registerId)
    {
        var register = CashRegisters.FirstOrDefault(r => r.Id == registerId)
            ?? throw new InvalidOperationException("La caja no existe.");
        return CashMovements.Where(m => m.CashRegisterId == registerId)
            .Aggregate(register.InitialAmount, (balance, m) => checked(balance +
                (m.Type == CashMovementType.Sale || m.Type == CashMovementType.Income
                    ? m.Amount : -m.Amount)));
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

        // Si no hay datos, crear datos de ejemplo
        if (Products.Count == 0)
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
        Suppliers.Add(new Supplier { Id = provId, Name = "Distribuidora San Martín" });

        // Seed de factura con precios
        var facturaId = GetNextInvoiceId();
        Invoices.Add(new Invoice
        {
            Id = facturaId,
            Date = DateTime.Now.AddDays(-5),
            SupplierId = provId,
            InvoiceNumber = "A-0001-00001234",
            Notes = "Primera compra de ingredientes",
            Items = new List<InvoiceItem>
            {
                new InvoiceItem { InvoiceId = facturaId, IngredientId = harinaId, IngredientName = "Harina 000", Quantity = 10, Unit = "kg", UnitPrice = 80 },
                new InvoiceItem { InvoiceId = facturaId, IngredientId = lecheId, IngredientName = "Leche", Quantity = 5, Unit = "lt", UnitPrice = 120 },
                new InvoiceItem { InvoiceId = facturaId, IngredientId = huevoId, IngredientName = "Huevos", Quantity = 30, Unit = "unidad", UnitPrice = 15 },
                new InvoiceItem { InvoiceId = facturaId, IngredientId = mantecaId, IngredientName = "Manteca", Quantity = 2, Unit = "kg", UnitPrice = 350 }
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
            var data = new
            {
                Products,
                ProductCategories,
                Sales,
                CashRegisters,
                CashMovements,
                CurrentCashRegisterId,
                Summaries,
                Users,
                Ingredients,
                Suppliers,
                Invoices,
                Recipes,
                NextProductId = _nextProductId,
                NextProductCategoryId = _nextProductCategoryId,
                NextSaleId = _nextSaleId,
                NextCashRegisterId = _nextCashRegisterId,
                NextCashMovementId = _nextCashMovementId,
                NextUserId = _nextUserId,
                NextIngredientId = _nextIngredientId,
                NextSupplierId = _nextSupplierId,
                NextInvoiceId = _nextInvoiceId,
                NextRecipeId = _nextRecipeId
            };

            var json = JsonSerializer.Serialize(data, new JsonSerializerOptions
            {
                WriteIndented = true
            });

            File.WriteAllText(_dataFilePath, json);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error guardando datos: {ex.Message}");
        }
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

        CashRegisters = registers;
        CashMovements = movements;
        CurrentCashRegisterId = current;
        _nextCashRegisterId = nextRegister;
        _nextCashMovementId = nextMovement;
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

            if (root.TryGetProperty("Recipes", out var recipesElement))
            {
                Recipes = JsonSerializer.Deserialize<List<Recipe>>(recipesElement.GetRawText()) ?? new();
            }

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
