# Magic Link Auth Throttle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add email- and IP-based throttling to the magic-link sign-in form (`UserLive.Login`) so it resists casual scripted abuse, per `docs/specs/2026-06-11-magic-link-auth-throttle-design.md`.

**Architecture:** A new `Speechwave.AuthThrottle` GenServer (mirroring `Speechwave.RateLimiter`) owns two `:public` ETS tables — a fixed 60s cooldown per email and an escalating cooldown (30s base, doubling to a 30-minute cap) per client IP. `UserLive.Login` derives the client IP from forwarded headers via the `remote_ip` package, checks both throttles before sending a magic link, and always shows the same "check your inbox" UI regardless of outcome. A config flag (`:auth_throttle_enabled`, `false` in `:test`) keeps existing LiveView tests unaffected.

**Tech Stack:** Elixir, Phoenix LiveView, ETS, `remote_ip` (new dependency)

---

## Implementation notes (read first)

A few small clarifications made while mapping the design doc to actual code — these aren't contradictions, just decisions needed to write exact code:

1. **Violation logging lives inside `AuthThrottle`, not `UserLive.Login`.** The `cooldown_ms`/`violation_count` values needed for the IP log line are computed right where the cooldown is bumped, inside `allow_ip?/1`. Rather than threading that data back out through a boolean return value, `allow_ip?/1` and `allow_email?/1` each log their own `Logger.warning` on a violation. `UserLive.Login` only logs the `:info` "missing client IP" case, which is its own concern (a header-configuration issue, not a throttle decision).
2. **`RemoteIp.from/1` only ever sees the `x-forwarded-for` header.** `get_connect_info(socket, :x_headers)` filters to headers whose name starts with `"x-"`, so Fly's `fly-client-ip` header (which doesn't start with `x-`) can never reach `RemoteIp.from/1` no matter what options are passed. `x-forwarded-for` is `remote_ip`'s default header to check, so no `:headers` option is needed at all.
3. **The integration test gets its own file**, `test/speechwave_web/live/user_live/login_auth_throttle_test.exs`, instead of an isolated `describe` block inside `login_test.exs`. ExUnit's `async` flag is set per-module via `use ... , async: ...`, not per-`describe`, and this test needs `async: false` (it temporarily flips a global `Application.put_env`).

## File Structure

- **`mix.exs`** — add `{:remote_ip, "~> 1.2"}`
- **`lib/speechwave/auth_throttle.ex`** (new) — `Speechwave.AuthThrottle` GenServer: two ETS tables, `allow_email?/1`, `allow_ip?/1`
- **`test/speechwave/auth_throttle_test.exs`** (new) — unit tests for both throttle functions
- **`lib/speechwave/application.ex`** — add `Speechwave.AuthThrottle` to the supervision tree
- **`config/config.exs`**, **`config/test.exs`** — `:auth_throttle_enabled` flag
- **`lib/speechwave_web/endpoint.ex`** — add `:x_headers` to the LiveView socket's `connect_info`
- **`lib/speechwave_web/live/user_live/login.ex`** — derive `client_ip` in `mount/3`; throttle checks in `handle_event("submit_magic", ...)`
- **`test/speechwave_web/live/user_live/login_auth_throttle_test.exs`** (new) — integration test with the flag temporarily enabled

---

## Task 1: Add the `remote_ip` dependency

**Files:**
- Modify: `mix.exs:75`

- [ ] **Step 1: Add the dependency**

In `mix.exs`, the deps list currently ends with:

```elixir
      {:eqrcode, "~> 0.2"}
    ]
```

Change it to:

```elixir
      {:eqrcode, "~> 0.2"},
      {:remote_ip, "~> 1.2"}
    ]
```

- [ ] **Step 2: Fetch the dependency**

Run: `mix deps.get`
Expected: output includes a line like `* Getting remote_ip (Hex package)` and ends without errors.

