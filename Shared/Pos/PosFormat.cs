using System.Globalization;

namespace GastroApp.Shared.Pos;

/// <summary>Display and input helpers shared by the POS components (es-AR display, current-culture input).</summary>
public static class PosFormat
{
    // Explicit format provider: independent of the host culture and of invariant-globalization builds.
    private static readonly NumberFormatInfo ArgentineNumbers = new()
    {
        NumberDecimalSeparator = ",",
        NumberGroupSeparator = ".",
        NumberGroupSizes = new[] { 3 },
        NumberDecimalDigits = 2
    };

    private const NumberStyles InputStyles = NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint
        | NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite;

    /// <summary>"$ 1.234" / "$ 1.234,50": cents are shown only when present; negatives keep the sign.</summary>
    public static string Money(decimal amount)
    {
        var text = amount % 1m == 0m ? amount.ToString("N0", ArgentineNumbers) : amount.ToString("N2", ArgentineNumbers);
        return "$ " + text;
    }

    /// <summary>Same rule the old POS used for every amount typed by the user (current culture, no thousands separator).</summary>
    public static bool TryParseDecimal(string? input, out decimal value)
    {
        value = 0m;
        return !string.IsNullOrWhiteSpace(input)
            && decimal.TryParse(input, InputStyles, CultureInfo.CurrentCulture, out value);
    }

    /// <summary>Round-trips through <see cref="TryParseDecimal"/>.</summary>
    public static string InputText(decimal value) => value.ToString(CultureInfo.CurrentCulture);

    public const string InvalidDiscountValueMessage =
        "El valor del descuento debe ser un número decimal válido, sin separador de miles.";

    /// <summary>"Sin descuento" always means zero; any other type needs a typed decimal (same rule as the old POS).</summary>
    public static bool TryReadDiscountValue(Models.DiscountType type, string? text, out decimal value)
    {
        value = 0m;
        return type == Models.DiscountType.None || TryParseDecimal(text, out value);
    }

    /// <summary>Full label, as in the select and the receipt.</summary>
    public static string PaymentLabel(Models.PaymentMethod method) => method switch
    {
        Models.PaymentMethod.Cash => "Efectivo",
        Models.PaymentMethod.DebitCard => "Tarjeta de débito",
        Models.PaymentMethod.CreditCard => "Tarjeta de crédito",
        Models.PaymentMethod.Transfer => "Transferencia",
        Models.PaymentMethod.MercadoPago => "Mercado Pago",
        Models.PaymentMethod.Other => "Otro",
        _ => "Medio inválido"
    };

    /// <summary>Compact label for the one-click method chips.</summary>
    public static string PaymentShortLabel(Models.PaymentMethod method) => method switch
    {
        Models.PaymentMethod.DebitCard => "Débito",
        Models.PaymentMethod.CreditCard => "Crédito",
        _ => PaymentLabel(method)
    };

    public static string DecimalSeparator => CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator;
}
