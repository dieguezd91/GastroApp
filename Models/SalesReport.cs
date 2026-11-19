namespace GastroApp.Models;

// Derived, never persisted: one day of sales reporting (S13). Closed DailySummary records are not inputs.
public sealed class SalesReport
{
    public DateTime Date { get; }
    // List price before any line or sale discount, of the Completed sales of the day.
    public decimal GrossSales { get; }
    // Line and sale discounts of those same sales.
    public decimal Discounts { get; }
    // GrossSales - Discounts: the existing "Total Vendido" (completed sales only, cancelled ones excluded).
    public decimal SoldTotal => GrossSales - Discounts;
    public int SalesCount { get; }
    // Final total (after discounts) and number of sales of the day that were cancelled; excluded from every figure above.
    public decimal CancelledTotal { get; }
    public int CancelledCount { get; }
    // Refunds dated on the day, whatever the date of the refunded sale.
    public decimal RefundedTotal { get; }
    public int RefundCount { get; }
    // SoldTotal - RefundedTotal.
    public decimal NetTotal => SoldTotal - RefundedTotal;

    internal SalesReport(DateTime date, decimal grossSales, decimal discounts, int salesCount,
        decimal cancelledTotal, int cancelledCount, decimal refundedTotal, int refundCount)
    {
        Date = date; GrossSales = grossSales; Discounts = discounts; SalesCount = salesCount;
        CancelledTotal = cancelledTotal; CancelledCount = cancelledCount;
        RefundedTotal = refundedTotal; RefundCount = refundCount;
    }
}
