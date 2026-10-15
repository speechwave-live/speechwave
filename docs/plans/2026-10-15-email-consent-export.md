# Email Consent Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An admin-only CSV download of currently-consented, confirmed marketing-email users, with a filter form on `/admin/stats`.

**Architecture:** A query module returns plain row maps (user and consent fields plus talk/session aggregates from subqueries). A small CSV module encodes rows with formula-injection protection. A controller behind a new admin plug serves the file. `StatsLive` renders a plain GET form that targets the controller.

**Tech Stack:** Phoenix 1.8, Ecto (SQLite/Postgres via `Speechwave.Repo`), ExUnit. No new dependencies.

**Spec:** `docs/specs/2026-10-15-email-consent-export-design.md`

## Global Constraints

- CSV columns, in order: `email,source,consented_at,plan,signed_up_at,talk_count,session_count,last_session_at`
- Included users: `marketing_email` consent with `granted = true` and `revoked_at` nil, and `users.confirmed_at` not nil
- Dates are ISO 8601 UTC; rows ordered by `granted_at` ascending, then email
- Response: `text/csv; charset=utf-8`, `content-disposition: attachment`, filename `marketing-consent-YYYY-MM-DD.csv`
- Fields beginning with `=`, `+`, `-`, `@`, tab or CR get a leading `'`; fields containing comma, quote, CR or LF are quoted with embedded quotes doubled
- No new dependencies. No plan, signup-date or activity filters. No new LiveView route.
- Follow `CLAUDE.md`: unique DOM ids, `to_form`, `<.input>`, conventional commits, `mix precommit` before finishing.

## Review Focus

- Email or source containing a comma, double quote or newline: CSV stays one row per user with correct quoting (Task 1).
- Source such as `=HYPERLINK(...)`: output cell is prefixed with `'` (Task 1).
- Consent-granted user with no talks, and one with a talk but no sessions: appear with `0` counts and blank `last_session_at` (Task 2).
- User with several talks and sessions: counts are not multiplied by the join (Task 2).
- User who revoked and later re-granted: appears once, with the current `granted_at` (Task 2).
- `to` date equal to the day of a consent granted at 23:59:59: still included (Task 2).
- Garbage or blank date params and blank source: treated as no filter, no 500 (Task 2, Task 3).
- Logged-out and non-admin requests to the download route get no CSV (Task 3).

---

### Task 1: CSV encoder

**Files:**
- Create: `lib/speechwave/admin/csv.ex`
- Test: `test/speechwave/admin/csv_test.exs`

**Interfaces:**
- Produces: `Speechwave.Admin.CSV.encode(headers :: [String.t()], rows :: [[term()]]) :: iodata()`. Cells may be strings, integers, `nil` (blank), `DateTime` (ISO 8601 via `DateTime.to_iso8601/1`) or atoms (`to_string/1`). Lines end in `\r\n`, header line first.

- [ ] **Step 1: Write failing tests** in `csv_test.exs` (`use ExUnit.Case, async: true`, compare via `IO.iodata_to_binary/1`):
  - `"header row then rows joined with CRLF"`: `encode(["a","b"], [["x", 1]])` == `"a,b\r\nx,1\r\n"`
  - `"nil is blank, DateTime is ISO 8601, atom is stringified"`: row `[nil, ~U[2026-10-15 12:00:00Z], :pro]` → `",2026-10-15T12:00:00Z,pro\r\n"` after the header
  - `"quotes fields with comma, quote or newline"`: `"a,b"` → `"\"a,b\""`, `~s(say "hi")` → `"\"say \"\"hi\"\"\""`, `"a\nb"` → `"\"a\nb\""`
  - `"neutralizes formula prefixes"`: for each of `"=1+1"`, `"+1"`, `"-1"`, `"@x"`, `"\tx"`, `"\rx"` the cell begins with `'` (the `\r` and `\t` cases are also quoted if they contain a quoted character; assert the first character after any opening quote is `'`)
  - `"does not prefix a plain negative-looking integer"`: integer `-5` is written as `-5`, because only binaries are neutralized

- [ ] **Step 2: Run** `mix test test/speechwave/admin/csv_test.exs` — expect FAIL (module undefined).

- [ ] **Step 3: Implement `encode/2`** in `csv.ex` with a `@moduledoc` and a short comment on why formula prefixes are neutralized. Neutralize first, then quote.

