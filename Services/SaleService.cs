using GastroApp.Models;

namespace GastroApp.Services;

public class SaleService
{
    private readonly DataStorageService _storage;
    private RecipeService? _recipeService;
    private IngredientService? _ingredientService;

    public SaleService(DataStorageService storage)
    {
        _storage = storage;
    }

    // Setters para evitar dependencias circulares
    public void SetRecipeService(RecipeService recipeService)
    {
        _recipeService = recipeService;
    }

    public void SetIngredientService(IngredientService ingredientService)
    {
        _ingredientService = ingredientService;
    }

    public List<Sale> GetAll() => _storage.Sales;

    public List<Sale> GetToday()
    {
        var today = DateTime.Today;
        return _storage.Sales
            .Where(s => s.Date.Date == today && s.Status == SaleStatus.Completed)
            .ToList();
    }

    // The seller is optional for internal callers; when given it must be a live user.
    public void Add(Sale sale, User? seller = null)
    {
        var (isValid, errorMessage) = ValidateSale(sale);
        if (!isValid)
            throw new InvalidOperationException(errorMessage);
        var operatorUser = _storage.FindLiveUser(seller);
        if (seller != null && operatorUser == null)
            throw new UnauthorizedAccessException("Se requiere un usuario vigente para registrar la venta.");

        _storage.EnsureSaleCapacity();
        var registerId = _storage.CurrentCashRegister!.Id;
        var cashAmount = sale.Payments.Where(p => p.PaymentMethod == PaymentMethod.Cash)
            .Sum(p => p.Amount);
        if (cashAmount > 0m)
        {
            _storage.EnsureCashMovementCapacity();
            try { _ = checked(_storage.GetExpectedCash(registerId) + cashAmount); }
            catch (OverflowException) { throw new InvalidOperationException("El saldo de caja supera el límite permitido."); }
        }

        // Plan and validate the whole deduction (aggregated per ingredient) before anything changes, so a
        // failure leaves no sale, movement, cash movement or counter behind. After this point nothing can fail.
        var now = DateTime.Now;
        var (lines, totals) = PlanDeductions(sale.Items);
        var batch = totals.Count == 0 ? null : RequireIngredientService().Prepare(totals.Select(t =>
            new StockMovementRequest { IngredientId = t.IngredientId, Type = StockMovementType.SaleConsumption, Quantity = -t.Quantity }).ToList(),
            operatorUser, now);

        foreach (var item in sale.Items)
        {
            item.Notes = string.IsNullOrWhiteSpace(item.Notes) ? null : item.Notes.Trim();
            // Like the sale snapshot, the per-line one is owned by checkout; legacy lines keep null.
            item.StockConsumption = new();
        }

        // The checkout owns the snapshot; no caller-provided deductions are trusted.
        sale.StockConsumption = new();
        sale.Id = _storage.GetNextSaleId();
        sale.CashRegisterId = registerId;
        sale.CreatedByUserId = operatorUser?.Id;
        sale.CreatedByUsername = operatorUser?.Username;
        sale.Date = now;
        _storage.Sales.Add(sale);

        // Snapshots record the same quantities the ledger deducts: per line, and aggregated for cancellation.
        foreach (var (item, entry) in lines)
        {
            sale.StockConsumption.Add(new SaleStockConsumption { IngredientId = entry.IngredientId, Quantity = entry.Quantity, Unit = entry.Unit });
            // Per-line copy lets a partial refund restock proportionally; the aggregate stays intact.
            item.StockConsumption!.Add(new SaleStockConsumption { IngredientId = entry.IngredientId, Quantity = entry.Quantity, Unit = entry.Unit });
        }
        if (batch != null)
        {
            foreach (var movement in batch.Movements)
                movement.SaleId = sale.Id;
            _ingredientService!.Commit(batch);
        }
        sale.IsStockConsumptionReliable = true;

        if (cashAmount > 0m)
            _storage.CashMovements.Add(new CashMovement
            {
                Id = _storage.GetNextCashMovementId(), CashRegisterId = registerId,
                Date = sale.Date, Type = CashMovementType.Sale,
                Amount = cashAmount, SaleId = sale.Id
            });

        // Guardar el estado final incluso si ningún producto tiene receta.
        _storage.SaveToFile();
    }

