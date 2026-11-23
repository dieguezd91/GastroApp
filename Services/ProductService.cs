using GastroApp.Models;

namespace GastroApp.Services;

/// <summary>
/// Latest recipe unit cost (cost per portion) for a product and whether the product's saved cost has drifted from it.
/// <see cref="ProductCost"/> is null when the product has no saved cost.
/// </summary>
public sealed record RecipeCostDrift(decimal RecipeCost, decimal? ProductCost, bool HasDrift);

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

    // ---- Recipe cost sync (S9): the recipe is matched by exact product name, like SaleService's stock rule ----

    /// <summary>
    /// Read-only. The recipe whose <c>Name</c> equals the product name (ordinal, first match) supplies the unit cost
    /// (<see cref="Recipe.UnitCost"/> = total cost / yield, i.e. cost per portion). Returns null without a matching
    /// recipe or when that recipe has no calculated (positive) unit cost. Costs drift when they differ at cent precision.
    /// </summary>
    public RecipeCostDrift? GetRecipeCostDrift(Product product)
    {
        var recipeCost = FindRecipeUnitCost(product);
        if (recipeCost == null) return null;

        var saved = product.Cost;
        var hasDrift = saved == null || Cents(saved.Value) != Cents(recipeCost.Value);
        return new RecipeCostDrift(recipeCost.Value, saved, hasDrift);
    }

    /// <summary>
    /// Sets only <see cref="Product.Cost"/> to the recipe unit cost and saves. Throws, leaving state untouched, when the
    /// actor (if given) is not a live administrator, the product does not exist, or it has no recipe with a calculated cost.
    /// </summary>
    public Product SyncCostFromRecipe(int productId, User? actor = null)
    {
        if (actor != null) _storage.RequireLiveAdmin(actor);
        var product = GetById(productId) ?? throw new InvalidOperationException("El producto no existe.");
        var recipeCost = FindRecipeUnitCost(product)
            ?? throw new InvalidOperationException("El producto no tiene una receta con costo calculado.");

        product.Cost = recipeCost;
        _storage.SaveToFile();
        return product;
    }

    private decimal? FindRecipeUnitCost(Product product)
    {
        var recipe = _storage.Recipes.FirstOrDefault(r => r.Name == product.Name);
        return recipe is { UnitCost: > 0m } ? recipe.UnitCost : null;
    }

    private static decimal Cents(decimal amount) => Math.Round(amount, 2, MidpointRounding.AwayFromZero);
}
