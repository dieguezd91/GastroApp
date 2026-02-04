namespace GastroApp.Models;

public class RecipeIngredient
{
    public int RecipeId { get; set; }
    public int IngredientId { get; set; }
    public string IngredientName { get; set; } = string.Empty; // Desnormalizado para display
    public decimal Quantity { get; set; }
    public string Unit { get; set; } = string.Empty;

    // Precio y subtotal (calculados, no persistidos necesariamente)
    public decimal UnitPrice { get; set; }
    public decimal Subtotal { get; set; }
}
