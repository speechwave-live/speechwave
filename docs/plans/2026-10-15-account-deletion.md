# Account Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can permanently delete their own account from a Danger zone on `/users/settings`; deletions survive a restore of `speechwave.db` via a separate `deletions.db` log.

**Architecture:** A small `Speechwave.DeletionLog` module talks to `deletions.db` through `Exqlite.Sqlite3` (one short-lived connection per call, table created if absent, no Ecto repo, no migration). `Accounts.delete_account/2` checks the rules, writes the log row, then deletes the user (FK cascades do the rest). A controller action performs the deletion and clears the session; the Settings LiveView hosts the card and dialog and submits to it with `phx-trigger-action`.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto SQLite (`ecto_sqlite3`), `exqlite` (already a dependency), ExUnit.

**Spec:** `docs/specs/2026-10-15-account-deletion-design.md`

## Global Constraints

- Log table columns: `user_id` (nullable integer), `deleted_at` (text, ISO 8601 UTC, second precision); index on `deleted_at`. No email, hash or other personal data.
- Scrub threshold: rows with `deleted_at` older than 30 days get `user_id` set to NULL. Rows are never deleted.
- Order inside `delete_account`: admin check, typed-email check (trimmed, case-sensitive), log write, scrub, delete the user. Log write failure returns `{:error, :log_failed}` and deletes nothing.
- Return values: `delete_account/2` is `{:ok, user}` or `{:error, :admin | :confirmation_mismatch | :log_failed}`; `reapply_recorded_deletions/0` returns an integer.
- Flash after deletion: `"Your account and its data have been deleted."`
- Public text says "within 30 days" and never "5 days". User-facing prose: no dash-separated phrases, no filler.
- App is light-only; Danger zone card is the tinted style: pale red fill, 5px red left accent bar, red heading with a warning mark, solid red "Delete my account…" button.
- Follow `CLAUDE.md`: unique DOM ids, `to_form`, `<.input>`, no inline `<script>` (colocated hooks only), conventional commits, `mix precommit` before finishing. Do not run `mix compile` in dev while the dev server runs; use `mix test`.
- No new dependencies. No data export, grace period or confirmation email.

## Review Focus

- Typed email with surrounding spaces is accepted; different case is rejected (Task 2, Task 5).
- Deleting twice (second tab, double submit) neither crashes nor 500s (Task 2, Task 4).
- Old session cookie after deletion: next request is logged out, no crash (Task 4).
- Log directory missing or unwritable: user is not deleted and sees an error (Task 2).
- Row exactly at the 30 day boundary and a row with NULL `user_id` in scrub and re-apply (Task 1, Task 2).
- A user with talks, sessions and reactions is deleted with everything, including an active session (Task 2).
- Admin sees the explanation and no delete button, and a forged request for an admin is refused (Task 2, Task 4, Task 5).

---

### Task 1: DeletionLog module and config

**Files:**
- Create: `lib/speechwave/deletion_log.ex`
- Modify: `config/dev.exs`, `config/test.exs`, `config/runtime.exs`
- Test: `test/speechwave/deletion_log_test.exs`

**Interfaces:**
- Produces (all in `Speechwave.DeletionLog`):
  - `path() :: String.t()` reads `Application.fetch_env!(:speechwave, :deletions_db_path)`
  - `record(user_id :: integer, deleted_at :: DateTime.t() \\ DateTime.utc_now()) :: :ok | {:error, term}`
  - `scrub(now :: DateTime.t() \\ DateTime.utc_now()) :: :ok | {:error, term}` nulls `user_id` where `deleted_at` is older than `now` minus 30 days
  - `logged_ids() :: [integer]` non-NULL ids, ascending
  - `deleted_ats() :: [DateTime.t()]` all rows' timestamps, ascending (used by tests and future reporting)
  - `snapshot_to(dest_path :: String.t()) :: :ok | {:error, term}` writes a consistent copy with `VACUUM INTO`

