using System.Text.Json.Serialization;

namespace GastroApp.Models;

public class Supplier
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    // 11 digits without dashes. An empty CUIT or a null condition means a legacy supplier without fiscal data.
    public string Cuit { get; set; } = string.Empty;
    public TaxCondition? TaxCondition { get; set; }

    [JsonIgnore]
    public bool HasFiscalData => !string.IsNullOrWhiteSpace(Cuit) && TaxCondition.HasValue;
}