    // Validate the entire restoration before changing any ingredient or audit state.
    public void Cancel(int saleId, string? reason, User? cancellingUser)
    {
        var sale = _storage.Sales.FirstOrDefault(s => s.Id == saleId)
            ?? throw new InvalidOperationException("La venta no existe.");
        if (sale.Status != SaleStatus.Completed)
            throw new InvalidOperationException("La venta ya no está completada.");
        // Refunds and cancellation are separate operations (S9): a refunded sale is not voided afterwards.
        if (_storage.SaleRefunds.Any(r => r != null && r.SaleId == saleId))
            throw new InvalidOperationException("La venta tiene devoluciones registradas; no puede anularse.");
        var trimmedReason = reason?.Trim();
        if (string.IsNullOrWhiteSpace(trimmedReason))
            throw new InvalidOperationException("Debe indicar un motivo de cancelación.");

        if (cancellingUser == null || cancellingUser.Role != UserRole.Admin)
            throw new UnauthorizedAccessException("Se requiere un usuario administrador vigente.");

        var user = _storage.Users.FirstOrDefault(u => u.Id == cancellingUser.Id);
        if (user == null || user.Id <= 0 || string.IsNullOrWhiteSpace(user.Username)
            || user.Username != cancellingUser.Username || user.Role != UserRole.Admin
            || user.Role != cancellingUser.Role)
            throw new UnauthorizedAccessException("Se requiere un usuario administrador vigente.");

        if (!sale.IsStockConsumptionReliable || sale.StockConsumption == null)
            throw new InvalidOperationException("La venta no tiene un registro confiable de stock consumido.");

        var additions = new Dictionary<int, (Ingredient Ingredient, decimal Quantity)>();
        foreach (var entry in sale.StockConsumption)
        {
            if (entry == null || entry.IngredientId <= 0 || entry.Quantity <= 0m
                || string.IsNullOrWhiteSpace(entry.Unit))
                throw new InvalidOperationException("El registro de stock consumido es inválido.");

            var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == entry.IngredientId);
            if (ingredient == null || ingredient.Unit != entry.Unit)
                throw new InvalidOperationException("El ingrediente ya no existe o cambió de unidad.");

            try
            {
                var previous = additions.TryGetValue(entry.IngredientId, out var aggregate)
                    ? aggregate.Quantity : 0m;
                additions[entry.IngredientId] = (ingredient, checked(previous + entry.Quantity));
            }
            catch (OverflowException)
            {
                throw new InvalidOperationException("El stock a restaurar supera el límite permitido.");
            }
        }

        foreach (var addition in additions.Values)
        {
            try
            {
                _ = checked(addition.Ingredient.CurrentStock + addition.Quantity);
            }
            catch (OverflowException)
            {
                throw new InvalidOperationException("El stock a restaurar supera el límite permitido.");
            }
        }

        var now = DateTime.Now;
        var batch = additions.Count == 0 ? null : RequireIngredientService().Prepare(additions.Values.Select(a =>
            new StockMovementRequest { IngredientId = a.Ingredient.Id, Type = StockMovementType.SaleCancellationReturn,
                Quantity = a.Quantity, Reason = trimmedReason, SaleId = sale.Id }).ToList(), user, now);
        if (batch != null)
            _ingredientService!.Commit(batch);

