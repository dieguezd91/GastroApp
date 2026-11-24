using GastroApp.Models;

namespace GastroApp.Services;

// Entry point of the admin "Reiniciar datos" screen. The reset itself lives in DataStorageService because it
// replaces collections with private setters and the data file; see Docs/Architecture/DataReset.md.
public class DataResetService
{
    private readonly DataStorageService _storage;

    public DataResetService(DataStorageService storage)
    {
        _storage = storage;
    }

    // Revalidates that the actor is a live admin, backs up data.json and empties everything except that admin.
    // Returns the backup file name. Throws UnauthorizedAccessException (not an admin) or
    // InvalidOperationException (backup or save failed); in both cases nothing changed.
    public string ResetAll(User? actor) => _storage.ResetAll(actor);
}
