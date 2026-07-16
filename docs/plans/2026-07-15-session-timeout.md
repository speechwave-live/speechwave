# Session Timeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure a `TalkSession` never stays "active" (`ended_at: nil`) indefinitely — an explicit "start" always begins a fresh session, and a periodic sweep closes sessions abandoned without an explicit stop.

**Architecture:** Two independent mechanisms, both living in the existing `Speechwave.Talks` context:
1. `Talks.start_session/1` changes from "reuse the active session if one exists" to "always close any existing active session and create a new one." This is the interactive path — triggered only by the extension popup's "Start Session" button — and fixes the reported friction where the next day's start silently resumed yesterday's abandoned session.
2. `Talks.close_stale_sessions/0`, run periodically by a new `Speechwave.Talks.SessionReaper` GenServer, closes any session left open past a configurable timeout (default 4 hours) regardless of whether anyone ever explicitly restarts that talk. This is the backstop — it's what makes `count_full_sessions_this_month/1` (which only counts sessions with `ended_at` set) eventually count abandoned sessions instead of letting them dodge the free-tier limit forever.

These two mechanisms were investigated to not conflict: the browser extension's reconnect logic (`chrome-extension/background/background.js`) only rejoins the Phoenix channel on reconnects — it never re-pushes `start_session` — so switching `start_session` to always-fresh cannot regress reconnect behavior.

**Tech Stack:** Elixir, Phoenix, Ecto (SQLite via `ecto_sqlite3`), ExUnit. No new dependencies.

## Global Constraints

- Default session timeout: 4 hours, configurable via `config :speechwave, :session_timeout_hours` (no env var override needed yet — a compile-time default is sufficient).
- Default sweep interval: 15 minutes, hardcoded as a module attribute (not config — no requirement to tune this without a deploy).
- No new dependencies (no Oban/Quantum) — a plain GenServer with `Process.send_after/3`, matching the existing `Speechwave.RateLimiter` / `Speechwave.AuthThrottle` pattern in `lib/speechwave/application.ex`.
- Follow this project's Ecto/GenServer/test conventions exactly (see `CLAUDE.md`): `start_supervised!/1` in tests, no `Process.sleep/1`, synchronize on messages via `:sys.get_state/1` or by sending the message yourself and then calling the process synchronously.
- Run `mix precommit` at the end and fix any issues before considering the work done.

---

## Task 1: `Talks.start_session/1` always creates a fresh session

**Files:**
- Modify: `lib/speechwave/talks.ex:57-72` (the `start_session/1` function)
- Modify: `test/speechwave/talks_test.exs` (new `describe "start_session/1"` block)
- Modify: `test/speechwave_web/channels/reaction_channel_test.exs:70-76` (existing test asserts the *old* reuse behavior and must be updated or it will fail after this change)

**Interfaces:**
- Consumes: `Talks.get_active_session/1` (existing, unchanged), `Talks.stop_session/1` (existing, unchanged — sets `ended_at` to `DateTime.utc_now()`), `Talks.TalkSession.changeset/2` (existing, unchanged).
- Produces: `Talks.start_session/1` — same signature and `{:ok, %TalkSession{}} | {:error, changeset}` return shape as before, but now **always** returns a newly-inserted session; if one was already active for that talk, it is closed (`ended_at` set to now) as a side effect before the new one is created.

- [ ] **Step 1: Write the new/updated tests in `talks_test.exs`**

Add this `describe` block (e.g. right after the existing `describe "count_full_sessions_this_month/1"` block, before the final `end` of the module):

```elixir
  describe "start_session/1" do
    test "creates a new session when none is active" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "start-fresh"})

      assert {:ok, session} = Talks.start_session(talk)
      assert session.label == "Session 1"
      assert session.ended_at == nil
    end

    test "closes an existing active session, even a recent one, and starts a new one" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "start-replace"})

      {:ok, first} = Talks.start_session(talk)
      {:ok, second} = Talks.start_session(talk)

      refute first.id == second.id
      assert Talks.get_session(first.id).ended_at != nil
      assert second.label == "Session 2"
      assert second.ended_at == nil
    end
  end
```

- [ ] **Step 2: Run the tests to confirm the second one fails against current behavior**

Run: `mix test test/speechwave/talks_test.exs`
Expected: `creates a new session when none is active` PASSES (existing code already does this correctly). `closes an existing active session...` FAILS on `refute first.id == second.id` because current `start_session/1` returns the same existing session both times.

