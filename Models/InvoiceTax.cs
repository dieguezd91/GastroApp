namespace GastroApp.Models;

// A tax listed on the invoice besides IVA. Detail is the jurisdiction (IIBB) or the description (otros tributos).
public class InvoiceTax
{
    public InvoiceTaxKind Kind { get; set; }
    public string Detail { get; set; } = string.Empty;
    public decimal Amount { get; set; }
}
