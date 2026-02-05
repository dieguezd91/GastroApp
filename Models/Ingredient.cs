namespace GastroApp.Models;

public class Ingredient
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Unit { get; set; } = "kg"; // kg, lt, unidad
    public bool IsActive { get; set; } = true;

    // Control de stock
    public decimal CurrentStock { get; set; } = 0;
    public decimal MinStock { get; set; } = 0;

    // Indicador visual de stock
    public string StockIndicator
    {
        get
        {
            if (CurrentStock <= 0) return "red";      // Sin stock
            if (CurrentStock <= MinStock) return "yellow"; // Stock bajo
            return "green";                            // Stock OK
        }
    }
}
