# Monotonic `confirmed_at` Column Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the volatile, token/identity-derived "confirmed" signal in `Speechwave.Admin.Stats` with a dedicated `users.confirmed_at` timestamp that is set once at first login and never cleared, eliminating the logout-driven count drop documented in `docs/decisions.md`.

**Architecture:** A new migration adds a nullable `confirmed_at :utc_datetime` column to `users` and backfills existing rows from their earliest session-token/identity timestamp. `Accounts.generate_user_session_token/1` — the single function every real login path funnels through — sets it once, guarded against races. `Speechwave.Admin.Stats` swaps its `EXISTS`-based queries and two-phase reconciliation for direct `confirmed_at` filters. See `docs/specs/2026-07-06-confirmed-at-column-design.md` for full rationale.

**Tech Stack:** Phoenix, Ecto (SQLite via `ecto_sqlite3`/`exqlite`, bundled SQLite 3.51.3), ExUnit.

## Global Constraints

- The app uses **SQLite**, not Postgres. Raw SQL must use SQLite's `UPDATE ... FROM` syntax, and the target table in an `UPDATE` clause cannot be aliased the way Postgres allows.
- `confirmed_at` transitions `nil -> timestamp` exactly once and is never cleared by any code path. Every check against it (in-memory or SQL) can rely on that monotonicity.
- Per the spec, the migration's backfill gets **manual** verification (running it against real data), not an automated ExUnit test — the test suite migrates an empty database, so there's nothing to backfill in-test. The one exception is the deploy-time verification query itself (Task 4), which is pure query logic and is unit-tested directly.
- Follow `CLAUDE.md`: this is a backend-only change, no LiveView/HEEx touched. Run `mix precommit` after the final task and fix anything it flags.
- Every existing test file this plan touches must still pass in full after each task, not just the tests added in that task.

---

### Task 1: `confirmed_at` migration + backfill

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_confirmed_at_to_users.exs`

**Interfaces:**
- Produces: `users.confirmed_at` column (`:utc_datetime`, nullable), available to every later task.

- [ ] **Step 1: Generate the migration file**

Run: `mix ecto.gen.migration add_confirmed_at_to_users`

This creates `priv/repo/migrations/<timestamp>_add_confirmed_at_to_users.exs` with an empty `change/0`. Note the generated filename — you'll edit this file next.

- [ ] **Step 2: Write the migration**

Replace the generated file's contents with:

```elixir
defmodule Speechwave.Repo.Migrations.AddConfirmedAtToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :confirmed_at, :utc_datetime
    end

    execute("""
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
    WHERE users.id = sub.user_id
    """)
  end

  def down do
    alter table(:users) do
      remove :confirmed_at
    end
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: the migration listed as applied, no errors.

- [ ] **Step 4: Manually verify the backfill against dev data**

Do not run `mix ecto.reset` here — it would wipe your dev data before you can check it. Instead, with `speechwave_dev.db` (path from `config/dev.exs:5`) already migrated by Step 3, query it directly:

```
sqlite3 speechwave_dev.db "SELECT u.id, u.confirmed_at, (SELECT MIN(inserted_at) FROM users_tokens WHERE user_id = u.id AND context = 'session') AS min_token, (SELECT MIN(inserted_at) FROM user_identities WHERE user_id = u.id) AS min_identity FROM users u LIMIT 20;"
```

Expected: for every row, `confirmed_at` equals whichever of `min_token`/`min_identity` is earlier (or is empty when both are empty).

- [ ] **Step 5: Run the full test suite**

Run: `mix test`
Expected: PASS — nothing reads or writes `confirmed_at` yet, so this only proves the migration itself doesn't break anything.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: add confirmed_at column to users with backfill"
```

---

### Task 2: Set `confirmed_at` on first login

**Files:**
- Modify: `lib/speechwave/accounts.ex:320` (`generate_user_session_token/1`)
- Modify: `test/support/fixtures/accounts_fixtures.ex:116` (`session_token_fixture/2`)
- Modify: `test/speechwave/accounts_test.exs`

**Interfaces:**
- Consumes: `users.confirmed_at` column from Task 1.
- Produces: `Accounts.generate_user_session_token/1` now sets `confirmed_at` as a side effect on a user's first call. `session_token_fixture/2` in tests does the same, so any test using it accurately simulates a real login.

- [ ] **Step 1: Write the failing test**

In `test/speechwave/accounts_test.exs`, inside the existing `describe "generate_user_session_token/1"` block (around line 163), add:

```elixir
test "sets confirmed_at on first login and leaves it unchanged on the next", %{user: user} do
  refute user.confirmed_at

  Accounts.generate_user_session_token(user)
  first_login = Repo.get!(User, user.id)
  assert %DateTime{} = first_login.confirmed_at

  Accounts.generate_user_session_token(first_login)
  second_login = Repo.get!(User, user.id)
  assert second_login.confirmed_at == first_login.confirmed_at
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/speechwave/accounts_test.exs`
Expected: FAIL — `assert %DateTime{} = first_login.confirmed_at` fails because `confirmed_at` is `nil`.

- [ ] **Step 3: Implement the guarded write**

In `lib/speechwave/accounts.ex`, replace `generate_user_session_token/1` (line 320):

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

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/speechwave/accounts_test.exs`
Expected: PASS, all tests in the file including the two pre-existing ones in the same `describe` block.

