namespace GastroApp.Models;

// Condición frente al IVA. The numeric values are persisted in data.json.
public enum TaxCondition
{
    ResponsableInscripto = 1,
    Monotributista = 2,
    Exento = 3
}
