# Suspicious User Reaper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete unconfirmed users older than 15 days automatically, and record the source (`self`, `suspicious`, `inactive`) of every account deletion in the deletion log.

**Architecture:** `Speechwave.DeletionLog` (a raw-SQLite `deletions.db`, no Ecto) gains a `source` column added by a guarded `ALTER TABLE`. `Accounts.erase_user/2` becomes the one erase path, taking a source. A new `Accounts.delete_suspicious_users/0` finds eligible users and erases each with source `:suspicious`. A new GenServer, `Speechwave.Accounts.SuspiciousUserReaper`, modelled on `Speechwave.Talks.SessionReaper`, calls it once a day.

**Tech Stack:** Elixir, Phoenix 1.8, Ecto/SQLite, `Exqlite.Sqlite3` (deletion log), ExUnit.

**Spec:** `docs/specs/2026-10-22-suspicious-user-reaper-design.md`

## Global Constraints

- Branch is `feat/suspicious-user-reaper`. No git worktrees. Conventional commit messages.
- Cutoff config key: `config :speechwave, :suspicious_user_retention_days, 15`, read with `Application.get_env(:speechwave, :suspicious_user_retention_days, 15)`.
- Source values are exactly `:self`, `:suspicious`, `:inactive`, stored as the text `"self"`, `"suspicious"`, `"inactive"`. Never use `String.to_atom/1` on stored text; map explicitly.
- Existing rows get `'self'` via `ALTER TABLE deletions ADD COLUMN source TEXT NOT NULL DEFAULT 'self'`.
- "Unconfirmed" is `is_nil(confirmed_at)`, the same definition `Speechwave.Admin.Stats` uses. Admins are never deleted.
- `DeletionLog` only creates its file in `record/3`. `entries/1` and `deletions_by_source/0` must never create or modify a file.
- Reaper default sweep interval is one day (`:timer.hours(24)`); `name: nil` starts it unnamed, as in `SessionReaper`.
- Tests that touch the deletion log are `async: false` and `File.rm(DeletionLog.path())` in `setup`.
- Run `mix precommit` before the final task is considered done.

## Review Focus

- An unconfirmed **admin** older than the cutoff is not deleted (Task 2).
- A user **just inside** the cutoff (14 days) survives; one just outside (16 days) is deleted (Task 2).
- An **OAuth-registered** user (has `confirmed_at` set) of any age survives (Task 2).
- `entries/1` on an **old-schema** `deletions.db` (no `source` column) returns `:self` and leaves the file byte-identical (Task 1).
- A broken log path makes the sweep delete nobody and **not raise** (Task 2).
- A second sweep immediately after the first deletes nothing and writes nothing (Task 2).

---

### Task 1: `source` column in the deletion log, and every caller

The `record` signature changes, so the log module, its one production caller in `Accounts`, and all existing test call sites change together to keep the suite green.

**Files:**
- Modify: `lib/speechwave/deletion_log.ex`
- Modify: `lib/speechwave/accounts.ex` (`delete_account/2`, `erase_user/1`, `reapply_recorded_deletions/1`)
- Modify (existing call sites): `test/speechwave/deletion_log_test.exs`, `test/speechwave/accounts_delete_test.exs`, `test/speechwave/db_backup_test.exs`

**Interfaces:**
- Produces:
  - `DeletionLog.record(user_id :: integer, source :: :self | :suspicious | :inactive, deleted_at :: DateTime.t() \\ DateTime.utc_now()) :: :ok | {:error, term}`. Raises `ArgumentError` for any other `source`.
  - `DeletionLog.entries(log_path :: String.t()) :: [{integer, DateTime.t(), atom}]` (was pairs; still only unscrubbed rows, ascending by id).
  - `DeletionLog.deletions_by_source() :: [{DateTime.t(), atom}]`, ascending by `deleted_at`, scrubbed rows included, `[]` if the file is missing (never creates it).
  - Private `Accounts.erase_user(user, source)`; `delete_account/2` passes `:self`.

- [ ] **Step 1: Update existing tests to the new arity**
  - `DeletionLog.record(x)` becomes `DeletionLog.record(x, :self)`; `DeletionLog.record(x, dt)` becomes `DeletionLog.record(x, :self, dt)`. Sites: `db_backup_test.exs` (lines ~61, 70, 79, 98, 99), `deletion_log_test.exs` (throughout), `accounts_delete_test.exs` (lines ~136, 213, 218, and the `extra_log_with/1` helper at ~259-260).
  - `entries/1` expectations become triples: `[{11, %DateTime{}, :self}]` and `[{1, at, :self}]`.
  - The `extra_log_with/1` helper also accepts `{id, at, source}` and records it with that source.

