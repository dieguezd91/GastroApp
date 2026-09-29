# AGENTS.md

## Purpose

This file is the repository-level operating contract for AI coding agents working on GastroApp.

It is intentionally tool-agnostic and should be treated as the shared source of instructions for Codex, Claude Code, Antigravity, Gentle Shell, and other coding agents.

If a client requires a tool-specific instruction file (for example `CLAUDE.md`), keep that file minimal and point it to this document instead of duplicating repository rules.

---

## Repository

- Repository: `dieguezd91/GastroApp`
- Default branch: `main`
- Application: web-based food business management system
- Current framework: ASP.NET Core / Blazor Server
- Target framework: `.NET 7.0`
- Language: C#
- Current persistence: local JSON through `DataStorageService`
- Authentication dependency: `BCrypt.Net-Next 4.0.3`

Do not upgrade the framework, replace persistence, or introduce a new architectural stack unless the task explicitly requires it.

---

## Source of Truth

Before answering questions about implementation, architecture, contracts, configuration, versions, or technical state, inspect the repository.

Use this priority order:

1. Current source code, `GastroApp.csproj`, configuration, and repository structure.
2. Current documents under `Docs/Architecture/`, when that directory exists.
3. This `AGENTS.md`.
4. Current repository design/product documents.
5. Historical implementation notes such as `CAMBIOS_IMPLEMENTADOS.md` and `NUEVAS_FUNCIONALIDADES.md`.
6. External notes, uploaded copies, plans, walkthroughs, or prior conversations.

When documentation conflicts with current code, current code wins unless the task is explicitly to change the code to match an approved specification.

Do not assume a copied or uploaded Markdown file is current when a repository version exists.

If a relevant fact cannot be verified from the repository, state that clearly instead of guessing.

---

## Required Startup Workflow

For implementation or architecture work:

1. Read this file.
2. Inspect the files directly related to the requested change.
3. Read relevant files in `Docs/Architecture/` if present.
4. Check `GastroApp.csproj` and configuration when dependencies, versions, hosting, or runtime behavior matter.
5. Trace callers and dependencies before changing shared services or models.
6. Make the smallest coherent change that solves the requested problem.
7. Validate the result before reporting completion.

Do not perform speculative refactors outside the requested scope.

---

## Current Structure

The current project is a single ASP.NET Core / Blazor Server application.

Primary responsibilities:

- `Models/`
  - Domain/data models.
  - Keep business behavior small and domain-focused.
  - Avoid UI concerns.

- `Services/`
  - Business logic and state coordination.
  - Persistence currently flows through `DataStorageService`.
  - Prefer putting business rules here instead of Razor components.

- `Pages/`
  - Blazor routable UI.
  - Keep pages focused on presentation, user interaction, and orchestration.
  - Avoid duplicating business rules already owned by services.

- `Shared/`
  - Shared Blazor layout/navigation components.

- `wwwroot/`
  - Static assets and frontend styles/scripts.

- `Program.cs`
  - Application composition root and service registration.
  - Keep dependency wiring here rather than hiding global service lookups elsewhere.

- `data.json`
  - Current persisted application state / seed-like working data.
  - Do not edit it as part of normal code changes unless the task explicitly requires data changes.

- `bin/` and `obj/`
  - Build output.
  - Do not manually edit generated files or treat them as source of truth.

There is currently no `Docs/Architecture/` directory. When architectural decisions become stable, new architecture documents should be placed there.

---

## Current Architectural Constraints

The application is still a prototype and some implementation choices are transitional.

### Service lifetime

Most application services are currently registered as singletons to preserve shared in-memory state.

Treat this as current implementation state, not as a general rule for future features.

Do not put new user-specific, request-specific, or session-specific mutable state into a singleton without explicitly validating the lifetime and isolation requirements.

### Persistence

`DataStorageService` owns JSON persistence through `data.json`.

Current code is not a database-backed transactional system. Do not assume:

- concurrency safety;
- transactional rollback;
- multi-instance consistency;
- production-grade persistence guarantees.

Do not introduce EF Core, SQL, repositories, Unit of Work, or another persistence abstraction unless required by the task or an approved architecture document.

### Cross-service dependencies

Some current services are wired after DI construction from `Program.cs` using setter methods to avoid dependency cycles.

Do not create additional dependency cycles casually.

When modifying these areas:

- trace the dependency graph first;
- prefer explicit, directional dependencies;
- avoid service-locator patterns;
- do not redesign the entire graph unless the task requires it.

### Authentication

Authentication currently exists through `AuthService`, `UserService`, and BCrypt password verification.

Do not rely on older documentation claiming that authentication is absent.

Because the application uses Blazor Server and current services include singleton state, verify user/session isolation before extending authentication or authorization behavior.

---

## Coding Standards

Write clean, readable, modular C#.

Prefer:

- small classes with a clear responsibility;
- explicit dependencies through constructor injection when practical;
- domain-relevant names;
- early returns for invalid states;
- simple control flow;
- reusable business logic in services;
- nullable reference types used correctly;
- immutable/read-only data where mutation is unnecessary;
- methods that expose intent rather than implementation detail.

