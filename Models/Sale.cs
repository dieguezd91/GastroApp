namespace GastroApp.Models;

public enum DiscountType
{
    None = 0,
    Percentage = 1,
    Fixed = 2
}

public enum PaymentMethod
{
    Cash = 0,
    DebitCard = 1,
    CreditCard = 2,
    Transfer = 3,
    MercadoPago = 4,
    Other = 5
}

public class SalePayment
{
    public PaymentMethod PaymentMethod { get; set; }
    // Importe aplicado a la venta; el efectivo entregado puede ser mayor.
    public decimal Amount { get; set; }
    public decimal? ReceivedAmount { get; set; }
    // Los pagos históricos o inválidos nunca muestran un vuelto ficticio.
    public decimal Change => PaymentMethod == PaymentMethod.Cash && Amount > 0m
        && ReceivedAmount >= Amount ? ReceivedAmount.Value - Amount : 0m;
}

public class Sale
{
    public int Id { get; set; }
    public DateTime Date { get; set; } = DateTime.Now;
    public List<SaleItem> Items { get; set; } = new();
    // Las ventas históricas sin Payments conservan una colección vacía.
    public List<SalePayment> Payments { get; set; } = new();

    public DiscountType DiscountType { get; set; } = DiscountType.None;
    public decimal DiscountValue { get; set; } = 0m;

    // El descuento de la venta se aplica después de los descuentos de línea.
    public decimal Subtotal => Items?.Sum(i => i?.Subtotal ?? 0m) ?? 0m;
    public decimal DiscountAmount => DiscountCalculation.Calculate(Subtotal, DiscountType, DiscountValue);
    public decimal Total => Math.Max(0m, Subtotal - DiscountAmount);
}

public class SaleItem
{
    public int ProductId { get; set; }
    public string ProductName { get; set; } = string.Empty;
    public decimal Price { get; set; }
    public int Quantity { get; set; }
    public string? Notes { get; set; }

    public DiscountType DiscountType { get; set; } = DiscountType.None;
    public decimal DiscountValue { get; set; } = 0m;

    public decimal GrossSubtotal => Math.Max(0m, Price * Quantity);
    // El descuento fijo corresponde a toda la línea, no a cada unidad.
    public decimal DiscountAmount => DiscountCalculation.Calculate(GrossSubtotal, DiscountType, DiscountValue);
    public decimal Subtotal => Math.Max(0m, GrossSubtotal - DiscountAmount);
}

internal static class DiscountCalculation
{
    public static decimal Calculate(decimal applicableBase, DiscountType type, decimal value)
    {
        // Proteger importes derivados de datos inválidos; el servicio rechaza esos descuentos.
        // Porcentaje: base * valor / 100 con decimal, sin nuevo redondeo monetario.
        return type switch
        {
            DiscountType.Percentage => applicableBase * Math.Clamp(value, 0m, 100m) / 100m,
            DiscountType.Fixed => Math.Clamp(value, 0m, applicableBase),
            _ => 0m
        };
    }
}
