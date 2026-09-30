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
            .Where(s => s.Date.Date == today)
            .ToList();
    }

    public void Add(Sale sale)
    {
        var (isValid, errorMessage) = ValidateSale(sale);
        if (!isValid)
            throw new InvalidOperationException(errorMessage);

        foreach (var item in sale.Items)
        {
            item.Notes = string.IsNullOrWhiteSpace(item.Notes) ? null : item.Notes.Trim();
        }

        sale.Id = _storage.GetNextSaleId();
        sale.Date = DateTime.Now;
        _storage.Sales.Add(sale);

        // Descontar stock por cada producto vendido
        DeductStockFromSale(sale);

        // Guardar el estado final incluso si ningún producto tiene receta.
        _storage.SaveToFile();
    }

    public (bool IsValid, string ErrorMessage) ValidateSale(Sale sale)
    {
        if (sale == null || sale.Items == null || sale.Items.Count == 0)
            return (false, "La venta debe contener al menos un producto.");

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

        var paymentValidation = ValidatePayments(sale);
        if (!paymentValidation.IsValid)
            return paymentValidation;

        return ValidateStock(sale.Items);
    }

    private static (bool IsValid, string ErrorMessage) ValidatePayments(Sale sale)
    {
        if (sale.Payments == null)
            return (false, "La colección de pagos de la venta es inválida.");

        if (sale.Total == 0m)
        {
            return sale.Payments.Count == 0
                ? (true, string.Empty)
                : (false, "Una venta con total cero no debe contener pagos.");
        }

        if (sale.Payments.Count != 1)
            return (false, "La venta debe contener exactamente un pago por el total final.");

        var payment = sale.Payments[0];
        if (payment == null || !Enum.IsDefined(typeof(PaymentMethod), payment.PaymentMethod))
            return (false, "El medio de pago de la venta es inválido.");

        if (payment.Amount <= 0m || payment.Amount != sale.Total)
            return (false, "El importe del pago debe ser positivo e igual al total final de la venta.");

        return (true, string.Empty);
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
        if (_recipeService == null || _ingredientService == null) return;

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

                // Descontar stock
                _ingredientService.TryRemoveStock(recipeIngredient.IngredientId, quantityToDeduct.Value);
            }
        }
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
