# GDPR Data Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Download my data" button in Settings that returns `speechwave-data.zip` (JSON data, JSON Schema, README) for the signed-in user, rate limited, with the privacy page updated.

**Architecture:** `Speechwave.DataExport` builds the export map for a scope's user and packs the three files into a zip in memory. `Speechwave.DataExportThrottle` is an ETS cooldown (modelled on `Speechwave.AuthThrottle`) with an atomic claim that is released if the build fails. A plain controller action serves the zip (a LiveView cannot send a file); the Settings button is a link to it.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Ecto, Erlang `:zip`, Jason, `ex_json_schema` (test only).

**Spec:** `docs/specs/2026-10-23-gdpr-data-export-design.md`

## Global Constraints

- Branch is `feat/gdpr-data-export` (already created). No git worktrees. Conventional commit messages.
- Zip is named `speechwave-data.zip` and holds exactly `speechwave_data.json`, `speechwave_data.schema.json`, `README.md`. Built in memory, nothing stored or emailed.
- Excluded from every file: the API key, `users_tokens`, individual reaction rows, reaction timestamps, audience IDs. Included: `is_admin` and provider UIDs.
- Cooldown is 5 minutes per user id, in ETS, fails open on restart, logs a warning when it blocks.
- Only dependency added: `ex_json_schema`, `only: :test`.
- Context functions take `%Scope{}` first and query only that user's rows.
- README and privacy text is user-facing: use the `writing-tracy` skill, no AI cliches, no dash-separated phrases.
- Run `mix precommit` before the last task is done.

## Review Focus

1. User with no talks, no consents and no identities: every list is `[]`, the export still validates.
2. Talk with no sessions, and a session with no reactions: `total` 0, `audience_size` null, empty `by_emoji` and `by_slide`.
3. Another user's talks, sessions, identities and consents never appear in the export.
4. The user's real `api_key` string appears in none of the three files, and no `audience_id` value does either.
5. A build that raises releases the cooldown claim, so a retry is not blocked; and one user's claim does not block another user.
6. Unconfirmed user (`confirmed_at` nil) and talk titles with quotes, emoji and non-ASCII characters produce valid JSON.

## File Structure

- `lib/speechwave/data_export_throttle.ex` (new): cooldown GenServer + ETS.
- `lib/speechwave/data_export.ex` (new): `build/1`, `to_zip/1`.
- `priv/data_export/speechwave_data.schema.json`, `priv/data_export/README.md` (new): shipped as-is into the zip (README has an `{{exported_at}}` placeholder).
- `lib/speechwave_web/controllers/user_data_export_controller.ex` (new), `lib/speechwave_web/router.ex`, `lib/speechwave_web/live/user_live/settings.ex` (modify).
- `lib/speechwave_web/controllers/page_html/privacy.html.heex`, `docs/roadmap.md` (modify).

---

### Task 1: Test-only dependency and the export throttle

**Files:**
- Modify: `mix.exs` (add `{:ex_json_schema, "~> 0.10", only: :test}`), `lib/speechwave/application.ex:22` (add child after `Speechwave.AuthThrottle`)
- Create: `lib/speechwave/data_export_throttle.ex`
- Test: `test/speechwave/data_export_throttle_test.exs`

**Interfaces:**
- Produces: `Speechwave.DataExportThrottle.claim(user_id :: integer) :: :ok | {:error, retry_after_seconds :: pos_integer}`; `release(user_id) :: :ok`.

- [ ] **Step 1: Write the failing test.** Non-async, `@moduletag :capture_log`, `setup` does `:ets.delete_all_objects(:data_export_throttle)`. Tests: first `claim(1)` is `:ok`; a second `claim(1)` is `{:error, secs}` with `secs` between 1 and 300; `claim(2)` is `:ok` after `claim(1)`; after `release(1)`, `claim(1)` is `:ok`; an entry back-dated with `:ets.insert(:data_export_throttle, {1, now - 301_000})` allows `claim(1)`.
- [ ] **Step 2: Run it.** `mix deps.get && mix test test/speechwave/data_export_throttle_test.exs`. Expected: FAIL, module not defined.
- [ ] **Step 3: Implement `Speechwave.DataExportThrottle`** as a GenServer owning a `:public` named ETS table `:data_export_throttle` (key `user_id`, value monotonic ms of the claim), `@cooldown_ms 300_000`. `claim/1` must be atomic: use `:ets.insert_new/2` and, when the key exists but is expired, a compare-and-swap via `:ets.select_replace/2` (or equivalent) so two concurrent requests cannot both pass. Log a warning when blocking. Start it in `application.ex` next to `AuthThrottle`.
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat: add per-user cooldown for data export"` (include `mix.exs`, `mix.lock`).

