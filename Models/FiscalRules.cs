namespace GastroApp.Models;

// Single owner of the Argentine purchase-invoice rules so services, loading and screens cannot diverge.
// Tax rules should be confirmed with an accountant (see Docs/Architecture/Purchasing.md).
public static class FiscalRules
{
    // Alícuotas de IVA in percent.
    public static readonly IReadOnlyList<decimal> VatRates = new[] { 0m, 2.5m, 5m, 10.5m, 21m, 27m };

    private static readonly int[] CuitWeights = { 5, 4, 3, 2, 7, 6, 5, 4, 3, 2 };

    public static string Label(TaxCondition condition) => condition switch
    {
        TaxCondition.ResponsableInscripto => "Responsable Inscripto",
        TaxCondition.Monotributista => "Monotributista",
        TaxCondition.Exento => "Exento",
        _ => condition.ToString()
    };

    public static string Label(InvoiceTaxKind kind) => kind switch
    {
        InvoiceTaxKind.PercepcionIva => "Percepción de IVA",
        InvoiceTaxKind.PercepcionIibb => "Percepción de IIBB",
        InvoiceTaxKind.ImpuestosInternos => "Impuestos internos",
        InvoiceTaxKind.OtrosTributos => "Otros tributos",
        _ => kind.ToString()
    };

    // Accepts 11 digits, optionally typed with dashes, with a valid check digit; returns them without dashes.
    public static bool TryNormalizeCuit(string? text, out string cuit)
    {
        cuit = string.Empty;
        var digits = (text ?? string.Empty).Trim().Replace("-", string.Empty);
        if (digits.Length != 11 || !digits.All(char.IsAsciiDigit)) return false;

        var sum = 0;
        for (var i = 0; i < CuitWeights.Length; i++) sum += (digits[i] - '0') * CuitWeights[i];
        var check = 11 - sum % 11;
        if (check == 10) return false; // no valid check digit exists for this prefix
        if (check == 11) check = 0;
        if (digits[10] - '0' != check) return false;

        cuit = digits;
        return true;
    }

    // The type the supplier must issue: C for Monotributista and Exento; A for a Responsable Inscripto
    // supplier unless the business is Exento, which receives B.
    public static InvoiceType ExpectedInvoiceType(TaxCondition supplier, TaxCondition business) =>
        supplier != TaxCondition.ResponsableInscripto ? InvoiceType.C
        : business == TaxCondition.Exento ? InvoiceType.B
        : InvoiceType.A;

    // The unit cost recipes use. A Responsable Inscripto business recovers the IVA of a factura A (crédito fiscal),
    // so its cost is the net price; any other business pays it, so the cost is net x (1 + alícuota).
    // B, C and legacy invoices (no type) keep the typed price: it is already final.
    public static decimal UnitCost(Invoice invoice, InvoiceItem item, TaxCondition? business)
    {
        if (invoice.Type != InvoiceType.A || business == TaxCondition.ResponsableInscripto) return item.UnitPrice;
        return item.UnitPrice * (1m + (item.VatRate ?? 0m) / 100m);
    }
}
