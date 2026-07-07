# Monotonic `confirmed_at` for the admin stats dashboard

## Problem

`docs/decisions.md` ("Super-admin stats dashboard") documents that the
"confirmed" metric in `Speechwave.Admin.Stats` is not strictly monotonic: a
magic-link-only user (no linked OAuth identity) who explicitly logs out has
their only session token deleted (`Accounts.delete_user_session_token/1`),
which is the only evidence `confirmed_users_query/0` uses to count them as
confirmed. They drop out of the confirmed count on logout and their
reconstructed confirmation date can drift forward on next login. This also
forces `Speechwave.Admin.Stats.recent_confirmation_timestamps/1` into a
two-phase reconciliation (stats.ex:270-331) to correctly attribute a user's
*true* earliest confirmation when they have both an old token and a newer
identity.

This spec adds a dedicated, monotonic `confirmed_at` timestamp on `users`,
set once at first login and never cleared, removing the volatility and the
reconciliation logic it necessitated.

## Current state

- `confirmed_users_query/0` and `unconfirmed_users_query/0` (stats.ex:237,
  253) derive confirmation from `EXISTS` checks against `users_tokens`
  (`context: "session"`) and `user_identities`.
- `Accounts.generate_user_session_token/1` (accounts.ex:320) is the single
  function that creates a session token, and is called by
  `UserAuth.log_in_user/3` for every real login path: magic link
  (`user_session_controller.ex`), OAuth (`user_session_controller.ex`), and
  the dev-only backdoor (`dev_login_controller.ex`).
- Linking an OAuth identity (`oauth_upsert/3`, accounts.ex:220) never happens
  without a session token being created in the same flow — either
  immediately after, for a first-time OAuth signup, or because the user was
  already logged in (settings "connect a provider" flow). There is no real
  path where a user has an identity but has never had a session token.
- The app uses **SQLite** via `ecto_sqlite3`/`exqlite` (bundled SQLite
  3.51.3), not Postgres. `UPDATE ... FROM` is supported (since SQLite 3.33)
  but the target table cannot be aliased in the `UPDATE` clause the way a
  Postgres query would.
- `users.confirmed_at` existed previously under `phx.gen.auth` (email
  confirmation) and was dropped in the passwordless-auth migration
  (`20260506193042_drop_password_columns_from_users.exs`). This spec reuses
  the name for a different but compatible concept: "this user has
  authenticated at least once," not "this user confirmed their email."

## Design

### Schema

