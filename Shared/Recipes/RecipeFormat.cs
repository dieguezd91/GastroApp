using System.Globalization;
using GastroApp.Models;
using GastroApp.Services;
using GastroApp.Shared.Pos;

namespace GastroApp.Shared.Recipes;

/// <summary>State of one recipe line in the builder, derived from what <see cref="RecipeService.CalculateCosts"/> stores.</summary>
public enum RecipeLineStatus
{
    /// <summary>Compatible unit and a latest invoice price: the line is costed.</summary>
    Ok,
    /// <summary>Compatible unit but no invoice price yet: the service costs the line at zero.</summary>
    NoPrice,
    /// <summary>The recipe unit cannot be converted to the ingredient unit: the service excludes the line.</summary>
    Incompatible,
    /// <summary>The ingredient no longer exists.</summary>
    Missing
}

public sealed record RecipeLinePreview(RecipeIngredient Line, Ingredient? Ingredient, RecipeLineStatus Status, decimal Cost);

public sealed record RecipePreview(IReadOnlyList<RecipeLinePreview> Lines, decimal TotalCost, decimal UnitCost);

/// <summary>Display, unit and live-preview helpers of the recipes screen (es-AR display).</summary>
public static class RecipeFormat
{
    private static readonly NumberFormatInfo ArgentineNumbers = new()
    {
        NumberDecimalSeparator = ",",
        NumberGroupSeparator = ".",
        NumberGroupSizes = new[] { 3 }
    };

    public static string Money(decimal amount) => PosFormat.Money(amount);

    /// <summary>"0,018": up to six decimals, no trailing zeros.</summary>
    public static string Number(decimal value) => value.ToString("#,##0.######", ArgentineNumbers);

    /// <summary>"0,018 kg".</summary>
    public static string Qty(decimal value, string unit) => $"{Number(value)} {unit}";

    /// <summary>"1 porción" / "4 porciones".</summary>
    public static string Portions(int yield) => yield == 1 ? "1 porción" : $"{yield} porciones";

    /// <summary>Quantities typed in the numeric input arrive with a dot, whatever the host culture.</summary>
    public static bool TryParseQuantity(string? text, out decimal value)
    {
        value = 0m;
        return !string.IsNullOrWhiteSpace(text)
            && decimal.TryParse(text, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingWhite | NumberStyles.AllowTrailingWhite,
                CultureInfo.InvariantCulture, out value);
    }

    /// <summary>
    /// Units a recipe line may use for an ingredient stored in <paramref name="baseUnit"/>: only units
    /// <see cref="UnitConverter"/> can convert to it. Weight and volume offer two options (small unit first),
    /// anything else (unidad) is fixed.
    /// </summary>
    public static IReadOnlyList<string> UnitOptions(string baseUnit) => UnitConverter.GetUnitCategory(baseUnit) switch
    {
        "peso" => new[] { "gr", "kg" },
        "volumen" => new[] { "ml", "lt" },
        _ => new[] { baseUnit }
    };

    /// <summary>Preselected unit: gr / ml for weight and volume (no mental "0,018 kg" arithmetic), the fixed unit otherwise.</summary>
    public static string DefaultUnit(string baseUnit) => UnitOptions(baseUnit)[0];

    /// <summary>Badge variant, icon and label of the stored variation indicator (&lt;10% / 10–30% / &gt;=30%).</summary>
    public static (string Variant, string Icon, string Label) VariationOf(string? indicator) => indicator switch
    {
        "red" => ("danger", "alertOctagon", "Variación alta (≥ 30%)"),
        "yellow" => ("warn", "alertTriangle", "Variación media (10–30%)"),
        "green" => ("ok", "checkCircle", "Estable (< 10%)"),
        _ => ("neutral", "info", "Sin variación calculada")
    };

    /// <summary>
    /// Costs <paramref name="recipe"/> exactly as the service does when it saves it (same conversion, same latest
    /// invoice price), on a scratch copy so nothing is stored and the edited recipe is left untouched.
    /// </summary>
    public static RecipePreview Preview(RecipeService recipes, IngredientService ingredients, Recipe recipe)
    {
        var scratch = new Recipe
        {
            Id = recipe.Id,
            Name = recipe.Name,
            Yield = recipe.Yield,
            Ingredients = recipe.Ingredients.Select(CopyOf).ToList()
        };
        recipes.CalculateCosts(scratch);

        var lines = scratch.Ingredients.Select(line =>
        {
            var ingredient = ingredients.GetById(line.IngredientId);
            var status = ingredient == null ? RecipeLineStatus.Missing
                : !UnitConverter.AreCompatible(line.Unit, ingredient.Unit) ? RecipeLineStatus.Incompatible
                : line.UnitPrice > 0m ? RecipeLineStatus.Ok
                : RecipeLineStatus.NoPrice;
            return new RecipeLinePreview(line, ingredient, status, line.Subtotal);
        }).ToList();
        return new RecipePreview(lines, scratch.TotalCost, scratch.UnitCost);
    }

    /// <summary>
    /// Strip shown under the picker: "Equivale a 0,018 kg · Costo estimado: $ 648". The cost is the one the service
    /// would store for that line.
    /// </summary>
    public static string LinePreviewText(RecipeService recipes, IngredientService ingredients, Ingredient? ingredient, string unit, string? quantityText)
    {
        if (ingredient == null)
            return "Elegí un ingrediente para ver la unidad compatible y el costo estimado.";

        var converts = !string.Equals(unit, ingredient.Unit, StringComparison.OrdinalIgnoreCase);
        if (!TryParseQuantity(quantityText, out var quantity) || quantity <= 0m)
            return converts
                ? $"Ingresá la cantidad en {unit} (se convierte automáticamente a {ingredient.Unit})."
                : $"Ingresá la cantidad en {unit}.";

        var converted = UnitConverter.Convert(quantity, unit, ingredient.Unit);
        if (converted == null)
            return "Unidad incompatible con el ingrediente.";

        var equivalence = converts ? $"Equivale a {Qty(converted.Value, ingredient.Unit)} · " : string.Empty;
        var line = new RecipeIngredient { IngredientId = ingredient.Id, IngredientName = ingredient.Name, Quantity = quantity, Unit = unit };
        var preview = Preview(recipes, ingredients, new Recipe { Yield = 1, Ingredients = { line } });
        return preview.Lines[0].Status == RecipeLineStatus.NoPrice
            ? $"{equivalence}Sin precio de factura cargado aún"
            : $"{equivalence}Costo estimado: {Money(preview.TotalCost)}";
    }

    /// <summary>Copy used for editing and previews (RecipeId is not carried over, as the page always did).</summary>
    public static RecipeIngredient CopyOf(RecipeIngredient line) => new()
    {
        IngredientId = line.IngredientId,
        IngredientName = line.IngredientName,
        Quantity = line.Quantity,
        Unit = line.Unit,
        UnitPrice = line.UnitPrice,
        Subtotal = line.Subtotal
    };
}
