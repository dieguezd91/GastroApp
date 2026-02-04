using GastroApp.Models;

namespace GastroApp.Services;

public class SaleService
{
    private readonly DataStorageService _storage;

    public SaleService(DataStorageService storage)
    {
        _storage = storage;
    }

    public List<Sale> GetAll() => _storage.Sales;

    public List<Sale> GetToday()
    {
        var today = DateTime.Today;
        return _storage.Sales
            .Where(s => s.Date.Date == today)
            .ToList();
    }

    public void Add(Sale sale)
    {
        sale.Id = _storage.GetNextSaleId();
        sale.Date = DateTime.Now;
        _storage.Sales.Add(sale);
    }

    public decimal GetTodayTotal()
    {
        return GetToday().Sum(s => s.Total);
    }

    public int GetTodayCount()
    {
        return GetToday().Count;
    }

    public (string Name, int Quantity) GetTopProduct()
    {
        var todaySales = GetToday();
        if (!todaySales.Any()) return ("Ninguno", 0);

        var productSales = todaySales
            .SelectMany(s => s.Items)
            .GroupBy(i => i.ProductName)
            .Select(g => new { Name = g.Key, Quantity = g.Sum(i => i.Quantity) })
            .OrderByDescending(x => x.Quantity)
            .FirstOrDefault();

        return productSales != null ? (productSales.Name, productSales.Quantity) : ("Ninguno", 0);
    }
}