- [ ] **Step 1: Configure the path.** `:deletions_db_path` under `config :speechwave`: dev `Path.expand("../deletions_dev.db", __DIR__)`; test `priv/repo/deletions_test#{MIX_TEST_PARTITION}.db` (same pattern as the test repo); prod in `runtime.exs` from `DELETIONS_DATABASE_PATH` or, if unset, `Path.join(Path.dirname(database_path), "deletions.db")`. `*.db` is already git-ignored.

- [ ] **Step 2: Write failing tests** in `deletion_log_test.exs` (`use ExUnit.Case, async: false`; `setup` removes the file at `DeletionLog.path()` before each test so tests start empty):
  - `"record stores the id and timestamp and nothing else"`: after `record(42)`, `logged_ids() == [42]`, one `deleted_ats/0` entry, and a direct `PRAGMA table_info` query shows exactly the columns `user_id` and `deleted_at`
  - `"creates the file and table on first use"`: file absent, `record(1)` returns `:ok`
  - `"scrub nulls ids older than 30 days and keeps the row"`: `record(1, 31 days ago)`, `record(2, now)`; after `scrub()`, `logged_ids() == [2]` and `length(deleted_ats()) == 2`
  - `"scrub leaves a row just inside 30 days"`: `record(3, 29 days 23 hours ago)` survives
  - `"scrub is idempotent"`: calling twice changes nothing more
  - `"record returns an error tuple when the directory does not exist"`: temporarily `Application.put_env` a path under a missing directory (restore in `on_exit`), assert `{:error, _}`
  - `"snapshot_to writes a readable copy"`: `record(7)`, `snapshot_to(tmp_path)`, open the copy with `Exqlite.Sqlite3` and select the row; remove the copy afterwards

- [ ] **Step 3: Run** `mix test test/speechwave/deletion_log_test.exs` — expect FAIL (module undefined).

- [ ] **Step 4: Implement `Speechwave.DeletionLog`.** Every public function opens `Exqlite.Sqlite3.open(path())`, runs `PRAGMA busy_timeout = 5000`, `CREATE TABLE IF NOT EXISTS` plus `CREATE INDEX IF NOT EXISTS` on `deleted_at`, does its work with prepared statements, and closes the connection in an `after`. Timestamps are stored as `DateTime.truncate(:second) |> DateTime.to_iso8601()` so string comparison orders correctly. Include a `@moduledoc` explaining why this is a separate file (a log inside `speechwave.db` would be rolled back by a restore) and why it avoids an Ecto repo. Check `Exqlite.Sqlite3` docs (`get_docs`) for the installed version's `bind` arity.

