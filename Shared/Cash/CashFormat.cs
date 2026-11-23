using GastroApp.Shared.Pos;

namespace GastroApp.Shared.Cash;

/// <summary>Display helpers shared by the cash screens (es-AR amounts, never a fabricated zero for unavailable figures).</summary>
public static class CashFormat
{
    public const string Unavailable = "No disponible";

    public static string Money(decimal? amount) => amount.HasValue ? PosFormat.Money(amount.Value) : Unavailable;

    /// <summary>Cell classes of a refunded amount: highlighted only when something was refunded.</summary>
    public static string RefundClass(decimal? refunded) => refunded is > 0m ? "col-num text-danger" : "col-num text-muted";

    /// <summary>Positive differences carry an explicit "+"; negative ones keep the sign of <see cref="PosFormat.Money"/>.</summary>
    public static string SignedMoney(decimal amount) => amount > 0m ? "+" + PosFormat.Money(amount) : PosFormat.Money(amount);

    /// <summary>Badge variant and icon for a count difference: exact = ok, surplus = info, shortage = danger.</summary>
    public static (string Variant, string Icon) DifferenceBadge(decimal difference) =>
        difference < 0m ? ("danger", "alertOctagon") : difference > 0m ? ("info", "info") : ("ok", "checkCircle");
}
