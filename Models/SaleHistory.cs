namespace GastroApp.Models;

// Completed = display status Collected (cobradas sin devoluciones); refunded sales have their own filters.
public enum SaleHistoryStatusFilter { All, Completed, Cancelled, PartiallyRefunded, Refunded }

// Dates compare by calendar day (time of day ignored), inclusive at both ends.
// OperatorUserId selects one user; WithoutOperator selects legacy sales without one ("Sin registro").
public sealed record SaleHistoryFilter(DateTime? DateFrom = null, DateTime? DateTo = null, int? SaleId = null,
    int? OperatorUserId = null, bool WithoutOperator = false, PaymentMethod? PaymentMethod = null,
    int? CashRegisterId = null, SaleHistoryStatusFilter Status = SaleHistoryStatusFilter.All,
    string? ProductText = null, int Page = 1, int PageSize = 10);

public sealed class SaleHistoryOperator
{
    public int UserId { get; }
    public string Username { get; }

    internal SaleHistoryOperator(int userId, string username) { UserId = userId; Username = username; }
}

// Detached, derived snapshot of one sale. Null amounts mean unavailable (decimal overflow), never a fabricated zero.
public sealed class SaleHistoryEntry
{
    public int Id { get; }
    public DateTime Date { get; }
    public int? CashRegisterId { get; }
    // Null for legacy sales: the UI shows "Sin registro".
    public int? OperatorUserId { get; }
    public string? OperatorUsername { get; }
    public SaleStatus Status { get; }
    // Derived: Collected / Cancelled / PartiallyRefunded / Refunded (S4). Status stays the stored sale state.
    public SaleDisplayStatus DisplayStatus { get; }
    public decimal? Total { get; }
    // Sum of recorded refunds; null when unavailable (decimal overflow).
    public decimal? RefundedTotal { get; }
    public long ItemCount { get; }
    public IReadOnlyList<string> ProductNames { get; }
    public IReadOnlyList<PaymentMethod> PaymentMethods { get; }
    public bool AmountsUnavailable { get; }

    internal SaleHistoryEntry(int id, DateTime date, int? cashRegisterId, int? operatorUserId, string? operatorUsername,
        SaleStatus status, SaleDisplayStatus displayStatus, decimal? total, decimal? refundedTotal, long itemCount,
        IEnumerable<string> productNames, IEnumerable<PaymentMethod> paymentMethods, bool amountsUnavailable)
    {
        Id = id; Date = date; CashRegisterId = cashRegisterId; OperatorUserId = operatorUserId;
        OperatorUsername = operatorUsername; Status = status; DisplayStatus = displayStatus; Total = total;
        RefundedTotal = refundedTotal; ItemCount = itemCount;
        ProductNames = productNames.ToList().AsReadOnly();
        PaymentMethods = paymentMethods.ToList().AsReadOnly();
        AmountsUnavailable = amountsUnavailable;
    }
}

public sealed class SaleHistoryPage
{
    public IReadOnlyList<SaleHistoryEntry> Entries { get; }
    public int TotalCount { get; }
    public int Page { get; }
    public int PageSize { get; }
    public int TotalPages { get; }

    internal SaleHistoryPage(IEnumerable<SaleHistoryEntry> entries, int totalCount, int page, int pageSize, int totalPages)
    {
        Entries = entries.ToList().AsReadOnly();
        TotalCount = totalCount; Page = page; PageSize = pageSize; TotalPages = totalPages;
    }
}

public sealed class SaleHistoryLine
{
    public int ProductId { get; }
    public string ProductName { get; }
    public decimal Price { get; }
    public int Quantity { get; }
    public string? Notes { get; }
    public DiscountType DiscountType { get; }
    public decimal DiscountValue { get; }
    public decimal? GrossSubtotal { get; }
    public decimal? DiscountAmount { get; }
    public decimal? Subtotal { get; }

    internal SaleHistoryLine(int productId, string productName, decimal price, int quantity, string? notes,
        DiscountType discountType, decimal discountValue, decimal? grossSubtotal, decimal? discountAmount, decimal? subtotal)
    {
        ProductId = productId; ProductName = productName; Price = price; Quantity = quantity; Notes = notes;
        DiscountType = discountType; DiscountValue = discountValue;
        GrossSubtotal = grossSubtotal; DiscountAmount = discountAmount; Subtotal = subtotal;
    }
}

public sealed class SaleHistoryPayment
{
    public PaymentMethod Method { get; }
    public decimal Amount { get; }
    public decimal? ReceivedAmount { get; }
    public decimal Change { get; }

    internal SaleHistoryPayment(PaymentMethod method, decimal amount, decimal? receivedAmount, decimal change)
    {
        Method = method; Amount = amount; ReceivedAmount = receivedAmount; Change = change;
    }
}

// Consumers must not assume a fixed set of kinds.
public enum SaleHistoryEventKind { Created, Cancelled, Refunded }

// At/user/reason are null when a legacy record never stored them.
// Amount and RefundId are only set on Refunded events.
public sealed class SaleHistoryEvent
{
    public SaleHistoryEventKind Kind { get; }
    public DateTime? At { get; }
    public int? UserId { get; }
    public string? Username { get; }
    public string? Reason { get; }
    public decimal? Amount { get; }
    public int? RefundId { get; }

    internal SaleHistoryEvent(SaleHistoryEventKind kind, DateTime? at, int? userId, string? username, string? reason,
        decimal? amount = null, int? refundId = null)
    {
        Kind = kind; At = at; UserId = userId; Username = username; Reason = reason;
        Amount = amount; RefundId = refundId;
    }
}

public sealed class SaleHistoryDetail
{
    public SaleHistoryEntry Entry { get; }
    public IReadOnlyList<SaleHistoryLine> Lines { get; }
    public DiscountType SaleDiscountType { get; }
    public decimal SaleDiscountValue { get; }
    public decimal? Subtotal { get; }
    public decimal? DiscountAmount { get; }
    public decimal? Total { get; }
    public IReadOnlyList<SaleHistoryPayment> Payments { get; }
    public IReadOnlyList<SaleHistoryEvent> Events { get; }

    internal SaleHistoryDetail(SaleHistoryEntry entry, IEnumerable<SaleHistoryLine> lines, DiscountType saleDiscountType,
        decimal saleDiscountValue, decimal? subtotal, decimal? discountAmount, decimal? total,
        IEnumerable<SaleHistoryPayment> payments, IEnumerable<SaleHistoryEvent> events)
    {
        Entry = entry; SaleDiscountType = saleDiscountType; SaleDiscountValue = saleDiscountValue;
        Subtotal = subtotal; DiscountAmount = discountAmount; Total = total;
        Lines = lines.ToList().AsReadOnly();
        Payments = payments.ToList().AsReadOnly();
        Events = events.ToList().AsReadOnly();
    }
}
