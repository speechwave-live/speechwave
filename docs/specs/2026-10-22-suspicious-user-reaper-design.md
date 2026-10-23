# Automatic deletion of suspicious users

## Why

A "suspicious" user is an unconfirmed user whose account is 3 days old or
more (see `docs/specs/2026-07-06-super-admin-stats-design.md`). Unconfirmed
means `confirmed_at` is nil: the person never completed the magic link or
OAuth sign-in. They never had a login session, so they cannot have created
talks, sessions or reactions. There is nothing to lose by deleting them, and
if the address was real the person can sign up again and land exactly where
they were.

Today these accounts pile up forever. This adds a periodic job that deletes
them, and extends the deletion log so it records every account deletion and
why it happened.

Out of scope:

- Deleting inactive confirmed users. The `:inactive` source value is
  reserved in the log so that feature needs no further schema change.
- Warning emails, undo, or a dry-run mode. Unconfirmed accounts hold no data.
- Changes to the admin stats page (see "Follow-up" below).

## What it does

A GenServer, `Speechwave.Accounts.SuspiciousUserReaper`, sweeps once a day.
Each sweep deletes every user who is:

- unconfirmed (`confirmed_at` is nil), and
- older than `:suspicious_user_retention_days` (config, default 15), and
- not an admin.

The retention is longer than the 3-day onboarding boundary on purpose. A
magic-link email can sit unread over a weekend, and 15 days leaves the user
a real chance to confirm before the account goes.

Each sweep logs how many accounts it deleted, at info level, only when the
count is above zero.

### Structure

The reaper follows `Speechwave.Talks.SessionReaper`: `start_link/1` with an
optional `:name`, a configurable `:sweep_interval` (default one day), a
`:sweep` info message that reschedules itself, and a synchronous
`:sweep_now` call for tests. It is added to the supervision tree next to
`SessionReaper` in `lib/speechwave/application.ex`.

The sweep calls a new `Accounts.delete_suspicious_users/0`, which finds the
users and deletes each through the shared erase path below. It returns the
number deleted. A failure to log one user's deletion skips that user (the
existing `:log_failed` behaviour) and does not stop the rest of the sweep;
the skipped user is picked up on the next sweep.

### Shared erase path

`erase_user/1` in `lib/speechwave/accounts.ex` becomes `erase_user(user, source)`.

- `delete_account/2` keeps its admin and typed-email checks, then calls
  `erase_user(user, :self)`.
- `delete_suspicious_users/0` calls `erase_user(user, :suspicious)` and
  skips the typed-email check, which only makes sense for a person
  confirming their own deletion.

The rest of `erase_user` is unchanged: log first, then delete, so a failure
errs toward erasure.

## The deletion log gets a source column

`Speechwave.DeletionLog` records why each account was deleted, so the log
tracks all deletions and not only self-service ones.

### Schema

`ensure_schema/1` creates new tables with the column included. For existing
files it checks `PRAGMA table_info(deletions)` and, if `source` is missing,
runs:

    ALTER TABLE deletions ADD COLUMN source TEXT NOT NULL DEFAULT 'self'

SQLite has no `ADD COLUMN IF NOT EXISTS`, hence the check. The default is
correct for every existing row, because every row so far came from a user
deleting their own account. A `deletions.db` restored from a backup that
predates this change is upgraded the next time it is opened for writing.

There is still no Ecto migration; the module's "nothing to set up at deploy
time" property is kept.

### API

- `record(user_id, source, deleted_at \\ DateTime.utc_now())`, where `source`
  is one of `:self`, `:suspicious`, `:inactive`. It is a required argument so
  a future caller cannot forget to say why. Any other value raises
  `ArgumentError`. Stored as text (`"self"`, `"suspicious"`, `"inactive"`).
- `entries/1` returns `{user_id, deleted_at, source}` triples. It opens files
  read-only and must not alter them, so for a file without the `source`
  column it selects `'self'` as a literal instead of the column.
- `reapply_recorded_deletions/1` in `Accounts` passes each entry's source
  through to `record/3`, so a replay from an extra log keeps the original
  reason. Its two existing call sites are updated for the new arity.
- `deleted_ats/0` is unchanged. A new `deletions_by_source/0` returns
  `{deleted_at, source}` pairs (scrubbed rows included) for reporting.

### Scrubbing

Unchanged. After 30 days `scrub/1` sets `user_id` to NULL and keeps the row,
so `deleted_at` and `source` stay available for reporting indefinitely. The
moduledoc currently says a row holds "only `user_id` and `deleted_at`"; it is
updated to include `source`, which identifies no one.

### Restores

After a restore from backup, `reapply_recorded_deletions` also replays
suspicious deletions. That is harmless: those accounts hold no data and
would be deleted again by the next sweep anyway.

## Config

In `config/config.exs`, beside `:session_timeout_hours`:

    config :speechwave, :suspicious_user_retention_days, 15

The sweep interval is an option to the reaper, not application config, as
with `SessionReaper`. No `config/test.exs` change is needed. Like
`SessionReaper`, the reaper is an unconditional child in the supervision
tree, so it also runs under `mix test`, but its daily interval means the
supervised instance never fires during a test run. Tests start their own
instance with `start_supervised!/1`, passing `name: nil` to avoid clashing
with the supervised one and a long `sweep_interval`, and call `:sweep_now`
(see `test/speechwave/talks/session_reaper_test.exs`).

## Testing

`test/speechwave/accounts_delete_test.exs` and
`test/speechwave/deletion_log_test.exs` gain, and a new
`test/speechwave/accounts/suspicious_user_reaper_test.exs` holds:

- Deletes an unconfirmed user older than the cutoff; keeps one younger.
- Keeps a confirmed user of any age, and an unconfirmed admin.
- The deletion is recorded in the log with source `suspicious`; a
  self-service deletion is recorded with source `self`.
- A sweep with nothing to delete returns 0 and writes nothing to the log.
- A log failure for one user does not stop the others.
- `DeletionLog`: a fresh file has the `source` column; a file created with
  the old schema gains it with existing rows reading `self`; `record/3`
  rejects an unknown source; `entries/1` reads an old-schema file without
  modifying it; scrubbing keeps `source`.
- `reapply_recorded_deletions` preserves the source from an extra log.
- The reaper process: `:sweep_now` on a test-started instance
  (`name: nil`) runs a sweep and replies `:ok`.

Run `mix precommit` when done.

## Docs

- Update the `DeletionLog` moduledoc as described above.
- Add an entry to `docs/decisions.md`: suspicious users are deleted at 15
  days with no warning, because unconfirmed accounts hold no data; the
  deletion log records the source of every deletion.

## Follow-up (separate change)

The admin stats chart for suspicious users is rebuilt from the current
`users` table, so once the reaper runs, deleted users vanish from past days
and the trend shrinks retroactively. The planned fix is to make it a stacked
bar chart: historical suspicious deletions (from
`DeletionLog.deletions_by_source/0`, source `suspicious`) stacked with the
current undeleted suspicious users. `deletions_by_source/0` exists in this
change so that work needs no further log changes.
