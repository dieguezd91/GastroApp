using GastroApp.Models;

namespace GastroApp.Services;

public class ProductCategoryService
{
    private readonly DataStorageService _storage;

    public ProductCategoryService(DataStorageService storage)
    {
        _storage = storage;
    }

    // Copias para que las ediciones pasen por la validación del servicio.
    public List<ProductCategory> GetAll() => _storage.ProductCategories
        .Select(c => new ProductCategory { Id = c.Id, Name = c.Name })
        .ToList();

    public ProductCategory? GetById(int id)
    {
        var category = _storage.ProductCategories.FirstOrDefault(c => c.Id == id);
        return category == null ? null : new ProductCategory { Id = category.Id, Name = category.Name };
    }

    public void Add(ProductCategory category)
    {
        var name = ValidateName(category.Name);
        category.Id = _storage.GetNextProductCategoryId();
        category.Name = name;
        _storage.ProductCategories.Add(new ProductCategory { Id = category.Id, Name = name });
        _storage.SaveToFile();
    }

    public void Update(ProductCategory category)
    {
        var existing = _storage.ProductCategories.FirstOrDefault(c => c.Id == category.Id);
        if (existing == null) return;

        var name = ValidateName(category.Name, category.Id);
        existing.Name = name;
        _storage.SaveToFile();
    }

    public void Delete(int id)
    {
        var category = _storage.ProductCategories.FirstOrDefault(c => c.Id == id);
        if (category == null) return;

        if (_storage.Products.Any(p => p.CategoryId == id))
            throw new InvalidOperationException("No se puede eliminar una categoría con productos asignados.");

        _storage.ProductCategories.Remove(category);
        _storage.SaveToFile();
    }

    private string ValidateName(string? name, int? excludedId = null)
    {
        var trimmedName = name?.Trim();
        if (string.IsNullOrWhiteSpace(trimmedName))
            throw new ArgumentException("El nombre de la categoría es obligatorio.", nameof(name));

        if (_storage.ProductCategories.Any(c => c.Id != excludedId
            && string.Equals(c.Name.Trim(), trimmedName, StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("Ya existe una categoría con ese nombre.");

        return trimmedName;
    }
}