- [ ] **Step 2: Write the new failing tests in `deletion_log_test.exs`**
  - `"record stores the source"`: `record(1, :suspicious)` then `deletions_by_source()` matches `[{%DateTime{}, :suspicious}]`.
  - `"record rejects an unknown source"`: `assert_raise ArgumentError, fn -> DeletionLog.record(1, :bogus) end`, and the log file is not created.
  - `"deletions_by_source is empty and creates nothing when the log is missing"`.
  - `"scrub keeps the source"`: record a 40-day-old `:suspicious` row, `scrub()`, `logged_ids() == []`, `deletions_by_source()` still returns `[{_, :suspicious}]`.
  - `"an old-schema log is upgraded by record and read as :self before that"`: create the file at `DeletionLog.path()` with `Exqlite.Sqlite3` using the old DDL (`CREATE TABLE deletions (user_id INTEGER, deleted_at TEXT NOT NULL)`) and one inserted row; capture `File.read!/1`; assert `entries(path)` is `[{id, %DateTime{}, :self}]` and the file bytes are unchanged; then `record(2, :suspicious)` and assert `deletions_by_source()` returns `:self` then `:suspicious`.
  - In `accounts_delete_test.exs`, under `"reapply_recorded_deletions/1 with extra log files"`: `"keeps the original source"`: build an extra log with `{id, at, :suspicious}`, reapply, and `deletions_by_source()` of the live log contains `:suspicious`.

- [ ] **Step 3: Run to verify failure**

Run: `mix test test/speechwave/deletion_log_test.exs test/speechwave/accounts_delete_test.exs test/speechwave/db_backup_test.exs`
Expected: FAIL (compile or `UndefinedFunctionError`/`FunctionClauseError` on `record/3`, `deletions_by_source/0`).

- [ ] **Step 4: Implement the log changes in `lib/speechwave/deletion_log.ex`**
  - `@sources [:self, :suspicious, :inactive]`; `record/3` raises `ArgumentError` unless `source in @sources`, stores `Atom.to_string(source)`.
  - `ensure_schema/1`: create the table with `source TEXT NOT NULL DEFAULT 'self'`; for pre-existing files, run `PRAGMA table_info(deletions)` through the module's `query/3` helper (column name is element 1 of each row) and run the `ALTER TABLE` only when `source` is absent. Keep the existing `deleted_at` index statement.
  - A private helper that, for a read-only connection, returns the select expression for the source (`"source"` when the column exists, else the literal `"'self'"`), and a private `source_atom/1` using an explicit three-clause map.
  - `entries/1` selects `user_id, deleted_at, <source expr>`; `deletions_by_source/0` mirrors `deleted_ats/0` (file-exists check, `read_only/2`) with the same source handling. Raise the existing `ArgumentError` for a non-log file exactly as today.
  - Update the moduledoc: a row holds `user_id`, `deleted_at` and `source` (why it was deleted; identifies no one).

- [ ] **Step 5: Implement the `Accounts` changes in `lib/speechwave/accounts.ex`**
  - `erase_user(user, source)` passes `source` to `DeletionLog.record/3`; `delete_account/2` calls `erase_user(user, :self)`.
  - `reapply_recorded_deletions/1` iterates `{id, deleted_at, source}` triples and calls `DeletionLog.record(id, source, deleted_at)`; `Enum.uniq_by(&elem(&1, 0))` is unchanged.

- [ ] **Step 6: Run to verify pass**

Run: `mix test test/speechwave/deletion_log_test.exs test/speechwave/accounts_delete_test.exs test/speechwave/db_backup_test.exs test/speechwave_web/controllers/user_account_controller_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave/deletion_log.ex lib/speechwave/accounts.ex test
git commit -m "feat: record the source of every deletion in the deletion log"
```

---

### Task 2: `Accounts.delete_suspicious_users/0`

**Files:**
- Modify: `lib/speechwave/accounts.ex`
- Modify: `config/config.exs` (beside `:session_timeout_hours`, line ~53)
- Test: `test/speechwave/accounts_delete_test.exs` (new `describe "delete_suspicious_users/0"`)

**Interfaces:**
- Consumes: `erase_user(user, :suspicious)` from Task 1; `DeletionLog.deletions_by_source/0`.
- Produces: `Accounts.delete_suspicious_users() :: non_neg_integer` (number actually deleted).

- [ ] **Step 1: Write the failing tests**

