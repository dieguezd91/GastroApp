namespace GastroApp.Shared.Pos;

/// <summary>
/// What the catalog shows for a product tile. Sales.razor blocks products whose recipe cannot cover one more
/// unit (SaleService.GetAvailability, counting what the cart reserves); checkout still validates stock atomically.
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
