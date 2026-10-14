namespace GastroApp.Models;

public enum CashPaymentSummaryState { NoSession, Complete, Partial, Unavailable }

public enum CashPaymentWarningReason
{
    UnlinkedHistoricalSales, UnattributedInvalidSales, InvalidSaleItems,
    InvalidPayments, MissingPayments, AllocationMismatch, ArithmeticOverflow
}

public sealed class CashPaymentRow
{
    public PaymentMethod Method { get; }
    public decimal? Amount { get; }
    internal CashPaymentRow(PaymentMethod method, decimal? amount) { Method = method; Amount = amount; }
}

public sealed class CashPaymentWarning
{
    public CashPaymentWarningReason Reason { get; }
    public int Count { get; }
    public bool IsGlobal => Reason is CashPaymentWarningReason.UnlinkedHistoricalSales
        or CashPaymentWarningReason.UnattributedInvalidSales;
    public string Message => Reason switch
    {
        CashPaymentWarningReason.UnlinkedHistoricalSales => "Advertencia global: ventas históricas sin caja vinculada; no se atribuyen a esta sesión.",
        CashPaymentWarningReason.UnattributedInvalidSales => "Advertencia global: registros de venta nulos sin sesión identificable.",
        CashPaymentWarningReason.InvalidSaleItems => "Ventas excluidas: productos o descuentos inválidos; no se puede validar el total.",
        CashPaymentWarningReason.InvalidPayments => "Ventas excluidas: pagos nulos, medios desconocidos o repetidos, o importes no positivos.",
        CashPaymentWarningReason.MissingPayments => "Ventas excluidas: faltan pagos para un total positivo.",
        CashPaymentWarningReason.AllocationMismatch => "Ventas excluidas: los importes de pago no coinciden exactamente con el total final.",
        _ => "Resumen no disponible: desbordamiento decimal al calcular una venta, sus pagos o los cobros acumulados. No se muestran importes."
    };
    internal CashPaymentWarning(CashPaymentWarningReason reason, int count) { Reason = reason; Count = count; }
}

// Detached, derived snapshot. Null amounts mean unavailable, never a fabricated zero.
public sealed class CashPaymentSummary
{
    public int? CashRegisterId { get; }
    public CashPaymentSummaryState State { get; }
    public IReadOnlyList<CashPaymentRow> Rows { get; }
    public decimal? RegisteredTotal { get; }
    public IReadOnlyList<CashPaymentWarning> Warnings { get; }

    internal CashPaymentSummary(int? registerId, CashPaymentSummaryState state,
        IEnumerable<CashPaymentRow> rows, decimal? total, IEnumerable<CashPaymentWarning> warnings)
    {
        CashRegisterId = registerId; State = state; RegisteredTotal = total;
        Rows = rows.ToList().AsReadOnly();
        Warnings = warnings.ToList().AsReadOnly();
    }
}
