using GastroApp.Models;

namespace GastroApp.Services;

public class CashRegisterService
{
    private readonly DataStorageService _storage;
    private readonly SaleService _saleService;

    public CashRegisterService(DataStorageService storage, SaleService saleService)
    {
        _storage = storage;
        _saleService = saleService;
    }

    public CashRegister? GetCurrent() => _storage.CurrentCashRegister;

    public bool IsOpen() => _storage.CurrentCashRegister?.IsOpen ?? false;

    public decimal GetCashInflow(int registerId) => _storage.GetCashInflow(registerId);
    public decimal GetExpectedCash(int registerId) => _storage.GetExpectedCash(registerId);

    // Copies protect the append-only ledger even though the existing model is mutable.
    public IReadOnlyList<CashMovement> GetCurrentMovements()
    {
        var registerId = _storage.CurrentCashRegisterId;
        return _storage.CashMovements.Where(m => m.CashRegisterId == registerId)
            .Select(m => new CashMovement
            {
                Id = m.Id, CashRegisterId = m.CashRegisterId, Date = m.Date,
                Type = m.Type, Amount = m.Amount, SaleId = m.SaleId,
                UserId = m.UserId, Username = m.Username, Reason = m.Reason
            }).ToList().AsReadOnly();
    }

    // Session identity only: dates, sale status, tender and the movement ledger are not inputs.
    public CashPaymentSummary GetCurrentPaymentSummary()
    {
        var registerId = GetCurrent()?.Id;
        var amounts = Enum.GetValues<PaymentMethod>().ToDictionary(method => method, _ => 0m);
        var warningCounts = new Dictionary<CashPaymentWarningReason, int>();
        decimal total = 0m;
        bool unavailable = false;
        void Warn(CashPaymentWarningReason reason) =>
            warningCounts[reason] = warningCounts.GetValueOrDefault(reason) + 1;

        foreach (var sale in _storage.Sales)
        {
            if (sale == null) { Warn(CashPaymentWarningReason.UnattributedInvalidSales); continue; }
            if (!sale.CashRegisterId.HasValue) { Warn(CashPaymentWarningReason.UnlinkedHistoricalSales); continue; }
            if (!registerId.HasValue || sale.CashRegisterId != registerId) continue;

            try
            {
                var invalidReason = ValidateReceipt(sale);
                if (invalidReason.HasValue) { Warn(invalidReason.Value); continue; }
                if (unavailable) continue;
                // Validate the WHOLE sale before adding any allocation. Overflow hides all totals.
                foreach (var payment in sale.Payments)
                {
                    amounts[payment.PaymentMethod] = checked(amounts[payment.PaymentMethod] + payment.Amount);
                    total = checked(total + payment.Amount);
                }
            }
            catch (OverflowException)
            {
                unavailable = true;
                Warn(CashPaymentWarningReason.ArithmeticOverflow);
            }
        }

        var state = unavailable ? CashPaymentSummaryState.Unavailable
            : !registerId.HasValue ? CashPaymentSummaryState.NoSession
            : warningCounts.Count > 0 ? CashPaymentSummaryState.Partial : CashPaymentSummaryState.Complete;
        return new CashPaymentSummary(registerId, state,
            amounts.Select(pair => new CashPaymentRow(pair.Key, unavailable ? null : pair.Value)),
            unavailable ? null : total,
            warningCounts.Select(pair => new CashPaymentWarning(pair.Key, pair.Value)));
    }

    // Historical receipt validation deliberately differs from checkout: no tender or catalog checks.
    private static CashPaymentWarningReason? ValidateReceipt(Sale sale)
    {
        if (sale.Items == null || sale.Items.Count == 0)
            return CashPaymentWarningReason.InvalidSaleItems;
        foreach (var item in sale.Items)
        {
            if (item == null || item.Quantity <= 0 || item.Price < 0m
                || !SaleService.ValidateDiscount(item.DiscountType, item.DiscountValue,
                    item.GrossSubtotal, "").IsValid)
                return CashPaymentWarningReason.InvalidSaleItems;
        }
        if (!SaleService.ValidateDiscount(sale.DiscountType, sale.DiscountValue, sale.Subtotal, "").IsValid)
            return CashPaymentWarningReason.InvalidSaleItems;
        var saleTotal = sale.Total; // Existing model arithmetic/precision, never a clamped malformed substitute.
        if (sale.Payments == null) return CashPaymentWarningReason.InvalidPayments;
        if (saleTotal == 0m)
            return sale.Payments.Count == 0 ? null : CashPaymentWarningReason.AllocationMismatch;
        if (sale.Payments.Count == 0) return CashPaymentWarningReason.MissingPayments;

        var methods = new HashSet<PaymentMethod>();
        decimal allocated = 0m;
        foreach (var payment in sale.Payments)
        {
            if (payment == null || !Enum.IsDefined(payment.PaymentMethod)
                || !methods.Add(payment.PaymentMethod) || payment.Amount <= 0m)
                return CashPaymentWarningReason.InvalidPayments;
            allocated = checked(allocated + payment.Amount);
        }
        return allocated == saleTotal ? null : CashPaymentWarningReason.AllocationMismatch;
    }

