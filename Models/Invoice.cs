namespace GastroApp.Models;

public class Invoice
{
    public int Id { get; set; }
    public DateTime Date { get; set; } = DateTime.Now;
    public int SupplierId { get; set; }
    public string InvoiceNumber { get; set; } = string.Empty;
    public string Notes { get; set; } = string.Empty;
    public List<InvoiceItem> Items { get; set; } = new();

    // Helper: total de la factura
    public decimal Total => Items.Sum(i => i.Subtotal);
}
