using GastroApp.Models;
using GastroApp.Shared.Pos;

namespace GastroApp.Shared.Catalog;

/// <summary>Tabs of the unified catalog view; each one is served by its own route.</summary>
public enum CatalogTab
{
    Products,
    Categories
}

/// <summary>Margin presentation shared by the catalog table rows, filters and the low-margin banner.</summary>
public static class CatalogFormat
{
    /// <summary>Same boundary as <see cref="Product.MarginColor"/>: below it the margin is "bajo".</summary>
    public const decimal LowMarginThresholdPct = 30m;

    public static string Money(decimal amount) => PosFormat.Money(amount);

    /// <summary>A margin exists only when the product has a cost (and a price to divide by).</summary>
    public static bool TryGetMargin(Product product, out decimal margin)
    {
        margin = 0m;
        if (!product.Cost.HasValue || product.Price <= 0m) return false;
        margin = product.Margin;
        return true;
    }

    public static bool IsLowMargin(Product product) =>
        TryGetMargin(product, out var margin) && margin < LowMarginThresholdPct;

    /// <summary>Badge variant and label: &lt; 0 danger, &lt; 30 warn, otherwise ok; neutral without cost.</summary>
    public static (string Variant, string Label) MarginHealth(Product product)
    {
        if (!TryGetMargin(product, out var margin)) return ("neutral", "Sin costo");
        var text = Percent(margin);
        if (margin < 0m) return ("danger", $"{text} · Margen negativo");
        if (margin < LowMarginThresholdPct) return ("warn", $"{text} · Margen bajo");
        return ("ok", $"{text} · Saludable");
    }

    /// <summary>"12,5%" (es-AR decimal comma, independent of the host culture).</summary>
    public static string Percent(decimal value) =>
        value.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture).Replace('.', ',') + "%";
}
