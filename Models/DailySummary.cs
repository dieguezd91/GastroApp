namespace GastroApp.Models;

public class DailySummary
{
    public DateTime Date { get; set; }
    public decimal TotalSales { get; set; }
    public int SalesCount { get; set; }
    public string TopProduct { get; set; } = string.Empty;
    public int TopProductQuantity { get; set; }
    public decimal InitialCash { get; set; }
    public decimal FinalCash { get; set; }
    public decimal Difference { get; set; }
}
