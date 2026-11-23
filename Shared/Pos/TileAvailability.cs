namespace GastroApp.Shared.Pos;

/// <summary>
/// What the catalog shows for a product tile. T4 (stock pre-block) replaces the provider in Sales.razor with
/// one that blocks products whose recipe cannot be covered; today everything is available and the server
/// still validates stock atomically at checkout.
/// </summary>
/// <param name="IsBlocked">Renders aria-disabled and prevents adding the product.</param>
/// <param name="Reason">Why it is blocked (e.g. the missing ingredient); announced to assistive tech.</param>
/// <param name="BadgeLabel">Optional short status badge ("Sin stock", "Quedan 3").</param>
/// <param name="BadgeVariant">Badge variant: warn | danger.</param>
public sealed record TileAvailability(bool IsBlocked = false, string? Reason = null,
    string? BadgeLabel = null, string BadgeVariant = "warn")
{
    public static TileAvailability Available { get; } = new();
}