- [ ] **Step 3: Update `start_session/1` in `lib/speechwave/talks.ex`**

Replace the current implementation (lines 57-72):

```elixir
  def start_session(%Talk{} = talk) do
    case get_active_session(talk.id) do
      nil ->
        n = count_sessions(talk.id)

        %TalkSession{talk_id: talk.id}
        |> TalkSession.changeset(%{
          label: "Session #{n + 1}",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end
```

with:

```elixir
  def start_session(%Talk{} = talk) do
    case get_active_session(talk.id) do
      nil ->
        insert_session(talk)

      existing ->
        {:ok, _} = stop_session(existing)
        insert_session(talk)
    end
  end
```

Then add the extracted private helper in the `# Private` section at the bottom of the module (near `defp count_sessions/1`):

```elixir
  defp insert_session(talk) do
    n = count_sessions(talk.id)

    %TalkSession{talk_id: talk.id}
    |> TalkSession.changeset(%{
      label: "Session #{n + 1}",
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end
```

- [ ] **Step 4: Run the tests to confirm both pass**

Run: `mix test test/speechwave/talks_test.exs`
Expected: PASS (all tests in the file, including both new ones)

- [ ] **Step 5: Update the pre-existing channel-level test that asserted the old reuse behavior**

In `test/speechwave_web/channels/reaction_channel_test.exs`, replace lines 70-76:

```elixir
    test "start_session is idempotent when a session is already active", %{joined: joined} do
      ref1 = push(joined, "start_session", %{})
      assert_reply ref1, :ok, %{session_id: id1}
      ref2 = push(joined, "start_session", %{})
      assert_reply ref2, :ok, %{session_id: id2}
      assert id1 == id2
    end
```

with:

```elixir
    test "start_session always creates a fresh session, closing any prior active one", %{
      joined: joined
    } do
      ref1 = push(joined, "start_session", %{})
      assert_reply ref1, :ok, %{session_id: id1}
      ref2 = push(joined, "start_session", %{})
      assert_reply ref2, :ok, %{session_id: id2}
      refute id1 == id2
      assert Speechwave.Talks.get_session(id1).ended_at != nil
    end
```

- [ ] **Step 6: Run the full channel test file to confirm it passes**

Run: `mix test test/speechwave_web/channels/reaction_channel_test.exs`
Expected: PASS (all tests)

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave/talks.ex test/speechwave/talks_test.exs test/speechwave_web/channels/reaction_channel_test.exs
git commit -m "fix: always start a fresh talk session, closing any prior active one"
```

---

## Task 2: `Talks.close_stale_sessions/0` and the timeout config

**Files:**
- Modify: `config/config.exs:49` (add the new config key right after the existing `:auth_throttle_enabled` line)
- Modify: `lib/speechwave/talks.ex` (add `close_stale_sessions/0`)
- Modify: `test/speechwave/talks_test.exs` (new `describe "close_stale_sessions/0"` block)

**Interfaces:**
- Consumes: `TalkSession` schema, `Repo`, `import Ecto.Query` (all already present in `talks.ex`), the `:speechwave, :session_timeout_hours` config key added in this task.
- Produces: `Talks.close_stale_sessions/0` — arity 0, no return value relied on by callers (used for its side effect), closes every session with `ended_at: nil` and `started_at` older than `session_timeout_hours` (config, default 4), setting `ended_at` to `started_at` plus the timeout — not to the current time — so a session's recorded duration reflects the timeout window itself rather than sweep-cycle lag.

- [ ] **Step 1: Add the config key**

In `config/config.exs`, right after line 49 (`config :speechwave, :auth_throttle_enabled, true`), add:

```elixir
# Sessions left open (never explicitly stopped) are closed automatically
# after this many hours. See docs/plans/2026-07-15-session-timeout.md.
config :speechwave, :session_timeout_hours, 4
```

- [ ] **Step 2: Write the failing tests in `talks_test.exs`**

Add this `describe` block after the `describe "start_session/1"` block added in Task 1:

```elixir
  describe "close_stale_sessions/0" do
    test "closes a session older than the configured timeout" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "stale-old"})

      timeout_hours = Application.get_env(:speechwave, :session_timeout_hours, 4)

      old_start =
        DateTime.utc_now()
        |> DateTime.add(-(timeout_hours + 1) * 3600, :second)
        |> DateTime.truncate(:second)

      session = session_fixture(talk, %{started_at: old_start})

      Talks.close_stale_sessions()

      closed = Talks.get_session(session.id)
      assert closed.ended_at != nil
      assert DateTime.diff(closed.ended_at, old_start, :second) == timeout_hours * 3600
    end

    test "leaves a session within the timeout untouched" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "stale-fresh"})

      session = session_fixture(talk, %{started_at: DateTime.utc_now() |> DateTime.truncate(:second)})

      Talks.close_stale_sessions()

      assert Talks.get_session(session.id).ended_at == nil
    end

    test "leaves an already-ended session untouched" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "stale-ended"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old_start = DateTime.add(now, -10 * 3600, :second)
      session = session_fixture(talk, %{started_at: old_start, ended_at: now})

      Talks.close_stale_sessions()

      assert Talks.get_session(session.id).ended_at == now
    end
  end
