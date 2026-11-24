namespace GastroApp.Models;

// Other taxes an invoice may list besides IVA. The values are persisted.
public enum InvoiceTaxKind
{
    PercepcionIva = 1,
    PercepcionIibb = 2,
    ImpuestosInternos = 3,
    OtrosTributos = 4
}
