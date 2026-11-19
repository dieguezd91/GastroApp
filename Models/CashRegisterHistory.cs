namespace GastroApp.Models;

public enum CashHistoryStatusFilter { All, Open, Closed }

// Dates compare by calendar day (time of day ignored), inclusive at both ends.
public sealed record CashHistoryFilter(DateTime? OpenedFrom = null, DateTime? OpenedTo = null,
    CashHistoryStatusFilter Status = CashHistoryStatusFilter.All, int Page = 1, int PageSize = 10);

// Detached, derived snapshot of one session. Null amounts mean not applicable or unavailable, never a fabricated zero.
public sealed class CashHistoryEntry
{
    public int Id { get; }
    public DateTime OpenDate { get; }
    public DateTime? CloseDate { get; }
    public bool IsOpen { get; }
    public decimal InitialAmount { get; }
    public decimal? ExpectedAmount { get; }
    public decimal? CountedAmount { get; }
    public decimal? Difference { get; }
    public bool HasCount { get; }
    public bool AmountsUnavailable { get; }

    internal CashHistoryEntry(int id, DateTime openDate, DateTime? closeDate, bool isOpen, decimal initialAmount,
        decimal? expectedAmount, decimal? countedAmount, decimal? difference, bool hasCount, bool amountsUnavailable)
    {
        Id = id; OpenDate = openDate; CloseDate = closeDate; IsOpen = isOpen; InitialAmount = initialAmount;
        ExpectedAmount = expectedAmount; CountedAmount = countedAmount; Difference = difference;
        HasCount = hasCount; AmountsUnavailable = amountsUnavailable;
    }
}

public sealed class CashHistoryPage
{
    public IReadOnlyList<CashHistoryEntry> Entries { get; }
    public int TotalCount { get; }
    public int Page { get; }
    public int PageSize { get; }
    public int TotalPages { get; }

    internal CashHistoryPage(IEnumerable<CashHistoryEntry> entries, int totalCount, int page, int pageSize, int totalPages)
    {
        Entries = entries.ToList().AsReadOnly();
        TotalCount = totalCount; Page = page; PageSize = pageSize; TotalPages = totalPages;
    }
}

public sealed class CashHistoryDetail
{
    public CashHistoryEntry Entry { get; }
    public IReadOnlyList<CashMovement> Movements { get; }
    public CashPaymentSummary PaymentSummary { get; }
    public CashCount? Count { get; }
    public IReadOnlyList<DailySummary> LinkedSummaries { get; }

    internal CashHistoryDetail(CashHistoryEntry entry, IEnumerable<CashMovement> movements,
        CashPaymentSummary paymentSummary, CashCount? count, IEnumerable<DailySummary> linkedSummaries)
    {
        Entry = entry; PaymentSummary = paymentSummary; Count = count;
        Movements = movements.ToList().AsReadOnly();
        LinkedSummaries = linkedSummaries.ToList().AsReadOnly();
    }
}