- [ ] **Step 5: Update the test fixture to match production behavior**

In `test/support/fixtures/accounts_fixtures.ex`, replace `session_token_fixture/2` (line 116):

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

- [ ] **Step 6: Run the full test suite**

Run: `mix test`
Expected: PASS. `Speechwave.Admin.Stats` still queries tokens/identities directly at this point (Task 3 hasn't touched it), so the fixture now setting an extra unused `confirmed_at` field changes nothing observable yet.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave/accounts.ex test/support/fixtures/accounts_fixtures.ex test/speechwave/accounts_test.exs
git commit -m "feat: set confirmed_at once on a user's first session token"
```

---

### Task 3: Simplify `Speechwave.Admin.Stats` to use `confirmed_at`

**Files:**
- Modify: `lib/speechwave/admin/stats.ex`
- Modify: `test/speechwave/admin/stats_test.exs`
- Modify: `docs/decisions.md`

**Interfaces:**
- Consumes: `session_token_fixture/2` (Task 2) now setting `confirmed_at` to the same value it backdates the token to.
- Produces: `confirmed_users_query/0`, `unconfirmed_users_query/0`, and `recent_confirmation_timestamps/1` in `Speechwave.Admin.Stats` now read `users.confirmed_at` directly. No other function in the module changes signature or behavior.

This task is a **behavior-preserving refactor**, not new functionality — the whole point is that the dashboard's output doesn't change, only how it's computed. So the sequence here is green → refactor → green, not red → green: the edited tests are expected to already pass against the *old* implementation (since the fixture already sets `confirmed_at` to match the same timestamps the old token/identity-based queries use), and must still pass against the *new* one.

- [ ] **Step 1: Update test fixtures to match how a real user reaches each state**

In `test/speechwave/admin/stats_test.exs`:

Replace line 18-19:
```elixir
confirmed_via_identity = user_fixture()
identity_fixture(confirmed_via_identity)
```
with:
```elixir
confirmed_via_identity = user_fixture()
session_token_fixture(confirmed_via_identity)
identity_fixture(confirmed_via_identity)
```
(A real OAuth signup always creates a session token via `log_in_user` — see the design spec's Current State section. An identity with no session token isn't a reachable state.)

Replace lines 32-34:
```elixir
old_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -40, :day))
{_token, user_token} = session_token_fixture(old_confirmed)
backdate_token(user_token.id, DateTime.add(now, -40, :day))
```
with:
```elixir
old_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -40, :day))
{_token, _user_token} = session_token_fixture(old_confirmed, DateTime.add(now, -40, :day))
```

Replace lines 38-40:
```elixir
recently_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -20, :day))
{_token, user_token2} = session_token_fixture(recently_confirmed)
backdate_token(user_token2.id, DateTime.add(now, -2, :day))
```
with:
```elixir
recently_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -20, :day))
{_token, _user_token2} = session_token_fixture(recently_confirmed, DateTime.add(now, -2, :day))
```

Replace lines 111-115:
```elixir
confirmed_recently =
  user_fixture() |> backdate_user(DateTime.add(now, -15, :day))

{_token, user_token} = session_token_fixture(confirmed_recently)
backdate_token(user_token.id, DateTime.add(now, -2, :day))
```
with:
```elixir
confirmed_recently =
  user_fixture() |> backdate_user(DateTime.add(now, -15, :day))

session_token_fixture(confirmed_recently, DateTime.add(now, -2, :day))
```

Delete the entire test at lines 63-86 (`"a user confirmed via an old token isn't misreported as recently confirmed via a newer identity"`) — it exists only to pin down the two-phase reconciliation logic this task removes, and the scenario it guards against can't happen with a single `confirmed_at` column.

- [ ] **Step 2: Run the suite to confirm these edits are behavior-neutral so far**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: PASS — `Speechwave.Admin.Stats` hasn't changed yet, so this proves the fixture-usage edits alone don't alter outcomes.

- [ ] **Step 3: Simplify the stats queries**

In `lib/speechwave/admin/stats.ex`, replace `confirmed_users_query/0` (line 237) and its preceding comment (lines 231-236):

```elixir
defp confirmed_users_query do
  from u in User, where: not is_nil(u.confirmed_at)