- [ ] **Step 4: Run** the same command — expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave/admin/csv.ex test/speechwave/admin/csv_test.exs
git commit -m "feat: add CSV encoder with formula-injection protection"
```

---

### Task 2: Consent export query

**Files:**
- Create: `lib/speechwave/admin/consent_export.ex`
- Test: `test/speechwave/admin/consent_export_test.exs`

**Interfaces:**
- Consumes: `Speechwave.Admin.CSV.encode/2` (Task 1).
- Produces:
  - `Speechwave.Admin.ConsentExport.list(filters :: map()) :: [map()]`. `filters` has optional keys `:source` (string or nil), `:from` and `:to` (`Date.t()` or nil). Each row map has keys `:email, :source, :consented_at, :plan, :signed_up_at, :talk_count, :session_count, :last_session_at`.
  - `Speechwave.Admin.ConsentExport.parse_filters(params :: map()) :: map()` — takes string-keyed params (`"source"`, `"from"`, `"to"`), returns the `filters` map. Blank or unparseable → nil.
  - `Speechwave.Admin.ConsentExport.to_csv(rows :: [map()]) :: iodata()` — header per Global Constraints, built with `CSV.encode/2`.
  - `Speechwave.Admin.ConsentExport.filename(date :: Date.t()) :: String.t()` → `"marketing-consent-2026-10-15.csv"`.

- [ ] **Step 1: Write failing tests** in `consent_export_test.exs` (`use Speechwave.DataCase`; fixtures from `Speechwave.AccountsFixtures` and `Speechwave.TalksFixtures`). Add a private test helper `confirmed_consented(source)` that creates a user via `consented_user_fixture(%{source: source})` and confirms it with `session_token_fixture(user)` (that fixture sets `confirmed_at`). Tests:
  - `"includes granted, confirmed users with all columns"`: one row, assert `email`, `source`, `plan == :free`, `consented_at` is a `DateTime`
  - `"excludes unconfirmed users"`
  - `"excludes revoked consent"` (use `Accounts.revoke_consent/2`)
  - `"revoked then re-granted appears once"`
  - `"excludes users who never granted"` (plain `user_fixture` confirmed)
  - `"source filter is an exact match"`
  - `"date range is inclusive on both ends"`: backdate `granted_at` with `Repo.update_all` to `2026-10-01 00:00:00` and `2026-10-10 23:59:59`; `from: ~D[2026-10-01], to: ~D[2026-10-10]` returns both; `to: ~D[2026-10-09]` returns one
  - `"user with no talks has zero counts and nil last_session_at"`
  - `"user with a talk but no sessions has talk_count 1, session_count 0"`
  - `"counts are not multiplied across joins"`: 2 talks, 3 sessions total → `talk_count 2`, `session_count 3`, `last_session_at` equals the latest `started_at`
  - `"orders by consented_at then email"`
  - `"parse_filters ignores blank and unparseable values"`: `%{"source" => "", "from" => "nope", "to" => ""}` → all nil; valid `"2026-10-01"` → `~D[2026-10-01]`
  - `"to_csv has the exact header and one line per row"`
  - `"filename"` returns the dated name

- [ ] **Step 2: Run** `mix test test/speechwave/admin/consent_export_test.exs` — expect FAIL.

- [ ] **Step 3: Implement** the four functions in `consent_export.ex`. Approach: base query from `UserConsent` inner-joined to `User`, filtered on `consent_type == "marketing_email" and granted == true and is_nil(revoked_at)` and `not is_nil(u.confirmed_at)`; two grouped subqueries (talk counts per `user_id`; session count and `max(started_at)` per `talks.user_id` via join to `talk_sessions`), left-joined with `coalesce(..., 0)`. Date bounds compare `granted_at` to start-of-day `from` and end-of-day `to` as UTC `DateTime`s. Add `@moduledoc` and a one-line comment on why subqueries are used instead of a single join (avoids count multiplication).

- [ ] **Step 4: Run** the same command — expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave/admin/consent_export.ex test/speechwave/admin/consent_export_test.exs
git commit -m "feat: add marketing consent export query and CSV rows"
```

---

### Task 3: Admin plug, route and download controller

**Files:**
- Modify: `lib/speechwave_web/user_auth.ex` (add `require_admin_user/2` plug next to `require_authenticated_user/2`)
- Modify: `lib/speechwave_web/router.ex` (admin scope, around lines 52-65)
- Create: `lib/speechwave_web/controllers/admin/consent_export_controller.ex`
- Test: `test/speechwave_web/controllers/admin/consent_export_controller_test.exs`

**Interfaces:**
- Consumes: `ConsentExport.parse_filters/1`, `list/1`, `to_csv/1`, `filename/1` (Task 2).
- Produces:
  - `SpeechwaveWeb.UserAuth.require_admin_user(conn, opts)` — plug; if `conn.assigns.current_scope.user.is_admin` is not true, flash `"You must be an admin to access this page."`, redirect to `~p"/"`, halt. Assumes it runs after `require_authenticated_user`.
  - Route `get "/consent-export", ConsentExportController, :show` in a new `scope "/admin", SpeechwaveWeb.Admin` using `pipe_through [:browser, :require_authenticated_user, :require_admin_user]`, so `~p"/admin/consent-export"` works. Keep the existing LiveView scope untouched; LiveView and plain routes cannot share one pipeline here.
  - `ConsentExportController.show(conn, params)` reads filters from `params["export"]` (the form nests under `export`; treat a missing key as `%{}`).