### Task 2: Build the export data

**Files:**
- Create: `lib/speechwave/data_export.ex`
- Test: `test/speechwave/data_export_test.exs`

**Interfaces:**
- Consumes: `Accounts.list_user_identities/1`, `Reactions.count_audience/1` (nil when none), `Reactions.slide_reaction_totals/1`; fixtures `user_scope_fixture/1`, `talk_fixture/2`, `session_fixture/2`, `reaction_fixture/4`, `identity_fixture/2`.
- Produces: `Speechwave.DataExport.build(scope :: %Scope{}, exported_at :: DateTime.t() \\ DateTime.utc_now()) :: map` with atom keys, shaped exactly:
  `%{format_version: 1, exported_at, account: %{email, plan (string), is_admin, confirmed_at, welcomed_at, overlay_size_percent, fireworks_enabled, inserted_at, updated_at}, sign_in_providers: [%{provider, uid, linked_at}], consents: [%{consent_type, granted, granted_at, revoked_at, source}], talks: [%{title, slug, inserted_at, updated_at, sessions: [%{label, started_at, ended_at, reactions: %{total, audience_size, by_emoji: %{emoji => count}, by_slide: [%{slide_number, emoji, count}]}}]}]}`.

- [ ] **Step 1: Write failing tests** for Review Focus 1, 2, 3 and 4: (a) a bare user yields empty lists and the account fields from the user row; (b) a user with two talks, sessions and reactions (several emoji, two slides, two audience ids plus one nil) yields the exact `total`, `audience_size: 2`, `by_emoji` and `by_slide`; (c) a second user's data is absent; (d) `Jason.encode!(build(scope))` does not contain the user's `api_key` nor any audience id string.
- [ ] **Step 2: Run** `mix test test/speechwave/data_export_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement `build/2`** in `lib/speechwave/data_export.ex`. Load the user's talks with sessions in one preloaded query ordered by `inserted_at`; compute per-session aggregates with grouped queries, not per-row Elixir loops over reactions. Never select `api_key` or `audience_id` into the result.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat: build the user data export map`.

### Task 3: Schema, README and the zip

**Files:**
- Create: `priv/data_export/speechwave_data.schema.json`, `priv/data_export/README.md`
- Modify: `lib/speechwave/data_export.ex`
- Test: `test/speechwave/data_export_test.exs` (extend)

**Interfaces:**
- Consumes: `DataExport.build/2`.
- Produces: `Speechwave.DataExport.to_zip(scope, exported_at \\ DateTime.utc_now()) :: {:ok, binary}`, a zip with the three files named in Global Constraints.

- [ ] **Step 1: Write failing tests.** Unzip with `:zip.unzip(binary, [:memory])` and assert: the three file names; the JSON decodes and passes `ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(schema), data)` for both a rich user and a bare user (Review Focus 1, 2, 6 with a title like `"Q&A \"live\" 日本語 🎉"` and an unconfirmed user); README contains the export date and, case-insensitively, the phrases "not a backup" and "re-import"; none of the three files contains the user's `api_key`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Write the schema** (draft-07, `additionalProperties: false` on every object, `format: date-time` on timestamps, nullable fields typed `["string","null"]`, `by_emoji` with `additionalProperties: {"type":"integer"}`). Every property has a `description`, since an LLM reads this. If `ex_json_schema` rejects `format: date-time` on nullable types, keep the format and report it rather than dropping strictness silently.
- [ ] **Step 4: Write the README** (use `writing-tracy`): what Speechwave is; each section and field; export date via `{{exported_at}}` placeholder replaced in `to_zip/2`; snapshot; **not a backup and cannot be re-imported at this time**; the exclusions table from the spec with reasons (API key and tokens, individual reactions with times and audience IDs, backups); link to https://speechwave.live/privacy and admin@speechwave.live.
- [ ] **Step 5: Implement `to_zip/2`** reading both priv files at compile time (`@external_resource`) and building the archive with `:zip.create(~c"speechwave-data.zip", files, [:memory])`; encode JSON with `Jason.encode!(map, pretty: true)`.
- [ ] **Step 6: Run.** Expected: PASS.
- [ ] **Step 7: Commit.** `feat: package the data export as a zip with schema and README`.