end
```

Replace `unconfirmed_users_query/0` (line 253):

```elixir
defp unconfirmed_users_query do
  from u in User, where: is_nil(u.confirmed_at)
end
```

Replace `recent_confirmation_timestamps/1` and its preceding comment in full (lines 270-331):

```elixir
defp recent_confirmation_timestamps(cutoff) do
  Repo.all(
    from u in User, where: u.confirmed_at >= ^cutoff, select: {u.id, u.confirmed_at}
  )
  |> Map.new()
end
```

Remove the moduledoc paragraph about "confirmed" being the one non-monotonic exception (lines 21-27) — replace it with nothing (the paragraph directly above it, about the reconstruction technique, stands fine without it).

- [ ] **Step 4: Run the suite to confirm behavior is preserved**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: PASS — same outcomes, computed from `confirmed_at` instead of token/identity existence.

- [ ] **Step 5: Update `docs/decisions.md`**

Replace the bullet starting `**"Confirmed" is not strictly monotonic.**` (lines 56-66) with:

```markdown
- **"Confirmed" is now monotonic.** Originally inferred from session-token/
  identity existence (volatile — logout deleted the evidence), this was
  fixed on 2026-07-06 by adding a dedicated `users.confirmed_at` column, set
  once on first login and never cleared. See
  `docs/specs/2026-07-06-confirmed-at-column-design.md`.
```

- [ ] **Step 6: Run the full test suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave/admin/stats.ex test/speechwave/admin/stats_test.exs docs/decisions.md
git commit -m "refactor: derive confirmed users from confirmed_at, not token/identity existence"
```

---

### Task 4: Deploy-time backfill verification

**Files:**
- Modify: `lib/speechwave/release.ex`
- Create: `test/speechwave/release_test.exs`

**Interfaces:**
- Produces: `Speechwave.Release.unconfirmed_with_evidence_count/1` (public, default arg `Speechwave.Repo`) — returns the count of users with a session token or identity but no `confirmed_at`. `Release.migrate/0` calls it after migrating and raises if it's non-zero, failing the deploy.

- [ ] **Step 1: Write the failing tests**

Create `test/speechwave/release_test.exs`:

```elixir
defmodule Speechwave.ReleaseTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures
  alias Speechwave.Accounts.User
  alias Speechwave.Release

  describe "unconfirmed_with_evidence_count/1" do
    test "counts a user with a session token but no confirmed_at" do
      user = user_fixture()
      session_token_fixture(user)

      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [confirmed_at: nil]
      )

      assert Release.unconfirmed_with_evidence_count(Repo) == 1
    end

    test "excludes a properly confirmed user" do
      user = user_fixture()
      session_token_fixture(user)

      assert Release.unconfirmed_with_evidence_count(Repo) == 0
    end

    test "excludes a genuinely unconfirmed user with no token or identity" do
      user_fixture()

      assert Release.unconfirmed_with_evidence_count(Repo) == 0
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/speechwave/release_test.exs`
Expected: FAIL — `Speechwave.Release.unconfirmed_with_evidence_count/1` is undefined.

- [ ] **Step 3: Implement the check**

In `lib/speechwave/release.ex`, add the public helper and wire it into `migrate/0`:

```elixir
def migrate do
  load_app()

  for repo <- repos() do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  verify_confirmed_at_backfill()
end

def unconfirmed_with_evidence_count(repo \\ Speechwave.Repo) do
  {:ok, %{rows: [[count]]}} =
    Ecto.Adapters.SQL.query(repo, """
    SELECT COUNT(*) FROM users u
    WHERE u.confirmed_at IS NULL
      AND (EXISTS (SELECT 1 FROM users_tokens t WHERE t.user_id = u.id AND t.context = 'session')
        OR EXISTS (SELECT 1 FROM user_identities i WHERE i.user_id = u.id))
    """, [])

  count
end

defp verify_confirmed_at_backfill do
  count = unconfirmed_with_evidence_count()

  if count != 0 do
    raise "confirmed_at backfill left #{count} users unconfirmed despite having a session token or identity"
  end
end
```

Place `unconfirmed_with_evidence_count/1` and `verify_confirmed_at_backfill/0` after `migrate/0` and before `seed/0` in the file.

- [ ] **Step 4: Run it to verify it passes**

Run: `mix test test/speechwave/release_test.exs`
Expected: PASS, all three tests.

- [ ] **Step 5: Run the full test suite and `mix precommit`**

Run: `mix test`
Expected: PASS, entire suite.

Run: `mix precommit`
Expected: PASS. Fix anything it flags (formatting, credo, dialyzer) before committing.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/release.ex test/speechwave/release_test.exs
git commit -m "feat: fail the deploy if confirmed_at backfill misses any user"
```
