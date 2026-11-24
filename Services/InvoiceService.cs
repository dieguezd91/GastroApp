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

        ValidateFiscalData(invoice);
        var batch = PrepareReceipts(invoice, operatorUser);

        foreach (var tax in invoice.OtherTaxes)
            tax.Detail = (tax.Detail ?? string.Empty).Trim();
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

    // Business condition, supplier, derived type, legend, VAT and other taxes (S1-S5). Changes nothing.
    private void ValidateFiscalData(Invoice invoice)
    {
        var businessCondition = _storage.BusinessSettings.TaxCondition;
        if (!businessCondition.HasValue)
            throw new InvalidOperationException("Configurá la condición frente al IVA del negocio en Datos fiscales antes de registrar facturas.");

        var supplier = _storage.Suppliers.FirstOrDefault(s => s.Id == invoice.SupplierId);
        if (supplier == null)
            throw new InvalidOperationException("Seleccioná un proveedor.");
        if (!supplier.HasFiscalData)
            throw new InvalidOperationException("Completá el CUIT y la condición frente al IVA del proveedor antes de registrar la factura.");

        var supplierCondition = supplier.TaxCondition!.Value;
        var expected = FiscalRules.ExpectedInvoiceType(supplierCondition, businessCondition.Value);
        if (invoice.Type != expected)
            throw new InvalidOperationException($"Un proveedor {FiscalRules.Label(supplierCondition)} debe emitirte factura {expected}.");

        if (!Enum.IsDefined(invoice.Legend))
            throw new InvalidOperationException("La leyenda de la factura no es válida.");
        if (invoice.Legend != InvoiceLegend.None && expected != InvoiceType.A)
            throw new InvalidOperationException("La leyenda solo corresponde a facturas A.");

        if (expected == InvoiceType.A)
        {
            if (invoice.Items.Any(i => !i.VatRate.HasValue || !FiscalRules.VatRates.Contains(i.VatRate.Value)))
                throw new InvalidOperationException("Elegí una alícuota de IVA válida para cada ítem de la factura A.");
        }
        else if (invoice.Items.Any(i => i.VatRate.HasValue))
            throw new InvalidOperationException($"Las facturas {expected} no discriminan IVA por ítem.");

        if (invoice.ContainedVat.HasValue)
        {
            if (expected != InvoiceType.B)
                throw new InvalidOperationException("El IVA contenido solo se informa en facturas B.");
            if (invoice.ContainedVat.Value < 0m || invoice.ContainedVat.Value >= invoice.Total)
                throw new InvalidOperationException("El IVA contenido debe ser mayor o igual a cero y menor que el total de la factura.");
        }

        if (invoice.OtherTaxes.Any(t => !Enum.IsDefined(t.Kind)))
            throw new InvalidOperationException("El tipo de tributo no es válido.");
        if (invoice.OtherTaxes.Any(t => t.Amount <= 0m))
            throw new InvalidOperationException("El importe de cada tributo debe ser mayor a cero.");
        if (expected != InvoiceType.A && invoice.OtherTaxes.Any(t => t.Kind == InvoiceTaxKind.PercepcionIva))
            throw new InvalidOperationException("La percepción de IVA solo corresponde a facturas A.");
        if (invoice.OtherTaxes.Any(t => t.Kind == InvoiceTaxKind.PercepcionIibb && string.IsNullOrWhiteSpace(t.Detail)))
            throw new InvalidOperationException("Indicá la jurisdicción de la percepción de IIBB.");
        if (invoice.OtherTaxes.Any(t => t.Kind == InvoiceTaxKind.OtrosTributos && string.IsNullOrWhiteSpace(t.Detail)))
            throw new InvalidOperationException("Describí el tributo.");
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
            existing.Type = invoice.Type;
            existing.Legend = invoice.Legend;
            existing.ContainedVat = invoice.ContainedVat;
            existing.OtherTaxes = invoice.OtherTaxes;
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

    // Obtener último costo para un ingrediente (más reciente). The cost follows the S6 policy for the business
    // condition: it is not always the typed price (see FiscalRules.UnitCost).
    public decimal? GetLastPriceForIngredient(int ingredientId)
    {
        var business = _storage.BusinessSettings.TaxCondition;
        // Buscar en todas las facturas ordenadas por fecha descendente
        var last = _storage.Invoices
            .OrderByDescending(inv => inv.Date)
            .SelectMany(inv => inv.Items.Select(item => (Invoice: inv, Item: item)))
            .FirstOrDefault(entry => entry.Item.IngredientId == ingredientId);

        return last.Item == null ? null : FiscalRules.UnitCost(last.Invoice, last.Item, business);
    }

    // Historial de costos para un ingrediente (más reciente primero), con la misma política de costo.
    public List<(DateTime Date, decimal Price)> GetPriceHistory(int ingredientId)
    {
        var business = _storage.BusinessSettings.TaxCondition;
        return _storage.Invoices
            .OrderByDescending(inv => inv.Date)
            .SelectMany(inv => inv.Items.Where(item => item.IngredientId == ingredientId)
                .Select(item => (inv.Date, FiscalRules.UnitCost(inv, item, business))))
            .ToList();
    }
}
