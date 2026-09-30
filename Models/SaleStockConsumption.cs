namespace GastroApp.Models;

// Captured in the ingredient's stock unit at the time of successful deduction.
public class SaleStockConsumption
{
    public int IngredientId { get; set; }
    public decimal Quantity { get; set; }
    public string Unit { get; set; } = string.Empty;
}
