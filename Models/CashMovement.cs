namespace GastroApp.Models;

public class CashMovement
{
    public int Id { get; set; }
    public int CashRegisterId { get; set; }
    public DateTime Date { get; set; }
    public CashMovementType Type { get; set; }
    public decimal Amount { get; set; }
    public int? SaleId { get; set; }
    public int? UserId { get; set; }
    public string? Username { get; set; }
    public string? Reason { get; set; }
}
