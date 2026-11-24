using System.Text.Json.Serialization;

namespace GastroApp.Models;

// IVA of one rate on a factura A: Net is the taxable base, Vat the rounded amount.
public record InvoiceVatLine(decimal Rate, decimal Net, decimal Vat);

public class Invoice
{
    public int Id { get; set; }
    public DateTime Date { get; set; } = DateTime.Now;
    public int SupplierId { get; set; }
    public string InvoiceNumber { get; set; } = string.Empty;
    public string Notes { get; set; } = string.Empty;
    public List<InvoiceItem> Items { get; set; } = new();

    // Null on invoices stored before the fiscal data existed: their price is final and their type unknown.
    public InvoiceType? Type { get; set; }
    public InvoiceLegend Legend { get; set; }
    // Informative IVA printed on a factura B (RG 5614/2024); not crédito fiscal.
    public decimal? ContainedVat { get; set; }
    public List<InvoiceTax> OtherTaxes { get; set; } = new();

    // Items subtotal as typed (net of IVA on a factura A).
    [JsonIgnore]
    public decimal NetTotal => Items.Sum(i => i.Subtotal);

    // Factura A only: net and IVA per rate, rate ascending, IVA rounded to cents per rate.
    [JsonIgnore]
    public IReadOnlyList<InvoiceVatLine> VatByRate => Type != InvoiceType.A
        ? Array.Empty<InvoiceVatLine>()
        : Items.Where(i => i.VatRate.HasValue)
            .GroupBy(i => i.VatRate!.Value)
            .OrderBy(group => group.Key)
            .Select(group =>
            {
                var net = group.Sum(i => i.Subtotal);
                return new InvoiceVatLine(group.Key, net, Math.Round(net * group.Key / 100m, 2, MidpointRounding.AwayFromZero));
            })
            .ToList();

    [JsonIgnore]
    public decimal VatTotal => VatByRate.Sum(l => l.Vat);

    [JsonIgnore]
    public decimal OtherTaxesTotal => OtherTaxes.Sum(t => t.Amount);

    // Helper: total de la factura (IVA solo se suma en facturas A; en B y C el precio ya lo incluye)
    public decimal Total => NetTotal + VatTotal + OtherTaxesTotal;
}
