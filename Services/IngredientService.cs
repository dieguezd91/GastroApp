using GastroApp.Models;

namespace GastroApp.Services;

// A requested change of stock before validation. Quantity is signed; Unit null means the ingredient unit.
internal sealed class StockMovementRequest
{
    public int IngredientId { get; init; }
    public StockMovementType Type { get; init; }
    public decimal Quantity { get; init; }
    public string? Unit { get; init; }
    public string? Reason { get; init; }
    public WasteCategory? WasteCategory { get; init; }
    public int? SaleId { get; init; }
    public int? RefundId { get; init; }
    public int? InvoiceId { get; init; }
    public int? StockCountId { get; init; }
}

// A fully validated batch. Nothing is changed until IngredientService.Commit; the creator may still set
// the origin links that only exist after its own validation (for example the new sale or refund ID).
internal sealed class StockMovementBatch
{
    public List<StockMovement> Movements { get; } = new();
    internal List<(Ingredient Ingredient, decimal Stock)> Finals { get; } = new();
}

public class IngredientService
{
    private readonly DataStorageService _storage;
    private readonly InvoiceService _invoiceService;

    public IngredientService(DataStorageService storage, InvoiceService invoiceService)
    {
        _storage = storage;
        _invoiceService = invoiceService;
    }

    public List<Ingredient> GetAll() => _storage.Ingredients;

    public List<Ingredient> GetActive() => _storage.Ingredients.Where(i => i.IsActive).ToList();

    public Ingredient? GetById(int id) => _storage.Ingredients.FirstOrDefault(i => i.Id == id);

    // A positive CurrentStock is the opening balance and is recorded as an InitialStock movement.
    public void Add(Ingredient ingredient, User? actor = null)
    {
        if (ingredient.CurrentStock < 0m)
            throw new InvalidOperationException("El stock inicial no puede ser negativo.");
        var operatorUser = _storage.FindLiveUser(actor);
        if (actor != null && operatorUser == null)
            throw new UnauthorizedAccessException("Se requiere un usuario vigente para registrar el stock inicial.");

        var initialStock = ingredient.CurrentStock;
        if (initialStock > 0m)
            _storage.EnsureStockMovementCapacity();
        ingredient.Id = _storage.GetNextIngredientId();
        ingredient.CurrentStock = 0m;
        _storage.Ingredients.Add(ingredient);
        if (initialStock > 0m)
            Commit(Prepare(new[]
            {
                new StockMovementRequest { IngredientId = ingredient.Id, Type = StockMovementType.InitialStock, Quantity = initialStock }
            }, operatorUser, DateTime.Now));
        _storage.SaveToFile();
    }

    // Stock is never edited here: it only changes through the ledger (S6).
    public void Update(Ingredient ingredient)
    {
        var existing = GetById(ingredient.Id);
        if (existing != null)
        {
            existing.Name = ingredient.Name;
            existing.Unit = ingredient.Unit;
            existing.IsActive = ingredient.IsActive;
            existing.MinStock = ingredient.MinStock;
            _storage.SaveToFile();
        }
    }

    // ---- Commands (Admin only, with a mandatory reason) ----

    // Sets the stock to newStock and records the difference. A negative target and a no-op are rejected.
    public StockMovement AdjustStock(int ingredientId, decimal newStock, string? reason, User? actor)
    {
        var admin = _storage.RequireLiveAdmin(actor);
        var ingredient = GetById(ingredientId)
            ?? throw new InvalidOperationException("El ingrediente no existe.");
        if (newStock < 0m)
            throw new InvalidOperationException("El stock no puede ser negativo.");
        if (string.IsNullOrWhiteSpace(reason))
            throw new InvalidOperationException("Debe indicar el motivo del ajuste de stock.");
        var delta = Difference(newStock, ingredient.CurrentStock);
        if (delta == 0m)
            throw new InvalidOperationException("El nuevo stock es igual al actual; no hay nada que ajustar.");

        return Apply(new[]
        {
            new StockMovementRequest { IngredientId = ingredientId, Type = StockMovementType.Adjustment, Quantity = delta, Reason = reason }
        }, admin)[0];
    }

    // Waste (merma) in the ingredient unit: positive quantity, not above the current stock, with category and reason.
    public StockMovement RegisterWaste(int ingredientId, decimal quantity, WasteCategory category, string? reason, User? actor)
    {
        var admin = _storage.RequireLiveAdmin(actor);
        _ = GetById(ingredientId) ?? throw new InvalidOperationException("El ingrediente no existe.");
        if (quantity <= 0m)
            throw new InvalidOperationException("La cantidad de la merma debe ser positiva.");

        return Apply(new[]
        {
            new StockMovementRequest { IngredientId = ingredientId, Type = StockMovementType.Waste, Quantity = -quantity,
                Reason = reason, WasteCategory = category }
        }, admin)[0];
    }

