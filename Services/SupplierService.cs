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
        supplier.Id = _storage.GetNextSupplierId();
        _storage.Suppliers.Add(supplier);
        _storage.SaveToFile();
    }

    public void Update(Supplier supplier)
    {
        var existing = GetById(supplier.Id);
        if (existing != null)
        {
            existing.Name = supplier.Name;
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
}
