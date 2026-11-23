using GastroApp.Models;
using GastroApp.Shared.Pos;

namespace GastroApp.Shared.SalesHistory;

/// <summary>Display helpers shared by the sales-history components (es-AR amounts; unavailable figures are never invented).</summary>
public static class SaleHistoryFormat
{
    public const string Unavailable = "No disponible";

    public static string Money(decimal? amount) => amount.HasValue ? PosFormat.Money(amount.Value) : Unavailable;

    public static string DiscountLabel(DiscountType type, decimal value, decimal? amount) => type switch
    {
        DiscountType.Percentage => $"{value}% ({Money(amount)})",
        DiscountType.Fixed => $"{PosFormat.Money(value)} fijo ({Money(amount)})",
        _ => "Sin descuento"
    };

    /// <summary>Badge variant of a derived sale status: collected = ok, cancelled = danger, partial refund = warn, full refund = neutral.</summary>
    public static string StatusVariant(SaleDisplayStatus status) => status switch
    {
        SaleDisplayStatus.Collected => "ok",
        SaleDisplayStatus.Cancelled => "danger",
        SaleDisplayStatus.PartiallyRefunded => "warn",
        _ => "neutral"
    };
}
