# speechwave — Overview

> **Navigation aid.** This article shows WHERE things live (routes, models, files). Read actual source files before implementing new features or making changes.

**speechwave** is a elixir project built with phoenix, using ecto for data persistence, organized as a monorepo.

**Workspaces:** `assets` (`assets`), `speechwave-load-test` (`scripts/load_test`)

## Scale

16 API routes · 7 database models · 1 library files · 6 middleware layers · 9 environment variables

## Subsystems

- **[Auth](./auth.md)** — 2 routes — touches: auth
- **[Audience_load](./audience_load.md)** — 3 routes
- **[Router.ex](./router.ex.md)** — 9 routes — touches: auth
- **[Infra](./infra.md)** — 2 routes — touches: auth

**Database:** ecto, 7 models — see [database.md](./database.md)

## High-Impact Files

Changes to these files have the widest blast radius across the codebase:

- `lib/speechwave/accounts_fixtures.ex` — imported by **29** files
- `lib/speechwave_web/conn_case.ex` — imported by **23** files
- `lib/speechwave/accounts.ex` — imported by **22** files
- `lib/speechwave/talks_fixtures.ex` — imported by **16** files
- `lib/speechwave/repo.ex` — imported by **15** files
- `lib/speechwave/data_case.ex` — imported by **14** files

## Required Environment Variables

- `NODE_ENV` — `assets/js/app.js`

---
_Back to [index.md](./index.md) · Generated 2026-11-20_