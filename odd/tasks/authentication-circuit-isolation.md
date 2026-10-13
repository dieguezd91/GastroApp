# Authentication circuit isolation

## Objective and scope
Isolate AuthService per Blazor Server circuit before manual cash movements; preserve business singletons and existing JSON. Preserve Admin/Employee and internal login/logout/menu redirects; enforce live permission/identity checks at sensitive actions and current audit attribution. No Identity/cookies/new dependencies/database/session persistence/unrelated refactors/data.json edits. No commits or push authorized or performed.

## Tasks
- [x] AUTH-1: Circuit identity, navigation/events, action guards, English docs, deterministic tests. Delegated gentle-ai-worker (multi-file trigger).
- [x] AUTH-2: Independent build/harness, two actual Chrome contexts and basic POS/sales/cash smoke verification. Delegated gentle-ai-verify (independent/external verification trigger). Extended lifecycle and stale-form browser coverage remain explicitly pending below.

## Decisions
Only AuthService changes to scoped. Circuit stores user ID plus login-time username/password-hash snapshots, resolves live user/role, and invalidates deleted/renamed/password-changed identities. No singleton captures AuthService. Auth navigation no longer forces document reload. Layout/menu dispatch notifications and unsubscribe on disposal. Sensitive callbacks recheck auth/admin; cancellation passes fresh circuit actor into existing service validation.
19 authored files: 431 additions/84 deletions, including 195-line reusable fixture harness; production/docs 320 changed lines. Delivery strategy ask-on-risk if delivery later requested. Commit evidence: not authorized. Existing user csproj net8.0 change preserved.

## Executed evidence
Writer observed RED before source changes (initial scratch compile issue corrected), GREEN 147 checks, final 215 checks. Independent verifier reran powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-auth-isolation.ps1: 215 passed, zero failures. dotnet build independently passed with zero warnings/errors. git diff --check passed.
Chrome/Node CDP drove two independent browser contexts against isolated disposable fixture process: distinct Admin/Employee identities, independent login/logout, menu role visibility, Employee denied /cash, internal navigation preserves identity, shared catalog/open cash, Employee Cafe sale 150, Admin summary and cancellation attributed to test-admin ID 4, Admin cash open 100/close 250, persisted fixture sale/movement/audit, full reload redirects to /login. Browser driver first failed on scratch assumptions (missing Add payment and automatic cross-circuit refresh expectation); final run passed. No packages installed. App/browser stopped in finally.
Live hashes unchanged before/after: data.json 0f8def10c364036b406c8d225f8e5fa059b26954; GastroApp.csproj 190890656d669c27c178fc53dfc526a9a184e818. No live app startup; fixture writes only in OS temp.
Browser driver: C:/Users/Dani/AppData/Local/Temp/gastro-browser-L0QGGg/verify.cjs. Independent harness fixture: C:/Users/Dani/AppData/Local/Temp/gastro-auth-54d96143d0d54cf285e113eaa28fad54.

## Native review
ASSESS initially unassessable/high due to undeclared untracked paths; independent verification performed. INSPECT included Authentication.md and verification script, excluded mutable task bookkeeping; native preflight stopped managed_assets_outdated. No lineage/approval claimed. Offered continuation: managed tooling sync, intentionally not executed in this scoped application task. Review pending tooling maintenance. Pre-existing csproj change appears in workspace projection; not authored by this feature.

## Pending coverage and risks
- Disconnect/reconnect, retained circuit recovery, expiry/replacement and queued disposal behavior not executed; documented lifecycle is not test evidence.
- Browser demotion/password change/deletion while a form is open, every individual admin-route denial and stock-consuming POS variants not executed. Deterministic harness covers stale identity/role and callbacks; it includes structural/reflection checks, not browser rendering proof.
- Existing shared business state is nontransactional. Already-mounted POS does not automatically rerender after another circuit closes cash; navigating away/back updates it. No auth leak observed, no unrelated freshness refactor.
- Circuit auth is intentionally nonpersistent: reload/new circuit/server restart loses login; same retained circuit may survive transient reconnect, replacement cannot.

## Commit authorization
After implementation and verification, the user explicitly authorized a commit. The authentication work unit includes its source, harness and documentation on a feature branch. The pre-existing GastroApp.csproj framework change remains excluded and uncommitted. Earlier no-commit statements above describe the implementation phase. Push is not authorized. Resolve the work-unit identity with git log --format=%H --grep='fix(auth): isolate authentication per Blazor circuit' -1.

## Next step
Human review and optional tooling maintenance/native review; optional extended lifecycle browser checks. Manual cash movements remain a separate subsequent feature, not implemented here.