- [ ] **Step 1: Write failing tests** in the controller test (`use SpeechwaveWeb.ConnCase`; log in with `log_in_user/2`):
  - `"logged-out request redirects to login and returns no CSV"`: `get(build_conn(), ~p"/admin/consent-export")` → redirected to `/users/log-in`, body has no consented email
  - `"non-admin is redirected home and gets no CSV"`: redirected to `~p"/"`, response content type is not `text/csv`
  - `"admin gets a CSV attachment"`: status 200; `get_resp_header(conn, "content-type")` starts with `text/csv`; `content-disposition` header matches `~r/attachment; filename="marketing-consent-\d{4}-\d{2}-\d{2}\.csv"/`; body's first line is the header; body contains a seeded consented, confirmed user's email
  - `"filters from the export param nest are applied"`: two users with different sources, `get(conn, ~p"/admin/consent-export", %{"export" => %{"source" => "pricing_pro"}})` contains only one
  - `"garbage dates do not crash"`: `%{"export" => %{"from" => "nope", "to" => "x"}}` → 200

- [ ] **Step 2: Run** `mix test test/speechwave_web/controllers/admin/consent_export_controller_test.exs` — expect FAIL (no route).

- [ ] **Step 3: Implement** the plug, route and controller. Use `send_download`-free approach: `conn |> put_resp_content_type("text/csv") |> put_resp_header("content-disposition", ~s(attachment; filename="...")) |> send_resp(200, csv)`. The browser pipeline's `accepts ["html"]` is fine for a form navigation; do not change the pipeline.

- [ ] **Step 4: Run** the same command — expect PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/user_auth.ex lib/speechwave_web/router.ex lib/speechwave_web/controllers/admin test/speechwave_web/controllers/admin
git commit -m "feat: add admin-only marketing consent CSV download"
```

---

### Task 4: Export section on the stats page, roadmap upkeep

**Files:**
- Modify: `lib/speechwave_web/live/admin/stats_live.ex` (mount: assign the form)
- Modify: `lib/speechwave_web/live/admin/stats_live.html.heex` (add section after the stats grid)
- Modify: `test/speechwave_web/live/admin/stats_live_test.exs`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes: route `~p"/admin/consent-export"` (Task 3).
- Produces: in `StatsLive`, assign `:export_form` = `to_form(%{"source" => "", "from" => "", "to" => ""}, as: :export)`. Template ids: `#consent-export`, `#consent-export-form`, `#export-source`, `#export-from`, `#export-to`, `#consent-export-submit`.

- [ ] **Step 1: Write failing test** `"admin sees the consent export form"` in `stats_live_test.exs`: log in as admin, `live(conn, ~p"/admin/stats")`, assert `has_element?` for `#consent-export`, `#consent-export-form[action="/admin/consent-export"][method="get"]`, `#export-source`, `#export-from`, `#export-to`, `#consent-export-submit`.

- [ ] **Step 2: Run** `mix test test/speechwave_web/live/admin/stats_live_test.exs` — expect the new test FAIL.

- [ ] **Step 3: Implement** the section: a card in the page's existing style with a heading ("Email consent export"), one sentence saying it lists currently consented, confirmed users, a `<.form for={@export_form} id="consent-export-form" action={~p"/admin/consent-export"} method="get">` with `<.input type="text">` for `source` and `<.input type="date">` for `from` and `to`, and a submit button labelled "Download CSV". No `phx-submit`, so the browser performs a normal GET. Match the surrounding Tailwind tokens (`text-ink`, `bg-canvas`, etc.).

- [ ] **Step 4: Run** `mix test test/speechwave_web/live/admin/stats_live_test.exs` — expect PASS.

- [ ] **Step 5: Roadmap upkeep.** In `docs/roadmap.md` remove the "Super-admin panel: email consent export" item and the "Super admin email export UI" item (and its IEx fallback note), since both are now shipped.

- [ ] **Step 6: Run `mix precommit`** and fix anything it reports. Expect a clean exit.

- [ ] **Step 7: Manual check** in the dev server: log in as an admin, open `/admin/stats`, download with and without filters, open the file in a spreadsheet and confirm columns and that a `source` starting with `=` shows as text.

- [ ] **Step 8: Commit**

```bash
git add lib/speechwave_web/live/admin test/speechwave_web/live/admin/stats_live_test.exs docs/roadmap.md
git commit -m "feat: add email consent export form to admin stats page"
```
