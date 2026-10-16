# Self-service account deletion

## Why

GDPR gives people the right to have their personal data erased. Today the
privacy policy (section 6) says to email admin@speechwave.live and promises
action within 30 days. Tracy wants deletion available to users directly on
`/users/settings`, so that it is immediate and does not depend on anyone
reading an inbox.

Consent revocation, the other half of the original roadmap item, already
exists: the Unsubscribe button in Settings calls `Accounts.revoke_consent/2`.
Nothing else is needed for it. Data access and portability (a "download my
data" export) is a separate roadmap item and out of scope here.

## What it does

A "Danger zone" card sits at the bottom of `/users/settings`, after the Email
preferences section. It describes what deletion removes and has a
"Delete my account…" button that opens a confirmation dialog. In the dialog
the user types their account email exactly; the red "Delete my account"
button stays disabled until the typed text matches. Pressing it deletes the
account immediately and permanently, logs the user out, and sends them to the
home page with a short flash message confirming the deletion.

There is no grace period and no undo. Holding the data of someone who asked
for erasure would defeat the purpose of the right.

### What is deleted

Everything that belongs to the user, via the existing
`on_delete: :delete_all` foreign keys: the `users` row, talks, talk sessions,
reactions, consent records (`user_consents`), linked sign-in providers
(`user_identities`) and login/session tokens (`users_tokens`). No other table
references a user. Deleting the `users` row is therefore sufficient.

### The deleted-id log (decided with Tracy: a separate database file)

A log of deleted user ids lets deletions be re-applied if `speechwave.db` is
ever restored from a backup (a restore would otherwise bring deleted people
back). It stores only:

- `user_id` (nullable integer, the deleted user's id; cleared to NULL when the
  row ages out, see Scrubbing)
- `deleted_at` (`utc_datetime`)

It never stores an email, a hash of an email, or anything else about the
person. An email hash is still personal data under GDPR (anyone holding it can
hash a known address and check for it), while an id is meaningless without a
database that contains that id. Tracy's view, which this design adopts: the ids
are not personal data, so they may stay longer than 30 days. `users.id` is
`INTEGER PRIMARY KEY AUTOINCREMENT`, so ids are never reused after a deletion.

**Where it lives:** its own SQLite file, `deletions.db`, in the same directory
as `speechwave.db` on the mounted volume. A log kept inside `speechwave.db`
would be rolled back by a restore along with everything else and could not do
its job. Because the file is separate, a normal restore of `speechwave.db`
leaves `deletions.db` untouched. The log is only restored from a backup if the
live `deletions.db` is missing or corrupt.

**Scrubbing (Tracy's idea):** rows are never deleted. When a row is older than
30 days its `user_id` is set to NULL, leaving only `deleted_at`. That keeps
the frequency and timing of account deletions available for reporting with
nothing that identifies an account. Scrubbing is lazy: it runs at application
start (each deploy) and inside every deletion, with no scheduler, so an id may
stay for longer than 30 days between deploys or deletions; that is accepted.
`deleted_at` keeps its full timestamp (author's call; rounding to the day is
the alternative). Rows with a NULL `user_id` are ignored by re-apply and by
the sequence raise below, which is safe because they are older than every
backup.

**Ordering and failure:** the two databases cannot share a transaction. On
deletion, write the log row first, then delete the user (the user delete and
its cascades are one transaction in `speechwave.db`). If the user delete
fails, a logged id may belong to a user who still exists; that fails toward
erasure and is accepted. If the log write fails, the deletion does not
proceed and the user sees an error.

### Backups

Deleted data remains in backups until they expire:

- Fly volume snapshots are daily and expire after 5 days (configured in the
  Fly dashboard; confirmed by Tracy on 2026-10-15). They cover the whole
  volume, including `deletions.db`.
- `Speechwave.DbBackup` uploads an hourly snapshot to Tigris at the fixed key
  `backup/speechwave.db`, overwriting the previous one. The bucket has soft
  delete off, no lifecycle rules, and (as far as Tracy can see) no versioning.
  **Change:** `DbBackup` also uploads a `VACUUM INTO` snapshot of
  `deletions.db` hourly at `backup/deletions.db` (author's call), so losing the
  whole volume costs at most an hour of log entries.

So deleted data leaves all backups in about 5 days. Public pages (the privacy
policy and the docs site) promise **30 days**, not 5, deliberately: the policy
should state what Tracy is willing to be held to, with room to change
retention later. The real numbers (5 days, overwrite behavior) belong only in
internal docs (`docs/administration.md`, `docs/decisions.md`).

**Local copies break the promise.** `docs/administration.md` tells the
operator to download the production database for analysis, and those copies
never expire. Add a rule there: delete analysis copies when finished and never
keep one longer than 30 days (author's call).

### Restore procedure

Normal restore of `speechwave.db` from a backup: `deletions.db` stays as it is.
Before the app accepts traffic, call
`Speechwave.Accounts.reapply_recorded_deletions/0` from the production IEx
console. It deletes every user whose id is in the log and returns the number
removed. If `deletions.db` itself is missing or corrupt, first restore it from
`backup/deletions.db` (or the latest Fly snapshot), then re-apply.

`reapply_recorded_deletions/0` also raises the `users` `sqlite_sequence` value
to at least the highest logged id (author's call). After a restore the sequence
rolls back to its snapshot value, and without this a new signup could be given
an id that appears in the log and be deleted by a later re-apply. With it, ids
stay unique across restores. Document in `docs/administration.md` that
re-applying happens immediately after the restore, before traffic.

## Goals, non-goals, anti-goals

- Goal: a user can fully delete their account in under a minute, with no
  support contact.
- Goal: deletions survive a backup restore without keeping any personal data.
- Non-goal: a data export (separate roadmap item), a grace period, an email
  confirming the deletion, revoking tokens at OAuth providers (Speechwave
  holds none), purging historical backups on demand.
- Anti-goal: accidental deletion. The typed-email confirmation is the safety
  net, and it must be enforced on the server, not only by disabling the button.
- Anti-goal: any identifying data left behind by the log.

## Behavior details decided

- **Typed confirmation:** compared against the user's current email,
  case-sensitive, after trimming surrounding whitespace. Enforced in the
  context function, which returns `{:error, :confirmation_mismatch}` without
  touching data when it does not match.
- **Admins:** a user with `is_admin: true` cannot delete their own account
  from this page, so the only admin cannot lock themselves out of `/admin`.
  The context function returns `{:error, :admin}`; the card tells admins why
  instead of showing the button. (Author's call.)
- **Live connections:** deletion must end the user's live connections: the
  Chrome extension channel (existing `user:#{id}:disconnect` broadcast, as used
  by API key regeneration) and the user's LiveView sessions
  (`SpeechwaveWeb.UserAuth.disconnect_sessions/1`). A presenter in the middle
  of a talk simply loses the connection; no special handling.
- **Session cookie:** after deletion the browser's session must be cleared and
  the user lands on `/` logged out with the flash "Your account and its data
  have been deleted." A stale cookie alone must not cause errors (the existing
  session lookup already treats a missing token as logged out).
- **Statistics:** the admin stats history is reconstructed from current rows,
  so deleting users lowers past counts retroactively. Record this as an
  accepted limitation in `docs/decisions.md` next to the existing reporting
  limitations.

## Styling (decided with the mockups)

The Danger zone card uses the tinted style: pale red fill, a 5px red left
accent bar, red heading with a warning mark, short description, and a solid red
"Delete my account…" button. Per `docs/decisions.md` (2026-10-15) the app is
light-only. The dialog states what is removed, that it cannot be undone, that
deleted data leaves backups within 30 days, then the typed-email field with
Cancel and the red Delete button (disabled until the text matches). There is
no existing modal component in `core_components.ex`; the builder chooses how to
build one (native `<dialog>` with `Phoenix.LiveView.JS`, or a colocated hook).

## Constraints

- Follow `CLAUDE.md`: unique DOM ids on the card, dialog, input and buttons;
  `to_form` for the confirmation form; no inline `<script>` outside colocated
  hooks; conventional commits; `mix precommit` before finishing.
- New code in the `Speechwave.Accounts` context; the Settings LiveView only
  calls it.
- `deletions.db` sits beside `speechwave.db` in dev, test and production, with
  its path configured next to the main database path. Its table (name left to
  the builder) has `user_id` and `deleted_at` and an index on `deleted_at`. No
  foreign key to anything. It is created automatically at start if absent, and
  production deploys must create it without manual steps. Whether this is a
  second Ecto repo or a small module on `exqlite` is the builder's choice; the
  simpler one wins. Tests must not touch the real file and must stay async-safe
  where the rest of the suite is.

## Interfaces the plan should pin down

- `Speechwave.Accounts.delete_account(user, typed_email)` returns
  `{:ok, user}` or `{:error, :confirmation_mismatch | :admin | :log_failed}`. It
  checks the confirmation and admin rules, writes the log row, scrubs log
  rows older than 30 days (sets `user_id` to NULL), then deletes the user.
- `Speechwave.Accounts.reapply_recorded_deletions/0` returns an integer count
  and raises the `users` sequence as described above.
- A function run at application start that scrubs old log rows.
- `Speechwave.DbBackup` backs up both databases.

## Documentation changes

In this repo:

- `lib/speechwave_web/controllers/page_html/privacy.html.heex`: rewrite
  section 6 (Data Deletion) to say users can delete their account themselves
  from Settings, that the account and all associated data are removed
  immediately, that deleted data is removed from backups within 30 days, and
  that an anonymous account identifier is kept to prevent deleted accounts
  from being restored from backup within the 30 day window (never worded as
  deletions being "re-applied", which could read as the account being
  restorable), and that after 30 days only the date of the deletion remains,
  with no identifier. Keep the email route for people who cannot sign in. Update section 3 to mention
  backups. Bump "Last updated". Check `terms.html.heex` for anything
  contradicting this.
- `docs/administration.md`: add the restore procedure (including the ordering
  note and the `deletions.db` cases), the local-copy rule, and the internal
  retention facts (Fly 5 days, Tigris overwrite, soft delete off, no lifecycle
  rules, versioning not seen) with a note to re-check them if the storage setup
  changes.
- `docs/decisions.md`: a 2026-10-15 entry for this decision (separate
  `deletions.db` instead of an email hash or an in-database log, no grace
  period, 30-day public promise vs 5-day reality, admins cannot self-delete,
  stats history effect).
- `docs/roadmap.md`: remove the "Account deletion and consent revocation
  features for GDPR compliance" item when this ships. The separate "download my
  data" item stays.

In the docs repo (`../docs`, a separate Jekyll repo; use its own branch and
commits):

- `dashboard.md`: add a short "Delete your account" section after the Account
  Settings material, describing what is removed, the typed-email confirmation,
  and that it cannot be undone.
- `dev/explainer/data-model.md`: document the deletion cascade and the
  deleted-id log.
- `dev/explainer/db-backup.md`: explain how deleted data ages out of backups,
  the second database file, and the restore re-apply step (link to the
  administration doc's procedure if the docs site cannot link to this repo's
  `docs/` folder).
- `dev/explainer/authentication.md`: one note that deleting an account ends
  all sessions and sign-ins and what happens to linked providers.
- Check `troubleshooting.md` and `getting-started.md`; edit only if they
  mention account removal.

Writing style for all user-facing prose: no dash-separated phrases, no
filler. Public pages say "within 30 days", never "5 days".

## Tests

- Context: deleting removes the user and cascades to talks, sessions,
  reactions, consents, identities and tokens; records exactly one log row with
  that id and a `deleted_at`; wrong or blank typed email returns
  `:confirmation_mismatch` and changes nothing; an admin returns `:admin` and
  changes nothing; if the log write fails the user is not deleted; log rows
  older than 30 days have `user_id` set to NULL on deletion (the row and its
  `deleted_at` remain) and newer ones are untouched.
- The start-up scrub clears only rows older than 30 days and deletes nothing.
- `reapply_recorded_deletions/0`: restoring a deleted user's row by hand and
  calling it removes the user again and returns the count; it removes nothing
  for ids with no matching user; afterwards the next inserted user gets an id
  higher than every logged id.
- `DbBackup` includes `deletions.db` in what it uploads (follow how the
  existing backup test stubs storage).
- LiveView: the Danger zone card and dialog render with their ids; the Delete
  button is disabled until the typed email matches; submitting a wrong email
  leaves the account in place with an error; a correct email deletes the
  account and ends on `/` with the flash; admins see the explanation instead of
  the button.
- Session: after deletion the old session cookie no longer authenticates, and
  a request with it does not crash.
- Live connections: deleting broadcasts the extension disconnect for that user.

## Left to the builder

The dialog implementation, the exact flash and card copy within the facts
above, how the redirect clears the session (a small controller action is the
likely route since the session lives in the plug layer), the log table's
module name, and whether `deletions.db` is a second Ecto repo or a thin
`exqlite` module.