- [ ] **Step 5: Run** the same command — expect PASS. Then `mix test` — expect the full suite green.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/deletion_log.ex config test/speechwave/deletion_log_test.exs
git commit -m "feat: add deletions.db log for deleted account ids"
```

---

### Task 2: Accounts.delete_account and reapply_recorded_deletions

**Files:**
- Modify: `lib/speechwave/accounts.ex`
- Test: `test/speechwave/accounts_delete_test.exs` (new; `use Speechwave.DataCase, async: false`; `setup` removes the file at `DeletionLog.path()`)

**Interfaces:**
- Consumes: `Speechwave.DeletionLog.record/1`, `scrub/0`, `logged_ids/0`
- Produces:
  - `Speechwave.Accounts.delete_account(user :: User.t(), typed_email :: term) :: {:ok, User.t()} | {:error, :admin | :confirmation_mismatch | :log_failed}`
  - `Speechwave.Accounts.reapply_recorded_deletions() :: non_neg_integer`

- [ ] **Step 1: Write failing tests** (build data with existing fixtures; create talks, a session and a reaction for the cascade test using the existing `Talks`/`Reactions` fixtures or contexts, whichever the other tests use):
  - `"deletes the user and cascades to talks, sessions, reactions, consents, identities and tokens"`: assert each table has no rows for that user afterwards, and a different user's rows remain
  - `"records exactly one log row with the user's id"`: `DeletionLog.logged_ids() == [user.id]`
  - `"accepts the email with surrounding whitespace"`
  - `"rejects a different case or a wrong or blank email"`: `{:error, :confirmation_mismatch}`, user still present, `logged_ids() == []`; also non-binary input (`nil`)
  - `"refuses an admin even with the right email"`: `{:error, :admin}`, nothing changed
  - `"returns :log_failed and deletes nothing when the log cannot be written"`: point `:deletions_db_path` at a missing directory (restore in `on_exit`)
  - `"scrubs old log rows while deleting"`: pre-record an id 31 days old; after a deletion it is no longer in `logged_ids/0`
  - `"deleting a user that is already gone returns {:ok, user} without raising"`: call twice with the same struct
  - `"reapply_recorded_deletions removes a user restored by hand"`: delete via `delete_account`, re-insert a user row with the same id (`Repo.insert!(%User{id: id, email: ...})` or raw SQL), call it, assert returns `1` and the user is gone
  - `"reapply returns 0 when no logged id has a user"`
  - `"reapply raises the users id sequence above the highest logged id"`: record id 500 directly, call it, insert a new user, assert its id > 500
  - `"reapply ignores NULL user_id rows"`: record then `scrub(future_now)`, reapply returns `0`

- [ ] **Step 2: Run** `mix test test/speechwave/accounts_delete_test.exs` — expect FAIL (undefined functions).

- [ ] **Step 3: Implement `delete_account/2`** in `accounts.ex`, following the order in Global Constraints. Delete with `Repo.delete_all(from u in User, where: u.id == ^user.id)` so a missing row is not an error. Ignore the `scrub/0` result except for a `Logger.warning`.

- [ ] **Step 4: Implement `reapply_recorded_deletions/0`**: delete users whose id is in `DeletionLog.logged_ids/0` and return the count, then set `sqlite_sequence` for `users` to at least the highest logged id (UPDATE where `seq` is lower; INSERT the row if none exists). Add `@doc` comments describing the restore use and the sequence reason.

- [ ] **Step 5: Run** the test file — expect PASS; then `mix test` — expect green.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/accounts.ex test/speechwave/accounts_delete_test.exs
git commit -m "feat: add delete_account and reapply_recorded_deletions"
```

---

### Task 3: Scrub at start and back up deletions.db

**Files:**
- Modify: `lib/speechwave/application.ex`, `lib/speechwave/db_backup.ex`

**Interfaces:**
- Consumes: `DeletionLog.scrub/0`, `DeletionLog.snapshot_to/1`

- [ ] **Step 1: Scrub at start.** In `Application.start/2`, before building children, call `Speechwave.DeletionLog.scrub()` and log a warning on `{:error, reason}` instead of crashing boot. No new test: it is a one-line call covered by Task 1's scrub tests (ruling: the app boots in the test run, which exercises it).

- [ ] **Step 2: Back up both files.** Refactor `DbBackup.run_backup/0` to back up two targets independently: `speechwave.db` via the existing `VACUUM INTO` to `/tmp/speechwave_backup.db` uploaded at `backup/speechwave.db`, and `deletions.db` via `DeletionLog.snapshot_to("/tmp/deletions_backup.db")` uploaded at `backup/deletions.db`. A failure in one must still let the other run, each logging its own error, each temp file removed afterwards. `upload/1` takes the object key as a second argument. No new test (ruling: `DbBackup` has no existing test harness and its upload needs real storage credentials; `snapshot_to/1` is tested in Task 1).