    // Confirms a physical count: each line with a difference becomes a CountAdjustment linked to stockCountId.
    // All lines are validated first and applied together; lines without difference create no movement.
    public IReadOnlyList<StockMovement> ApplyCountAdjustments(int stockCountId,
        IEnumerable<StockCountAdjustment>? adjustments, User? actor)
    {
        var admin = _storage.RequireLiveAdmin(actor);
        if (stockCountId <= 0)
            throw new InvalidOperationException("El conteo es inválido.");
        var lines = adjustments?.ToList()
            ?? throw new InvalidOperationException("Debe indicar al menos una línea de conteo.");
        if (lines.Count == 0)
            throw new InvalidOperationException("Debe indicar al menos una línea de conteo.");

        var seen = new HashSet<int>();
        var requests = new List<StockMovementRequest>();
        foreach (var line in lines)
        {
            if (line == null)
                throw new InvalidOperationException("La línea de conteo es inválida.");
            if (!seen.Add(line.IngredientId))
                throw new InvalidOperationException("No se puede repetir un ingrediente en el conteo.");
            var ingredient = GetById(line.IngredientId)
                ?? throw new InvalidOperationException("El ingrediente no existe.");
            if (line.CountedStock < 0m)
                throw new InvalidOperationException("El stock contado no puede ser negativo.");
            if (line.ExpectedStock.HasValue && line.ExpectedStock.Value != ingredient.CurrentStock)
                throw new InvalidOperationException($"El stock de {ingredient.Name} cambió desde que se inició el conteo.");
            var delta = Difference(line.CountedStock, ingredient.CurrentStock);
            if (delta == 0m) continue;
            requests.Add(new StockMovementRequest { IngredientId = ingredient.Id, Type = StockMovementType.CountAdjustment,
                Quantity = delta, Reason = line.Reason, StockCountId = stockCountId });
        }

        return requests.Count == 0 ? Array.Empty<StockMovement>() : Apply(requests, admin);
    }

    // ---- Queries (detached copies, never mutate) ----

    // Newest first (Date, then Id descending). Unknown ingredients yield an empty list.
    public List<StockMovement> GetMovements(int ingredientId, StockMovementFilter? filter = null)
    {
        var types = filter?.Types is { Count: > 0 } selected ? selected.ToHashSet() : null;
        return _storage.StockMovements
            .Where(m => m != null && m.IngredientId == ingredientId && (types == null || types.Contains(m.Type))
                && InDayRange(m.Date, filter?.From, filter?.To))
            .OrderByDescending(m => m.Date).ThenByDescending(m => m.Id)
            .Select(m => m.Clone()).ToList();
    }

    public bool HasMovements(int ingredientId) =>
        _storage.StockMovements.Any(m => m != null && m.IngredientId == ingredientId);

    // Net quantity consumed by sales (consumption minus cancellation and refund returns) over the calendar days
    // from..to inclusive, in the ingredient unit and never negative. Waste and adjustments are not consumption.
    public decimal GetConsumption(int ingredientId, DateTime from, DateTime to)
    {
        var net = _storage.StockMovements
            .Where(m => m != null && m.IngredientId == ingredientId && InDayRange(m.Date, from, to)
                && m.Type is StockMovementType.SaleConsumption or StockMovementType.SaleCancellationReturn
                    or StockMovementType.RefundReturn)
            .Sum(m => m.Quantity);
        return Math.Max(0m, -net);
    }

    private static bool InDayRange(DateTime date, DateTime? from, DateTime? to) =>
        (from == null || date.Date >= from.Value.Date) && (to == null || date.Date <= to.Value.Date);

    public void Delete(int id)
    {
        var ingredient = GetById(id);
        if (ingredient != null)
        {
            _storage.Ingredients.Remove(ingredient);
            _storage.SaveToFile();
        }
    }

    // Obtener último precio conocido desde facturas
    public decimal? GetLastPrice(int ingredientId)
    {
        return _invoiceService.GetLastPriceForIngredient(ingredientId);
    }

    // ---- The single mutation path for CurrentStock ----

    private static decimal Difference(decimal target, decimal current)
    {
        try { return checked(target - current); }
        catch (OverflowException) { throw new InvalidOperationException("La diferencia de stock supera el límite permitido."); }
    }

    private IReadOnlyList<StockMovement> Apply(IReadOnlyList<StockMovementRequest> requests, User? actor)
    {
        var batch = Prepare(requests, actor, DateTime.Now);
        Commit(batch);
        _storage.SaveToFile();
        return batch.Movements.Select(m => m.Clone()).ToList();
    }

