# Super-admin Stats Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an `/admin/stats` LiveView, gated behind a new admin-authorization mechanism, showing 11 metric cards (current value + 30-day trend chart) covering user confirmation state, notification signups, and talk/session activity.

**Architecture:** A new `on_mount :require_admin` hook + `live_session` gates `/admin/stats`. A new `Speechwave.Admin.Stats` context computes each metric as `%{current: integer, history: [{Date.t(), integer}]}` using current-total aggregate queries plus bounded recent-window deltas (never a full historical table scan) — see `docs/specs/2026-07-06-super-admin-stats-design.md`. Contex renders each trend as a server-side SVG.

**Tech Stack:** Phoenix LiveView 1.8, Ecto (SQLite via `ecto_sqlite3`), Contex (new dep, SVG chart rendering).

## Global Constraints

- The app uses **SQLite**, not Postgres — no `generate_series`, no Postgres-only SQL. All date-bucketing logic must run in Elixir, not SQL.
- `User.plan` enum values are `:free | :pro | :org`. The pricing page's "Enterprise" button passes `phx-value-plan="enterprise"` (confirmed in `pricing_live.ex`), so the consent `source` literal is `"pricing_enterprise"`, not `"pricing_org"`.
- No new database migrations are needed for this feature — `is_admin` already exists on `User`.
- Granting `is_admin` stays out of scope. Do not build any UI for it; the existing `Speechwave.Release` mix-release task remains the only mechanism.
- Follow `CLAUDE.md`: `<Layouts.app flash={@flash} current_scope={@current_scope}>` wraps all LiveView templates; use `@current_scope.user`, never `@current_user`; use the `<.icon>` component for icons; use `mix precommit` when the whole plan is done.
- Every history list returned by `Speechwave.Admin.Stats` covers the last 30 days, oldest first, with the last entry always representing "now" — `current` for each metric is defined as the last entry of its own `history` list, so the two can never drift apart.

---

### Task 1: Admin authorization + `/admin/stats` route skeleton

**Files:**
- Modify: `lib/speechwave_web/user_auth.ex`
- Modify: `lib/speechwave_web/router.ex`
- Create: `lib/speechwave_web/live/admin/stats_live.ex`
- Create: `lib/speechwave_web/live/admin/stats_live.html.heex`
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Create: `test/speechwave_web/live/admin/stats_live_test.exs`

**Interfaces:**
- Produces: `SpeechwaveWeb.UserAuth.on_mount(:require_admin, params, session, socket)` — usable in any future admin `live_session`.
- Produces: route `GET /admin/stats` → `SpeechwaveWeb.Admin.StatsLive`.
- Produces: `Speechwave.AccountsFixtures.admin_user_fixture/1` — returns a `%User{}` with `is_admin: true`, for use in all admin tests going forward.

- [ ] **Step 1: Write the failing tests**

Create `test/speechwave_web/live/admin/stats_live_test.exs`:

```elixir
defmodule SpeechwaveWeb.Admin.StatsLiveTest do
  use SpeechwaveWeb.ConnCase

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  test "redirects to login when logged out" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/stats")
    assert path =~ "/users/log-in"
  end

  test "redirects non-admin users to the home page" do
    user = user_fixture()
    conn = log_in_user(build_conn(), user)

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/stats")
    assert path == ~p"/"
  end

  test "admin users can view the page", %{conn: conn} do
    admin = admin_user_fixture()
    conn = log_in_user(conn, admin)

    {:ok, _view, html} = live(conn, ~p"/admin/stats")
    assert html =~ "Admin Stats"
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/speechwave_web/live/admin/stats_live_test.exs`
Expected: FAIL — no route matches `/admin/stats` (or `admin_user_fixture/1` undefined).

- [ ] **Step 3: Add `admin_user_fixture/1`**

In `test/support/fixtures/accounts_fixtures.ex`, add after `oauth_user_fixture/1`:

```elixir
  def admin_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)

    user
    |> Ecto.Changeset.change(is_admin: true)
    |> Speechwave.Repo.update!()
  end
```

- [ ] **Step 4: Add the `:require_admin` on_mount clause**

In `lib/speechwave_web/user_auth.ex`, add a new clause after `on_mount(:require_sudo_mode, ...)` (after line 253, before `defp mount_current_scope`):

```elixir
  def on_mount(:require_admin, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user &&
         socket.assigns.current_scope.user.is_admin do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must be an admin to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end
```

Also update the `@doc` above `on_mount/4` (around line 189-220) to document the new clause, adding after the `:require_sudo_mode` bullet is not present there today — instead add a new bullet after `:require_authenticated`:

```elixir
    * `:require_admin` - Authenticates the user from the session, and
      redirects to `/` if the user is not an admin. Assumes
      `current_scope` has not already been mounted by an earlier
      `on_mount` in the same `live_session` — safe to chain after
      `:require_authenticated`.
```

- [ ] **Step 5: Add the router route**

In `lib/speechwave_web/router.ex`, add a new scope after the `:require_authenticated_user` scope (after line 48, before the "Auth routes" comment block):

```elixir
  # ---------------------------------------------------------------------------
  # Admin routes — require is_admin
  # ---------------------------------------------------------------------------

  scope "/admin", SpeechwaveWeb.Admin do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_admin,
      on_mount: [
        {SpeechwaveWeb.UserAuth, :require_authenticated},
        {SpeechwaveWeb.UserAuth, :require_admin}
      ] do
      live "/stats", StatsLive, :index
    end
  end
```

- [ ] **Step 6: Create the LiveView skeleton**

Create `lib/speechwave_web/live/admin/stats_live.ex`:

```elixir
defmodule SpeechwaveWeb.Admin.StatsLive do
  use SpeechwaveWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
```