- [ ] **Step 3: Run** `mix test` — expect green.

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave/application.ex lib/speechwave/db_backup.ex
git commit -m "feat: scrub the deletion log on start and back it up hourly"
```

---

### Task 4: Deletion controller action and route

**Files:**
- Create: `lib/speechwave_web/controllers/user_account_controller.ex`
- Modify: `lib/speechwave_web/router.ex`
- Test: `test/speechwave_web/controllers/user_account_controller_test.exs`

**Interfaces:**
- Consumes: `Accounts.delete_account/2`, `UserAuth.disconnect_sessions/1`, `UserAuth.log_out_user/1`
- Produces: `DELETE /users/account` handled by `SpeechwaveWeb.UserAccountController.delete/2`, params `%{"account" => %{"email" => typed}}`. Success: all live connections ended, session cleared, redirect to `/` with the flash from Global Constraints. Mismatch, admin or log failure: redirect to `/users/settings` with an error flash and nothing deleted.

- [ ] **Step 1: Route.** Add `delete "/users/account", UserAccountController, :delete` in the existing scope that pipes through `[:browser, :require_authenticated_user]` (the same scope that holds the authenticated controller routes), because only a logged-in user may delete their own account and the plug supplies `current_scope`. Say which scope you used in the commit body.

- [ ] **Step 2: Write failing tests** (ConnCase, `log_in_user` helper, `async: false` with the log file removed in `setup`):
  - `"deletes the account and redirects home with the flash"`: user gone, redirected to `/`, flash set
  - `"clears the session so the old cookie no longer authenticates"`: reuse the pre-delete conn's cookie via `recycle` and request `/users/settings`; expect a redirect to the login page, no crash
  - `"broadcasts the extension disconnect for that user"`: subscribe to `"user:#{id}:disconnect"` before the request; `assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}`
  - `"wrong email leaves the account and redirects to settings with an error"`
  - `"admin cannot delete via a forged request"`: admin user, correct email, account still present
  - `"a request without a session is sent to login"` (already guaranteed by the plug; assert it)

- [ ] **Step 3: Run** `mix test test/speechwave_web/controllers/user_account_controller_test.exs` — expect FAIL.

- [ ] **Step 4: Implement the controller.** Fetch the user's session tokens before deleting (use the same token query other callers of `disconnect_sessions/1` use; grep for it), call `delete_account`, on `{:ok, _}` broadcast `SpeechwaveWeb.Endpoint.broadcast!("user:#{id}:disconnect", "disconnect", %{})`, call `disconnect_sessions(tokens)`, `put_flash(:info, ...)` and `UserAuth.log_out_user(conn)`. Match `:confirmation_mismatch`, `:admin` and `:log_failed` to distinct error messages.

- [ ] **Step 5: Run** the controller test, then `mix test` — expect green.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave_web/controllers/user_account_controller.ex lib/speechwave_web/router.ex test/speechwave_web/controllers/user_account_controller_test.exs
git commit -m "feat: add DELETE /users/account to delete the signed-in account"
```

---

### Task 5: Danger zone card and dialog on Settings

**Files:**
- Modify: `lib/speechwave_web/live/user_live/settings.ex`
- Test: `test/speechwave_web/live/user_live/settings_delete_account_test.exs`

**Interfaces:**
- Consumes: `DELETE /users/account` with `account[email]` from Task 4
- DOM ids (tests rely on them): `#danger-zone` (card), `#open-delete-dialog` (button), `#delete-account-dialog`, `#delete-account-form`, `#delete-account-email` (input), `#cancel-delete-account`, `#confirm-delete-account` (submit), `#danger-zone-admin-note` (shown instead of the button for admins)

- [ ] **Step 1: Write failing tests** (LiveViewTest, log in with the existing helper):
  - `"renders the danger zone after email preferences with the open button"`
  - `"admins see the explanation and no button"`: `#danger-zone-admin-note` present, `#open-delete-dialog` absent
  - `"the confirm button is disabled until the typed email matches exactly"`: `render_change` with the wrong text then the right text; assert the `disabled` attribute through `has_element?(view, "#confirm-delete-account[disabled]")`
  - `"typed email is compared after trimming and case-sensitively"`: padded address enables the button, upper-cased one does not
  - `"submitting a wrong email does not submit the form and leaves the account in place"`
  - `"submitting the right email triggers the form action"`: after `render_submit`, assert the form has `phx-trigger-action` set (the redirect and deletion themselves are covered in Task 4)

- [ ] **Step 2: Run** the test file — expect FAIL.

- [ ] **Step 3: Implement.** Add the card after the Email preferences section inside `Layouts.app`, with the dialog markup. Assigns: `:delete_email` (typed text), `:trigger_delete` (boolean). The form is `to_form(%{"email" => ...}, as: :account)` with `phx-change="delete_account_change"` and `phx-submit="delete_account_submit"`, `action={~p"/users/account"}`, `method="post"`, a hidden `_method` of `delete`, and `phx-trigger-action={@trigger_delete}`. `delete_account_submit` re-checks the match on the server and only then sets `trigger_delete` true. Confirm button `disabled` unless the trimmed typed text equals `current_scope.user.email`. Dialog copy per the spec: what is removed, cannot be undone, deleted data leaves backups within 30 days, then the typed-email field with Cancel and the red Delete button. How the dialog opens and closes (native `<dialog>` with `Phoenix.LiveView.JS` or a colocated hook) is your call. Include a short comment on why the form posts to a controller (the session cookie can only be changed in the plug layer).

