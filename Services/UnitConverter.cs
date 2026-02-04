namespace GastroApp.Services;

/// <summary>
/// Helper para convertir unidades compatibles (kg/gr y lt/ml).
/// Permite normalizar cantidades a la unidad base del ingrediente.
/// </summary>
public static class UnitConverter
{
    // Categorías de unidades
    private static readonly string[] WeightUnits = { "kg", "gr" };
    private static readonly string[] VolumeUnits = { "lt", "ml" };

    /// <summary>
    /// Convierte una cantidad de una unidad a otra compatible.
    /// Retorna la cantidad convertida, o null si las unidades no son compatibles.
    /// </summary>
    public static decimal? Convert(decimal quantity, string fromUnit, string toUnit)
    {
        // Si son la misma unidad, no hay conversión
        if (fromUnit.ToLower() == toUnit.ToLower())
            return quantity;

        fromUnit = fromUnit.ToLower();
        toUnit = toUnit.ToLower();

        // Verificar que ambas sean compatibles
        if (!AreCompatible(fromUnit, toUnit))
            return null;

        // Conversiones de peso
        if (fromUnit == "kg" && toUnit == "gr")
            return quantity * 1000;
        if (fromUnit == "gr" && toUnit == "kg")
            return quantity / 1000;

        // Conversiones de volumen
        if (fromUnit == "lt" && toUnit == "ml")
            return quantity * 1000;
        if (fromUnit == "ml" && toUnit == "lt")
            return quantity / 1000;

        // No debería llegar aquí, pero por seguridad
        return null;
    }

    /// <summary>
    /// Verifica si dos unidades son compatibles (pueden convertirse entre sí).
    /// </summary>
    public static bool AreCompatible(string unit1, string unit2)
    {
        unit1 = unit1.ToLower();
        unit2 = unit2.ToLower();

        // Misma unidad siempre es compatible
        if (unit1 == unit2)
            return true;

        // Verificar si ambas son de peso
        if (WeightUnits.Contains(unit1) && WeightUnits.Contains(unit2))
            return true;

        // Verificar si ambas son de volumen
        if (VolumeUnits.Contains(unit1) && VolumeUnits.Contains(unit2))
            return true;

        // No compatibles
        return false;
    }

    /// <summary>
    /// Obtiene la categoría de una unidad (peso, volumen, unidad).
    /// Útil para mensajes de error.
    /// </summary>
    public static string GetUnitCategory(string unit)
    {
        unit = unit.ToLower();

        if (WeightUnits.Contains(unit))
            return "peso";
        if (VolumeUnits.Contains(unit))
            return "volumen";

        return "unidad";
    }
}
