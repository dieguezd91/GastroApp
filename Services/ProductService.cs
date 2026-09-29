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
        ValidateCategory(product.CategoryId);
        product.Id = _storage.GetNextProductId();
        _storage.Products.Add(product);
        _storage.SaveToFile();
    }

    public void Update(Product product)
    {
        var existing = GetById(product.Id);
        if (existing != null)
        {
            ValidateCategory(product.CategoryId);
            existing.Name = product.Name;
            existing.Price = product.Price;
            existing.Cost = product.Cost;
            existing.CategoryId = product.CategoryId;
            existing.IsActive = product.IsActive;
            _storage.SaveToFile();
        }
    }

    public void Delete(int id)
    {
        var product = GetById(id);
        if (product != null)
        {
            _storage.Products.Remove(product);
            _storage.SaveToFile();
        }
    }

    private void ValidateCategory(int? categoryId)
    {
        if (categoryId.HasValue && !_storage.ProductCategories.Any(c => c.Id == categoryId.Value))
            throw new ArgumentException("La categoría seleccionada no existe.", nameof(categoryId));
    }
}
