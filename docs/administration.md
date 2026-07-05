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

This uses `VACUUM INTO` to produce a consistent snapshot of the live database, then uploads it to Tigris at `backup/speechwave.db` in the configured bucket. Check the application logs to confirm it succeeded:

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

