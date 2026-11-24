using GastroApp.Models;

namespace GastroApp.Services;

public class SupplierService
{
    private readonly DataStorageService _storage;

    public SupplierService(DataStorageService storage)
    {
        _storage = storage;
    }

    public List<Supplier> GetAll() => _storage.Suppliers;

    public Supplier? GetById(int id) => _storage.Suppliers.FirstOrDefault(s => s.Id == id);

    public void Add(Supplier supplier)
    {
        var cuit = Validate(supplier);
        supplier.Cuit = cuit;
        supplier.Id = _storage.GetNextSupplierId();
        _storage.Suppliers.Add(supplier);
        _storage.SaveToFile();
    }

    public void Update(Supplier supplier)
    {
        var cuit = Validate(supplier);
        var existing = GetById(supplier.Id);
        if (existing != null)
        {
            existing.Name = supplier.Name;
            existing.Cuit = cuit;
            existing.TaxCondition = supplier.TaxCondition;
            _storage.SaveToFile();
        }
    }

    public void Delete(int id)
    {
        var supplier = GetById(id);
        if (supplier != null)
        {
            _storage.Suppliers.Remove(supplier);
            _storage.SaveToFile();
        }
    }

    // Rejects before anything is stored or any ID is allocated; returns the CUIT as 11 digits.
    private string Validate(Supplier supplier)
    {
        if (string.IsNullOrWhiteSpace(supplier.Name))
            throw new InvalidOperationException("Ingresá un nombre para el proveedor.");
        if (string.IsNullOrWhiteSpace(supplier.Cuit))
            throw new InvalidOperationException("Ingresá el CUIT del proveedor.");
        if (!FiscalRules.TryNormalizeCuit(supplier.Cuit, out var cuit))
            throw new InvalidOperationException("El CUIT no es válido.");
        if (!supplier.TaxCondition.HasValue || !Enum.IsDefined(supplier.TaxCondition.Value))
            throw new InvalidOperationException("Elegí la condición frente al IVA del proveedor.");
        if (_storage.Suppliers.Any(s => s.Id != supplier.Id && s.Cuit == cuit))
            throw new InvalidOperationException("Ya existe un proveedor con ese CUIT.");
        return cuit;
    }
}
