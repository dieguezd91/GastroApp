using GastroApp.Models;

namespace GastroApp.Services;

public class IngredientService
{
    private readonly DataStorageService _storage;
    private readonly InvoiceService _invoiceService;

    public IngredientService(DataStorageService storage, InvoiceService invoiceService)
    {
        _storage = storage;
        _invoiceService = invoiceService;
    }

    public List<Ingredient> GetAll() => _storage.Ingredients;

    public List<Ingredient> GetActive() => _storage.Ingredients.Where(i => i.IsActive).ToList();

    public Ingredient? GetById(int id) => _storage.Ingredients.FirstOrDefault(i => i.Id == id);

    public void Add(Ingredient ingredient)
    {
        ingredient.Id = _storage.GetNextIngredientId();
        _storage.Ingredients.Add(ingredient);
        _storage.SaveToFile();
    }

    public void Update(Ingredient ingredient)
    {
        var existing = GetById(ingredient.Id);
        if (existing != null)
        {
            existing.Name = ingredient.Name;
            existing.Unit = ingredient.Unit;
            existing.IsActive = ingredient.IsActive;
            _storage.SaveToFile();
        }
    }

    public void Delete(int id)
    {
        var ingredient = GetById(id);
        if (ingredient != null)
        {
            _storage.Ingredients.Remove(ingredient);
            _storage.SaveToFile();
        }
    }

    // Obtener último precio conocido desde facturas
    public decimal? GetLastPrice(int ingredientId)
    {
        return _invoiceService.GetLastPriceForIngredient(ingredientId);
    }
}
