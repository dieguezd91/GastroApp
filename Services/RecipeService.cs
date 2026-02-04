using GastroApp.Models;

namespace GastroApp.Services;

public class RecipeService
{
    private readonly DataStorageService _storage;
    private readonly InvoiceService _invoiceService;

    public RecipeService(DataStorageService storage, InvoiceService invoiceService)
    {
        _storage = storage;
        _invoiceService = invoiceService;
    }

    public List<Recipe> GetAll() => _storage.Recipes;

    public Recipe? GetById(int id) => _storage.Recipes.FirstOrDefault(r => r.Id == id);

    public void Add(Recipe recipe)
    {
        recipe.Id = _storage.GetNextRecipeId();
        recipe.CreatedAt = DateTime.Now;

        // Calcular costos antes de guardar
        CalculateCosts(recipe);

        _storage.Recipes.Add(recipe);
        _storage.SaveToFile();
    }

    public void Update(Recipe recipe)
    {
        var existing = GetById(recipe.Id);
        if (existing != null)
        {
            existing.Name = recipe.Name;
            existing.Yield = recipe.Yield;
            existing.Ingredients = recipe.Ingredients;

            // Recalcular costos
            CalculateCosts(existing);

            _storage.SaveToFile();
        }
    }

    public void Delete(int id)
    {
        var recipe = GetById(id);
        if (recipe != null)
        {
            _storage.Recipes.Remove(recipe);
            _storage.SaveToFile();
        }
    }

    // Calcular costos de una receta usando últimos precios de facturas
    public void CalculateCosts(Recipe recipe)
    {
        decimal totalCost = 0;

        foreach (var ingredient in recipe.Ingredients)
        {
            // Obtener último precio del ingrediente desde facturas
            var lastPrice = _invoiceService.GetLastPriceForIngredient(ingredient.IngredientId);

            if (lastPrice == null)
            {
                // Sin precio, no podemos calcular
                ingredient.UnitPrice = 0;
                ingredient.Subtotal = 0;
                continue;
            }

            // Obtener la información del ingrediente para su unidad base
            var ingredientInfo = _storage.Ingredients.FirstOrDefault(i => i.Id == ingredient.IngredientId);
            if (ingredientInfo == null)
            {
                ingredient.UnitPrice = lastPrice.Value;
                ingredient.Subtotal = ingredient.Quantity * lastPrice.Value;
                totalCost += ingredient.Subtotal;
                continue;
            }

            // Verificar compatibilidad de unidades
            if (!UnitConverter.AreCompatible(ingredient.Unit, ingredientInfo.Unit))
            {
                // Unidades incompatibles: excluir del cálculo
                ingredient.UnitPrice = 0;
                ingredient.Subtotal = 0;
                continue;
            }

            // Convertir cantidad a la unidad base del ingrediente
            var convertedQuantity = UnitConverter.Convert(ingredient.Quantity, ingredient.Unit, ingredientInfo.Unit);
            if (convertedQuantity == null)
            {
                // Error en conversión (no debería pasar, pero por seguridad)
                ingredient.UnitPrice = 0;
                ingredient.Subtotal = 0;
                continue;
            }

            // Calcular subtotal usando cantidad convertida y precio en unidad base
            ingredient.UnitPrice = lastPrice.Value;
            ingredient.Subtotal = convertedQuantity.Value * lastPrice.Value;
            totalCost += ingredient.Subtotal;
        }

        // Guardar costo anterior para comparación
        var previousCost = recipe.LastCalculatedCost;

        // Actualizar costos actuales
        recipe.TotalCost = totalCost;
        recipe.UnitCost = recipe.Yield > 0 ? totalCost / recipe.Yield : 0;

        // Calcular indicador basado en variación porcentual
        if (previousCost > 0)
        {
            // Hay un costo previo: calcular variación
            var variation = Math.Abs(recipe.UnitCost - previousCost) / previousCost;

            recipe.CostIndicator = variation switch
            {
                >= 0.30m => "red",      // Variación >= 30%
                >= 0.10m => "yellow",   // Variación >= 10% y < 30%
                _ => "green"            // Variación < 10%
            };
        }
        else
        {
            // Primera vez o costo previo era 0: verde por defecto
            recipe.CostIndicator = "green";
        }

        // Actualizar referencia para próximo cálculo
        recipe.LastCalculatedCost = recipe.UnitCost;
        recipe.LastCalculatedAt = DateTime.Now;
    }

    // Recalcular costos de todas las recetas (útil cuando cambian precios)
    public void RecalculateAllCosts()
    {
        foreach (var recipe in _storage.Recipes)
        {
            CalculateCosts(recipe);
        }
        _storage.SaveToFile();
    }
}
