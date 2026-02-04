using GastroApp.Models;

namespace GastroApp.Services;

public class InvoiceService
{
    private readonly DataStorageService _storage;

    public InvoiceService(DataStorageService storage)
    {
        _storage = storage;
    }

    public List<Invoice> GetAll() => _storage.Invoices.OrderByDescending(i => i.Date).ToList();

    public Invoice? GetById(int id) => _storage.Invoices.FirstOrDefault(i => i.Id == id);

    public void Add(Invoice invoice)
    {
        invoice.Id = _storage.GetNextInvoiceId();
        // Asignar InvoiceId a todos los items
        foreach (var item in invoice.Items)
        {
            item.InvoiceId = invoice.Id;
        }
        _storage.Invoices.Add(invoice);
        _storage.SaveToFile();
    }

    public void Update(Invoice invoice)
    {
        var existing = GetById(invoice.Id);
        if (existing != null)
        {
            existing.Date = invoice.Date;
            existing.SupplierId = invoice.SupplierId;
            existing.InvoiceNumber = invoice.InvoiceNumber;
            existing.Notes = invoice.Notes;
            existing.Items = invoice.Items;
            _storage.SaveToFile();
        }
    }

    public void Delete(int id)
    {
        var invoice = GetById(id);
        if (invoice != null)
        {
            _storage.Invoices.Remove(invoice);
            _storage.SaveToFile();
        }
    }

    // Obtener último precio para un ingrediente (más reciente)
    public decimal? GetLastPriceForIngredient(int ingredientId)
    {
        // Buscar en todas las facturas ordenadas por fecha descendente
        var lastItem = _storage.Invoices
            .OrderByDescending(inv => inv.Date)
            .SelectMany(inv => inv.Items)
            .FirstOrDefault(item => item.IngredientId == ingredientId);

        return lastItem?.UnitPrice;
    }

    // Historial de precios para un ingrediente (ordenado por fecha)
    public List<(DateTime Date, decimal Price)> GetPriceHistory(int ingredientId)
    {
        return _storage.Invoices
            .OrderByDescending(inv => inv.Date)
            .SelectMany(inv => inv.Items.Where(item => item.IngredientId == ingredientId)
                .Select(item => (inv.Date, item.UnitPrice)))
            .ToList();
    }
}