### Task 4: Route, controller and Settings button

**Files:**
- Create: `lib/speechwave_web/controllers/user_data_export_controller.ex`
- Modify: `lib/speechwave_web/router.ex` (in the authenticated scope beside `delete "/users/account"`: `get "/users/settings/export", UserDataExportController, :show`), `lib/speechwave_web/live/user_live/settings.ex` (beside the danger zone)
- Test: `test/speechwave_web/controllers/user_data_export_controller_test.exs`, plus a LiveView assertion in the existing Settings test file

**Interfaces:**
- Consumes: `DataExportThrottle.claim/1`, `release/1`, `DataExport.to_zip/1`.
- Produces: `GET /users/settings/export`, `id="download-my-data"` link on Settings (use a plain `<a href download>` or `<.link href=...>`, not `navigate`).

- [ ] **Step 1: Write failing tests** (`ConnCase`, `async: false`, clear `:data_export_throttle` in `setup`): logged-in GET returns 200, `content-type` `application/zip`, `content-disposition` containing `speechwave-data.zip`, a body that unzips to the three files; second GET within the cooldown redirects to `/users/settings` with an error flash containing "minutes" and sends no file; a different user is unaffected; a logged-out GET redirects to the login page; if building the zip raises (the controller calls `Application.get_env(:speechwave, :data_export_zip_fun, &DataExport.to_zip/1)`; the test sets it to a function that raises and removes it in `on_exit`), the claim is released so the next GET works (Review Focus 5). Settings LiveView test: `has_element?(view, "#download-my-data")`, for both a normal user and an admin.
- [ ] **Step 2: Run** the new tests. Expected: FAIL.
- [ ] **Step 3: Implement `UserDataExportController.show/2`:** claim, build with `to_zip`, `send_download(conn, {:binary, zip}, filename: "speechwave-data.zip", content_type: "application/zip")`; rescue-and-release on exceptions then re-raise; on `{:error, secs}` redirect with flash "You downloaded your data recently. Please try again in N minutes." (N = ceil(secs / 60)). Add the Settings card: a "Your data" block above the danger zone with a short explanation and the link, in the style of the existing cards.
- [ ] **Step 4: Run** the new tests and `mix test test/speechwave_web`. Expected: PASS.
- [ ] **Step 5: Commit.** `feat: add Download my data to Settings`.

### Task 5: Privacy page, roadmap, precommit

**Files:**
- Modify: `lib/speechwave_web/controllers/page_html/privacy.html.heex` (section 6, and any other place that tells people to email for access), `docs/roadmap.md` (remove the "GDPR: download my data" section)
- Test: `test/speechwave_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Write the failing test:** the privacy page mentions the Settings download (assert on an element id such as `#privacy-data-export` on the new paragraph, per project test style).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Update the privacy page** (use `writing-tracy`): add a paragraph with `id="privacy-data-export"` saying signed-in users can download a copy of their data from Settings, what it contains, that it leaves out credentials and other people's data, and that emailing admin@speechwave.live remains available for anything it does not cover. Check the rest of the page for access-request wording and make it consistent. Delete the roadmap item.
- [ ] **Step 4: Run** `mix precommit`. Expected: passes with no warnings.
- [ ] **Step 5: Commit.** `docs: document the data export in the privacy policy and clear the roadmap item`.