```

`test/speechwave/talks_test.exs` currently only has `import Speechwave.AccountsFixtures` (line 8) — it does not yet import `Speechwave.TalksFixtures`, which is where `session_fixture/2` lives. Add this line directly below it:

```elixir
  import Speechwave.TalksFixtures
```

- [ ] **Step 3: Run the tests to confirm they fail**

Run: `mix test test/speechwave/talks_test.exs`
Expected: FAIL with `undefined function close_stale_sessions/0` (or similar `UndefinedFunctionError`) for all three new tests.

- [ ] **Step 4: Implement `close_stale_sessions/0` in `lib/speechwave/talks.ex`**

Add this function in the `# Sessions` section, after `delete_session/1` and before `count_full_sessions_this_month/1`:

```elixir
  @doc """
  Closes any session left open past `:session_timeout_hours` (config,
  default 4). `ended_at` is set to the moment the session actually timed
  out (`started_at` plus the timeout), not to the time this sweep ran, so
  recorded duration reflects the timeout window rather than sweep-cycle lag.
  Called periodically by `Speechwave.Talks.SessionReaper`.
  """
  def close_stale_sessions do
    timeout_hours = Application.get_env(:speechwave, :session_timeout_hours, 4)
    cutoff = DateTime.add(DateTime.utc_now(), -timeout_hours * 3600, :second)

    from(s in TalkSession, where: is_nil(s.ended_at) and s.started_at < ^cutoff)
    |> Repo.all()
    |> Enum.each(fn session ->
      expired_at = DateTime.add(session.started_at, timeout_hours * 3600, :second)

      session
      |> TalkSession.changeset(%{ended_at: expired_at})
      |> Repo.update()
    end)

    :ok
  end
```

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `mix test test/speechwave/talks_test.exs`
Expected: PASS (all tests in the file)

- [ ] **Step 6: Commit**

```bash
git add config/config.exs lib/speechwave/talks.ex test/speechwave/talks_test.exs
git commit -m "feat: add Talks.close_stale_sessions/0 and session_timeout_hours config"
```

---

## Task 3: `Speechwave.Talks.SessionReaper` — periodic sweep GenServer

**Files:**
- Create: `lib/speechwave/talks/session_reaper.ex`
- Modify: `lib/speechwave/application.ex` (add to the supervision tree)
- Create: `test/speechwave/talks/session_reaper_test.exs`

**Interfaces:**
- Consumes: `Talks.close_stale_sessions/0` (Task 2).
- Produces: `Speechwave.Talks.SessionReaper.start_link/1`, accepting an optional keyword list (`:name`, defaulting to `__MODULE__`; `:sweep_interval` in ms, defaulting to 15 minutes). Started with no args as part of `Speechwave.Application`'s permanent supervision tree. Exposes `handle_call(:sweep_now, ...)` as a synchronous test hook that runs a sweep immediately and replies `:ok` once it's done — this is how tests observe the sweep without waiting on the internal timer.

- [ ] **Step 1: Write the failing tests in `test/speechwave/talks/session_reaper_test.exs`**

