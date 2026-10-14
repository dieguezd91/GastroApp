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

        var user = RequireLiveAdmin(actor);

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

    public void Open(decimal initialAmount) => _storage.OpenCashRegister(initialAmount);

    public CashCountReview GetCountReview()
    {
        var register = _storage.CurrentCashRegister;
        if (register?.IsOpen != true)
            throw new InvalidOperationException("No hay caja abierta");
        return BuildReview(register);
    }

    // The expected amount always comes from the session movements, never from the UI.
    private CashCountReview BuildReview(CashRegister register)
    {
        var movements = _storage.CashMovements.Where(m => m.CashRegisterId == register.Id).ToList();
        try
        {
            return new CashCountReview(register.Id, GetExpectedCash(register.Id), movements.Count,
                movements.Count == 0 ? 0 : movements.Max(m => m.Id));
        }
        catch (OverflowException)
        {
            throw new InvalidOperationException("El saldo de caja supera el límite permitido.");
        }
    }

    // Pure: validates and calculates without touching any state.
    public CashCountPreview PreviewCount(IEnumerable<CashCountLineInput>? lines, decimal expectedAmount)
    {
        try
        {
            var built = CashCountCalculator.Build(lines);
            var counted = CashCountCalculator.Total(built);
            return new CashCountPreview(built, counted, expectedAmount, checked(counted - expectedAmount));
        }
        catch (OverflowException)
        {
            throw new InvalidOperationException("El conteo supera el límite permitido.");
        }
    }

    public CashCount? GetCount(int registerId) =>
        _storage.CashCounts.FirstOrDefault(c => c.CashRegisterId == registerId)?.Clone();

    // Every rejection happens before the single mutation block below.
    public DailySummary Close(CashCountRequest request, User? actor)
    {
        if (request == null)
            throw new InvalidOperationException("Debe indicar el arqueo de caja.");
        var user = RequireLiveAdmin(actor);

        var cashRegister = _storage.CurrentCashRegister;
        if (cashRegister == null || !cashRegister.IsOpen)
            throw new InvalidOperationException("No hay caja abierta");
        if (request.Review == null || request.Review.RegisterId != cashRegister.Id)
            throw new InvalidOperationException("El arqueo no corresponde a la caja abierta.");
        if (_storage.CashCounts.Any(c => c.CashRegisterId == cashRegister.Id))
            throw new InvalidOperationException("La caja ya tiene un arqueo registrado.");

        var current = BuildReview(cashRegister);
        if (current != request.Review)
            throw new CashCountReviewOutdatedException(current);

        var expected = current.ExpectedAmount;
        var preview = PreviewCount(request.Lines, expected);
        var reason = request.Reason?.Trim();
        if (preview.Difference != 0m && string.IsNullOrWhiteSpace(reason))
            throw new InvalidOperationException("Debe indicar un motivo para la diferencia.");
        if (preview.CountedAmount == 0m && !request.ZeroCountConfirmed)
            throw new InvalidOperationException("Debe confirmar que el conteo de caja es cero.");
        if (!request.Confirmed)
            throw new InvalidOperationException("Debe confirmar el arqueo antes de cerrar la caja.");

        var topProduct = _saleService.GetTopProduct();
        var totalSales = _saleService.GetTodayTotal();
        var salesCount = _saleService.GetTodayCount();

        var now = DateTime.Now;
        cashRegister.FinalAmount = preview.CountedAmount;
        cashRegister.ExpectedAmount = expected;
        cashRegister.IsOpen = false;
        cashRegister.CloseDate = now;
        _storage.CashCounts.Add(new CashCount
        {
            CashRegisterId = cashRegister.Id, CountedAt = now, UserId = user.Id, Username = user.Username,
            Lines = preview.Lines.Select(l => l.Clone()).ToList(), ExpectedAmount = expected,
            CountedAmount = preview.CountedAmount, Difference = preview.Difference,
            Reason = string.IsNullOrWhiteSpace(reason) ? null : reason
        });

        var summary = new DailySummary
        {
            Date = DateTime.Today,
            TotalSales = totalSales,
            SalesCount = salesCount,
            TopProduct = topProduct.Name,
            TopProductQuantity = topProduct.Quantity,
            InitialCash = cashRegister.InitialAmount,
            FinalCash = cashRegister.FinalAmount,
            Difference = cashRegister.Difference,
            CashRegisterId = cashRegister.Id
        };

        _storage.Summaries.Add(summary);
        _storage.SaveToFile();
        return summary;
    }
}
