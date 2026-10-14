namespace GastroApp.Models;

// Single owner of the line rules so the service and JSON loading cannot diverge.
public static class CashCountCalculator
{
    public const int MaxLines = 100;

    // Validates raw input and returns detached lines with computed subtotals.
    public static List<CashCountLine> Build(IEnumerable<CashCountLineInput>? inputs)
    {
        if (inputs == null)
            throw new InvalidOperationException("Debe indicar el detalle del conteo.");
        var lines = new List<CashCountLine>();
        foreach (var input in inputs)
        {
            if (input == null)
                throw new InvalidOperationException("El detalle del conteo contiene una línea vacía.");
            lines.Add(new CashCountLine { Denomination = input.Denomination, Quantity = input.Quantity });
        }
        Validate(lines);
        foreach (var line in lines) line.Subtotal = Subtotal(line);
        return lines;
    }

    // Stored lines must satisfy the same rules plus an exact stored subtotal.
    public static decimal ValidateStored(IReadOnlyList<CashCountLine?>? lines)
    {
        if (lines == null)
            throw new InvalidOperationException("El detalle del conteo es inválido.");
        var concrete = lines.Select(l => l ?? throw new InvalidOperationException("El detalle del conteo contiene una línea vacía.")).ToList();
        Validate(concrete);
        if (concrete.Any(l => l.Subtotal != Subtotal(l)))
            throw new InvalidOperationException("El subtotal de una línea no coincide con denominación por cantidad.");
        return Total(concrete);
    }

    public static decimal Total(IEnumerable<CashCountLine> lines) =>
        lines.Aggregate(0m, (total, line) => checked(total + line.Subtotal));

    public static decimal Subtotal(CashCountLine line) => checked(line.Denomination * line.Quantity);

    private static void Validate(IReadOnlyList<CashCountLine> lines)
    {
        if (lines.Count > MaxLines)
            throw new InvalidOperationException($"El conteo admite como máximo {MaxLines} denominaciones.");
        var seen = new HashSet<decimal>(); // decimal equality ignores scale: 1000 and 1000.00 collide.
        foreach (var line in lines)
        {
            if (line.Denomination <= 0m)
                throw new InvalidOperationException("La denominación debe ser mayor que cero.");
            if (line.Quantity < 0)
                throw new InvalidOperationException("La cantidad no puede ser negativa.");
            if (!seen.Add(line.Denomination))
                throw new InvalidOperationException("No se puede repetir una denominación.");
        }
    }
}