```elixir
defmodule Speechwave.Talks.SessionReaperTest do
  use Speechwave.DataCase, async: true

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Accounts.Scope
  alias Speechwave.Talks
  alias Speechwave.Talks.SessionReaper

  defp scope(user), do: %Scope{user: user}

  defp start_reaper!(opts \\ []) do
    pid = start_supervised!({SessionReaper, Keyword.merge([name: nil, sweep_interval: :timer.hours(1)], opts)})
    Ecto.Adapters.SQL.Sandbox.allow(Speechwave.Repo, self(), pid)
    pid
  end

  defp old_start(timeout_hours) do
    DateTime.utc_now()
    |> DateTime.add(-(timeout_hours + 1) * 3600, :second)
    |> DateTime.truncate(:second)
  end

  test ":sweep_now closes a session older than the configured timeout" do
    user = user_fixture()
    {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "reaper-old"})

    timeout_hours = Application.get_env(:speechwave, :session_timeout_hours, 4)
    session = session_fixture(talk, %{started_at: old_start(timeout_hours)})

    pid = start_reaper!()
    :ok = GenServer.call(pid, :sweep_now)

    assert Talks.get_session(session.id).ended_at != nil
  end

  test ":sweep_now leaves a session within the timeout untouched" do
    user = user_fixture()
    {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "reaper-fresh"})

    session = session_fixture(talk, %{started_at: DateTime.utc_now() |> DateTime.truncate(:second)})

    pid = start_reaper!()
    :ok = GenServer.call(pid, :sweep_now)

    assert Talks.get_session(session.id).ended_at == nil
  end

  test "processes an internal :sweep message by closing stale sessions" do
    user = user_fixture()
    {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "reaper-sweep-msg"})

    timeout_hours = Application.get_env(:speechwave, :session_timeout_hours, 4)
    session = session_fixture(talk, %{started_at: old_start(timeout_hours)})

    pid = start_reaper!()
    send(pid, :sweep)
    # :sys.get_state/1 blocks until pid has finished processing every message
    # already in its mailbox, including the :sweep we just sent — no sleep needed.
    _ = :sys.get_state(pid)

    assert Talks.get_session(session.id).ended_at != nil
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `mix test test/speechwave/talks/session_reaper_test.exs`
Expected: FAIL to compile — `Speechwave.Talks.SessionReaper` doesn't exist yet.

- [ ] **Step 3: Implement `lib/speechwave/talks/session_reaper.ex`**

```elixir
defmodule Speechwave.Talks.SessionReaper do
  @moduledoc false
  # Periodically closes TalkSessions that were never explicitly stopped
  # (extension crash, laptop closed, network drop) so a session never stays
  # "active" forever. This is the backstop for Talks.start_session/1's
  # always-fresh behavior: it catches sessions on talks nobody ever
  # explicitly restarts, so they eventually count toward the monthly
  # full-session limit instead of hiding from it indefinitely.
  use GenServer

  @sweep_interval :timer.minutes(15)

  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :sweep_interval, @sweep_interval)
    schedule_sweep(interval)
    {:ok, %{sweep_interval: interval}}
  end

  @impl true
  def handle_info(:sweep, state) do
    Speechwave.Talks.close_stale_sessions()
    schedule_sweep(state.sweep_interval)
    {:noreply, state}
  end

  # Synchronous test hook — runs a sweep immediately and replies only once
  # it's done, so tests don't need to wait on the internal timer.
  @impl true
  def handle_call(:sweep_now, _from, state) do
    Speechwave.Talks.close_stale_sessions()
    {:reply, :ok, state}
  end

  defp schedule_sweep(ms), do: Process.send_after(self(), :sweep, ms)
end
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `mix test test/speechwave/talks/session_reaper_test.exs`
Expected: PASS (all three tests)

- [ ] **Step 5: Wire `SessionReaper` into the supervision tree**

In `lib/speechwave/application.ex`, modify the `children` list:

```elixir
    children =
      [
        SpeechwaveWeb.Telemetry,
        Speechwave.Repo,
        {DNSCluster, query: Application.get_env(:speechwave, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Speechwave.PubSub},
        Speechwave.RateLimiter,
        Speechwave.AuthThrottle,
        Speechwave.Talks.SessionReaper,
        SpeechwaveWeb.Endpoint,
        SpeechwaveWeb.Presence
      ] ++ backup_children()
```

(`Speechwave.Repo` is already listed before this point, so the reaper can safely query the database as soon as it starts.)

- [ ] **Step 6: Run the full test suite and `mix precommit`**

Run: `mix precommit`
Expected: compiles with `--warnings-as-errors`, `deps.unlock --unused` finds nothing to unlock, `format` makes no changes (or run `mix format` first if it does), full test suite passes, `lint` passes. Fix anything that doesn't.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave/talks/session_reaper.ex lib/speechwave/application.ex test/speechwave/talks/session_reaper_test.exs
git commit -m "feat: add SessionReaper to close abandoned talk sessions after a timeout"
```
