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
