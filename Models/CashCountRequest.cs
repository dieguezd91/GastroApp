namespace GastroApp.Models;

// Session state the counter reviewed; any movement changes it, even a +X/-X pair that keeps the balance.
public record CashCountReview(int RegisterId, decimal ExpectedAmount, int MovementCount, int LastMovementId);

public record CashCountLineInput(decimal Denomination, int Quantity);

public class CashCountRequest
{
    public CashCountReview Review { get; set; } = null!;
    public IReadOnlyList<CashCountLineInput> Lines { get; set; } = Array.Empty<CashCountLineInput>();
    public string? Reason { get; set; }
    public bool Confirmed { get; set; }
    public bool ZeroCountConfirmed { get; set; }
}

public enum CashCountOutcome { Exact, Surplus, Shortage }

public class CashCountPreview
{
    public IReadOnlyList<CashCountLine> Lines { get; }
    public decimal CountedAmount { get; }
    public decimal ExpectedAmount { get; }
    public decimal Difference { get; }
    public CashCountOutcome Outcome { get; }

    public CashCountPreview(IEnumerable<CashCountLine> lines, decimal countedAmount, decimal expectedAmount, decimal difference)
    {
        Lines = lines.Select(l => l.Clone()).ToList().AsReadOnly();
        CountedAmount = countedAmount;
        ExpectedAmount = expectedAmount;
        Difference = difference;
        Outcome = difference == 0m ? CashCountOutcome.Exact
            : difference > 0m ? CashCountOutcome.Surplus : CashCountOutcome.Shortage;
    }
}

public class CashCountReviewOutdatedException : InvalidOperationException
{
    public CashCountReview Current { get; }

    public CashCountReviewOutdatedException(CashCountReview current)
        : base("El saldo esperado de la caja cambió desde la revisión. Revisá el arqueo nuevamente.")
    {
        Current = current;
    }
}
