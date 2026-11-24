using System.Globalization;
using GastroApp.Models;
using GastroApp.Services;
using GastroApp.Shared.Pos;

namespace GastroApp.Shared.Purchasing;

/// <summary>Tabs of the unified purchasing view; each one is served by its own route.</summary>
public enum PurchasingTab
{
    Invoices,
    Suppliers
}

/// <summary>Display and input helpers shared by the purchasing components (es-AR display).</summary>
public static class PurchasingFormat
{
    public const string InvoicesRoute = "/invoices";
    public const string SuppliersRoute = "/suppliers";

    public static string RouteOf(PurchasingTab tab) => tab == PurchasingTab.Invoices ? InvoicesRoute : SuppliersRoute;

    public static string Money(decimal amount) => PosFormat.Money(amount);

    /// <summary>"2,5": up to four decimals, no trailing zeros, decimal comma independent of the host culture.</summary>
    public static string Number(decimal value) => value.ToString("0.####", CultureInfo.InvariantCulture).Replace('.', ',');

    /// <summary>Name of an invoice line: the one stored on the line, else "Ingrediente eliminado (#id)".</summary>
    public static string ItemName(InvoiceItem item) =>
        string.IsNullOrWhiteSpace(item.IngredientName) ? IngredientService.DeletedName(item.IngredientId) : item.IngredientName;

    /// <summary>"2,5 kg".</summary>
    public static string Qty(decimal value, string unit) => $"{Number(value)} {unit}";

    /// <summary>"23/11/2026".</summary>
    public static string DateText(DateTime date) => date.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);

    /// <summary>Quantities and prices typed in a numeric input arrive with a dot, whatever the host culture.</summary>
    public static bool TryParseDecimal(string? text, out decimal value)
    {
        value = 0m;
        return !string.IsNullOrWhiteSpace(text)
            && decimal.TryParse(text, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite,
                CultureInfo.InvariantCulture, out value);
    }

    /// <summary>
    /// Units an invoice line may use for an ingredient stored in <paramref name="baseUnit"/> (poka-yoke): only units
    /// <see cref="UnitConverter"/> can convert to it. Weight and volume offer two options (small unit first),
    /// anything else (unidad) is fixed.
    /// </summary>
    public static IReadOnlyList<string> UnitOptions(string baseUnit) => UnitConverter.GetUnitCategory(baseUnit) switch
    {
        "peso" => new[] { "gr", "kg" },
        "volumen" => new[] { "ml", "lt" },
        _ => new[] { baseUnit }
    };

    /// <summary>
    /// Builds the invoice line for a quantity and price typed in <paramref name="unit"/>, stored in the ingredient's own unit:
    /// the stored price is what <see cref="InvoiceService.GetLastPriceForIngredient"/> hands to recipe costing, which reads it
    /// as a price per base unit. Null when the unit cannot be converted. Entering the base unit stores the values as typed.
    /// </summary>
    public static InvoiceItem? BuildItem(Ingredient ingredient, decimal quantity, string unit, decimal unitPrice)
    {
        var converted = UnitConverter.Convert(quantity, unit, ingredient.Unit);
        var factor = UnitConverter.Convert(1m, unit, ingredient.Unit);
        if (converted == null || factor == null || factor.Value <= 0m) return null;

        var sameUnit = string.Equals(unit, ingredient.Unit, StringComparison.OrdinalIgnoreCase);
        return new InvoiceItem
        {
            IngredientId = ingredient.Id,
            IngredientName = ingredient.Name,
            Quantity = sameUnit ? quantity : converted.Value,
            Unit = ingredient.Unit,
            UnitPrice = sameUnit ? unitPrice : unitPrice / factor.Value
        };
    }

    /// <summary>One-line live preview of the line being composed (stock impact and subtotal).</summary>
    public static string LinePreview(Ingredient? ingredient, string unit, string? quantityText, string? priceText)
    {
        if (ingredient == null)
            return "Elegí un ingrediente para ver la unidad compatible y el impacto en stock.";

        var converts = !string.Equals(unit, ingredient.Unit, StringComparison.OrdinalIgnoreCase);
        if (!TryParseDecimal(quantityText, out var quantity) || quantity <= 0m)
            return converts
                ? $"Ingresá la cantidad en {unit} (se convierte automáticamente a {ingredient.Unit})."
                : $"Se sumará al stock de {ingredient.Name} en {ingredient.Unit}.";

        var converted = UnitConverter.Convert(quantity, unit, ingredient.Unit);
        if (converted == null) return "Unidad incompatible con el ingrediente.";

        var text = $"Impacto en stock: +{Qty(converted.Value, ingredient.Unit)} (de {Qty(ingredient.CurrentStock, ingredient.Unit)} a {Qty(ingredient.CurrentStock + converted.Value, ingredient.Unit)})";
        if (TryParseDecimal(priceText, out var price) && price > 0m)
        {
            text += $" · Subtotal: {Money(quantity * price)}";
            if (converts) text += $" · Se registra a {Money(BuildItem(ingredient, quantity, unit, price)!.UnitPrice)} por {ingredient.Unit}";
        }
        return text;
    }
}
