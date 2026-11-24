# Data reset ("Reiniciar datos")

An admin-only screen (`/settings/reset`, last sidebar entry) that empties the application and keeps only the admin who runs it. It exists to start from scratch after testing, and it is irreversible from the UI.

## What it does

| Deleted | Kept |
|---------|------|
| Products, categories, sales, refunds | The acting admin (same id, username, role and password hash) |
| Stock movements, stock counts | ID counters (`NextProductId`, `NextSaleId`, `NextUserId`, ...): ids are never reused, so stale sessions or copies cannot collide with new records |
| Cash registers (including the current one: `CurrentCashRegisterId` becomes `null`), cash movements, cash counts, daily summaries | |
| Ingredients, suppliers, invoices, recipes | |
| Every other user | |

## Confirmation (UI)

The button is disabled until both hold: the checkbox acknowledging the action is irreversible, and the text box contains exactly `REINICIAR` (case-sensitive, no trimming). The service does not trust the page: `ResetAll` re-checks the actor with `RequireLiveAdmin`, so employees, anonymous callers and stale or demoted admins are rejected with `UnauthorizedAccessException` and nothing changes. The page redirects employees to `/unauthorized` and anonymous users to `/login`, like the other admin pages.

## Service flow

`DataResetService.ResetAll(User? actor)` delegates to `DataStorageService.ResetAll`, which owns the private collection setters and the data file:

1. Validate the live admin (`RequireLiveAdmin`).
2. Serialize the post-reset document (same format as `SaveToFile`: empty collections, the admin only, the current counters).
3. Copy `data.json` byte for byte to `data.backup-<yyyyMMdd-HHmmss>.json` (local time) next to it, created with `CreateNew` so an existing backup is never overwritten. If `data.json` does not exist, the serialized current state is written instead.
4. Write the new document to `data.json.reset.tmp` and move it over `data.json`.
5. Only after the file is replaced, empty the in-memory collections.

If any step before 5 fails, `ResetAll` throws `InvalidOperationException` ("No se pudo crear la copia de seguridad..." / "No se pudo guardar el reinicio..."), removes the backup and temp file it created, and leaves memory and `data.json` exactly as they were. On success it returns the backup file name; the page shows it and then navigates to the dashboard.

`data.backup-*.json` is git-ignored. The application never rotates or deletes backups, and restoring one is manual (stop the app, copy it over `data.json`, restart).

## Effect on other sessions

Services are singletons that read the shared collections on every call, so they see the empty state immediately. `AuthService` is scoped per circuit and re-resolves its user by id on every read:

- The acting admin keeps the same stored user, so their circuit stays logged in.
- Circuits logged in as removed users find no matching user on their next check (`CurrentUser` is `null`, `IsAuthenticated` is false) and are treated as logged out: pages redirect to `/login` and protected actions are rejected.
- Pages already open in other circuits keep their old in-memory lists until they reload or act; the services validate their actions against the empty state.

## Startup

An empty state must survive a restart: `DataStorageService` seeds the demo data only when the loaded state has neither products nor users. A reset system still has its admin, so it is not reseeded; a directory without `data.json` still is.

## Limits

- No locking: like the rest of the JSON persistence, mutations from other circuits during the reset are not serialized.
- Two resets within the same second would collide on the backup name; the second aborts with nothing changed.
- Verification: `scripts/verify-data-reset.ps1`.
