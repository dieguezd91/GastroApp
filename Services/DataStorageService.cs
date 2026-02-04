using GastroApp.Models;
using System.Text.Json;

namespace GastroApp.Services;

public class DataStorageService
{
    public List<Product> Products { get; set; } = new();
    public List<Sale> Sales { get; set; } = new();
    public CashRegister? CurrentCashRegister { get; set; }
    public List<DailySummary> Summaries { get; set; } = new();
    public List<User> Users { get; set; } = new();

    private int _nextProductId = 1;
    private int _nextSaleId = 1;
    private int _nextUserId = 1;

    private readonly string _dataFilePath = "data.json";

    public int GetNextProductId() => _nextProductId++;
    public int GetNextSaleId() => _nextSaleId++;
    public int GetNextUserId() => _nextUserId++;

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
    }

    public void SaveToFile()
    {
        try
        {
            var data = new
            {
                Products,
                Sales,
                CurrentCashRegister,
                Summaries,
                Users,
                NextProductId = _nextProductId,
                NextSaleId = _nextSaleId,
                NextUserId = _nextUserId
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
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error cargando datos: {ex.Message}");
        }
    }
}
