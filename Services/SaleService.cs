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

    public void Add(Sale sale)
    {
        var (isValid, errorMessage) = ValidateSale(sale);
        if (!isValid)
            throw new InvalidOperationException(errorMessage);

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

        foreach (var item in sale.Items)
        {
            item.Notes = string.IsNullOrWhiteSpace(item.Notes) ? null : item.Notes.Trim();
        }

        // The checkout owns the snapshot; no caller-provided deductions are trusted.
        sale.StockConsumption = new();
        sale.IsStockConsumptionReliable = false;
        sale.Id = _storage.GetNextSaleId();
        sale.CashRegisterId = registerId;
        sale.Date = DateTime.Now;
        _storage.Sales.Add(sale);

        // Descontar stock por cada producto vendido
        DeductStockFromSale(sale);

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

        foreach (var addition in additions.Values)
            addition.Ingredient.CurrentStock += addition.Quantity;

        sale.Status = SaleStatus.Cancelled;
        sale.CancellationReason = trimmedReason;
        sale.CancelledAt = DateTime.Now;
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

        foreach (var item in items)
        {
            // Buscar si el producto tiene una receta asociada
            var recipe = _storage.Recipes.FirstOrDefault(r => r.Name == item.ProductName);
            if (recipe == null) continue; // Producto sin receta, omitir validación

            // Verificar stock de cada ingrediente de la receta
            foreach (var recipeIngredient in recipe.Ingredients)
            {
                var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == recipeIngredient.IngredientId);
                if (ingredient == null) continue;

                // Convertir cantidad a unidad base del ingrediente
                var quantityNeeded = UnitConverter.Convert(
                    recipeIngredient.Quantity * item.Quantity,
                    recipeIngredient.Unit,
                    ingredient.Unit
                );

                if (quantityNeeded == null) continue; // Unidades incompatibles
                if (quantityNeeded <= 0m)
                    return (false, "La receta contiene una cantidad de ingrediente no positiva.");

                // Verificar si hay stock suficiente
                if (ingredient.CurrentStock < quantityNeeded.Value)
                {
                    return (false, $"Stock insuficiente de {ingredient.Name}. Disponible: {ingredient.CurrentStock} {ingredient.Unit}");
                }
            }
        }

        return (true, string.Empty);
    }

    private void DeductStockFromSale(Sale sale)
    {
        if (_recipeService == null || _ingredientService == null)
        {
            sale.IsStockConsumptionReliable = true;
            return;
        }

        foreach (var item in sale.Items)
        {
            // Buscar si el producto tiene una receta asociada
            var recipe = _storage.Recipes.FirstOrDefault(r => r.Name == item.ProductName);
            if (recipe == null) continue; // Producto sin receta

            // Descontar stock de cada ingrediente de la receta
            foreach (var recipeIngredient in recipe.Ingredients)
            {
                var ingredient = _storage.Ingredients.FirstOrDefault(i => i.Id == recipeIngredient.IngredientId);
                if (ingredient == null) continue;

                // Convertir cantidad a unidad base del ingrediente
                var quantityToDeduct = UnitConverter.Convert(
                    recipeIngredient.Quantity * item.Quantity,
                    recipeIngredient.Unit,
                    ingredient.Unit
                );

                if (quantityToDeduct == null) continue; // Unidades incompatibles

                // TryRemoveStock persists each successful deduction as before. Capture only
                // those successes, never recipe projections or failed attempts.
                if (!_ingredientService.TryRemoveStock(recipeIngredient.IngredientId, quantityToDeduct.Value))
                    throw new InvalidOperationException($"No se pudo descontar stock de {ingredient.Name}.");
                sale.StockConsumption!.Add(new SaleStockConsumption
                {
                    IngredientId = ingredient.Id,
                    Quantity = quantityToDeduct.Value,
                    Unit = ingredient.Unit
                });
            }
        }

        sale.IsStockConsumptionReliable = true;
    }

    public decimal GetTodayTotal()
    {
        return GetToday().Sum(s => s.Total);
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
