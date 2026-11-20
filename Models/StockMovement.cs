namespace GastroApp.Models;

// Why the stock of an ingredient changed (S1, S11). Numeric values are persisted; never reorder.
public enum StockMovementType
{
    InvoiceReceipt = 0,
    SaleConsumption = 1,
    SaleCancellationReturn = 2,
    RefundReturn = 3,
    Adjustment = 4,
    Waste = 5,
    CountAdjustment = 6,
    InitialStock = 7
}

// Independent from sales (S8). Numeric values are persisted; never reorder.
public enum WasteCategory
{
    Vencimiento = 0,
    RoturaODerrame = 1,
    ErrorDePreparacion = 2,
    Otro = 3
}

public static class StockMovementLabels
{
    public static string GetLabel(StockMovementType type) => type switch
    {
        StockMovementType.InvoiceReceipt => "Ingreso por compra",
        StockMovementType.SaleConsumption => "Consumo por venta",
        StockMovementType.SaleCancellationReturn => "Reposición por anulación",
        StockMovementType.RefundReturn => "Reposición por devolución",
        StockMovementType.Adjustment => "Ajuste manual",
        StockMovementType.Waste => "Merma",
        StockMovementType.CountAdjustment => "Ajuste por conteo",
        StockMovementType.InitialStock => "Stock inicial",
        _ => "Origen desconocido"
    };

    public static string GetLabel(WasteCategory category) => category switch
    {
        WasteCategory.Vencimiento => "Vencimiento",
        WasteCategory.RoturaODerrame => "Rotura o derrame",
        WasteCategory.ErrorDePreparacion => "Error de preparación",
        WasteCategory.Otro => "Otro",
        _ => "Categoría desconocida"
    };
}

// Append-only ledger entry. Quantity is signed and expressed in the ingredient unit (Unit):
// ResultingStock = PreviousStock + Quantity. Entries are never edited or deleted.
public class StockMovement
{
    public int Id { get; set; }
    public int IngredientId { get; set; }
    public DateTime Date { get; set; }
    public StockMovementType Type { get; set; }
    public decimal Quantity { get; set; }
    public string Unit { get; set; } = string.Empty;
    public decimal PreviousStock { get; set; }
    public decimal ResultingStock { get; set; }
    public string? Reason { get; set; }
    public WasteCategory? WasteCategory { get; set; }
    // Responsible user snapshot; null when the operation had no authenticated actor.
    public int? UserId { get; set; }
    public string? Username { get; set; }
    // Origin document or operation (S11).
    public int? SaleId { get; set; }
    public int? RefundId { get; set; }
    public int? InvoiceId { get; set; }
    public int? StockCountId { get; set; }

    public StockMovement Clone() => (StockMovement)MemberwiseClone();
}

// Query filter. From/To compare calendar days and are both inclusive; null/empty Types means every type.
public class StockMovementFilter
{
    public DateTime? From { get; set; }
    public DateTime? To { get; set; }
    public IReadOnlyCollection<StockMovementType>? Types { get; set; }
}

// One line of a physical count to confirm. The movement quantity is CountedStock minus the stock at
// confirmation; lines without difference create no movement. ExpectedStock (optional) is the registered
// stock the operator saw; a different current stock rejects the whole batch.
public class StockCountAdjustment
{
    public int IngredientId { get; set; }
    public decimal CountedStock { get; set; }
    public decimal? ExpectedStock { get; set; }
    public string? Reason { get; set; }
}
