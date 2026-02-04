namespace GastroApp.Models;

public class InvoiceItem
{
    public int InvoiceId { get; set; }
    public int IngredientId { get; set; }
    public string IngredientName { get; set; } = string.Empty; // Desnormalizado para facilitar display
    public decimal Quantity { get; set; }
    public string Unit { get; set; } = string.Empty;
    public decimal UnitPrice { get; set; }

    // Helper: subtotal del item
    public decimal Subtotal => Quantity * UnitPrice;
}
