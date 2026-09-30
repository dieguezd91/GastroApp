namespace GastroApp.Models;

public class CashRegister
{
    public int Id { get; set; }
    public DateTime OpenDate { get; set; }
    public decimal InitialAmount { get; set; }
    public decimal FinalAmount { get; set; }
    public bool IsOpen { get; set; }
    public DateTime? CloseDate { get; set; }

    public decimal ExpectedAmount { get; set; }
    public decimal Difference => FinalAmount - ExpectedAmount;
}