- [ ] **Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "chore: add remote_ip dependency for client IP detection"
```

---

## Task 2: `Speechwave.AuthThrottle` — email cooldown + supervision wiring

This task creates the `AuthThrottle` GenServer with both ETS tables and implements the email-cooldown half of its API (`allow_email?/1`). The IP half (`allow_ip?/1`) is added in Task 3 — the table for it is created here so Task 3 doesn't need to touch `init/1` again.

**Files:**
- Create: `lib/speechwave/auth_throttle.ex`
- Create: `test/speechwave/auth_throttle_test.exs`
- Modify: `lib/speechwave/application.ex:16`

- [ ] **Step 1: Write the failing tests**

Create `test/speechwave/auth_throttle_test.exs`:

```elixir
defmodule Speechwave.AuthThrottleTest do
  use ExUnit.Case, async: false

  alias Speechwave.AuthThrottle

  setup do
    :ets.delete_all_objects(:auth_throttle_email)
    :ets.delete_all_objects(:auth_throttle_ip)
    :ok
  end

  describe "allow_email?/1" do
    test "allows the first request for an unseen email" do
      assert AuthThrottle.allow_email?("new@example.com") == true
    end

    test "blocks a second request for the same email within 60 seconds" do
      assert AuthThrottle.allow_email?("repeat@example.com") == true
      assert AuthThrottle.allow_email?("repeat@example.com") == false
    end

    test "allows a request again once the cooldown has elapsed, with no escalation" do
      email = "expired@example.com"
      assert AuthThrottle.allow_email?(email) == true

      now = System.monotonic_time(:millisecond)
      :ets.insert(:auth_throttle_email, {email, now - 61_000})

      assert AuthThrottle.allow_email?(email) == true
      assert AuthThrottle.allow_email?(email) == false
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/speechwave/auth_throttle_test.exs`
Expected: FAIL — every test errors out of `setup` with something like:

```
** (ArgumentError) errors were found at the given arguments:

  * 1st argument: the table identifier does not refer to an existing ETS table
