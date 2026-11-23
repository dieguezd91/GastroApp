using System.Globalization;
using GastroApp.Models;
using GastroApp.Shared.Pos;

namespace GastroApp.Shared.Inventory;

/// <summary>Tabs of the unified inventory view; each one is served by its own route.</summary>
public enum InventoryTab
{
    Stock,
    Movements,
    Count
}

/// <summary>Display helpers shared by the inventory tabs. Quantities use the current culture, like the quantity inputs.</summary>
public static class InventoryFormat
{
    public const string StockRoute = "/ingredients";
    public const string MovementsRoute = "/ingredients/movements";
    public const string CountRoute = "/stock/count";

    public static string RouteOf(InventoryTab tab) => tab switch
    {
        InventoryTab.Movements => MovementsRoute,
        InventoryTab.Count => CountRoute,
        _ => StockRoute
    };

    /// <summary>"2,5": up to four decimals, no trailing zeros.</summary>
    public static string Number(decimal value) => value.ToString("0.####", CultureInfo.CurrentCulture);

    /// <summary>"2,5 kg".</summary>
    public static string Qty(decimal value, string unit) => $"{Number(value)} {unit}";

    /// <summary>"+2,5 kg" / "-1 kg" / "0 kg".</summary>
    public static string SignedQty(decimal value, string unit) => $"{value.ToString("+0.####;-0.####;0", CultureInfo.CurrentCulture)} {unit}";

    public static string Money(decimal amount) => PosFormat.Money(amount);

    /// <summary>Stock state of an active ingredient, same thresholds as <see cref="Ingredient.StockIndicator"/>.</summary>
    public static (string Variant, string Label, string Icon) StatusOf(Ingredient ingredient) => ingredient.StockIndicator switch
    {
        "red" => ("danger", "Agotado", "alertOctagon"),
        "yellow" => ("warn", "Bajo mínimo", "alertTriangle"),
        _ => ("ok", "Normal", "checkCircle")
    };

    /// <summary>Badge variant of a ledger entry: entries are green, waste red, other decreases neutral.</summary>
    public static string MovementVariant(StockMovement movement) =>
        movement.Quantity > 0m ? "ok" : movement.Type == StockMovementType.Waste ? "danger" : "neutral";
}