Use `backdate_user(user, DateTime.add(now, -N, :day))` as `stats_test.exs` does. `user_fixture/0` and `admin_user_fixture/0` are unconfirmed; `oauth_user_fixture/0` is confirmed.
  - `"deletes an unconfirmed user older than the cutoff and logs it as :suspicious"`: 16 days old; returns 1; `Repo.get(User, id)` is nil; `deletions_by_source()` matches `[{_, :suspicious}]`.
  - `"keeps an unconfirmed user inside the cutoff"`: 14 days old; returns 0; user still present.
  - `"keeps a confirmed user of any age"`: `oauth_user_fixture()` backdated 400 days; returns 0.
  - `"keeps an unconfirmed admin"`: `admin_user_fixture()` backdated 400 days; returns 0.
  - `"returns 0 and does not create the log when nothing is eligible"`: `refute File.exists?(DeletionLog.path())`.
  - `"a second sweep deletes nothing"`: two calls return `1` then `0`; the log has exactly one row.
  - `"honours :suspicious_user_retention_days"`: `Application.put_env` to 1 (restore in `on_exit`); a 2-day-old unconfirmed user is deleted.
  - `"deletes nobody and does not raise when the log cannot be written"` (`@tag :capture_log`): point `:deletions_db_path` at a missing directory as the existing `:log_failed` test does; two eligible users; returns 0; both still present.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/speechwave/accounts_delete_test.exs`
Expected: FAIL with `undefined function delete_suspicious_users/0`.

- [ ] **Step 3: Implement**
  - `config/config.exs`: `config :speechwave, :suspicious_user_retention_days, 15`.
  - `Accounts.delete_suspicious_users/0` with a `@doc` explaining what counts as suspicious here and why no confirmation or warning is needed. Query: `User` where `is_nil(confirmed_at)`, `not is_admin`, `inserted_at < ^cutoff` (now minus the configured days, truncated to seconds, as `:utc_datetime`). Erase each with `erase_user(user, :suspicious)`; count only `{:ok, _}` results. A skipped user (`{:error, :log_failed}`, already logged by `erase_user`) is retried next sweep.

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/speechwave/accounts_delete_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave/accounts.ex config/config.exs test/speechwave/accounts_delete_test.exs
git commit -m "feat: delete unconfirmed users older than the retention cutoff"
```

---

### Task 3: The reaper process, supervision, and docs

**Files:**
- Create: `lib/speechwave/accounts/suspicious_user_reaper.ex`
- Create: `test/speechwave/accounts/suspicious_user_reaper_test.exs`
- Modify: `lib/speechwave/application.ex` (add after `Speechwave.Talks.SessionReaper`)
- Modify: `docs/decisions.md` (append an entry)

**Interfaces:**
- Consumes: `Accounts.delete_suspicious_users/0` from Task 2.
- Produces: `Speechwave.Accounts.SuspiciousUserReaper` with `start_link/1` (options `:name`, default module name, `nil` for unnamed; `:sweep_interval`, default `:timer.hours(24)`), handling `:sweep` info and a `:sweep_now` call that replies `:ok` after sweeping.

- [ ] **Step 1: Write the failing tests**

Model on `test/speechwave/talks/session_reaper_test.exs`: `use Speechwave.DataCase, async: false`, `File.rm(DeletionLog.path())` in `setup`, a `start_reaper!/1` helper using `start_supervised!` with `name: nil, sweep_interval: :timer.hours(1)` and `Sandbox.allow(Speechwave.Repo, self(), pid)`.
  - `":sweep_now deletes an unconfirmed user older than the cutoff"`: user backdated 16 days; `GenServer.call(pid, :sweep_now) == :ok`; user gone.
  - `":sweep_now leaves a recent unconfirmed user"`: user backdated 1 day; still present.
  - `"processes an internal :sweep message"`: `send(pid, :sweep)`, then `_ = :sys.get_state(pid)`; old user gone.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/speechwave/accounts/suspicious_user_reaper_test.exs`
Expected: FAIL (module not available).

- [ ] **Step 3: Implement `SuspiciousUserReaper`**

Copy the structure of `lib/speechwave/talks/session_reaper.ex`. Both `handle_info(:sweep, ...)` and `handle_call(:sweep_now, ...)` go through one private `sweep/0` that calls `Accounts.delete_suspicious_users/0` and logs `"[SuspiciousUserReaper] Deleted N suspicious users"` at info level only when N > 0. Moduledoc is `@moduledoc false` with a short comment block like `SessionReaper`'s, saying what it deletes and why.

- [ ] **Step 4: Add it to the supervision tree**

In `lib/speechwave/application.ex`, add `Speechwave.Accounts.SuspiciousUserReaper` to `children` directly after `Speechwave.Talks.SessionReaper`. No config change: like `SessionReaper` it runs in tests, and the daily interval means it never fires during a run.

- [ ] **Step 5: Add the `docs/decisions.md` entry**

Heading `## 2026-10-22 — Suspicious users are deleted automatically at 15 days, and the deletion log records why`, in the style of the neighbouring entries (context, decision, alternatives, trade-offs, `Spec:` line). Content from the spec: unconfirmed accounts hold no data so there is no warning, undo or dry-run; 15 days leaves a real window to confirm after the 3-day onboarding boundary; the log's `source` column lets one file track all deletions and leaves `:inactive` reserved; the stats chart's retroactive shrinkage is a known trade-off with the stacked-bar fix as a follow-up. Per the project's memory notes, keep prose free of dash-separated phrases.

- [ ] **Step 6: Run the full suite and precommit**

Run: `mix test` then `mix precommit`
Expected: all tests pass; precommit reports no issues (fix any it raises).

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave/accounts/suspicious_user_reaper.ex lib/speechwave/application.ex test/speechwave/accounts docs/decisions.md
git commit -m "feat: sweep suspicious users daily with SuspiciousUserReaper"
```
