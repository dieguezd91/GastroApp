namespace GastroApp.Models;

// Definitive physical count stored once per closed session; legacy sessions have none.
public class CashCount
{
    public int CashRegisterId { get; set; }
    public DateTime CountedAt { get; set; }
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public List<CashCountLine> Lines { get; set; } = new();
    public decimal ExpectedAmount { get; set; }
    public decimal CountedAmount { get; set; }
    public decimal Difference { get; set; }
    public string? Reason { get; set; }

    public CashCount Clone() => new()
    {
        CashRegisterId = CashRegisterId, CountedAt = CountedAt, UserId = UserId, Username = Username,
        Lines = Lines.Select(l => l.Clone()).ToList(), ExpectedAmount = ExpectedAmount,
        CountedAmount = CountedAmount, Difference = Difference, Reason = Reason
    };
}

public class CashCountLine
{
    public decimal Denomination { get; set; }
    public int Quantity { get; set; }
    public decimal Subtotal { get; set; }

    public CashCountLine Clone() => new() { Denomination = Denomination, Quantity = Quantity, Subtotal = Subtotal };
}