    // Validates every request against the running balance of its ingredient and builds the movements, with no
    // mutation. Rejects: unknown ingredient, incompatible unit, zero or wrongly signed quantity, missing
    // reason/category, overflow, exhausted IDs, and a decrease below zero. Increases are never rejected for
    // the resulting balance, so a restore or receipt can always repair a legacy negative balance.
    internal StockMovementBatch Prepare(IReadOnlyList<StockMovementRequest> requests, User? actor, DateTime date)
    {
        var batch = new StockMovementBatch();
        if (requests == null || requests.Count == 0) return batch;
        _storage.EnsureStockMovementCapacity(requests.Count);

        var running = new Dictionary<int, (Ingredient Ingredient, decimal Stock)>();
        foreach (var request in requests)
        {
            if (request == null || !Enum.IsDefined(typeof(StockMovementType), request.Type))
                throw new InvalidOperationException("El movimiento de stock es inválido.");
            var ingredient = _storage.Ingredients.FirstOrDefault(i => i != null && i.Id == request.IngredientId)
                ?? throw new InvalidOperationException("El ingrediente no existe.");

            decimal quantity;
            try
            {
                quantity = request.Unit == null ? request.Quantity
                    : UnitConverter.Convert(request.Quantity, request.Unit, ingredient.Unit)
                        ?? throw new InvalidOperationException(
                            $"La unidad {request.Unit} no es compatible con la unidad de {ingredient.Name} ({ingredient.Unit}).");
            }
            catch (OverflowException)
            {
                throw new InvalidOperationException("La cantidad supera el límite permitido.");
            }
            if (quantity == 0m)
                throw new InvalidOperationException("La cantidad del movimiento de stock no puede ser cero.");
            var increases = request.Type is StockMovementType.InvoiceReceipt or StockMovementType.SaleCancellationReturn
                or StockMovementType.RefundReturn or StockMovementType.InitialStock;
            var decreases = request.Type is StockMovementType.SaleConsumption or StockMovementType.Waste;
            if ((increases && quantity < 0m) || (decreases && quantity > 0m))
                throw new InvalidOperationException("El signo de la cantidad no corresponde al tipo de movimiento.");

            var reason = string.IsNullOrWhiteSpace(request.Reason) ? null : request.Reason.Trim();
            if (reason == null)
            {
                var missing = request.Type switch
                {
                    StockMovementType.Adjustment => "Debe indicar el motivo del ajuste de stock.",
                    StockMovementType.Waste => "Debe indicar el motivo de la merma.",
                    StockMovementType.CountAdjustment => "Debe indicar el motivo de la diferencia de conteo.",
                    _ => null
                };
                if (missing != null) throw new InvalidOperationException(missing);
            }
            if (request.Type == StockMovementType.Waste
                ? !request.WasteCategory.HasValue || !Enum.IsDefined(typeof(WasteCategory), request.WasteCategory.Value)
                : request.WasteCategory.HasValue)
                throw new InvalidOperationException("Debe indicar una categoría de merma válida.");

            var previous = running.TryGetValue(ingredient.Id, out var current) ? current.Stock : ingredient.CurrentStock;
            decimal resulting;
            try { resulting = checked(previous + quantity); }
            catch (OverflowException)
            {
                throw new InvalidOperationException($"El stock resultante de {ingredient.Name} supera el límite permitido.");
            }
            if (quantity < 0m && resulting < 0m)
                throw new InvalidOperationException($"Stock insuficiente de {ingredient.Name}. Disponible: {previous} {ingredient.Unit}");

            running[ingredient.Id] = (ingredient, resulting);
            batch.Movements.Add(new StockMovement
            {
                IngredientId = ingredient.Id, Date = date, Type = request.Type, Quantity = quantity,
                Unit = ingredient.Unit, PreviousStock = previous, ResultingStock = resulting,
                Reason = reason, WasteCategory = request.WasteCategory,
                UserId = actor?.Id, Username = actor?.Username,
                SaleId = request.SaleId, RefundId = request.RefundId, InvoiceId = request.InvoiceId,
                StockCountId = request.StockCountId
            });
        }

        batch.Finals.AddRange(running.Values.Select(v => (v.Ingredient, v.Stock)));
        return batch;
    }

    // Cannot fail after Prepare: capacity was reserved and every balance is already computed. The caller saves.
    internal void Commit(StockMovementBatch batch)
    {
        foreach (var (ingredient, stock) in batch.Finals)
            ingredient.CurrentStock = stock;
        foreach (var movement in batch.Movements)
        {
            movement.Id = _storage.GetNextStockMovementId();
            _storage.StockMovements.Add(movement);
        }
    }
}