New migration adds `users.confirmed_at :utc_datetime`, nullable, no default.
No index — consistent with every other column these dashboard queries filter
on (see docs/decisions.md's "every metric's SQL query is a full base-table
scan" note); cheap at current table sizes, revisit alongside that existing
follow-up if it ever isn't.

The same migration backfills existing users in raw SQL (SQLite dialect):

```sql
UPDATE users
SET confirmed_at = sub.min_ts
FROM (
  SELECT user_id, MIN(inserted_at) AS min_ts FROM (
    SELECT user_id, inserted_at FROM users_tokens WHERE context = 'session'
    UNION ALL
    SELECT user_id, inserted_at FROM user_identities
  )
  GROUP BY user_id
) AS sub
WHERE users.id = sub.user_id;
```

Users with neither a session token nor an identity row keep `confirmed_at =
NULL` — correct, since they're currently counted unconfirmed too. Verified
directly against the bundled SQLite version (3.51.3) with seeded rows before
including it here.

### Write point

`Accounts.generate_user_session_token/1` gets the only write, guarded so it
sets the timestamp at most once and is safe under concurrent logins, with an
in-memory short-circuit to skip the extra statement entirely for the common
case of an already-confirmed returning user:

```elixir
def generate_user_session_token(user) do
  {token, user_token} = UserToken.build_session_token(user)
  Repo.insert!(user_token)

  if is_nil(user.confirmed_at) do
    Repo.update_all(
      from(u in User, where: u.id == ^user.id and is_nil(u.confirmed_at)),
      set: [confirmed_at: DateTime.utc_now(:second)]
    )
  end

  token
end
```

The in-memory check is safe even against a stale `user` struct: `confirmed_at`
only ever transitions `nil -> timestamp`, once, and nothing in this design
(or anywhere else in the app) ever clears it back to `nil`. A stale non-nil
value is therefore always still valid; a stale nil value still falls through
to the guarded `update_all`, which is race-safe on its own.

No changes are needed at `oauth_upsert/3` or `link_identity_to_user/2` — see
Current State above.

### `Speechwave.Admin.Stats` simplification

```elixir
defp confirmed_users_query do
  from u in User, where: not is_nil(u.confirmed_at)
end

defp unconfirmed_users_query do
  from u in User, where: is_nil(u.confirmed_at)
end

defp recent_confirmation_timestamps(cutoff) do
  Repo.all(
    from u in User, where: u.confirmed_at >= ^cutoff, select: {u.id, u.confirmed_at}
  )
  |> Map.new()
end
```

This replaces the ~45-line two-phase reconciliation currently at
stats.ex:270-331 (`recent_confirmation_timestamps/1`'s candidate-gathering
and true-earliest-timestamp phases), which existed only to correctly
attribute confirmation when it could come from either of two independent,
mutable signals. `recent_confirmers/1` and `age_split_history/3` are
unchanged; they already just consume this map's `%{user_id => timestamp}`
shape.

**Docs to update:**
- Remove the moduledoc paragraph at stats.ex:21-27 calling out "confirmed"
  as the one non-monotonic exception.
- Replace the "Confirmed is not strictly monotonic" bullet in
  `docs/decisions.md` with a short dated note that it was fixed by adding
  `users.confirmed_at`.

### Test impact

`session_token_fixture/2` (test/support/fixtures/accounts_fixtures.ex:116)
currently builds and inserts a `UserToken` directly, bypassing
`generate_user_session_token/1`, so it must also set `confirmed_at` itself to
keep simulating real behavior:

```elixir
def session_token_fixture(user, inserted_at \\ nil) do
  {token, user_token} = Accounts.UserToken.build_session_token(user)
  user_token = Speechwave.Repo.insert!(user_token)
  confirmed_at = inserted_at || DateTime.utc_now() |> DateTime.truncate(:second)

  Speechwave.Repo.update_all(
    from(u in Accounts.User, where: u.id == ^user.id and is_nil(u.confirmed_at)),
    set: [confirmed_at: confirmed_at]
  )

  if inserted_at, do: backdate_token(user_token.id, inserted_at)

  {token, user_token}
end
```

Call sites in `stats_test.exs` that currently call `session_token_fixture(user)`
then separately `backdate_token(user_token.id, ts)` collapse to
`session_token_fixture(user, ts)`, which the fixture already supports.

`identity_fixture/2` is **not** changed — see Current State above for why
identity-only confirmation isn't a real production state. The test at
stats_test.exs:18-19 (`confirmed_via_identity = user_fixture();
identity_fixture(confirmed_via_identity)`) is updated to pair
`identity_fixture` with `session_token_fixture`, matching an actual
first-time OAuth signup.

The test at stats_test.exs:63-86 ("a user confirmed via an old token isn't
misreported as recently confirmed via a newer identity") is **deleted**, not
adapted — it exists solely to pin down the two-phase reconciliation logic
being removed, and the scenario it guards against (two independent timestamps
needing reconciliation) can't occur once there's a single `confirmed_at`
column.

New coverage: an `Accounts` test asserting `generate_user_session_token/1`
sets `confirmed_at` on a user's first token and leaves the original
timestamp unchanged on a second login for the same user.

### Production backfill verification

Because the backfill runs once against real, irreplaceable production data —
the one part of this change an ExUnit test genuinely can't cover, since the
test suite migrates an empty database — `Speechwave.Release.migrate/0`
(lib/speechwave/release.ex:8), which is what the production deploy already
calls to run migrations, gets a verification step appended that fails the
deploy if any user with a session token or identity was left unconfirmed:

```elixir
def migrate do
  load_app()

  for repo <- repos() do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  verify_confirmed_at_backfill()
end

defp verify_confirmed_at_backfill do
  {:ok, {:ok, %{rows: [[count]]}}, _} =
    Ecto.Migrator.with_repo(Speechwave.Repo, fn repo ->
      Ecto.Adapters.SQL.query(repo, """
      SELECT COUNT(*) FROM users u
      WHERE u.confirmed_at IS NULL
        AND (EXISTS (SELECT 1 FROM users_tokens t WHERE t.user_id = u.id AND t.context = 'session')
          OR EXISTS (SELECT 1 FROM user_identities i WHERE i.user_id = u.id))
      """, [])
    end)

  if count != 0 do
    raise "confirmed_at backfill left #{count} users unconfirmed despite having a session token or identity"
  end
end
```

This is a one-off check tied to this migration's rollout, not a standing
pattern applied to every future migration.

## Alternatives considered

- **Soft-delete session tokens** (add `revoked_at`, stop hard-deleting on
  logout, redefine "confirmed" as "any token row ever existed"). Rejected:
  keeps the token table as the source of truth but requires changing
  semantics on the security-critical logout path
  (`SpeechwaveWeb.UserAuth.log_out_user`) for the same outcome a single
  additive column achieves without touching it.
- **Leave the data model alone, rename the metric** to something like
  "currently active accounts." Rejected: cheapest option, but doesn't fix the
  variance the user flagged — it only documents it more precisely.

## Out of scope

- No index on `confirmed_at` — see Schema section.
- No change to how `unconfirmed`/`onboarding`/`suspicious` are split by age;
  that logic is unaffected by this change beyond consuming the new,
  simpler `recent_confirmation_timestamps/1`.