Avoid:

- unnecessary abstractions;
- premature generic frameworks;
- hidden global state;
- duplicated business rules;
- large Razor code blocks containing domain logic;
- magic strings when a stable domain type or constant is warranted;
- broad static helper classes for stateful behavior;
- catching exceptions only to silently ignore failures;
- unrelated formatting or cleanup in task-focused changes.

Follow the existing repository style unless the task explicitly includes a style refactor.

Comments should explain non-obvious intent or constraints, not restate the code.

---

## SOLID and Modularity

Apply SOLID pragmatically.

In particular:

- A page should not become the owner of business rules.
- A service should not accumulate unrelated responsibilities.
- Persistence details should not leak throughout UI code.
- Shared behavior should have one clear owner.
- New dependencies should point toward the layer that owns the relevant rule.
- Prefer composition over adding conditionals to unrelated services.

Do not add interfaces mechanically. Introduce an abstraction when it creates a real boundary, supports substitution/testing, or removes an undesirable dependency.

---

## Data and Business Rules

Before changing a model or calculation:

1. Find every service and page that reads or writes the affected data.
2. Verify serialization impact in `DataStorageService`.
3. Consider compatibility with existing `data.json`.
4. Preserve IDs and relationships unless a migration is explicitly part of the task.
5. Keep unit conversion and stock/cost calculations centralized rather than duplicating formulas in UI code.

Current implemented domains include, among others:

- products;
- sales;
- cash register;
- daily summaries;
- users/authentication;
- ingredients and stock;
- suppliers;
- invoices;
- recipes and recipe costing.

This list is descriptive, not an API contract. Verify the current code before changing any of these areas.

---

## UI Changes

For Blazor UI work:

- preserve existing navigation and authorization behavior unless the task changes it;
- keep business logic out of markup when it belongs in a service;
- reuse existing visual patterns before introducing a parallel component style;
- check responsive behavior for layout changes;
- do not solve state bugs with forced reloads unless the lifecycle/state cause has been verified;
- unsubscribe event handlers when components subscribe to long-lived services.

When authentication state affects navigation or layout, trace the full event/state flow before changing the UI.

---

## Dependencies

Before adding a NuGet package:

1. Confirm the feature cannot be implemented reasonably with the existing stack.
2. Check compatibility with `net7.0`.
3. Add the package only to `GastroApp.csproj`.
4. Explain why the dependency is needed.
5. Validate restore/build afterward.

Do not upgrade existing packages or the target framework as incidental work.

---

## Validation

Minimum validation for code changes:

```bash
dotnet build
```

If the task affects runtime behavior, also run the application when the available environment supports it:

```bash
dotnet run
```

Then exercise the affected flow when practical.

There is currently no repository test project detected. Do not claim automated tests passed unless such tests actually exist and were executed.

If tests are later added, run the smallest relevant test set first, then the broader suite when warranted.

Never report a change as verified if validation was not actually performed.

---

## Change Discipline

Before editing:

- inspect the current implementation;
- identify direct callers and consumers;
- preserve unrelated behavior.

While editing:

- keep diffs focused;
- avoid renaming unrelated files/types;
- avoid mass formatting;
- do not overwrite user changes;
- do not modify generated output.

After editing:

- review the diff;
- build/test as applicable;
- verify that documentation still matches the implementation.

If a task reveals a broader architectural problem that is outside scope, report it separately instead of silently expanding the task.

---

## Documentation

Architecture documentation belongs under `Docs/Architecture/`.

Create or update architecture documentation when a change establishes or materially changes:

- ownership of a subsystem;
- service boundaries;
- persistence contracts;
- authentication/authorization flow;
- cross-module contracts;
- important lifecycle/state rules;
- deployment/runtime architecture.

Documentation should describe the implemented architecture, not an aspirational design unless clearly labeled as proposed.

Historical files such as `CAMBIOS_IMPLEMENTADOS.md` and `NUEVAS_FUNCIONALIDADES.md` may contain stale information. Do not use them as the primary source for current behavior.

---

## Agent Behavior

Agents must:

- inspect before modifying;
- distinguish verified facts from assumptions;
- prefer repository evidence over remembered context;
- keep implementations scoped;
- preserve existing behavior unless change is requested;
- report validation performed and any validation that could not be performed;
- mention important discrepancies between code and documentation.

Agents must not:

- claim work was performed when it was not;
- invent files, APIs, tests, database schemas, or requirements;
- silently introduce a new architecture;
- treat historical notes as current implementation truth;
- modify unrelated files to make a change appear cleaner;
- commit credentials, tokens, secrets, or machine-specific paths.

---

## Client-Specific Instruction Files

This repository should keep this file as the shared instruction source.

If a coding client needs its own root instruction file, that file should contain only the minimum client-specific bootstrap needed to load or follow `AGENTS.md`.

Do not maintain separate copies of architecture or coding rules per client. Divergent instruction files create inconsistent implementations across agents.
