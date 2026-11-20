using GastroApp.Models;

namespace GastroApp.Services;

// Physical stock counts (S4). Preview compares without mutating; Confirm records the count and applies its
// differences through IngredientService, the only writer of ingredient stock.
public class StockCountService
{
    // Shown when the registered stock moved after the preview (simultaneous count/operation); the page matches it.
    public const string StaleStockMessage = "El stock cambió desde que se inició el conteo; vuelva a calcular.";

    private readonly DataStorageService _storage;
    private readonly IngredientService _ingredients;
    private readonly object _gate = new();

    public StockCountService(DataStorageService storage, IngredientService ingredients)
    {
        _storage = storage;
        _ingredients = ingredients;
    }

    // Registered vs counted stock for the given lines, in request order. Reason and ExpectedStock are ignored.
    public StockCountPreview Preview(IEnumerable<StockCountLineInput>? lines)
    {
        lock (_gate)
            return new StockCountPreview { Lines = Compare(lines).Select(l => l.Preview).ToList() };
    }

    // Validates everything, then records the count and its CountAdjustment movements. A rejection leaves no
    // count, movement, stock change, counter change or file write behind.
    public StockCount Confirm(StockCountRequest? request, User? actor)
    {
        lock (_gate)
        {
            var admin = _storage.RequireLiveAdmin(actor);
            if (request == null || request.Lines == null || request.Lines.Count == 0)
                throw new InvalidOperationException("Debe indicar al menos una línea de conteo.");
            if (!request.Confirmed)
                throw new InvalidOperationException("Debe confirmar el conteo para registrarlo.");

            var compared = Compare(request.Lines);
            var lines = new List<StockCountLine>();
            foreach (var (input, preview) in compared)
            {
                if (!input.ExpectedStock.HasValue)
                    throw new InvalidOperationException("Debe comparar el conteo antes de confirmarlo.");
                if (input.ExpectedStock.Value != preview.ExpectedStock)
                    throw new InvalidOperationException(StaleStockMessage);
                var reason = string.IsNullOrWhiteSpace(input.Reason) ? null : input.Reason.Trim();
                if (preview.Difference != 0m && reason == null)
                    throw new InvalidOperationException($"Debe indicar el motivo de la diferencia de {preview.IngredientName}.");
                lines.Add(new StockCountLine
                {
                    IngredientId = preview.IngredientId, IngredientName = preview.IngredientName, Unit = preview.Unit,
                    ExpectedStock = preview.ExpectedStock, CountedStock = preview.CountedStock, Difference = preview.Difference,
                    Reason = preview.Difference != 0m ? reason : null
                });
            }

            var count = new StockCount
            {
                Date = DateTime.Now, UserId = admin.Id, Username = admin.Username,
                Notes = string.IsNullOrWhiteSpace(request.Notes) ? null : request.Notes.Trim(),
                Lines = lines, AdjustedLineCount = lines.Count(l => l.Difference != 0m)
            };
            var adjustments = lines.Select(l => new StockCountAdjustment
            {
                IngredientId = l.IngredientId, CountedStock = l.CountedStock, ExpectedStock = l.ExpectedStock, Reason = l.Reason
            }).ToList();

            _storage.AddStockCount(count);
            IReadOnlyList<StockMovement> movements;
            try
            {
                // Saves by itself when it creates movements, and the count is already in the list at that point.
                movements = _ingredients.ApplyCountAdjustments(count.Id, adjustments, admin);
            }
            catch
            {
                _storage.DiscardStockCount(count);
                throw;
            }
            if (movements.Count == 0)
                _storage.SaveToFile();
            return count.Clone();
        }
    }

    // Newest first; detached copies.
    public IReadOnlyList<StockCount> GetHistory()
    {
        lock (_gate)
            return _storage.StockCounts.Where(c => c != null).OrderByDescending(c => c.Date).ThenByDescending(c => c.Id)
                .Select(c => c.Clone()).ToList();
    }

    public StockCount? GetDetail(int id)
    {
        lock (_gate)
            return _storage.StockCounts.FirstOrDefault(c => c != null && c.Id == id)?.Clone();
    }

    private List<(StockCountLineInput Input, StockCountPreviewLine Preview)> Compare(IEnumerable<StockCountLineInput>? lines)
    {
        var inputs = lines?.ToList();
        if (inputs == null || inputs.Count == 0)
            throw new InvalidOperationException("Debe indicar al menos una línea de conteo.");
        var seen = new HashSet<int>();
        var result = new List<(StockCountLineInput, StockCountPreviewLine)>();
        foreach (var input in inputs)
        {
            if (input == null)
                throw new InvalidOperationException("La línea de conteo es inválida.");
            if (!seen.Add(input.IngredientId))
                throw new InvalidOperationException("No se puede repetir un ingrediente en el conteo.");
            var ingredient = _ingredients.GetById(input.IngredientId)
                ?? throw new InvalidOperationException("El ingrediente no existe.");
            if (!input.CountedStock.HasValue)
                throw new InvalidOperationException($"Debe indicar el stock contado de {ingredient.Name}.");
            if (input.CountedStock.Value < 0m)
                throw new InvalidOperationException("El stock contado no puede ser negativo.");
            decimal difference;
            try { difference = checked(input.CountedStock.Value - ingredient.CurrentStock); }
            catch (OverflowException) { throw new InvalidOperationException("La diferencia de stock supera el límite permitido."); }
            result.Add((input, new StockCountPreviewLine
            {
                IngredientId = ingredient.Id, IngredientName = ingredient.Name, Unit = ingredient.Unit,
                ExpectedStock = ingredient.CurrentStock, CountedStock = input.CountedStock.Value, Difference = difference
            }));
        }
        return result;
    }
}