- [ ] **Step 4: Run** the test file, then `mix test` — expect green. Then check the page visually in a browser at `/users/settings` (card style B, dialog opens, button enables on the exact email) and say in your report that you did or could not.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/live/user_live/settings.ex test/speechwave_web/live/user_live/settings_delete_account_test.exs
git commit -m "feat: add danger zone with account deletion dialog to settings"
```

---

### Task 6: Documentation in this repo

**Files:**
- Modify: `lib/speechwave_web/controllers/page_html/privacy.html.heex`, `docs/administration.md`, `docs/decisions.md`, `docs/roadmap.md`; check `lib/speechwave_web/controllers/page_html/terms.html.heex`

- [ ] **Step 1: Privacy policy.** Rewrite section 6 and update section 3 exactly as the spec's "Documentation changes" lists, including the wording that an anonymous account identifier is kept to prevent deleted accounts from being restored from backup within the 30 day window, and that afterwards only the deletion date remains. Bump "Last updated" to 2026-10-15. Check `terms.html.heex` for contradictions. Run any existing page tests.

- [ ] **Step 2: `docs/administration.md`.** Add: the restore procedure (normal restore leaves `deletions.db`; run `Speechwave.Accounts.reapply_recorded_deletions()` in the production IEx before traffic; if `deletions.db` is missing, restore it from `backup/deletions.db` first); the local-copy rule (delete downloaded production copies when done, never keep one more than 30 days); the internal retention facts (Fly snapshots daily and kept 5 days, Tigris copy overwritten hourly, soft delete off, no lifecycle rules, versioning not seen, re-check if storage setup changes); the `DELETIONS_DATABASE_PATH` default.

- [ ] **Step 3: `docs/decisions.md`.** Add a 2026-10-15 entry covering: a separate `deletions.db` with ids scrubbed to NULL after 30 days instead of an email hash or an in-database log; no grace period; 30 day public promise vs 5 day reality; admins cannot self-delete; past stats counts drop retroactively when users are deleted; ids are treated as non-personal data (Tracy's call) and the full deletion timestamp is kept.

- [ ] **Step 4: `docs/roadmap.md`.** Remove the "Account deletion and consent revocation features for GDPR compliance" item; keep "GDPR: download my data".

- [ ] **Step 5: Run** `mix test` — expect green. **Commit**

```bash
git add lib/speechwave_web/controllers/page_html docs/administration.md docs/decisions.md docs/roadmap.md
git commit -m "docs: document account deletion, restore procedure and retention"
```

---

### Task 7: Documentation in the docs repo (`../docs`)

**Files (in `/Users/tracy/projects/speechwave-live/docs`):** `dashboard.md`, `dev/explainer/data-model.md`, `dev/explainer/db-backup.md`, `dev/explainer/authentication.md`; check `troubleshooting.md` and `getting-started.md`.

- [ ] **Step 1:** In `../docs`, create branch `docs/account-deletion` from its main branch (feature branches, no worktrees). Read each page first to match its style.
- [ ] **Step 2:** Make the edits listed under "In the docs repo" in the spec. Public pages say "within 30 days" and never "5 days"; the internal retention numbers stay out of this repo.
- [ ] **Step 3:** Edit `troubleshooting.md` and `getting-started.md` only if they mention account removal.
- [ ] **Step 4:** Commit with conventional messages (`docs: ...`). Do not merge or push; report the branch name.

---

### Task 8: Verify

- [ ] Run `mix precommit`; fix anything it reports. Then `mix test` — all green.
- [ ] Walk through it in the browser as a non-admin test user: open Settings, open the dialog, confirm the button stays disabled until the exact email, delete, land on `/` with the flash, and confirm the old tab returns to login. Check the row in the dev `deletions_dev.db` has only an id and a timestamp.
