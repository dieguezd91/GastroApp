namespace GastroApp.Models;

public class Recipe
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public int Yield { get; set; } = 1; // Porciones / pax que rinde
    public DateTime CreatedAt { get; set; } = DateTime.Now;
    public List<RecipeIngredient> Ingredients { get; set; } = new();

    // Helpers calculados (se setean desde el servicio)
    public decimal TotalCost { get; set; }
    public decimal UnitCost { get; set; }

    // Referencia para cálculo de variación de costo
    public decimal LastCalculatedCost { get; set; }
    public DateTime? LastCalculatedAt { get; set; }

    // Indicador visual: green, yellow, red (basado en variación porcentual)
    public string CostIndicator { get; set; } = "green";
}