        sale.Status = SaleStatus.Cancelled;
        sale.CancellationReason = trimmedReason;
        sale.CancelledAt = now;
        sale.CancelledByUserId = user.Id;
        sale.CancelledByUsername = user.Username;
        _storage.SaveToFile();
    }

    public (bool IsValid, string ErrorMessage) ValidateSale(Sale sale)
    {
        if (_storage.CurrentCashRegister?.IsOpen != true)
            return (false, "Debe haber una caja abierta para vender.");
        if (sale == null || sale.Items == null || sale.Items.Count == 0)
            return (false, "La venta debe contener al menos un producto.");
        if (sale.Status != SaleStatus.Completed || sale.CancellationReason != null
            || sale.CancelledAt != null || sale.CancelledByUserId != null
            || sale.CancelledByUsername != null || sale.IsStockConsumptionReliable
            || sale.StockConsumption == null || sale.StockConsumption.Count != 0)
            return (false, "Una venta nueva no puede contener datos de cancelación o consumo de stock.");

        foreach (var item in sale.Items)
        {
            if (item == null)
                return (false, "La venta contiene un producto inválido.");

            var lineValidation = ValidateDiscount(item.DiscountType, item.DiscountValue,
                item.GrossSubtotal, $"El descuento de {item.ProductName}");
            if (!lineValidation.IsValid)
                return lineValidation;
        }

        var saleValidation = ValidateDiscount(sale.DiscountType, sale.DiscountValue,
            sale.Subtotal, "El descuento de la venta");
        if (!saleValidation.IsValid)
            return saleValidation;

        var paymentValidation = ValidatePayments(sale.Payments, sale.Total);
        if (!paymentValidation.IsValid)
            return paymentValidation;

        return ValidateStock(sale.Items);
    }

    // La misma regla se usa para el estado provisional del POS y para Add(), sin mutaciones.
    public static (bool IsValid, string ErrorMessage) ValidatePayments(List<SalePayment>? payments, decimal total)
    {
        if (payments == null)
            return (false, "La colección de pagos de la venta es inválida.");

        if (total == 0m)
            return payments.Count == 0
                ? (true, string.Empty)
                : (false, "Una venta con total cero no debe contener pagos.");

        if (total < 0m || payments.Count == 0)
            return (false, "La venta debe contener pagos por el total final.");

        var methods = new HashSet<PaymentMethod>();
        decimal assigned = 0m;
        foreach (var payment in payments)
        {
            if (payment == null || !Enum.IsDefined(typeof(PaymentMethod), payment.PaymentMethod))
                return (false, "El medio de pago de la venta es inválido.");
            if (!methods.Add(payment.PaymentMethod))
                return (false, "No se puede repetir un medio de pago en la venta.");
            if (payment.Amount <= 0m)
                return (false, "Cada importe de pago debe ser positivo.");

            if (payment.PaymentMethod == PaymentMethod.Cash)
            {
                if (!payment.ReceivedAmount.HasValue || payment.ReceivedAmount.Value < payment.Amount)
                    return (false, "El efectivo recibido debe ser igual o mayor al importe aplicado en efectivo.");
            }
            else if (payment.ReceivedAmount.HasValue)
                return (false, "El efectivo recibido sólo corresponde a pagos en efectivo.");

            try
            {
                assigned = checked(assigned + payment.Amount);
            }
            catch (OverflowException)
            {
                return (false, "La suma de pagos supera el importe permitido.");
            }
        }

        return assigned == total
            ? (true, string.Empty)
            : (false, "La suma de pagos debe ser exactamente igual al total final de la venta.");
    }

    // Compartido por checkout y los candidatos de edición del POS, sin mutar estado.
    public static (bool IsValid, string ErrorMessage) ValidateDiscount(
        DiscountType type, decimal value, decimal applicableBase, string description)
    {
        if (value < 0m)
            return (false, $"{description} no puede ser negativo.");

        switch (type)
        {
            case DiscountType.None:
                if (value != 0m)
                    return (false, $"{description} debe tener valor cero si no se aplica descuento.");
                break;
            case DiscountType.Percentage:
                if (value > 100m)
                    return (false, $"{description} no puede superar el 100%.");
                break;
            case DiscountType.Fixed:
                if (value > applicableBase)
                    return (false, $"{description} no puede superar el subtotal aplicable.");
                break;
            default:
                return (false, $"{description} tiene un tipo inválido.");
        }

        return (true, string.Empty);
    }

    // Validate checkout eligibility before the existing recipe-based stock checks.
    public (bool IsValid, string ErrorMessage) ValidateStock(List<SaleItem> items)
    {
        if (items == null || items.Count == 0)
            return (false, "La venta debe contener al menos un producto.");

        foreach (var item in items)
        {
            if (item == null || item.Quantity <= 0)
                return (false, "La cantidad de cada producto debe ser un entero positivo.");

            // Resolve current catalog state, not the cart's product snapshot.
            var product = _storage.Products.FirstOrDefault(p => p.Id == item.ProductId);
            if (product == null)
                return (false, "Uno de los productos de la venta ya no existe.");

            if (!product.IsActive)
                return (false, $"El producto {product.Name} está inactivo y no se puede vender.");
        }

        if (_recipeService == null || _ingredientService == null)
            return (true, string.Empty); // Sin validación si no hay servicios

        // Requirements are aggregated per ingredient across all lines (S9): two lines sharing an ingredient
        // must fit in its stock together, not one by one.
        var needed = new Dictionary<int, decimal>();
        try
        {
            foreach (var (_, ingredient, quantity) in RecipeRequirements(items))
            {
                if (quantity <= 0m)
                    return (false, "La receta contiene una cantidad de ingrediente no positiva.");

                var total = checked(needed.GetValueOrDefault(ingredient.Id) + quantity);
                needed[ingredient.Id] = total;
                if (ingredient.CurrentStock < total)
                    return (false, $"Stock insuficiente de {ingredient.Name}. Disponible: {ingredient.CurrentStock} {ingredient.Unit}");
            }
        }
        catch (OverflowException)
        {
            return (false, "La cantidad de ingredientes requerida supera el límite permitido.");
        }

        return (true, string.Empty);
    }

    // Recipes are matched by line product name; quantities are multiplied by the line quantity and converted to
    // the ingredient unit. Missing recipes/ingredients and incompatible units are skipped (existing behavior).
    private IEnumerable<(SaleItem Item, Ingredient Ingredient, decimal Quantity)> RecipeRequirements(IEnumerable<SaleItem> items)
    {
        foreach (var item in items)
        {
            var recipe = _storage.Recipes.FirstOrDefault(r => r.Name == item.ProductName);
            if (recipe == null) continue;

            foreach (var recipeIngredient in recipe.Ingredients)
            {
                var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == recipeIngredient.IngredientId);
                if (ingredient == null) continue;

                var quantity = UnitConverter.Convert(recipeIngredient.Quantity * item.Quantity, recipeIngredient.Unit, ingredient.Unit);
                if (quantity == null) continue;
                yield return (item, ingredient, quantity.Value);
            }
        }
    }

    private IngredientService RequireIngredientService() =>
        _ingredientService ?? throw new InvalidOperationException("El servicio de ingredientes no está disponible.");

    // Per-line snapshot entries and the per-ingredient totals (in order of first use) a sale deducts. Pure:
    // nothing is changed. Without the recipe/ingredient services no stock is deducted.
    private (List<(SaleItem Item, SaleStockConsumption Entry)> Lines, List<(int IngredientId, decimal Quantity)> Totals)
        PlanDeductions(List<SaleItem> items)
    {
        var lines = new List<(SaleItem, SaleStockConsumption)>();
        var totals = new List<(int IngredientId, decimal Quantity)>();
        if (_recipeService == null || _ingredientService == null)
            return (lines, totals);

        try
        {
            foreach (var (item, ingredient, quantity) in RecipeRequirements(items))
            {
                lines.Add((item, new SaleStockConsumption { IngredientId = ingredient.Id, Quantity = quantity, Unit = ingredient.Unit }));
                var index = totals.FindIndex(t => t.IngredientId == ingredient.Id);
                if (index < 0) totals.Add((ingredient.Id, quantity));
                else totals[index] = (ingredient.Id, checked(totals[index].Quantity + quantity));
            }
        }
        catch (OverflowException)
        {
            throw new InvalidOperationException("La cantidad de ingredientes requerida supera el límite permitido.");
        }
        return (lines, totals);
    }

    // ---- Refunds (money returned) are separate from cancellation (sale voided): S9 ----

    public IReadOnlyList<SaleRefund> GetRefunds(int saleId) => RefundsOf(saleId)
        .Select(r => r.Clone()).ToList().AsReadOnly();

    // Derived from the sale and its refunds; never persisted.
    public static SaleDisplayStatus GetDisplayStatus(Sale sale, IEnumerable<SaleRefund>? refunds)
    {
        if (sale.Status == SaleStatus.Cancelled) return SaleDisplayStatus.Cancelled;
        var mine = refunds?.Where(r => r != null && r.SaleId == sale.Id).ToList() ?? new List<SaleRefund>();
        if (mine.Count == 0) return SaleDisplayStatus.Collected;
        var units = RefundedUnits(sale, mine);
        var everythingRefunded = sale.Items != null
            && sale.Items.Select((item, index) => item == null || item.Quantity - units[index] <= 0).All(done => done);
        return everythingRefunded ? SaleDisplayStatus.Refunded : SaleDisplayStatus.PartiallyRefunded;
    }

    public SaleDisplayStatus? GetDisplayStatus(int saleId)
    {
        var sale = _storage.Sales.FirstOrDefault(s => s != null && s.Id == saleId);
        return sale == null ? null : GetDisplayStatus(sale, RefundsOf(saleId));
    }

    public static string GetDisplayStatusLabel(SaleDisplayStatus status) => status switch
    {
        SaleDisplayStatus.Collected => "Cobrada",
        SaleDisplayStatus.Cancelled => "Anulada",
        SaleDisplayStatus.PartiallyRefunded => "Parcialmente devuelta",
        SaleDisplayStatus.Refunded => "Devuelta",
        _ => "Estado desconocido"
    };

    // Remaining refundable units/amount per line and per payment method; null when the sale does not exist.
    public SaleRefundability? GetRefundability(int saleId)
    {
        var sale = _storage.Sales.FirstOrDefault(s => s != null && s.Id == saleId);
        if (sale == null) return null;
        var mine = RefundsOf(saleId);
        var units = RefundedUnits(sale, mine);
        var paid = PaidByMethod(sale);
        var refunded = RefundedByMethod(mine);
        var lines = (sale.Items ?? new List<SaleItem>()).Select((item, index) => new SaleRefundLineStatus(
            index, item?.ProductName ?? string.Empty, item?.Quantity ?? 0, units[index],
            sale.IsStockConsumptionReliable && item?.StockConsumption != null));
        var methods = Enum.GetValues<PaymentMethod>()
            .Where(m => paid.GetValueOrDefault(m) > 0m || refunded.GetValueOrDefault(m) > 0m)
            .Select(m => new SaleRefundMethodStatus(m, paid.GetValueOrDefault(m), refunded.GetValueOrDefault(m)));
        return new SaleRefundability(saleId, GetDisplayStatus(sale, mine), sale.Total,
            mine.Sum(r => r.Total), lines, methods);
    }

    // Computes the amounts a refund of these lines would have, without any mutation.
    public SaleRefundPreview PreviewRefund(int saleId, IEnumerable<SaleRefundLine>? lines)
    {
        var sale = FindRefundableSale(saleId);
        var (computed, total) = ComputeRefund(sale, lines);
        return new SaleRefundPreview(computed, total);
    }

    // Every rejection happens before the single mutation block at the end.
    public SaleRefund Refund(int saleId, string? reason, IEnumerable<SaleRefundLine>? lines,
        IEnumerable<SaleRefundPayment>? payments, User? actor)
    {
        var user = _storage.RequireLiveAdmin(actor);
        var sale = FindRefundableSale(saleId);
        var trimmedReason = reason?.Trim();
        if (string.IsNullOrWhiteSpace(trimmedReason))
            throw new InvalidOperationException("Debe indicar un motivo de devolución.");

        var (refundLines, total) = ComputeRefund(sale, lines);
        var refundPayments = ValidateRefundPayments(sale, payments, total);
        var restock = PlanRestock(sale, refundLines);

        var cashAmount = refundPayments.Where(p => p.PaymentMethod == PaymentMethod.Cash).Sum(p => p.Amount);
        var register = _storage.CurrentCashRegister?.IsOpen == true ? _storage.CurrentCashRegister : null;
        if (cashAmount > 0m)
        {
            if (register == null)
                throw new InvalidOperationException("Debe haber una caja abierta para devolver efectivo.");
            decimal available;
            try
            {
                available = _storage.GetExpectedCash(register.Id);
                _ = checked(available - cashAmount);
            }
            catch (OverflowException)
            {
                throw new InvalidOperationException("El saldo de caja supera el límite permitido.");
            }
            if (cashAmount > available)
                throw new InvalidOperationException("El monto supera el efectivo disponible en caja.");
            _storage.EnsureCashMovementCapacity();
        }
        _storage.EnsureSaleRefundCapacity();

        var now = DateTime.Now;
        var batch = restock.Count == 0 ? null : RequireIngredientService().Prepare(restock.Select(r =>
            new StockMovementRequest { IngredientId = r.Ingredient.Id, Type = StockMovementType.RefundReturn,
                Quantity = r.Quantity, Reason = trimmedReason, SaleId = sale.Id }).ToList(), user, now);

        var refund = new SaleRefund
        {
            Id = _storage.GetNextSaleRefundId(), SaleId = sale.Id, Date = now,
            UserId = user.Id, Username = user.Username, Reason = trimmedReason,
            CashRegisterId = register?.Id, Lines = refundLines, Payments = refundPayments, Total = total
        };
        _storage.SaleRefunds.Add(refund);
        if (batch != null)
        {
            foreach (var movement in batch.Movements)
                movement.RefundId = refund.Id;
            _ingredientService!.Commit(batch);
        }
        if (cashAmount > 0m)
            _storage.CashMovements.Add(new CashMovement
            {
                Id = _storage.GetNextCashMovementId(), CashRegisterId = register!.Id, Date = refund.Date,
                Type = CashMovementType.Refund, Amount = cashAmount, SaleId = sale.Id,
                UserId = user.Id, Username = user.Username, Reason = trimmedReason
            });
        _storage.SaveToFile();
        return refund.Clone();
    }

    private List<SaleRefund> RefundsOf(int saleId) => _storage.SaleRefunds
        .Where(r => r != null && r.SaleId == saleId).OrderBy(r => r.Id).ToList();

    private Sale FindRefundableSale(int saleId)
    {
        var sale = _storage.Sales.FirstOrDefault(s => s != null && s.Id == saleId)
            ?? throw new InvalidOperationException("La venta no existe.");
        if (sale.Status != SaleStatus.Completed)
            throw new InvalidOperationException("La venta anulada no admite devoluciones.");
        return sale;
    }

    private static int[] RefundedUnits(Sale sale, IEnumerable<SaleRefund> refunds)
    {
        var units = new int[sale.Items?.Count ?? 0];
        foreach (var line in refunds.SelectMany(r => r.Lines))
            if (line != null && line.SaleItemIndex >= 0 && line.SaleItemIndex < units.Length)
                units[line.SaleItemIndex] += line.Quantity;
        return units;
    }

    private static Dictionary<PaymentMethod, decimal> PaidByMethod(Sale sale)
    {
        var paid = new Dictionary<PaymentMethod, decimal>();
        foreach (var payment in sale.Payments ?? new List<SalePayment>())
            if (payment != null && Enum.IsDefined(typeof(PaymentMethod), payment.PaymentMethod) && payment.Amount > 0m)
                paid[payment.PaymentMethod] = paid.GetValueOrDefault(payment.PaymentMethod) + payment.Amount;
        return paid;
    }

    private static Dictionary<PaymentMethod, decimal> RefundedByMethod(IEnumerable<SaleRefund> refunds)
    {
        var refunded = new Dictionary<PaymentMethod, decimal>();
        foreach (var payment in refunds.SelectMany(r => r.Payments))
            refunded[payment.PaymentMethod] = refunded.GetValueOrDefault(payment.PaymentMethod) + payment.Amount;
        return refunded;
    }

    // Line amount = line subtotal * q / quantity, prorated by the sale discount (Total / Subtotal), rounded to cents.
    // A refund covering all remaining units takes the exact remaining refundable amount, so cumulative refunds
    // equal the sale total; no refund can exceed what is still refundable.
    private (List<SaleRefundLine> Lines, decimal Total) ComputeRefund(Sale sale, IEnumerable<SaleRefundLine>? requested)
    {
        var input = requested?.ToList();
        if (input == null || input.Count == 0)
            throw new InvalidOperationException("Debe indicar al menos una línea a devolver.");
        if (sale.Items == null || sale.Items.Count == 0 || sale.Items.Any(i => i == null || i.Quantity <= 0))
            throw new InvalidOperationException("La venta contiene líneas inválidas; no admite devoluciones.");

        var mine = RefundsOf(sale.Id);
        var units = RefundedUnits(sale, mine);
        var requestedUnits = new int[sale.Items.Count];
        var result = new List<SaleRefundLine>();
        var seen = new HashSet<int>();
        try
        {
            var subtotal = sale.Subtotal;
            var saleTotal = sale.Total;
            foreach (var line in input)
            {
                if (line == null || line.SaleItemIndex < 0 || line.SaleItemIndex >= sale.Items.Count)
                    throw new InvalidOperationException("La línea a devolver no existe en la venta.");
                if (!seen.Add(line.SaleItemIndex))
                    throw new InvalidOperationException("No se puede repetir una línea en la devolución.");
                if (line.Quantity <= 0)
                    throw new InvalidOperationException("La cantidad a devolver debe ser un entero positivo.");
                if (!Enum.IsDefined(typeof(RefundDisposition), line.Disposition))
                    throw new InvalidOperationException("El destino de la mercadería devuelta es inválido.");
                var item = sale.Items[line.SaleItemIndex];
                if (line.Quantity > item.Quantity - units[line.SaleItemIndex])
                    throw new InvalidOperationException(
                        $"La cantidad supera las unidades pendientes de devolución de {item.ProductName}.");

                requestedUnits[line.SaleItemIndex] = line.Quantity;
                var amount = subtotal == 0m ? 0m : Math.Round(
                    item.Subtotal * line.Quantity * saleTotal / (item.Quantity * subtotal),
                    2, MidpointRounding.AwayFromZero);
                result.Add(new SaleRefundLine
                {
                    SaleItemIndex = line.SaleItemIndex, Quantity = line.Quantity,
                    Disposition = line.Disposition, Amount = amount
                });
            }

            var remaining = Math.Max(0m, saleTotal - mine.Sum(r => r.Total));
            var sum = result.Sum(l => l.Amount);
            var coversEverything = Enumerable.Range(0, sale.Items.Count)
                .All(i => sale.Items[i].Quantity - units[i] - requestedUnits[i] == 0);
            var target = coversEverything ? remaining : Math.Min(sum, remaining);
            var difference = target - sum;
            if (difference > 0m)
                result.OrderByDescending(l => l.Amount).First().Amount += difference;
            else if (difference < 0m)
                foreach (var line in result.OrderByDescending(l => l.Amount))
                {
                    var cut = Math.Min(line.Amount, -difference);
                    line.Amount -= cut;
                    difference += cut;
                    if (difference == 0m) break;
                }
            return (result, target);
        }
        catch (OverflowException)
        {
            throw new InvalidOperationException("El importe de la devolución supera el límite permitido.");
        }
    }

    // The caller assigns the amounts; they must add up exactly and stay within what each method collected.
    private List<SaleRefundPayment> ValidateRefundPayments(Sale sale, IEnumerable<SaleRefundPayment>? payments, decimal total)
    {
        if (payments == null)
            throw new InvalidOperationException("Debe indicar el método e importe reintegrado.");
        var paid = PaidByMethod(sale);
        var refunded = RefundedByMethod(RefundsOf(sale.Id));
        var methods = new HashSet<PaymentMethod>();
        var result = new List<SaleRefundPayment>();
        decimal assigned = 0m;
        foreach (var payment in payments)
        {
            if (payment == null || !Enum.IsDefined(typeof(PaymentMethod), payment.PaymentMethod))
                throw new InvalidOperationException("El medio de pago de la devolución es inválido.");
            if (!methods.Add(payment.PaymentMethod))
                throw new InvalidOperationException("No se puede repetir un medio de pago en la devolución.");
            if (payment.Amount <= 0m)
                throw new InvalidOperationException("Cada importe devuelto debe ser positivo.");
            var cap = Math.Max(0m, paid.GetValueOrDefault(payment.PaymentMethod) - refunded.GetValueOrDefault(payment.PaymentMethod));
            if (payment.Amount > cap)
                throw new InvalidOperationException(
                    $"El importe devuelto en {PaymentMethodLabel(payment.PaymentMethod)} supera lo cobrado con ese medio que aún no se devolvió ({cap}).");
            try { assigned = checked(assigned + payment.Amount); }
            catch (OverflowException) { throw new InvalidOperationException("La suma de importes devueltos supera el importe permitido."); }
            result.Add(payment.Clone());
        }
        if (assigned != total)
            throw new InvalidOperationException("La suma de los importes devueltos debe ser exactamente igual al total de la devolución.");
        return result;
    }

    // Restock needs a valid per-line snapshot; everything is validated before any ingredient changes.
    private List<(Ingredient Ingredient, decimal Quantity)> PlanRestock(Sale sale, List<SaleRefundLine> lines)
    {
        var additions = new Dictionary<int, (Ingredient Ingredient, decimal Quantity)>();
        foreach (var line in lines.Where(l => l.Disposition == RefundDisposition.Restock))
        {
            var item = sale.Items[line.SaleItemIndex];
            if (!sale.IsStockConsumptionReliable || item.StockConsumption == null)
                throw new InvalidOperationException(
                    $"La línea {item.ProductName} no tiene registro de consumo de stock; sólo puede devolverse como merma.");
            foreach (var entry in item.StockConsumption)
            {
                if (entry == null || entry.IngredientId <= 0 || entry.Quantity <= 0m
                    || string.IsNullOrWhiteSpace(entry.Unit))
                    throw new InvalidOperationException("El registro de stock consumido es inválido.");
                var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == entry.IngredientId);
                if (ingredient == null || ingredient.Unit != entry.Unit)
                    throw new InvalidOperationException("El ingrediente ya no existe o cambió de unidad.");
                try
                {
                    var quantity = checked(entry.Quantity * line.Quantity / item.Quantity);
                    var previous = additions.TryGetValue(ingredient.Id, out var current) ? current.Quantity : 0m;
                    additions[ingredient.Id] = (ingredient, checked(previous + quantity));
                }
                catch (OverflowException)
                {
                    throw new InvalidOperationException("El stock a restaurar supera el límite permitido.");
                }
            }
        }
        foreach (var addition in additions.Values)
        {
            try { _ = checked(addition.Ingredient.CurrentStock + addition.Quantity); }
            catch (OverflowException) { throw new InvalidOperationException("El stock a restaurar supera el límite permitido."); }
        }
        return additions.Values.ToList();
    }

    private static string PaymentMethodLabel(PaymentMethod method) => method switch
    {
        PaymentMethod.Cash => "Efectivo",
        PaymentMethod.DebitCard => "Tarjeta de débito",
        PaymentMethod.CreditCard => "Tarjeta de crédito",
        PaymentMethod.Transfer => "Transferencia",
        PaymentMethod.MercadoPago => "Mercado Pago",
        _ => "Otro"
    };

    public decimal GetTodayTotal()
    {
        return GetToday().Sum(s => s.Total);
    }

    // Reporting (S13): sales by sale date, refunds by refund date; read-only and never persisted.
    public SalesReport GetTodayReport() => GetReport(DateTime.Today);

    public SalesReport GetReport(DateTime day)
    {
        var date = day.Date;
        var daySales = _storage.Sales.Where(s => s != null && s.Date.Date == date).ToList();
        var completed = daySales.Where(s => s.Status == SaleStatus.Completed).ToList();
        var cancelled = daySales.Where(s => s.Status == SaleStatus.Cancelled).ToList();
        var refunds = _storage.SaleRefunds.Where(r => r != null && r.Date.Date == date).ToList();
        var gross = completed.Sum(s => s.Items?.Sum(i => i?.GrossSubtotal ?? 0m) ?? 0m);
        return new SalesReport(date, gross, gross - completed.Sum(s => s.Total), completed.Count,
            cancelled.Sum(s => s.Total), cancelled.Count, refunds.Sum(r => r.Total), refunds.Count);
    }

    public int GetTodayCount()
    {
        return GetToday().Count;
    }

    public (string Name, int Quantity) GetTopProduct()
    {
        var todaySales = GetToday();
        if (!todaySales.Any()) return ("Ninguno", 0);

        var productSales = todaySales
            .SelectMany(s => s.Items)
            .GroupBy(i => i.ProductName)
            .Select(g => new { Name = g.Key, Quantity = g.Sum(i => i.Quantity) })
            .OrderByDescending(x => x.Quantity)
            .FirstOrDefault();

        return productSales != null ? (productSales.Name, productSales.Quantity) : ("Ninguno", 0);
    }
}
