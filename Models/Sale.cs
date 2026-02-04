namespace GastroApp.Models;

public class Sale
{
    public int Id { get; set; }
    public DateTime Date { get; set; } = DateTime.Now;
    public List<SaleItem> Items { get; set; } = new();

    public decimal Total => Items.Sum(i => i.Subtotal);
}

public class SaleItem
{
    public int ProductId { get; set; }
    public string ProductName { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public int Quantity { get; set; }

    public decimal Subtotal => Price * Quantity;
}
