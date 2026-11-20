namespace GastroApp.Models;

// Persisted physical stock count (S4). Immutable once confirmed: the lines are a snapshot of what the
// operator saw and counted, and every line with a difference has a CountAdjustment movement in the ledger
// that carries this count's Id (S11).
public class StockCount
{
    public int Id { get; set; }
    public DateTime Date { get; set; }
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string? Notes { get; set; }
    public List<StockCountLine> Lines { get; set; } = new();
    // Lines whose difference was not zero, that is, lines that created a movement.
    public int AdjustedLineCount { get; set; }

    public StockCount Clone()
    {
        var copy = (StockCount)MemberwiseClone();
        copy.Lines = Lines.Select(l => l.Clone()).ToList();
        return copy;
    }
}

// Difference = CountedStock - ExpectedStock, in the ingredient unit. Reason is mandatory when it is not zero.
public class StockCountLine
{
    public int IngredientId { get; set; }
    public string IngredientName { get; set; } = string.Empty;
    public string Unit { get; set; } = string.Empty;
    public decimal ExpectedStock { get; set; }
    public decimal CountedStock { get; set; }
    public decimal Difference { get; set; }
    public string? Reason { get; set; }

    public StockCountLine Clone() => (StockCountLine)MemberwiseClone();
}

public enum StockCountDifferenceKind
{
    Match = 0,
    Shortage = 1,
    Surplus = 2
}

public static class StockCountLabels
{
    public static StockCountDifferenceKind GetKind(decimal difference) =>
        difference < 0m ? StockCountDifferenceKind.Shortage
        : difference > 0m ? StockCountDifferenceKind.Surplus
        : StockCountDifferenceKind.Match;

    public static string GetLabel(StockCountDifferenceKind kind) => kind switch
    {
        StockCountDifferenceKind.Shortage => "Faltante",
        StockCountDifferenceKind.Surplus => "Sobrante",
        _ => "Sin diferencia"
    };

    public static string GetLabel(decimal difference) => GetLabel(GetKind(difference));
}

// One ingredient of a count as entered by the operator. ExpectedStock is the registered stock shown by the
// preview; Confirm requires it so a stock that moved in the meantime is detected.
public class StockCountLineInput
{
    public int IngredientId { get; set; }
    public decimal? CountedStock { get; set; }
    public decimal? ExpectedStock { get; set; }
    public string? Reason { get; set; }
}

public class StockCountRequest
{
    public List<StockCountLineInput> Lines { get; set; } = new();
    public string? Notes { get; set; }
    // The operator explicitly confirms the differences (S4).
    public bool Confirmed { get; set; }
}

public class StockCountPreviewLine
{
    public int IngredientId { get; init; }
    public string IngredientName { get; init; } = string.Empty;
    public string Unit { get; init; } = string.Empty;
    public decimal ExpectedStock { get; init; }
    public decimal CountedStock { get; init; }
    public decimal Difference { get; init; }
    public StockCountDifferenceKind Kind => StockCountLabels.GetKind(Difference);
    // S10: the registered stock was already negative; the count shows a visible warning.
    public bool HasNegativeStock => ExpectedStock < 0m;
}

public class StockCountPreview
{
    public IReadOnlyList<StockCountPreviewLine> Lines { get; init; } = Array.Empty<StockCountPreviewLine>();
    public int AdjustedLineCount => Lines.Count(l => l.Difference != 0m);
}
