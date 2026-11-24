namespace GastroApp.Models;

// One business per installation. Not configured (null) until an admin sets it.
public class BusinessSettings
{
    public TaxCondition? TaxCondition { get; set; }
}