```

This is because `:auth_throttle_email` doesn't exist yet — neither the module nor its ETS tables exist.

- [ ] **Step 3: Create the `AuthThrottle` module**

Create `lib/speechwave/auth_throttle.ex`:

```elixir
defmodule Speechwave.AuthThrottle do
  @moduledoc """
  Throttles magic-link auth requests by email and by client IP, to slow
  casual scripted abuse of `UserLive.Login`'s `submit_magic` event.

  Two `:public` ETS tables, owned by this GenServer and recreated empty on
  restart (fail open, matching `Speechwave.RateLimiter`):

    * `:auth_throttle_email` — key: normalized email (trimmed + downcased),
      value: `last_sent_at` (monotonic ms). Fixed 60s cooldown, no
      escalation.
    * `:auth_throttle_ip` — key: client IP string, value:
      `{last_at, cooldown_ms, violation_count}`. Cooldown starts at 30s,
      doubles on each violation up to a 30-minute cap, and resets to the
      base cooldown on any allowed request. `violation_count` is carried
      for logging only — it does not influence the cooldown math.

  Both `allow_email?/1` and `allow_ip?/1` log a warning when they return
  `false`, so repeated-violation patterns are visible in logs.
  """

  use GenServer

  require Logger

  @email_table :auth_throttle_email
  @ip_table :auth_throttle_ip

  @email_cooldown_ms 60_000
  @ip_base_cooldown_ms 30_000
  @ip_max_cooldown_ms 1_800_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@email_table, [:named_table, :public, read_concurrency: true])
    :ets.new(@ip_table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  Returns `true` if a magic-link request for `email` is allowed, `false` if
  the same email was sent a link within the last 60 seconds. `email` should
  already be normalized (trimmed + downcased) by the caller.
  """
  def allow_email?(email) when is_binary(email) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@email_table, email) do
      [{^email, last_sent_at}] when now - last_sent_at < @email_cooldown_ms ->
        Logger.warning("auth_throttle: email cooldown", email_domain: email_domain(email))
        false

      _ ->
        :ets.insert(@email_table, {email, now})
        true
    end
  end

  defp email_domain(email) do
    case String.split(email, "@") do
      [_local, domain] -> domain
      _ -> "unknown"
    end
  end
end
```

- [ ] **Step 4: Add `AuthThrottle` to the supervision tree**

In `lib/speechwave/application.ex`, the children list currently includes:

```elixir
        Speechwave.RateLimiter,
        SpeechwaveWeb.Endpoint,
```

Change it to:

```elixir
        Speechwave.RateLimiter,
        Speechwave.AuthThrottle,
        SpeechwaveWeb.Endpoint,
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/speechwave/auth_throttle_test.exs`
Expected: `3 tests, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave/auth_throttle.ex lib/speechwave/application.ex test/speechwave/auth_throttle_test.exs
git commit -m "feat: add AuthThrottle GenServer with email cooldown"
```

---

## Task 3: `Speechwave.AuthThrottle` — IP escalating cooldown

**Files:**
- Modify: `lib/speechwave/auth_throttle.ex`
- Modify: `test/speechwave/auth_throttle_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/speechwave/auth_throttle_test.exs`, after the `allow_email?/1` describe block (still inside `defmodule ... do ... end`):

```elixir
  describe "allow_ip?/1" do
    test "allows the first request for an unseen ip" do
      assert AuthThrottle.allow_ip?("203.0.113.10") == true
    end

    test "allows different ips independently" do
      assert AuthThrottle.allow_ip?("203.0.113.11") == true
      assert AuthThrottle.allow_ip?("203.0.113.12") == true
    end

    test "escalates the cooldown on repeated violations, then resets after a long gap" do
      ip = "203.0.113.20"

      # Call 1: no entry yet -> allowed, seeds the base cooldown
      assert AuthThrottle.allow_ip?(ip) == true
      assert [{^ip, _last_at, 30_000, 0}] = :ets.lookup(:auth_throttle_ip, ip)

      # Call 2: 5s later, inside the 30s cooldown -> blocked, cooldown doubles
      backdate_ip(ip, 5_000)
      assert AuthThrottle.allow_ip?(ip) == false
      assert [{^ip, _last_at, 60_000, 1}] = :ets.lookup(:auth_throttle_ip, ip)

      # Call 3: 5s later, inside the 60s cooldown -> blocked, cooldown doubles again
      backdate_ip(ip, 5_000)
      assert AuthThrottle.allow_ip?(ip) == false
      assert [{^ip, _last_at, 120_000, 2}] = :ets.lookup(:auth_throttle_ip, ip)

      # Call 4: 125s later, past the 120s cooldown -> allowed, resets to base
      backdate_ip(ip, 125_000)
      assert AuthThrottle.allow_ip?(ip) == true
      assert [{^ip, _last_at, 30_000, 0}] = :ets.lookup(:auth_throttle_ip, ip)
    end

    test "caps the cooldown at 30 minutes" do
      ip = "203.0.113.30"
      now = System.monotonic_time(:millisecond)

      # Seed an entry already at the cap, just violated
      :ets.insert(:auth_throttle_ip, {ip, now, 1_800_000, 10})

      assert AuthThrottle.allow_ip?(ip) == false
      assert [{^ip, _last_at, 1_800_000, 11}] = :ets.lookup(:auth_throttle_ip, ip)
    end
  end

  defp backdate_ip(ip, ms_ago) do
    [{^ip, _last_at, cooldown_ms, violation_count}] = :ets.lookup(:auth_throttle_ip, ip)
    now = System.monotonic_time(:millisecond)
    :ets.insert(:auth_throttle_ip, {ip, now - ms_ago, cooldown_ms, violation_count})
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/speechwave/auth_throttle_test.exs`
Expected: FAIL — the 4 new tests fail with `** (UndefinedFunctionError) function Speechwave.AuthThrottle.allow_ip?/1 is undefined or private`. The 3 email tests from Task 2 still pass.

- [ ] **Step 3: Implement `allow_ip?/1`**

In `lib/speechwave/auth_throttle.ex`, add after `allow_email?/1` (before the `defp email_domain` helper, or after it — placement among top-level defs doesn't matter, but keep `defp` helpers near the bottom):

```elixir
  @doc """
  Returns `true` if a magic-link request from `ip` is allowed, `false` if
  `ip` is still within its cooldown window. Every call updates `last_at`;
  a violation doubles the cooldown (capped at 30 minutes) and increments
  `violation_count`, while an allowed request resets both to their base
  values.
  """
  def allow_ip?(ip) when is_binary(ip) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@ip_table, ip) do
      [{^ip, last_at, cooldown_ms, violation_count}] when now - last_at < cooldown_ms ->
        {new_cooldown_ms, new_violation_count} = bump_cooldown(cooldown_ms, violation_count)
        :ets.insert(@ip_table, {ip, now, new_cooldown_ms, new_violation_count})

        Logger.warning("auth_throttle: ip cooldown",
          ip: ip,
          cooldown_ms: new_cooldown_ms,
          violation_count: new_violation_count
        )

        false

      _ ->
        :ets.insert(@ip_table, {ip, now, @ip_base_cooldown_ms, 0})
        true
    end
  end

  defp bump_cooldown(cooldown_ms, violation_count) do
    {min(cooldown_ms * 2, @ip_max_cooldown_ms), violation_count + 1}
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/speechwave/auth_throttle_test.exs`
Expected: `7 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave/auth_throttle.ex test/speechwave/auth_throttle_test.exs
git commit -m "feat: add escalating IP cooldown to AuthThrottle"
```

---

## Task 4: Add the `:auth_throttle_enabled` config flag

**Files:**
- Modify: `config/config.exs`
- Modify: `config/test.exs`

- [ ] **Step 1: Add the default (enabled) config**

In `config/config.exs`, after the mailer config block:

```elixir
config :speechwave, Speechwave.Mailer, adapter: Swoosh.Adapters.Local
```

add:

```elixir

# Throttles UserLive.Login's magic-link submissions by email and client IP.
# See docs/specs/2026-06-11-magic-link-auth-throttle-design.md.
config :speechwave, :auth_throttle_enabled, true
```

- [ ] **Step 2: Make `AuthThrottle`'s log metadata visible in output**

`AuthThrottle.allow_email?/1` and `allow_ip?/1` (Tasks 2-3) call
`Logger.warning/2` with extra metadata (`ip:`, `cooldown_ms:`,
`violation_count:`, `email_domain:`). The default formatter's `metadata:`
option is an *allowlist* — keys not listed are silently dropped from
formatted output. Currently only `:request_id` is listed, so none of
`AuthThrottle`'s violation details would actually appear in logs.

In `config/config.exs`, change:

```elixir
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
```

to:

```elixir
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :ip, :cooldown_ms, :violation_count, :email_domain]
```

- [ ] **Step 3: Disable AuthThrottle in test**

In `config/test.exs`, after the mailer config block:

```elixir
config :speechwave, Speechwave.Mailer, adapter: Swoosh.Adapters.Test
```

add:

```elixir

# AuthThrottle's ETS-backed cooldowns are wall-clock and global (BEAM-wide),
# which would make login_test.exs's async, repeated-email submissions
# flaky. AuthThrottle itself is covered directly by
# test/speechwave/auth_throttle_test.exs, and
# test/speechwave_web/live/user_live/login_auth_throttle_test.exs
# temporarily re-enables this flag to test the UserLive.Login wiring.
# See docs/specs/2026-06-11-magic-link-auth-throttle-design.md.
config :speechwave, :auth_throttle_enabled, false
```

- [ ] **Step 4: Commit**

```bash
git add config/config.exs config/test.exs
git commit -m "chore: add auth_throttle_enabled config flag and log metadata"
```

---

## Task 5: Derive the client IP in `UserLive.Login.mount/3`

**Files:**
- Modify: `lib/speechwave_web/endpoint.ex:14-16`
- Modify: `lib/speechwave_web/live/user_live/login.ex`

- [ ] **Step 1: Add `:x_headers` to the LiveView socket's connect_info**

In `lib/speechwave_web/endpoint.ex`, change:

```elixir
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
```

to:

```elixir
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:x_headers, session: @session_options]],
    longpoll: [connect_info: [:x_headers, session: @session_options]]
```

- [ ] **Step 2: Derive `client_ip` in `mount/3`**

In `lib/speechwave_web/live/user_live/login.ex`, change:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => ""}, as: "user")
    {:ok, assign(socket, form: form, link_sent: false, submitted_email: nil)}
  end
```

to:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"email" => ""}, as: "user")

    ip =
      socket
      |> get_connect_info(:x_headers)
      |> List.wrap()
      |> RemoteIp.from()
      |> format_ip()

    {:ok, assign(socket, form: form, link_sent: false, submitted_email: nil, client_ip: ip)}
  end
```

Add the private helper near the bottom of the module, after `any_oauth_provider_configured?/0`:

```elixir
  defp format_ip(nil), do: nil
  defp format_ip(ip), do: ip |> :inet.ntoa() |> to_string()
```

`get_connect_info(socket, :x_headers)` returns `nil` if `:x_headers` isn't available (defensively handled by `List.wrap/1`, which turns `nil` into `[]`), or a list of `{header_name, value}` tuples otherwise. `RemoteIp.from/1` parses `x-forwarded-for` from that list (its default header) and returns an `:inet.ip_address()` tuple or `nil`; `format_ip/1` converts the tuple to a string for use as an ETS key, or passes `nil` through.

- [ ] **Step 3: Run the existing login tests to confirm nothing broke**

Run: `mix test test/speechwave_web/live/user_live/login_test.exs`
Expected: `4 tests, 0 failures`

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave_web/endpoint.ex lib/speechwave_web/live/user_live/login.ex
git commit -m "feat: derive client IP in UserLive.Login via remote_ip"
```

---

## Task 6: Wire `AuthThrottle` into `submit_magic`

This is the integration point. The test is written first against the *current* (unthrottled) behavior so it fails, then the `handle_event` change makes it pass.

**Files:**
- Create: `test/speechwave_web/live/user_live/login_auth_throttle_test.exs`
- Modify: `lib/speechwave_web/live/user_live/login.ex`

- [ ] **Step 1: Write the failing integration test**

Create `test/speechwave_web/live/user_live/login_auth_throttle_test.exs`:

```elixir
defmodule SpeechwaveWeb.UserLive.LoginAuthThrottleTest do
  use SpeechwaveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Speechwave.Accounts
  alias Speechwave.Accounts.UserToken
  alias Speechwave.Repo

  @moduletag :capture_log

  setup do
    Application.put_env(:speechwave, :auth_throttle_enabled, true)
    :ets.delete_all_objects(:auth_throttle_email)
    :ets.delete_all_objects(:auth_throttle_ip)

    on_exit(fn ->
      Application.put_env(:speechwave, :auth_throttle_enabled, false)
    end)

    :ok
  end

  # Test conns never carry forwarded-IP headers, so `client_ip` is always
  # `nil` here, exercising only the `is_nil(ip)` branch of
  # `maybe_send_magic_link/2` (the email-cooldown path). The IP-cooldown
  # branches are covered directly by test/speechwave/auth_throttle_test.exs.
  test "throttles a second magic-link submission for the same email", %{conn: conn} do
    email = "throttle-test@example.com"

    {:ok, view, _html} = live(conn, ~p"/users/log-in")
    view |> form("#magic-link-form", %{"user" => %{"email" => email}}) |> render_submit()
    assert has_element?(view, "#magic-link-sent")

    {:ok, view2, _html} = live(conn, ~p"/users/log-in")
    view2 |> form("#magic-link-form", %{"user" => %{"email" => email}}) |> render_submit()
    assert has_element?(view2, "#magic-link-sent")

    user = Accounts.get_user_by_email(email)

    login_token_count =
      Repo.aggregate(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "login"),
        :count
      )

    assert login_token_count == 1
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/speechwave_web/live/user_live/login_auth_throttle_test.exs`
Expected: FAIL —

```
  1) test throttles a second magic-link submission for the same email (...)
     Assertion with == failed
     code:  assert login_token_count == 1
     left:  2
     right: 1
```

This is because `handle_event("submit_magic", ...)` doesn't check `AuthThrottle` yet, so each submission inserts its own `UserToken` with context `"login"`.

- [ ] **Step 3: Wire the throttle checks into `handle_event`**

In `lib/speechwave_web/live/user_live/login.ex`, add to the alias/require block at the top:

```elixir
  alias Speechwave.Accounts
  alias Speechwave.AuthThrottle

  require Logger
```

Then change:

```elixir
  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case Accounts.register_or_get_user_by_email(email) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/users/magic_link/#{&1}"))

      {:error, _} ->
        nil
    end

    {:noreply, assign(socket, link_sent: true, submitted_email: email)}
  end
```

to:

```elixir
  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    email = email |> String.trim() |> String.downcase()

    if auth_throttle_enabled?() do
      maybe_send_magic_link(socket.assigns.client_ip, email)
    else
      send_magic_link(email)
    end

    {:noreply, assign(socket, link_sent: true, submitted_email: email)}
  end
```

Then add these private helpers, alongside the other `defp` helpers at the bottom of the module:

```elixir
  defp maybe_send_magic_link(ip, email) do
    cond do
      is_nil(ip) ->
        Logger.info("auth_throttle: missing client ip, skipping ip check")
        send_if_email_allowed(email)

      not AuthThrottle.allow_ip?(ip) ->
        :ok

      true ->
        send_if_email_allowed(email)
    end
  end

  defp send_if_email_allowed(email) do
    if AuthThrottle.allow_email?(email), do: send_magic_link(email)
  end

  defp send_magic_link(email) do
    case Accounts.register_or_get_user_by_email(email) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/users/magic_link/#{&1}"))

      {:error, _} ->
        nil
    end
  end

  defp auth_throttle_enabled? do
    Application.get_env(:speechwave, :auth_throttle_enabled, true)
  end
```

This implements the design doc's flow: when `client_ip` is `nil` (no forwarded-IP headers, including all test conns), the IP check is skipped (logged at `:info`) and only the email cooldown applies via `send_if_email_allowed/1`; when `client_ip` is present, the IP cooldown is checked first and an IP violation skips the email check entirely (`:ok`, second branch); otherwise the email cooldown is checked via the same `send_if_email_allowed/1` (third branch). In every case the LiveView assigns `link_sent: true, submitted_email: email` so the UI is identical regardless of outcome. Note `submitted_email` is now always the normalized (trimmed/downcased) form.

- [ ] **Step 4: Run the integration test to verify it passes**

Run: `mix test test/speechwave_web/live/user_live/login_auth_throttle_test.exs`
Expected: `1 test, 0 failures`

- [ ] **Step 5: Run the full login test suite to confirm no regressions**

Run: `mix test test/speechwave_web/live/user_live/`
Expected: `5 tests, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave_web/live/user_live/login.ex test/speechwave_web/live/user_live/login_auth_throttle_test.exs
git commit -m "feat: throttle magic-link submissions by email and client IP"
```

---

## Task 7: Run `mix precommit`

**Files:** none (verification only; fix whatever it flags using the conventions already established in this plan)

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: compiles with no warnings, `mix format` makes no further changes, the full test suite passes, `credo --strict` and `dialyzer` report no new issues.

- [ ] **Step 2: Fix any issues and commit**

If `mix format` reformats files, or `credo`/`dialyzer` flag something, fix it in place (following the style of the surrounding code this plan just wrote) and commit:

```bash
git add -A
git commit -m "chore: fix precommit issues for auth throttle"
```

If `mix precommit` is clean, skip this step — no commit needed.

---

## Spec coverage check

- Two ETS tables, GenServer + supervision pattern mirroring `RateLimiter` → Task 2, 3, 4 (supervision in Task 2 step 4)
- Email cooldown (60s, no escalation) → Task 2
- IP escalating cooldown (30s base, doubling, 30min cap, reset on success) → Task 3
- Logging on violation (`ip cooldown` / `email cooldown` warnings) → Task 2 step 3, Task 3 step 3
- Client IP derivation via `remote_ip` + `:x_headers` → Task 1, Task 5
- `handle_event` flow (normalize email, IP check → email check → send, always same UI) → Task 6
- Config flag for test isolation → Task 4
- Unit tests (fresh entry, cooldown, escalation, cap) → Task 2, 3
- Integration test (fail-open IP branch + email cooldown branch) → Task 6
- `docs/roadmap.md` junk-user cleanup item → out of scope for this plan, already tracked separately
