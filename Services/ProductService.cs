using GastroApp.Models;

namespace GastroApp.Services;

public class ProductService
{
    private readonly DataStorageService _storage;

    public ProductService(DataStorageService storage)
    {
        _storage = storage;
    }

    public List<Product> GetAll() => _storage.Products;

    public Product? GetById(int id) => _storage.Products.FirstOrDefault(p => p.Id == id);

    public void Add(Product product)
    {
        product.Id = _storage.GetNextProductId();
        _storage.Products.Add(product);
    }

    public void Update(Product product)
    {
        var existing = GetById(product.Id);
        if (existing != null)
        {
            existing.Name = product.Name;
            existing.Price = product.Price;
            existing.Cost = product.Cost;
        }
    }

    public void Delete(int id)
    {
        var product = GetById(id);
        if (product != null)
        {
            _storage.Products.Remove(product);
        }
    }
}
