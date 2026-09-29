using GastroApp.Models;
using System.Text.Json;

namespace GastroApp.Services;

public class DataStorageService
{
    public List<Product> Products { get; set; } = new();
    public List<ProductCategory> ProductCategories { get; set; } = new();
    public List<Sale> Sales { get; set; } = new();
    public CashRegister? CurrentCashRegister { get; set; }
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
    private int _nextUserId = 1;
    private int _nextIngredientId = 1;
    private int _nextSupplierId = 1;
    private int _nextInvoiceId = 1;
    private int _nextRecipeId = 1;

    private readonly string _dataFilePath = "data.json";

    public int GetNextProductId() => _nextProductId++;
    public int GetNextProductCategoryId() => _nextProductCategoryId++;
    public int GetNextSaleId() => _nextSaleId++;
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
                CurrentCashRegister,
                Summaries,
                Users,
                Ingredients,
                Suppliers,
                Invoices,
                Recipes,
                NextProductId = _nextProductId,
                NextProductCategoryId = _nextProductCategoryId,
                NextSaleId = _nextSaleId,
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

            if (root.TryGetProperty("CurrentCashRegister", out var cashElement))
            {
                CurrentCashRegister = JsonSerializer.Deserialize<CashRegister>(cashElement.GetRawText());
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

            if (root.TryGetProperty("NextSaleId", out var nextSaleIdElement))
            {
                _nextSaleId = nextSaleIdElement.GetInt32();
            }

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
        catch (Exception ex)
        {
            Console.WriteLine($"Error cargando datos: {ex.Message}");
        }
    }
}
