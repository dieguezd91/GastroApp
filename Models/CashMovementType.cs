namespace GastroApp.Models;

public enum CashMovementType
{
    Sale = 0,
    Income = 1,
    Expense = 2,
    Withdrawal = 3,
    // Automatic outflow created by a sale refund, linked to the sale; never entered manually.
    Refund = 4
}
