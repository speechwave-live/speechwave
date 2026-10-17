# Administration Handbook

## Database migrations

Migrations run automatically at app startup in production. When you deploy,
the new app machine runs all pending migrations before serving traffic.

In development, run migrations manually after pulling new changes:

```sh
mix ecto.migrate
```

To check which migrations have and haven't run:

```sh
mix ecto.migrations
```

## How to send a user a fresh login link

Speechwave auth is passwordless (magic link or OAuth) — there is no password
to reset. If a user is stuck (e.g. their magic-link email never arrived),
connect to the running production node via a remote IEx console:

```sh
fly ssh console --app speechwave --pty -C "/app/bin/speechwave remote"
```

Then in IEx:

```elixir
user = Speechwave.Accounts.get_user_by_email("user@example.com")
url_fun = fn token -> "https://speechwave.live/users/magic_link/#{token}" end
Speechwave.Accounts.deliver_login_instructions(user, url_fun)
```

This calls the same `deliver_login_instructions/2` the app itself uses on
every login attempt — it sends the user a real email with a fresh one-time
login link. `url_fun` is built manually here (rather than using the `~p`
verified-routes sigil) since there's no router/endpoint context available in
a bare remote console. There's no session or password to invalidate in this
model — a successful send just gives the user a new way in.

## How to perform a manual backup

The `DbBackup` GenServer runs automatically every hour. To trigger an immediate backup, connect to the IEx console (see above) and call:

```elixir
Speechwave.DbBackup.run_now()
```

This uses `VACUUM INTO` to produce a consistent snapshot of the live database, then uploads it to Tigris at `backup/speechwave.db` in the configured bucket. The deletion log (`deletions.db`, see below) is backed up the same way, to `backup/deletions.db`. Check the application logs to confirm it succeeded:

```sh
fly logs --app speechwave | grep DbBackup
```

## How to download a copy of the database for analysis

The latest backup lives in Tigris object storage. Retrieve the storage credentials from fly secrets:

```sh
fly secrets list --app speechwave
```

The secret names are `STORAGE_URL`, `STORAGE_BUCKET`, `STORAGE_ACCESS_KEY_ID`, and `STORAGE_SECRET_ACCESS_KEY`. Use the AWS CLI to download:

```sh
aws s3 cp s3://$STORAGE_BUCKET/backup/speechwave.db ./speechwave.db \
  --endpoint-url "$STORAGE_URL" \
  --region auto
```

Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in your environment from the fly secrets values before running. The resulting `speechwave.db` is a standard SQLite file you can open with any SQLite client (e.g. `sqlite3 speechwave.db` or [DB Browser for SQLite](https://sqlitebrowser.org/)).

**Delete analysis copies when you are done, and never keep one longer than 30 days.** A downloaded database holds data that users may since have deleted. The privacy policy promises deleted data is gone from backups within 30 days, and that promise does not cover copies on a laptop.

## Deleted accounts and restoring from a backup

Users delete their own accounts from Settings. The user row goes (talks, sessions, reactions, consents, identities and tokens go with it through the foreign keys) and the user's id is written to a separate SQLite file, `deletions.db`, next to `speechwave.db` on the volume (`DELETIONS_DATABASE_PATH` overrides the location; by default it sits beside `DATABASE_PATH`). The file holds only an id and a deletion time. Ids older than 30 days are set to NULL at each deploy, at each deletion and before each hourly backup, leaving only the time. The file is created by the first recorded deletion.

The log is separate because a restore of `speechwave.db` would otherwise roll the log back with it. A normal restore does not touch `deletions.db`.

**After any restore of `speechwave.db`, before the app takes traffic**, connect to the IEx console and run:

```elixir
Speechwave.Accounts.reapply_recorded_deletions()
```

It deletes again every user whose id is in the log, returns how many it removed, and raises the `users` id sequence to at least the highest logged id. A restore rolls the sequence back, and without this a new signup could be given an id that is in the log and be deleted by a later re-apply. If it logs a warning that no deletion log was found, the file is missing: see below.

**Restoring a whole Fly volume snapshot** also rolls `deletions.db` back, so deletions made since the snapshot are missing from it. Do this instead:

1. Before restoring, download `backup/deletions.db` from Tigris to a scratch file (same `aws s3 cp` recipe as above). Do it first: once the restored volume boots, the hourly backup can overwrite the Tigris copy with the older log within 5 minutes.
2. Restore the snapshot and start the app.
3. Run `Speechwave.Accounts.reapply_recorded_deletions(["/path/to/downloaded-deletions.db"])`. Ids from the downloaded file are applied too and also recorded in the live log. A path that does not exist raises.

**If `deletions.db` is lost** (volume replaced, file deleted), the app does not create an empty one: only recording a deletion creates the file, and the backup skips `deletions.db` while the file is missing, so the good copy in Tigris is not overwritten. Download `backup/deletions.db` into place before the first new deletion, or pass it to `reapply_recorded_deletions/1` as above. The first deletion after the loss creates a fresh, nearly empty log, and the next hourly backup would then overwrite Tigris with it, so do the restore before anyone deletes an account.

Accounts deleted since the backup you restored are the ones this protects. The log has no email or hash by design, so it cannot tell you who was deleted.

### Retention facts (internal; the public pages say "within 30 days")

As of 2026-10-15:

- Fly volume snapshots are daily and expire after 5 days (Fly dashboard setting). They cover the whole volume, including `deletions.db`.
- The Tigris copy is overwritten every hour at a fixed key. The bucket has soft delete off and no lifecycle rules, and no versioning has been seen.

So deleted data leaves every backup in about 5 days. The public promise is 30 days on purpose, to leave room to change retention. Re-check these facts if the storage setup changes, and keep the public wording true.
