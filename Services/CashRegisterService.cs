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

    public void Open(decimal initialAmount)
    {
        _storage.CurrentCashRegister = new CashRegister
        {
            OpenDate = DateTime.Now,
            InitialAmount = initialAmount,
            IsOpen = true
        };
    }

    public DailySummary Close(decimal finalAmount)
    {
        if (_storage.CurrentCashRegister == null || !_storage.CurrentCashRegister.IsOpen)
            throw new InvalidOperationException("No hay caja abierta");

        var cashRegister = _storage.CurrentCashRegister;
        cashRegister.FinalAmount = finalAmount;
        cashRegister.ExpectedAmount = cashRegister.InitialAmount + _saleService.GetTodayTotal();
        cashRegister.IsOpen = false;
        cashRegister.CloseDate = DateTime.Now;

        var topProduct = _saleService.GetTopProduct();

        var summary = new DailySummary
        {
            Date = DateTime.Today,
            TotalSales = _saleService.GetTodayTotal(),
            SalesCount = _saleService.GetTodayCount(),
            TopProduct = topProduct.Name,
            TopProductQuantity = topProduct.Quantity,
            InitialCash = cashRegister.InitialAmount,
            FinalCash = cashRegister.FinalAmount,
            Difference = cashRegister.Difference
        };

        _storage.Summaries.Add(summary);
        return summary;
    }
}
