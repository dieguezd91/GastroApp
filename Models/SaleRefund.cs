namespace GastroApp.Models;

// What happens to the physical goods of a refunded line (S7).
public enum RefundDisposition
{
    Restock = 0, // Valid physical return: ingredients go back to stock.
    Waste = 1    // Merma: money is returned, stock is not touched.
}

// Derived, never persisted: Cobrada / Anulada / Parcialmente devuelta / Devuelta (S4).
public enum SaleDisplayStatus
{
    Collected = 0,
    Cancelled = 1,
    PartiallyRefunded = 2,
    Refunded = 3
}

// As a command input only SaleItemIndex, Quantity and Disposition are read; Amount is computed.
public class SaleRefundLine
{
    public int SaleItemIndex { get; set; }
    public int Quantity { get; set; }
    public RefundDisposition Disposition { get; set; }
    public decimal Amount { get; set; }

    public SaleRefundLine Clone() => new()
    {
        SaleItemIndex = SaleItemIndex, Quantity = Quantity, Disposition = Disposition, Amount = Amount
    };
}

public class SaleRefundPayment
{
    public PaymentMethod PaymentMethod { get; set; }
    public decimal Amount { get; set; }

    public SaleRefundPayment Clone() => new() { PaymentMethod = PaymentMethod, Amount = Amount };
}

// Append-only record; the sale is never deleted or rewritten to reflect it (S8, S9).
public class SaleRefund
{
    public int Id { get; set; }
    public int SaleId { get; set; }
    public DateTime Date { get; set; }
    public int UserId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    // Register where the cash outflow (or the non-cash reporting) was booked; null without an open register.
    public int? CashRegisterId { get; set; }
    public List<SaleRefundLine> Lines { get; set; } = new();
    public List<SaleRefundPayment> Payments { get; set; } = new();
    public decimal Total { get; set; }

    public SaleRefund Clone() => new()
    {
        Id = Id, SaleId = SaleId, Date = Date, UserId = UserId, Username = Username, Reason = Reason,
        CashRegisterId = CashRegisterId, Total = Total,
        Lines = Lines.Select(l => l.Clone()).ToList(), Payments = Payments.Select(p => p.Clone()).ToList()
    };
}

// Result of PreviewRefund: the computed (not caller-provided) amounts.
public sealed class SaleRefundPreview
{
    public IReadOnlyList<SaleRefundLine> Lines { get; }
    public decimal Total { get; }

    internal SaleRefundPreview(IEnumerable<SaleRefundLine> lines, decimal total)
    {
        Lines = lines.Select(l => l.Clone()).ToList().AsReadOnly();
        Total = total;
    }
}

public sealed class SaleRefundLineStatus
{
    public int SaleItemIndex { get; }
    public string ProductName { get; }
    public int SoldQuantity { get; }
    public int RefundedQuantity { get; }
    public int RemainingQuantity => SoldQuantity - RefundedQuantity;
    // False for legacy lines or unreliable sales: only Waste is allowed there.
    public bool CanRestock { get; }

    internal SaleRefundLineStatus(int index, string productName, int sold, int refunded, bool canRestock)
    {
        SaleItemIndex = index; ProductName = productName; SoldQuantity = sold;
        RefundedQuantity = refunded; CanRestock = canRestock;
    }
}

public sealed class SaleRefundMethodStatus
{
    public PaymentMethod PaymentMethod { get; }
    public decimal PaidAmount { get; }
    public decimal RefundedAmount { get; }
    public decimal RemainingAmount => Math.Max(0m, PaidAmount - RefundedAmount);

    internal SaleRefundMethodStatus(PaymentMethod method, decimal paid, decimal refunded)
    {
        PaymentMethod = method; PaidAmount = paid; RefundedAmount = refunded;
    }
}

// What T4 needs to render the refund form of one sale.
public sealed class SaleRefundability
{
    public int SaleId { get; }
    public SaleDisplayStatus Status { get; }
    public decimal SaleTotal { get; }
    public decimal RefundedTotal { get; }
    public decimal RemainingTotal => Math.Max(0m, SaleTotal - RefundedTotal);
    public IReadOnlyList<SaleRefundLineStatus> Lines { get; }
    public IReadOnlyList<SaleRefundMethodStatus> Methods { get; }
    public bool CanRefund => Status != SaleDisplayStatus.Cancelled && Lines.Any(l => l.RemainingQuantity > 0);

    internal SaleRefundability(int saleId, SaleDisplayStatus status, decimal saleTotal, decimal refundedTotal,
        IEnumerable<SaleRefundLineStatus> lines, IEnumerable<SaleRefundMethodStatus> methods)
    {
        SaleId = saleId; Status = status; SaleTotal = saleTotal; RefundedTotal = refundedTotal;
        Lines = lines.ToList().AsReadOnly(); Methods = methods.ToList().AsReadOnly();
    }
}
