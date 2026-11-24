namespace GastroApp.Models;

// Tipo de comprobante recibido. Factura M is not offered (removed by RG 5762/2025). The values are persisted.
public enum InvoiceType
{
    A = 1,
    B = 2,
    C = 3
}
