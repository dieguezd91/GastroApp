using GastroApp.Models;

namespace GastroApp.Services;

public class InvoiceService
{
    private readonly DataStorageService _storage;
    private IngredientService? _ingredientService;

    public InvoiceService(DataStorageService storage)
    {
        _storage = storage;
    }

    // Setter para evitar dependencia circular
    public void SetIngredientService(IngredientService ingredientService)
    {
        _ingredientService = ingredientService;
    }

    public List<Invoice> GetAll() => _storage.Invoices.OrderByDescending(i => i.Date).ToList();

    public Invoice? GetById(int id) => _storage.Invoices.FirstOrDefault(i => i.Id == id);

    // The invoice is the reception (S7): each applicable item becomes an InvoiceReceipt movement linked to it.
    // Everything is validated before the invoice is stored, so a rejected invoice leaves no trace.
    public void Add(Invoice invoice, User? actor = null)
    {
        var operatorUser = _storage.FindLiveUser(actor);
        if (actor != null && operatorUser == null)
            throw new UnauthorizedAccessException("Se requiere un usuario vigente para registrar la factura.");

        var batch = PrepareReceipts(invoice, operatorUser);

        invoice.Id = _storage.GetNextInvoiceId();
        // Asignar InvoiceId a todos los items
        foreach (var item in invoice.Items)
        {
            item.InvoiceId = invoice.Id;
        }
        _storage.Invoices.Add(invoice);

        if (batch != null)
        {
            foreach (var movement in batch.Movements)
                movement.InvoiceId = invoice.Id;
            _ingredientService!.Commit(batch);
        }

        _storage.SaveToFile();
    }

    private StockMovementBatch? PrepareReceipts(Invoice invoice, User? operatorUser)
    {
        if (_ingredientService == null) return null;

        var requests = new List<StockMovementRequest>();
        foreach (var item in invoice.Items)
        {
            // Obtener el ingrediente para saber su unidad base
            var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == item.IngredientId);
            if (ingredient == null) continue;

            // Convertir cantidad a unidad base del ingrediente
            decimal? quantityInBaseUnit;
            try { quantityInBaseUnit = UnitConverter.Convert(item.Quantity, item.Unit, ingredient.Unit); }
            catch (OverflowException) { throw new InvalidOperationException("La cantidad de la factura supera el límite permitido."); }
            if (quantityInBaseUnit == null) continue; // Unidades incompatibles
            if (quantityInBaseUnit.Value <= 0m)
                throw new InvalidOperationException("La cantidad de cada ítem de la factura debe ser positiva.");

            requests.Add(new StockMovementRequest
            {
                IngredientId = ingredient.Id, Type = StockMovementType.InvoiceReceipt, Quantity = quantityInBaseUnit.Value
            });
        }

        return requests.Count == 0 ? null : _ingredientService.Prepare(requests, operatorUser, DateTime.Now);
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
