using GastroApp.Models;

namespace GastroApp.Services;

// Owner of the business's own fiscal data (one business per installation).
public class BusinessSettingsService
{
    private readonly DataStorageService _storage;
    private readonly RecipeService _recipeService;

    public BusinessSettingsService(DataStorageService storage, RecipeService recipeService)
    {
        _storage = storage;
        _recipeService = recipeService;
    }

    // Null until an admin configures it; invoices cannot be registered meanwhile.
    public TaxCondition? TaxCondition => _storage.BusinessSettings.TaxCondition;

    // The condition changes the cost of factura A purchases (S6), so stored recipe costs are recalculated and saved.
    public void SetTaxCondition(TaxCondition condition, User? actor)
    {
        _storage.RequireLiveAdmin(actor);
        if (!Enum.IsDefined(condition))
            throw new InvalidOperationException("Elegí una condición frente al IVA válida.");

        _storage.BusinessSettings.TaxCondition = condition;
        _recipeService.RecalculateAllCosts();
    }
}