Create `lib/speechwave_web/live/admin/stats_live.html.heex`:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <h1 class="text-2xl font-bold text-ink mb-6">Admin Stats</h1>
  <div id="admin-stats-grid" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
  </div>
</Layouts.app>
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `mix test test/speechwave_web/live/admin/stats_live_test.exs`
Expected: PASS (3 tests, 0 failures)

- [ ] **Step 8: Commit**

```bash
git add lib/speechwave_web/user_auth.ex lib/speechwave_web/router.ex \
  lib/speechwave_web/live/admin/stats_live.ex \
  lib/speechwave_web/live/admin/stats_live.html.heex \
  test/support/fixtures/accounts_fixtures.ex \
  test/speechwave_web/live/admin/stats_live_test.exs
git commit -m "feat: add admin-gated /admin/stats route skeleton"
```

---

### Task 2: `Speechwave.Admin.Stats` — total users, confirmed, unconfirmed

**Files:**
- Create: `lib/speechwave/admin/stats.ex`
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Create: `test/speechwave/admin/stats_test.exs`

**Interfaces:**
- Consumes: `Speechwave.Accounts.User`, `Speechwave.Accounts.UserToken`, `Speechwave.Accounts.UserIdentity` schemas (all read-only queries).
- Produces: `Speechwave.Admin.Stats.user_categories(now \\ DateTime.utc_now())`, returning `%{total_users: metric, confirmed: metric, unconfirmed: metric}` where `metric` is `%{current: integer, history: [{Date.t(), integer}]}`. (`:onboarding` and `:suspicious` keys are added in Task 3 — do not add placeholder keys for them here.)
- Produces test fixture helpers: `backdate_user/2`, `backdate_token/2`, `backdate_identity/2` in `Speechwave.AccountsFixtures`, reusable by all later Stats tasks.

- [ ] **Step 1: Add backdating fixture helpers**

In `test/support/fixtures/accounts_fixtures.ex`, add `import Ecto.Query` near the top (after the `@moduledoc`) and these functions after `admin_user_fixture/1`:

```elixir
  def backdate_user(user, inserted_at) do
    Speechwave.Repo.update_all(
      from(u in Accounts.User, where: u.id == ^user.id),
      set: [inserted_at: inserted_at]
    )

    %{user | inserted_at: inserted_at}
  end

  def backdate_token(token_id, inserted_at) do
    Speechwave.Repo.update_all(
      from(t in Accounts.UserToken, where: t.id == ^token_id),
      set: [inserted_at: inserted_at]
    )
  end

  def backdate_identity(identity_id, inserted_at) do
    Speechwave.Repo.update_all(
      from(i in Accounts.UserIdentity, where: i.id == ^identity_id),
      set: [inserted_at: inserted_at]
    )
  end

  def session_token_fixture(user, inserted_at \\ nil) do
    {token, user_token} = Accounts.UserToken.build_session_token(user)
    user_token = Speechwave.Repo.insert!(user_token)

    if inserted_at do
      backdate_token(user_token.id, inserted_at)
    end

    {token, user_token}
  end

  def identity_fixture(user, attrs \\ %{}) do
    provider = Map.get(attrs, :provider, "google")
    uid = Map.get(attrs, :uid, "uid-#{System.unique_integer()}")

    {:ok, identity} = Accounts.link_identity_to_user(user, provider, uid)
    identity
  end
```

- [ ] **Step 2: Write the failing test**

Create `test/speechwave/admin/stats_test.exs`:

