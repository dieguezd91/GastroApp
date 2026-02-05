using GastroApp.Models;

namespace GastroApp.Services;

public class SaleService
{
    private readonly DataStorageService _storage;
    private RecipeService? _recipeService;
    private IngredientService? _ingredientService;

    public SaleService(DataStorageService storage)
    {
        _storage = storage;
    }

    // Setters para evitar dependencias circulares
    public void SetRecipeService(RecipeService recipeService)
    {
        _recipeService = recipeService;
    }

    public void SetIngredientService(IngredientService ingredientService)
    {
        _ingredientService = ingredientService;
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

        // Descontar stock por cada producto vendido
        DeductStockFromSale(sale);
    }

    // Validar si hay stock suficiente para una venta
    public (bool IsValid, string ErrorMessage) ValidateStock(List<SaleItem> items)
    {
        if (_recipeService == null || _ingredientService == null)
            return (true, string.Empty); // Sin validación si no hay servicios

        foreach (var item in items)
        {
            // Buscar si el producto tiene una receta asociada
            var recipe = _storage.Recipes.FirstOrDefault(r => r.Name == item.ProductName);
            if (recipe == null) continue; // Producto sin receta, omitir validación

            // Verificar stock de cada ingrediente de la receta
            foreach (var recipeIngredient in recipe.Ingredients)
            {
                var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == recipeIngredient.IngredientId);
                if (ingredient == null) continue;

                // Convertir cantidad a unidad base del ingrediente
                var quantityNeeded = UnitConverter.Convert(
                    recipeIngredient.Quantity * item.Quantity,
                    recipeIngredient.Unit,
                    ingredient.Unit
                );

                if (quantityNeeded == null) continue; // Unidades incompatibles

                // Verificar si hay stock suficiente
                if (ingredient.CurrentStock < quantityNeeded.Value)
                {
                    return (false, $"Stock insuficiente de {ingredient.Name}. Disponible: {ingredient.CurrentStock} {ingredient.Unit}");
                }
            }
        }

        return (true, string.Empty);
    }

    private void DeductStockFromSale(Sale sale)
    {
        if (_recipeService == null || _ingredientService == null) return;

        foreach (var item in sale.Items)
        {
            // Buscar si el producto tiene una receta asociada
            var recipe = _storage.Recipes.FirstOrDefault(r => r.Name == item.ProductName);
            if (recipe == null) continue; // Producto sin receta

            // Descontar stock de cada ingrediente de la receta
            foreach (var recipeIngredient in recipe.Ingredients)
            {
                var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == recipeIngredient.IngredientId);
                if (ingredient == null) continue;

                // Convertir cantidad a unidad base del ingrediente
                var quantityToDeduct = UnitConverter.Convert(
                    recipeIngredient.Quantity * item.Quantity,
                    recipeIngredient.Unit,
                    ingredient.Unit
                );

                if (quantityToDeduct == null) continue; // Unidades incompatibles

                // Descontar stock
                _ingredientService.TryRemoveStock(recipeIngredient.IngredientId, quantityToDeduct.Value);
            }
        }
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
