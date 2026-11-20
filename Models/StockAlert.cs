namespace GastroApp.Models;

public enum StockAlertLevel
{
    // Stock at or below zero (a legacy negative balance is also listed here).
    OutOfStock = 0,
    // Positive stock at or below the configured minimum.
    BelowMinimum = 1
}

// Read model of one ingredient that needs attention (S5). Built only by IngredientService.GetStockAlerts.
public sealed class StockAlert
{
    public int IngredientId { get; init; }
    public string Name { get; init; } = string.Empty;
    public string Unit { get; init; } = string.Empty;
    public decimal CurrentStock { get; init; }
    public decimal MinStock { get; init; }
    public StockAlertLevel Level { get; init; }
    public bool IsNegative => CurrentStock < 0m;
    // Days of the window the consumption was measured over.
    public int Days { get; init; }
    // Net sale consumption over the window, in the ingredient unit (never negative).
    public decimal RecentConsumption { get; init; }
    // Estimated days the stock lasts at the recent average consumption: CurrentStock / (RecentConsumption / Days).
    // Null when there was no recent consumption or the estimate is beyond the supported range.
    public decimal? CoverageDays { get; init; }
}