    public void AddManualMovement(CashMovementType type, decimal amount, string? reason, User? actor)
    {
        if (type != CashMovementType.Income && type != CashMovementType.Expense
            && type != CashMovementType.Withdrawal)
            throw new InvalidOperationException("El tipo de movimiento manual no es válido.");
        if (amount <= 0m)
            throw new InvalidOperationException("El monto debe ser mayor que cero.");
        var trimmedReason = reason?.Trim();
        if (string.IsNullOrWhiteSpace(trimmedReason))
            throw new InvalidOperationException("Debe indicar un motivo para el movimiento.");

        var register = _storage.CurrentCashRegister;
        if (register?.IsOpen != true)
            throw new InvalidOperationException("Debe haber una caja abierta para registrar movimientos.");

        // Trusted in-process boundary: the component supplies a fresh scoped actor.
        // Revalidate identity and live role without capturing scoped AuthService here.
        var user = actor == null ? null : _storage.Users.FirstOrDefault(u => u.Id == actor.Id);
        if (user == null || user.Id <= 0 || string.IsNullOrWhiteSpace(user.Username)
            || string.IsNullOrWhiteSpace(user.PasswordHash) || user.Username != actor!.Username
            || user.PasswordHash != actor.PasswordHash || user.Role != UserRole.Admin
            || actor.Role != UserRole.Admin)
            throw new UnauthorizedAccessException("Se requiere un usuario administrador vigente.");

        try
        {
            var available = GetExpectedCash(register.Id);
            if (type != CashMovementType.Income && amount > available)
                throw new InvalidOperationException("El monto supera el efectivo disponible en caja.");
            _ = checked(available + (type == CashMovementType.Income ? amount : -amount));
            // Gross inflow may overflow even when withdrawals leave a small balance.
            if (type == CashMovementType.Income)
                _ = checked(GetCashInflow(register.Id) + amount);
        }
        catch (OverflowException)
        {
            throw new InvalidOperationException("El saldo o ingreso de caja supera el límite permitido.");
        }
        _storage.EnsureCashMovementCapacity();

        var movement = new CashMovement
        {
            Id = _storage.GetNextCashMovementId(), Date = DateTime.Now,
            CashRegisterId = register.Id, Type = type, Amount = amount,
            UserId = user.Id, Username = user.Username, Reason = trimmedReason, SaleId = null
        };
        _storage.CashMovements.Add(movement);
        _storage.SaveToFile();
    }

    public void Open(decimal initialAmount) => _storage.OpenCashRegister(initialAmount);

    public DailySummary Close(decimal finalAmount)
    {
        if (finalAmount < 0m)
            throw new InvalidOperationException("El monto final no puede ser negativo.");
        if (_storage.CurrentCashRegister == null || !_storage.CurrentCashRegister.IsOpen)
            throw new InvalidOperationException("No hay caja abierta");

        var cashRegister = _storage.CurrentCashRegister;
        var expected = GetExpectedCash(cashRegister.Id);
        var topProduct = _saleService.GetTopProduct();
        var totalSales = _saleService.GetTodayTotal();
        var salesCount = _saleService.GetTodayCount();
        cashRegister.FinalAmount = finalAmount;
        cashRegister.ExpectedAmount = expected;
        cashRegister.IsOpen = false;
        cashRegister.CloseDate = DateTime.Now;

        var summary = new DailySummary
        {
            Date = DateTime.Today,
            TotalSales = totalSales,
            SalesCount = salesCount,
            TopProduct = topProduct.Name,
            TopProductQuantity = topProduct.Quantity,
            InitialCash = cashRegister.InitialAmount,
            FinalCash = cashRegister.FinalAmount,
            Difference = cashRegister.Difference
        };

        _storage.Summaries.Add(summary);
        _storage.SaveToFile();
        return summary;
    }
}