```elixir
defmodule Speechwave.Admin.StatsTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures

  alias Speechwave.Admin.Stats

  describe "user_categories/1" do
    test "counts total, confirmed, and unconfirmed users" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _unconfirmed = user_fixture()

      confirmed_via_token = user_fixture()
      {_token, _user_token} = session_token_fixture(confirmed_via_token)

      confirmed_via_identity = user_fixture()
      identity_fixture(confirmed_via_identity)

      %{total_users: total, confirmed: confirmed, unconfirmed: unconfirmed} =
        Stats.user_categories(now)

      assert total.current == 3
      assert confirmed.current == 2
      assert unconfirmed.current == 1
    end

    test "history reflects state as of each of the last 30 days" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      old_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -40, :day))
      {_token, user_token} = session_token_fixture(old_confirmed)
      backdate_token(user_token.id, DateTime.add(now, -40, :day))

      recent_signup = user_fixture() |> backdate_user(DateTime.add(now, -5, :day))

      recently_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -20, :day))
      {_token, user_token2} = session_token_fixture(recently_confirmed)
      backdate_token(user_token2.id, DateTime.add(now, -2, :day))

      %{total_users: total, confirmed: confirmed} = Stats.user_categories(now)

      # 10 days ago: only old_confirmed exists (signed up 40d ago) and is confirmed.
      # recent_signup (signed up 5d ago) and recently_confirmed (signed up 20d ago,
      # confirmed 2d ago) both already existed by 10 days ago.
      ten_days_ago = Date.add(DateTime.to_date(now), -10)
      {^ten_days_ago, total_10d_ago} = Enum.find(total.history, fn {d, _} -> d == ten_days_ago end)
      {^ten_days_ago, confirmed_10d_ago} = Enum.find(confirmed.history, fn {d, _} -> d == ten_days_ago end)

      assert total_10d_ago == 2
      # recently_confirmed hadn't confirmed yet 10 days ago (confirmed only 2 days ago)
      assert confirmed_10d_ago == 1

      assert total.current == 3
      assert confirmed.current == 2
    end
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: FAIL with `Speechwave.Admin.Stats` module not defined (or undefined function errors from the fixtures if Step 1 wasn't picked up — re-check imports if so).

- [ ] **Step 4: Implement `Speechwave.Admin.Stats`**

Create `lib/speechwave/admin/stats.ex`:

```elixir
defmodule Speechwave.Admin.Stats do
  @moduledoc """
  Aggregate queries for the super-admin stats dashboard
  (docs/specs/2026-07-06-super-admin-stats-design.md).

  Each metric is `%{current: integer, history: [{Date.t(), integer}]}`.
  `history` covers the last `@history_days` days, oldest first; each day's
  count reflects state as of 23:59:59 UTC that day, and `current` is always
  the same value as the last entry of `history` (state as of "now", which
  falls within today's bucket since no future rows can exist in the DB).

  History is reconstructed by walking backward from a current aggregate
  total using only rows that changed within the history window — never a
  full scan of all-time data. See the design doc for why this is valid
  (state transitions tracked here — signup, confirmation, consent,
  talk/session creation — are monotonic or single-event within the window).
  """

  import Ecto.Query

  alias Speechwave.Repo
  alias Speechwave.Accounts.{User, UserToken, UserIdentity}

  @history_days 30
  @onboarding_threshold_days 3

  @doc "Number of days of history returned by each metric's `history` list."
  def history_days, do: @history_days

  @doc "Account age (in days) below which an unconfirmed user is 'onboarding' rather than 'suspicious'."
  def onboarding_threshold_days, do: @onboarding_threshold_days

  @doc "Total, confirmed, and unconfirmed user counts, current and 30-day history."
  def user_categories(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    cutoff = DateTime.add(now, -@history_days, :day)
    days = last_n_days(now, @history_days)

    total_current = Repo.aggregate(User, :count)
    confirmed_current = Repo.aggregate(confirmed_users_query(), :count)

    recent_signups = Repo.all(from(u in User, where: u.inserted_at >= ^cutoff, select: u.inserted_at))
    recent_confirmations = recent_confirmation_timestamps(cutoff)

    total_history = history_from_baseline(total_current, recent_signups, days)
    confirmed_history = history_from_baseline(confirmed_current, Map.values(recent_confirmations), days)

    unconfirmed_history =
      Enum.zip_with(total_history, confirmed_history, fn {date, t}, {_date, c} -> {date, t - c} end)

    %{
      total_users: metric(total_history),
      confirmed: metric(confirmed_history),
      unconfirmed: metric(unconfirmed_history)
    }
  end

  defp confirmed_users_query do
    from u in User,
      as: :user,
      where:
        exists(
          from t in UserToken,
            where: t.user_id == parent_as(:user).id and t.context == "session",
            select: 1
        ) or
          exists(
            from i in UserIdentity,
              where: i.user_id == parent_as(:user).id,
              select: 1
          )
  end

  # Returns %{user_id => confirmed_at} for users whose earliest confirmation
  # (first session token OR first identity, whichever is earlier) falls
  # within the last `@history_days` days. Users confirmed earlier than that
  # don't need to appear here — they were already confirmed at the start of
  # the history window and are fully accounted for by `confirmed_current`.
  defp recent_confirmation_timestamps(cutoff) do
    token_confirmations =
      Repo.all(
        from t in UserToken,
          where: t.context == "session",
          group_by: t.user_id,
          having: min(t.inserted_at) >= ^cutoff,
          select: {t.user_id, min(t.inserted_at)}
      )
      |> Map.new()

    identity_confirmations =
      Repo.all(
        from i in UserIdentity,
          group_by: i.user_id,
          having: min(i.inserted_at) >= ^cutoff,
          select: {i.user_id, min(i.inserted_at)}
      )
      |> Map.new()

    Map.merge(token_confirmations, identity_confirmations, fn _user_id, a, b ->
      if DateTime.compare(a, b) == :lt, do: a, else: b
    end)
  end

  # Reconstructs a daily history by subtracting, from `current_total`, the
  # count of `recent_event_timestamps` that happened after each day's end.
  defp history_from_baseline(current_total, recent_event_timestamps, days) do
    Enum.map(days, fn day ->
      day_cutoff = day_end(day)
      count_after = Enum.count(recent_event_timestamps, &(DateTime.compare(&1, day_cutoff) == :gt))
      {day, current_total - count_after}
    end)
  end

  defp metric(history) do
    {_date, current} = List.last(history)
    %{current: current, history: history}
  end

  defp last_n_days(now, n) do
    today = DateTime.to_date(now)
    for offset <- (n - 1)..0//-1, do: Date.add(today, -offset)
  end

  defp day_end(date), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: PASS (2 tests, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/admin/stats.ex test/support/fixtures/accounts_fixtures.ex \
  test/speechwave/admin/stats_test.exs
git commit -m "feat: add total/confirmed/unconfirmed user stats queries"
```

---

### Task 3: `Speechwave.Admin.Stats` — onboarding and suspicious users

**Files:**
- Modify: `lib/speechwave/admin/stats.ex`
- Modify: `test/speechwave/admin/stats_test.exs`

**Interfaces:**
- Consumes: everything from Task 2 (`confirmed_users_query/0`, `recent_confirmation_timestamps/1`, `history_from_baseline/3`, `metric/1`, `last_n_days/2`, `day_end/1`, `@onboarding_threshold_days`).
- Produces: `user_categories/1` now also returns `:onboarding` and `:suspicious` keys, same `metric` shape. `onboarding.current + suspicious.current == unconfirmed.current` always, and this holds for every day in history too.

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave/admin/stats_test.exs`, inside `describe "user_categories/1"`:

```elixir
    test "splits unconfirmed users into onboarding and suspicious by account age" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _onboarding_user =
        user_fixture() |> backdate_user(DateTime.add(now, -1, :day))

      _suspicious_user =
        user_fixture() |> backdate_user(DateTime.add(now, -10, :day))

      %{onboarding: onboarding, suspicious: suspicious, unconfirmed: unconfirmed} =
        Stats.user_categories(now)

      assert onboarding.current == 1
      assert suspicious.current == 1
      assert unconfirmed.current == 2
    end

    test "onboarding + suspicious always sum to unconfirmed, including in history" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _user_a = user_fixture() |> backdate_user(DateTime.add(now, -1, :day))
      _user_b = user_fixture() |> backdate_user(DateTime.add(now, -35, :day))

      confirmed_recently =
        user_fixture() |> backdate_user(DateTime.add(now, -15, :day))

      {_token, user_token} = session_token_fixture(confirmed_recently)
      backdate_token(user_token.id, DateTime.add(now, -2, :day))

      %{onboarding: onboarding, suspicious: suspicious, unconfirmed: unconfirmed} =
        Stats.user_categories(now)

      for {{date, ob}, {^date, sp}, {^date, u}} <-
            Enum.zip([onboarding.history, suspicious.history, unconfirmed.history]) do
        assert ob + sp == u, "mismatch on #{date}: #{ob} + #{sp} != #{u}"
      end
    end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: FAIL — `%{onboarding: ..., suspicious: ...}` keys not present in the result of `user_categories/1` (`MatchError` or `KeyError`).

- [ ] **Step 3: Implement onboarding/suspicious**

In `lib/speechwave/admin/stats.ex`, replace the `user_categories/1` function body with:

```elixir
  @doc "Total, confirmed, unconfirmed, onboarding, and suspicious user counts, current and 30-day history."
  def user_categories(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    cutoff = DateTime.add(now, -@history_days, :day)
    days = last_n_days(now, @history_days)

    total_current = Repo.aggregate(User, :count)
    confirmed_current = Repo.aggregate(confirmed_users_query(), :count)

    recent_signups = Repo.all(from(u in User, where: u.inserted_at >= ^cutoff, select: u.inserted_at))
    recent_confirmations = recent_confirmation_timestamps(cutoff)
    recent_confirmers = recent_confirmers(recent_confirmations)
    unconfirmed_now = Repo.all(from(u in unconfirmed_users_query(), select: u.inserted_at))

    total_history = history_from_baseline(total_current, recent_signups, days)
    confirmed_history = history_from_baseline(confirmed_current, Map.values(recent_confirmations), days)

    unconfirmed_history =
      Enum.zip_with(total_history, confirmed_history, fn {date, t}, {_date, c} -> {date, t - c} end)

    {onboarding_history, suspicious_history} =
      age_split_history(unconfirmed_now, recent_confirmers, days)

    %{
      total_users: metric(total_history),
      confirmed: metric(confirmed_history),
      unconfirmed: metric(unconfirmed_history),
      onboarding: metric(onboarding_history),
      suspicious: metric(suspicious_history)
    }
  end
```

Add `unconfirmed_users_query/0` right after `confirmed_users_query/0`:

```elixir
  defp unconfirmed_users_query do
    from u in User,
      as: :user,
      where:
        not exists(
          from t in UserToken,
            where: t.user_id == parent_as(:user).id and t.context == "session",
            select: 1
        ),
      where:
        not exists(
          from i in UserIdentity,
            where: i.user_id == parent_as(:user).id,
            select: 1
        )
  end
```

Add `recent_confirmers/1` and `age_split_history/3` after `recent_confirmation_timestamps/1`:

```elixir
  # Fetches inserted_at for users who confirmed within the history window, so
  # `age_split_history/3` can determine what age bucket they were in on days
  # before they confirmed.
  defp recent_confirmers(recent_confirmations) do
    user_ids = Map.keys(recent_confirmations)

    inserted_ats =
      Repo.all(from(u in User, where: u.id in ^user_ids, select: {u.id, u.inserted_at}))
      |> Map.new()

    Enum.map(recent_confirmations, fn {user_id, confirmed_at} ->
      %{inserted_at: Map.fetch!(inserted_ats, user_id), confirmed_at: confirmed_at}
    end)
  end

  # For each day, the "still unconfirmed as of that day" population is:
  #   - users who are unconfirmed today, who already existed by that day, plus
  #   - users who confirmed later (within the window) but hadn't yet as of that day.
  # This exactly reconstructs the unconfirmed set for any day in the window
  # without needing to touch the full users table (see stats_test.exs for the
  # invariant this maintains: onboarding + suspicious == unconfirmed, every day).
  defp age_split_history(unconfirmed_now, recent_confirmers, days) do
    Enum.map(days, fn day ->
      day_cutoff = day_end(day)

      still_unconfirmed =
        Enum.filter(unconfirmed_now, &(DateTime.compare(&1, day_cutoff) != :gt))

      not_yet_confirmed =
        recent_confirmers
        |> Enum.filter(fn %{inserted_at: ia, confirmed_at: ca} ->
          DateTime.compare(ia, day_cutoff) != :gt and DateTime.compare(ca, day_cutoff) == :gt
        end)
        |> Enum.map(& &1.inserted_at)

      ages = still_unconfirmed ++ not_yet_confirmed

      onboarding_count =
        Enum.count(ages, &(DateTime.diff(day_cutoff, &1, :day) < @onboarding_threshold_days))

      {{day, onboarding_count}, {day, length(ages) - onboarding_count}}
    end)
    |> Enum.unzip()
  end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: PASS (4 tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave/admin/stats.ex test/speechwave/admin/stats_test.exs
git commit -m "feat: split unconfirmed users into onboarding and suspicious"
```

---

### Task 4: `Speechwave.Admin.Stats` — notification signup metrics

**Files:**
- Modify: `lib/speechwave/admin/stats.ex`
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Modify: `test/speechwave/admin/stats_test.exs`

**Interfaces:**
- Consumes: `Speechwave.Accounts.UserConsent`, `history_from_baseline` pattern conventions established in Task 2 (reimplemented here as `consent_history/3` since the delta math differs — grant/revoke rather than pure creation).
- Produces: `Speechwave.Admin.Stats.notification_signups(now \\ DateTime.utc_now())`, returning `%{pro_signups: metric, enterprise_signups: metric, total_signups: metric}`.

- [ ] **Step 1: Add a consent fixture helper**

In `test/support/fixtures/accounts_fixtures.ex`, add after `identity_fixture/2`:

```elixir
  def backdate_consent(user, consent_type, fields) do
    Speechwave.Repo.update_all(
      from(c in Accounts.UserConsent, where: c.user_id == ^user.id and c.consent_type == ^consent_type),
      set: fields
    )
  end
```

- [ ] **Step 2: Write the failing test**

Add to `test/speechwave/admin/stats_test.exs`:

```elixir
  describe "notification_signups/1" do
    test "counts current pro, enterprise, and total signups" do
      pro_user = user_fixture()
      {:ok, _} = Speechwave.Accounts.grant_consent(pro_user, "marketing_email", source: "pricing_pro")

      enterprise_user = user_fixture()

      {:ok, _} =
        Speechwave.Accounts.grant_consent(enterprise_user, "marketing_email", source: "pricing_enterprise")

      _login_only_user = consented_user_fixture(%{source: "login"})

      %{pro_signups: pro, enterprise_signups: enterprise, total_signups: total} =
        Stats.notification_signups()

      assert pro.current == 1
      assert enterprise.current == 1
      assert total.current == 2
    end

    test "history reflects grant/revoke state as of each day" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      user = user_fixture()
      {:ok, _} = Speechwave.Accounts.grant_consent(user, "marketing_email", source: "pricing_pro")
      backdate_consent(user, "marketing_email", granted_at: DateTime.add(now, -10, :day))

      %{pro_signups: pro} = Stats.notification_signups(now)

      five_days_ago = Date.add(DateTime.to_date(now), -5)
      fifteen_days_ago = Date.add(DateTime.to_date(now), -15)

      assert {^five_days_ago, 1} = Enum.find(pro.history, fn {d, _} -> d == five_days_ago end)
      assert {^fifteen_days_ago, 0} = Enum.find(pro.history, fn {d, _} -> d == fifteen_days_ago end)
      assert pro.current == 1
    end
  end
```

This test uses `consented_user_fixture/1` (already defined in `accounts_fixtures.ex`).

- [ ] **Step 3: Run the test to verify it fails**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: FAIL — `Stats.notification_signups/0` undefined.

- [ ] **Step 4: Implement `notification_signups/1`**

In `lib/speechwave/admin/stats.ex`, add `alias Speechwave.Accounts.UserConsent` to the existing alias line (change `alias Speechwave.Accounts.{User, UserToken, UserIdentity}` to `alias Speechwave.Accounts.{User, UserToken, UserIdentity, UserConsent}`), then add after `user_categories/1`:

```elixir
  @doc "Pro, enterprise, and total marketing-email notification signup counts, current and 30-day history."
  def notification_signups(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    cutoff = DateTime.add(now, -@history_days, :day)
    days = last_n_days(now, @history_days)

    pro_history = consent_history(days, cutoff, "pricing_pro")
    enterprise_history = consent_history(days, cutoff, "pricing_enterprise")

    total_history =
      Enum.zip_with(pro_history, enterprise_history, fn {date, p}, {_date, e} -> {date, p + e} end)

    %{
      pro_signups: metric(pro_history),
      enterprise_signups: metric(enterprise_history),
      total_signups: metric(total_history)
    }
  end

  defp consent_history(days, cutoff, source) do
    current_total =
      Repo.aggregate(
        from(c in UserConsent,
          where: c.consent_type == "marketing_email" and c.source == ^source and c.granted == true
        ),
        :count
      )

    recent_changes =
      Repo.all(
        from c in UserConsent,
          where:
            c.consent_type == "marketing_email" and c.source == ^source and
              ((not is_nil(c.granted_at) and c.granted_at >= ^cutoff) or
                 (not is_nil(c.revoked_at) and c.revoked_at >= ^cutoff)),
          select: {c.granted, c.granted_at, c.revoked_at}
      )

    Enum.map(days, fn day ->
      day_cutoff = day_end(day)

      adjustment =
        Enum.reduce(recent_changes, 0, fn {granted, granted_at, revoked_at}, acc ->
          active_then = consent_active_as_of?(granted_at, revoked_at, day_cutoff)

          cond do
            granted and not active_then -> acc - 1
            not granted and active_then -> acc + 1
            true -> acc
          end
        end)

      {day, current_total + adjustment}
    end)
  end

  # Reconstructs whether a consent row was active as of `day_cutoff`, based on
  # its most recent grant/revoke cycle only. `grant_consent/3`/`revoke_consent/2`
  # overwrite `granted_at`/`revoked_at` on each cycle rather than keeping full
  # history, so a user who has toggled consent more than once within the
  # history window can have earlier cycles undercounted. Acceptable for a
  # traction-tracking dashboard — this isn't an audit log.
  defp consent_active_as_of?(granted_at, revoked_at, day_cutoff) do
    not is_nil(granted_at) and DateTime.compare(granted_at, day_cutoff) != :gt and
      (is_nil(revoked_at) or DateTime.compare(revoked_at, day_cutoff) == :gt)
  end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: PASS (6 tests, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/admin/stats.ex test/support/fixtures/accounts_fixtures.ex \
  test/speechwave/admin/stats_test.exs
git commit -m "feat: add pro/enterprise notification signup stats queries"
```

---

### Task 5: `Speechwave.Admin.Stats` — talk activity metrics + `dashboard/1`

**Files:**
- Modify: `lib/speechwave/admin/stats.ex`
- Modify: `test/support/fixtures/talks_fixtures.ex`
- Modify: `test/speechwave/admin/stats_test.exs`

**Interfaces:**
- Consumes: `Speechwave.Talks.Talk`, `Speechwave.Talks.TalkSession`.
- Produces: `Speechwave.Admin.Stats.talk_activity(now \\ DateTime.utc_now())`, returning `%{talks: metric, talks_with_sessions: metric, sessions: metric}`.
- Produces: `Speechwave.Admin.Stats.dashboard(now \\ DateTime.utc_now())`, returning an **ordered list** of `{key, metric}` tuples covering all 11 metrics — this is what `SpeechwaveWeb.Admin.StatsLive` will call in Task 6.

- [ ] **Step 1: Add talk/session backdating fixture helpers**

In `test/support/fixtures/talks_fixtures.ex`, add `import Ecto.Query` after the `@moduledoc` comment, then add at the end of the module:

```elixir
  def backdate_talk(talk, inserted_at) do
    Speechwave.Repo.update_all(
      from(t in Speechwave.Talks.Talk, where: t.id == ^talk.id),
      set: [inserted_at: inserted_at]
    )

    %{talk | inserted_at: inserted_at}
  end

  def backdate_session(session, inserted_at) do
    Speechwave.Repo.update_all(
      from(s in Speechwave.Talks.TalkSession, where: s.id == ^session.id),
      set: [inserted_at: inserted_at]
    )

    %{session | inserted_at: inserted_at}
  end
```

- [ ] **Step 2: Write the failing test**

Add to `test/speechwave/admin/stats_test.exs`. First add `import Speechwave.TalksFixtures` near the top (alongside `import Speechwave.AccountsFixtures`), then add:

```elixir
  describe "talk_activity/1" do
    test "counts talks, talks with sessions, and sessions" do
      user = user_fixture()
      talk_with_session = talk_fixture(user)
      session_fixture(talk_with_session)
      _talk_without_session = talk_fixture(user)

      %{talks: talks, talks_with_sessions: with_sessions, sessions: sessions} =
        Stats.talk_activity()

      assert talks.current == 2
      assert with_sessions.current == 1
      assert sessions.current == 1
    end
  end

  describe "dashboard/1" do
    test "returns all 11 metrics in a fixed order" do
      user = user_fixture()
      talk = talk_fixture(user)
      session_fixture(talk)

      dashboard = Stats.dashboard()

      assert Enum.map(dashboard, fn {key, _} -> key end) == [
               :total_users,
               :confirmed,
               :unconfirmed,
               :onboarding,
               :suspicious,
               :pro_signups,
               :enterprise_signups,
               :total_signups,
               :talks,
               :talks_with_sessions,
               :sessions
             ]

      assert {_, %{current: _, history: _}} = List.keyfind(dashboard, :talks, 0)
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: FAIL — `Stats.talk_activity/0` and `Stats.dashboard/0` undefined.

- [ ] **Step 4: Implement `talk_activity/1` and `dashboard/1`**

In `lib/speechwave/admin/stats.ex`, add `alias Speechwave.Talks.{Talk, TalkSession}` after the `Accounts` alias line, then add after `notification_signups/1`:

```elixir
  @doc "Talk, talk-with-sessions, and session counts, current and 30-day history."
  def talk_activity(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    cutoff = DateTime.add(now, -@history_days, :day)
    days = last_n_days(now, @history_days)

    talks_current = Repo.aggregate(Talk, :count)
    sessions_current = Repo.aggregate(TalkSession, :count)

    talks_with_sessions_current =
      Repo.aggregate(
        from(t in Talk,
          as: :talk,
          where: exists(from(s in TalkSession, where: s.talk_id == parent_as(:talk).id, select: 1))
        ),
        :count
      )

    recent_talks = Repo.all(from(t in Talk, where: t.inserted_at >= ^cutoff, select: t.inserted_at))
    recent_sessions = Repo.all(from(s in TalkSession, where: s.inserted_at >= ^cutoff, select: s.inserted_at))

    recent_first_sessions =
      Repo.all(
        from s in TalkSession,
          group_by: s.talk_id,
          having: min(s.inserted_at) >= ^cutoff,
          select: min(s.inserted_at)
      )

    talks_history = history_from_baseline(talks_current, recent_talks, days)
    sessions_history = history_from_baseline(sessions_current, recent_sessions, days)

    talks_with_sessions_history =
      history_from_baseline(talks_with_sessions_current, recent_first_sessions, days)

    %{
      talks: metric(talks_history),
      talks_with_sessions: metric(talks_with_sessions_history),
      sessions: metric(sessions_history)
    }
  end

  @metric_order [
    :total_users,
    :confirmed,
    :unconfirmed,
    :onboarding,
    :suspicious,
    :pro_signups,
    :enterprise_signups,
    :total_signups,
    :talks,
    :talks_with_sessions,
    :sessions
  ]

  @doc "All 11 dashboard metrics, in display order, as `[{key, metric}, ...]`."
  def dashboard(now \\ DateTime.utc_now()) do
    metrics =
      user_categories(now)
      |> Map.merge(notification_signups(now))
      |> Map.merge(talk_activity(now))

    Enum.map(@metric_order, fn key -> {key, Map.fetch!(metrics, key)} end)
  end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: PASS (8 tests, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/admin/stats.ex test/support/fixtures/talks_fixtures.ex \
  test/speechwave/admin/stats_test.exs
git commit -m "feat: add talk/session activity stats and combined dashboard query"
```

---

### Task 6: Wire all 11 metrics into `StatsLive` as stat cards (no charts yet)

**Files:**
- Create: `lib/speechwave_web/components/admin_components.ex`
- Modify: `lib/speechwave_web/live/admin/stats_live.ex`
- Modify: `lib/speechwave_web/live/admin/stats_live.html.heex`
- Modify: `test/speechwave_web/live/admin/stats_live_test.exs`

**Interfaces:**
- Consumes: `Speechwave.Admin.Stats.dashboard/1` (Task 5).
- Produces: `SpeechwaveWeb.AdminComponents.admin_stat_card/1` function component — `id`, `title`, `current` required attrs; `chart_svg` optional (wired up in Task 7).

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave_web/live/admin/stats_live_test.exs`, replacing the body of the `"admin users can view the page"` test:

```elixir
  test "admin users see all 11 stat cards with correct current values", %{conn: conn} do
    admin = admin_user_fixture()

    talk = Speechwave.TalksFixtures.talk_fixture(admin)
    Speechwave.TalksFixtures.session_fixture(talk)

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    for id <- ~w(
          stat-total-users stat-confirmed stat-unconfirmed stat-onboarding
          stat-suspicious stat-pro-signups stat-enterprise-signups
          stat-total-signups stat-talks stat-talks-with-sessions stat-sessions
        ) do
      assert has_element?(view, "##{id}"), "expected ##{id} to be rendered"
    end

    assert has_element?(view, "#stat-talks", "1")
    assert has_element?(view, "#stat-confirmed", "1")
  end
```

Remove the now-redundant simpler `"admin users can view the page"` assertion (it's superseded by this test) so the file doesn't test the same mount twice — the file should end up with 3 tests total: logged-out redirect, non-admin redirect, and this one.

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/speechwave_web/live/admin/stats_live_test.exs`
Expected: FAIL — none of the `#stat-*` ids exist yet.

- [ ] **Step 3: Create the stat card component**

Create `lib/speechwave_web/components/admin_components.ex`:

```elixir
defmodule SpeechwaveWeb.AdminComponents do
  @moduledoc """
  Function components for the super-admin stats dashboard.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :current, :integer, required: true
  attr :chart_svg, :any, default: nil

  def admin_stat_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-2xl border border-hairline bg-surface p-5">
      <div class="text-sm text-steel">{@title}</div>
      <div class="mt-1 text-3xl font-semibold text-ink">{@current}</div>
      <div :if={@chart_svg} class="mt-3">{@chart_svg}</div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Wire metrics into the LiveView**

Replace `lib/speechwave_web/live/admin/stats_live.ex` entirely:

```elixir
defmodule SpeechwaveWeb.Admin.StatsLive do
  use SpeechwaveWeb, :live_view

  import SpeechwaveWeb.AdminComponents

  alias Speechwave.Admin.Stats

  @titles %{
    total_users: "Total Users",
    confirmed: "Confirmed Users",
    unconfirmed: "Unconfirmed Users",
    onboarding: "Onboarding Users",
    suspicious: "Suspicious Users",
    pro_signups: "Pro Notify Signups",
    enterprise_signups: "Enterprise Notify Signups",
    total_signups: "Total Notify Signups",
    talks: "Talks",
    talks_with_sessions: "Talks With Sessions",
    sessions: "Sessions"
  }

  def mount(_params, _session, socket) do
    {:ok, assign(socket, stats: Stats.dashboard())}
  end

  defp title_for(key), do: Map.fetch!(@titles, key)

  defp dom_id(key), do: "stat-#{key |> to_string() |> String.replace("_", "-")}"
end
```

Replace `lib/speechwave_web/live/admin/stats_live.html.heex` entirely:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <h1 class="text-2xl font-bold text-ink mb-6">Admin Stats</h1>
  <div id="admin-stats-grid" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
    <.admin_stat_card
      :for={{key, stat} <- @stats}
      id={dom_id(key)}
      title={title_for(key)}
      current={stat.current}
    />
  </div>
</Layouts.app>
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/speechwave_web/live/admin/stats_live_test.exs`
Expected: PASS (3 tests, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave_web/components/admin_components.ex \
  lib/speechwave_web/live/admin/stats_live.ex \
  lib/speechwave_web/live/admin/stats_live.html.heex \
  test/speechwave_web/live/admin/stats_live_test.exs
git commit -m "feat: render all 11 stat cards on the admin stats dashboard"
```

---

### Task 7: Add Contex and render 30-day trend charts

**Files:**
- Modify: `mix.exs`
- Create: `lib/speechwave/admin/chart.ex`
- Create: `test/speechwave/admin/chart_test.exs`
- Modify: `lib/speechwave_web/live/admin/stats_live.ex`
- Modify: `test/speechwave_web/live/admin/stats_live_test.exs`

**Interfaces:**
- Produces: `Speechwave.Admin.Chart.render_svg(history, opts \\ [])` — takes a `[{Date.t(), integer}]` history list, returns Contex's SVG output (safe for direct HEEx interpolation).

- [ ] **Step 1: Add the Contex dependency**

In `mix.exs`, add to the `deps` list (after `{:eqrcode, "~> 0.2"},`):

```elixir
      {:contex, "~> 0.5"},
```

Run: `mix deps.get`
Expected: Contex fetched successfully.

- [ ] **Step 2: Write the failing test**

Create `test/speechwave/admin/chart_test.exs`:

```elixir
defmodule Speechwave.Admin.ChartTest do
  use ExUnit.Case, async: true

  alias Speechwave.Admin.Chart

  test "renders a 30-day history as an SVG line chart" do
    history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), 30 - i}

    svg = Chart.render_svg(history)
    html = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    assert html =~ "<svg"
  end

  test "renders a flat history (all-zero counts) without raising" do
    history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), 0}

    svg = Chart.render_svg(history)
    html = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    assert html =~ "<svg"
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `mix test test/speechwave/admin/chart_test.exs`
Expected: FAIL — `Speechwave.Admin.Chart` module not defined.

- [ ] **Step 4: Implement the chart renderer**

Create `lib/speechwave/admin/chart.ex`:

```elixir
defmodule Speechwave.Admin.Chart do
  @moduledoc """
  Renders a stat's 30-day history as a server-side SVG line chart via
  Contex — no JS dependency, consistent with the project's SSR-first
  LiveView style.
  """

  alias Contex.{Dataset, LinePlot, Plot}

  @doc "Renders `history` (a list of `{Date.t(), integer}`, oldest first) as an SVG line chart."
  def render_svg(history, opts \\ []) do
    width = Keyword.get(opts, :width, 240)
    height = Keyword.get(opts, :height, 60)

    data =
      Enum.map(history, fn {date, count} ->
        {NaiveDateTime.new!(date, ~T[00:00:00]), count}
      end)

    dataset = Dataset.new(data, [:date, :count])

    dataset
    |> Plot.new(LinePlot, width, height, mapping: %{x_col: :date, y_cols: [:count]})
    |> Plot.to_svg()
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/speechwave/admin/chart_test.exs`
Expected: PASS (2 tests, 0 failures). If Contex's actual API differs from the signatures above (e.g. `Plot.to_svg/1` return shape), consult `mix hex.docs open contex` and adjust `render_svg/2` — the test's `<svg` assertion is what defines correctness here, not the exact internal call shape.

- [ ] **Step 6: Wire charts into the dashboard**

In `lib/speechwave_web/live/admin/stats_live.ex`, change the `mount/3` function to:

```elixir
  def mount(_params, _session, socket) do
    stats =
      Enum.map(Stats.dashboard(), fn {key, stat} ->
        {key, Map.put(stat, :chart_svg, Speechwave.Admin.Chart.render_svg(stat.history))}
      end)

    {:ok, assign(socket, stats: stats)}
  end
```

In `lib/speechwave_web/live/admin/stats_live.html.heex`, add the `chart_svg` attr to `<.admin_stat_card>`:

```heex
    <.admin_stat_card
      :for={{key, stat} <- @stats}
      id={dom_id(key)}
      title={title_for(key)}
      current={stat.current}
      chart_svg={stat.chart_svg}
    />
```

- [ ] **Step 7: Add a LiveView test asserting charts render**

Add to `test/speechwave_web/live/admin/stats_live_test.exs`:

```elixir
  test "each stat card renders an SVG trend chart", %{conn: conn} do
    admin = admin_user_fixture()
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert view
           |> element("#stat-total-users")
           |> render() =~ "<svg"
  end
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `mix test test/speechwave_web/live/admin/stats_live_test.exs test/speechwave/admin/chart_test.exs`
Expected: PASS (all tests, 0 failures)

- [ ] **Step 9: Commit**

```bash
git add mix.exs mix.lock lib/speechwave/admin/chart.ex test/speechwave/admin/chart_test.exs \
  lib/speechwave_web/live/admin/stats_live.ex \
  test/speechwave_web/live/admin/stats_live_test.exs
git commit -m "feat: render 30-day trend charts on the admin stats dashboard"
```

---

### Task 8: Admin nav link

**Files:**
- Modify: `lib/speechwave_web/components/layouts.ex`
- Modify: `test/speechwave_web/live/dashboard_live_test.exs`
- Modify: `test/speechwave_web/live/admin/stats_live_test.exs`

**Interfaces:**
- Produces: an `#admin-nav-link` anchor in the authenticated `Layouts.app` header, visible only when `@current_scope.user.is_admin`.

- [ ] **Step 1: Write the failing tests**

Add to `test/speechwave_web/live/dashboard_live_test.exs` (inside the top-level test list, using the existing `setup` block's non-admin `conn`):

```elixir
  test "does not show an Admin nav link for non-admin users", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard")
    refute has_element?(view, "#admin-nav-link")
  end
```

Add to `test/speechwave_web/live/admin/stats_live_test.exs`:

```elixir
  test "shows an Admin nav link for admin users", %{conn: conn} do
    admin = admin_user_fixture()
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/stats")
    assert has_element?(view, "#admin-nav-link")
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/speechwave_web/live/dashboard_live_test.exs test/speechwave_web/live/admin/stats_live_test.exs`
Expected: The new "shows an Admin nav link" test FAILs (no such element yet). The "does not show" test passes trivially since the element doesn't exist anywhere yet — that's expected; it'll start meaningfully guarding behavior once Step 3 adds the link.

- [ ] **Step 3: Add the nav link**

In `lib/speechwave_web/components/layouts.ex`, in the `app/1` function's authenticated header block (inside `<%= if @current_scope do %>`, around line 55-58), add the admin link after the Settings link and before the Help link:

```heex
            <a href={~p"/users/settings"} class="text-steel hover:text-ink transition-colors">
              Settings
            </a>
            <a
              :if={@current_scope.user.is_admin}
              id="admin-nav-link"
              href={~p"/admin/stats"}
              class="text-steel hover:text-ink transition-colors"
            >
              Admin
            </a>
            <a
              id="help-nav-link"
              href="https://docs.speechwave.live"
              target="_blank"
              rel="noopener noreferrer"
              class="text-steel hover:text-ink transition-colors"
            >
              Help
            </a>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/speechwave_web/live/dashboard_live_test.exs test/speechwave_web/live/admin/stats_live_test.exs`
Expected: PASS (all tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/components/layouts.ex \
  test/speechwave_web/live/dashboard_live_test.exs \
  test/speechwave_web/live/admin/stats_live_test.exs
git commit -m "feat: show an Admin nav link to admin users"
```

---

## Final verification

After all 8 tasks are committed, run the full project check per `CLAUDE.md`:

```bash
mix precommit
```

This runs `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, the full test suite, `credo --strict --all`, and `dialyzer`. Fix anything it surfaces before considering this feature done.
