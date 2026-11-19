using GastroApp.Models;

namespace GastroApp.Services;

// Read-only sales history: nothing here saves, allocates ids or changes a sale.
// Cancellation stays in SaleService; this service only exposes detached snapshots.
public class SaleHistoryService
{
    private const int MaxPageSize = 50;
    private readonly DataStorageService _storage;

    public SaleHistoryService(DataStorageService storage)
    {
        _storage = storage;
    }

    public SaleHistoryPage GetHistory(SaleHistoryFilter filter, User? actor)
    {
        RequireLiveAdmin(actor);
        if (filter == null)
            throw new InvalidOperationException("Debe indicar el filtro del historial.");
        if (filter.DateFrom.HasValue && filter.DateTo.HasValue
            && filter.DateFrom.Value.Date > filter.DateTo.Value.Date)
            throw new InvalidOperationException("La fecha inicial no puede ser posterior a la fecha final.");
        if (filter.OperatorUserId.HasValue && filter.WithoutOperator)
            throw new InvalidOperationException("Elija un operador o «Sin registro», no ambos.");

        var text = filter.ProductText?.Trim();
        var matches = _storage.Sales
            .Where(s => s != null
                && (!filter.DateFrom.HasValue || s.Date.Date >= filter.DateFrom.Value.Date)
                && (!filter.DateTo.HasValue || s.Date.Date <= filter.DateTo.Value.Date)
                && (!filter.SaleId.HasValue || s.Id == filter.SaleId.Value)
                && (!filter.OperatorUserId.HasValue || s.CreatedByUserId == filter.OperatorUserId.Value)
                && (!filter.WithoutOperator || s.CreatedByUserId == null)
                && (!filter.PaymentMethod.HasValue || Payments(s).Any(p => p.PaymentMethod == filter.PaymentMethod.Value))
                && (!filter.CashRegisterId.HasValue || s.CashRegisterId == filter.CashRegisterId.Value)
                && (filter.Status == SaleHistoryStatusFilter.All
                    || s.Status == (filter.Status == SaleHistoryStatusFilter.Cancelled ? SaleStatus.Cancelled : SaleStatus.Completed))
                && (string.IsNullOrEmpty(text) || Items(s).Any(i => i.ProductName != null
                    && i.ProductName.Contains(text, StringComparison.OrdinalIgnoreCase))))
            .OrderByDescending(s => s.Date).ThenByDescending(s => s.Id)
            .ToList();

        var pageSize = Math.Clamp(filter.PageSize, 1, MaxPageSize);
        var totalPages = (matches.Count + pageSize - 1) / pageSize;
        var page = Math.Clamp(filter.Page, 1, Math.Max(totalPages, 1));
        var entries = matches.Skip((page - 1) * pageSize).Take(pageSize).Select(BuildEntry);
        return new SaleHistoryPage(entries, matches.Count, page, pageSize, totalPages);
    }

    // Stable sale ID only; a missing sale is a normal "not found", not an error.
    public SaleHistoryDetail? GetDetail(int saleId, User? actor)
    {
        RequireLiveAdmin(actor);
        var sale = saleId <= 0 ? null : _storage.Sales.FirstOrDefault(s => s != null && s.Id == saleId);
        if (sale == null) return null;

        var lines = Items(sale).Select(i => new SaleHistoryLine(i.ProductId, i.ProductName ?? string.Empty, i.Price,
            i.Quantity, i.Notes, i.DiscountType, i.DiscountValue,
            Amount(() => i.GrossSubtotal), Amount(() => i.DiscountAmount), Amount(() => i.Subtotal)));
        var payments = Payments(sale).Select(p => new SaleHistoryPayment(p.PaymentMethod, p.Amount, p.ReceivedAmount, p.Change));
        var entry = BuildEntry(sale);
        return new SaleHistoryDetail(entry, lines, sale.DiscountType, sale.DiscountValue,
            Amount(() => sale.Subtotal), Amount(() => sale.DiscountAmount), entry.Total, payments, BuildEvents(sale));
    }

    // Distinct users seen on recorded sales (legacy sales without operator are not a user).
    public IReadOnlyList<SaleHistoryOperator> GetOperators(User? actor)
    {
        RequireLiveAdmin(actor);
        return _storage.Sales
            .Where(s => s != null && s.CreatedByUserId.HasValue && !string.IsNullOrWhiteSpace(s.CreatedByUsername))
            .OrderByDescending(s => s.Date).ThenByDescending(s => s.Id)
            .GroupBy(s => s.CreatedByUserId!.Value)
            .Select(g => new SaleHistoryOperator(g.Key, g.First().CreatedByUsername!))
            .OrderBy(o => o.Username, StringComparer.OrdinalIgnoreCase).ThenBy(o => o.UserId)
            .ToList().AsReadOnly();
    }

    // Trusted in-process boundary: the component supplies a fresh scoped actor.
    // Revalidate identity and live role without capturing scoped AuthService here.
    private User RequireLiveAdmin(User? actor)
    {
        var user = actor == null ? null : _storage.Users.FirstOrDefault(u => u.Id == actor.Id);
        if (user == null || user.Id <= 0 || string.IsNullOrWhiteSpace(user.Username)
            || string.IsNullOrWhiteSpace(user.PasswordHash) || user.Username != actor!.Username
            || user.PasswordHash != actor.PasswordHash || user.Role != UserRole.Admin
            || actor.Role != UserRole.Admin)
            throw new UnauthorizedAccessException("Se requiere un usuario administrador vigente.");
        return user;
    }

    // Legacy JSON may hold null collections or null elements.
    private static IEnumerable<SaleItem> Items(Sale sale) => (sale.Items ?? new()).Where(i => i != null);
    private static IEnumerable<SalePayment> Payments(Sale sale) => (sale.Payments ?? new()).Where(p => p != null);

    private static decimal? Amount(Func<decimal> calculate)
    {
        try { return calculate(); }
        catch (OverflowException) { return null; }
    }

    private static SaleHistoryEntry BuildEntry(Sale sale)
    {
        var total = Amount(() => sale.Total);
        return new SaleHistoryEntry(sale.Id, sale.Date, sale.CashRegisterId, sale.CreatedByUserId,
            string.IsNullOrWhiteSpace(sale.CreatedByUsername) ? null : sale.CreatedByUsername,
            sale.Status, total, Items(sale).Sum(i => (long)i.Quantity),
            Items(sale).Select(i => i.ProductName ?? string.Empty),
            Payments(sale).Select(p => p.PaymentMethod).Distinct(), total == null);
    }

    // Chronological events; refund events join this list later.
    private static IEnumerable<SaleHistoryEvent> BuildEvents(Sale sale)
    {
        yield return new SaleHistoryEvent(SaleHistoryEventKind.Created, sale.Date, sale.CreatedByUserId,
            string.IsNullOrWhiteSpace(sale.CreatedByUsername) ? null : sale.CreatedByUsername, null);
        if (sale.Status == SaleStatus.Cancelled)
            yield return new SaleHistoryEvent(SaleHistoryEventKind.Cancelled, sale.CancelledAt, sale.CancelledByUserId,
                string.IsNullOrWhiteSpace(sale.CancelledByUsername) ? null : sale.CancelledByUsername,
                string.IsNullOrWhiteSpace(sale.CancellationReason) ? null : sale.CancellationReason);
    }
}
