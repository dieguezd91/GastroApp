# Circuit-isolated authentication

`AuthService` is scoped to each Blazor Server circuit. Login and logout affect only that circuit; business services and JSON-backed data remain shared singletons. This is an in-memory prototype login, not ASP.NET Identity, cookie authentication, or persistent session storage.

## Identity and permissions

| Check | Current behavior |
|-------|------------------|
| Login | `UserService` finds the username and BCrypt verifies the password. The circuit stores the stable user ID plus the login-time username and password hash, not a cached `User` reference. |
| Authentication / actor | `CurrentUser` resolves the ID against the live `UserService` collection on every read. `IsAuthenticated` uses that same resolution. |
| Stale identity | A missing user, invalid ID/username, changed username, or changed password hash clears the circuit identity and fails closed. Restoring the old values after an observed invalidation does not restore login. |
| Role | `IsInRole` reads the currently stored role. Demotion takes effect on the next check without requiring logout. Role changes alone do not invalidate identity. |
| Notifications | Successful login and logout notify only subscribers in that circuit. Lazy invalidation does not emit an event from a getter while a component may be rendering. There is no cross-circuit user-change broadcast; permissions are checked again at action time. |

Only `AuthService` changes lifetime in `Program.cs`. No singleton consumes it. `UserService`, `DataStorageService`, and all existing business services remain singletons; separate users still operate on the same catalog, stock, sales and cash register. This change does not add data locking or transactional guarantees.

## Navigation and circuit lifecycle

- Login, logout, protected-page redirects and internal menu links use client-side Blazor navigation without forced reload. Successful login therefore survives navigation to the dashboard.
- A full reload, new tab/browser context, or replacement circuit starts unauthenticated. Login is not saved to JSON, browser storage or cookies.
- A transient disconnection can reconnect to the retained circuit with its identity intact. If that circuit expires or reconnection creates a new circuit, login is lost.
- Prerendering runs in a separate request scope; it cannot restore circuit login. Circuit termination/disposal releases its authentication state.
- `MainLayout` and `NavMenu` marshal auth notifications through `InvokeAsync`, suppress queued updates after disposal, and unsubscribe their handlers.

## Sensitive action boundary

Initialization checks control page access, but do not authorize later callbacks. Administrative cash, product/category, supplier, ingredient/stock, invoice and recipe callbacks recheck current Admin permissions and return before mutation when denied. Unauthenticated callers navigate to `/login`; authenticated non-admin callers navigate to `/unauthorized`. Existing Spanish UI and business validation remain unchanged.

`Sales.CompleteSale` checks live authentication before building or submitting checkout. Both Admin and Employee can sell; the existing sale service still validates payments, eligibility, stock and the open cash session.

`Summary.CancelSelectedSale` resolves a fresh circuit actor, verifies Admin, and passes that actor to `SaleService.Cancel`. The service retains its independent stored-ID/username/Admin validation and stock-restoration rules; the audit records the validated actor's ID and username. See [Sales.md](Sales.md#cancellation-and-daily-view).

These are component-level gates, not server authorization policies on every business service. Direct non-UI service callers must honor their own entry boundary. Shared mutable collections still permit concurrent edits; this change does not provide atomic permission checks and writes or protect a future API automatically.

## Verification

Run from the repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-auth-isolation.ps1
dotnet build
```

The script creates a retained fixture under the OS temporary directory, references the app without starting its host, and uses only synthetic users/data. It checks scope/event isolation, live identity/role resolution, denied component callbacks, navigation/subscription contracts, shared business instances, and checkout/cancellation/cash regressions. It compares the live data file's Git hash before and after; never start the application in the live repository for these checks.

Independent browser verification remains necessary: use two browser contexts to exercise login/logout, Admin/Employee menus, internal navigation, reload and reconnection. Static notification checks and direct callback tests do not prove browser rendering or transport lifecycle behavior.
