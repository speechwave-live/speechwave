# Magic Link Auth Throttle Design

**Date:** 2026-06-11
**Status:** Approved

## Overview

`UserLive.Login.handle_event("submit_magic", ...)` currently calls
`Accounts.register_or_get_user_by_email/1` (which inserts a `users` row on
first sight of any email) and sends a real "sign-in link" email, with no rate
limiting. This was a known, documented trade-off — see the 2026-05-05 entry
in `docs/decisions.md` ("Rate limiting on magic link sends is deferred...").

**Goal:** Make the magic-link form resistant to casual scripted abuse along
two axes:
1. **Email-bombing** — repeatedly sending sign-in links to a victim's address.
2. **Table/inbox flooding** — a single actor submitting many different emails
   to create `users` rows and trigger many outbound emails.

**Out of scope:**
- OAuth (`/auth/google`, `/auth/microsoft`, `/auth/github`) and the dev-only
  `/dev/login` route. OAuth requires completing a real provider auth flow —
  a much higher cost than submitting a form field — so it isn't throttled here.
- Cleanup of existing/future unconfirmed "junk" `users` rows. The throttle
  slows the *rate* of junk creation but can't eliminate it (the first
  submission of any new email must always succeed). Cleanup is a separate
  concern, tracked in `docs/roadmap.md`.
- Multi-node / cross-restart persistence of throttle state (see "Limitations"
  below).

---

## Architecture

A new module, `Speechwave.AuthThrottle` (`lib/speechwave/auth_throttle.ex`),
follows the same GenServer + `:public` ETS pattern as the existing
`Speechwave.RateLimiter` (`lib/speechwave/rate_limiter.ex`), and is added to
the supervision tree in `lib/speechwave/application.ex` immediately after it.

Two ETS tables, created in `init/1`:

- **`:auth_throttle_email`** — key: normalized email (trimmed + downcased),
  value: `last_sent_at` (monotonic ms). Fixed cooldown.
- **`:auth_throttle_ip`** — key: client IP string, value:
  `{last_at, cooldown_ms, violation_count}`. Escalating cooldown.

Public API (single ETS lookup/insert per call, no GenServer round-trip):

```elixir
AuthThrottle.allow_email?(email) :: boolean
AuthThrottle.allow_ip?(ip) :: boolean
```

### Throttle parameters

- **Email cooldown:** fixed at **60 seconds**. A second submission for the
  same address within 60s is throttled. No escalation — legitimate users
  rarely need a resend faster than this, and the existing UI already says
  the link is valid for 15 minutes.
- **IP cooldown:** starts at **30 seconds**, doubles on each violation
  (a request made before the current cooldown elapses) up to a cap of
  **30 minutes**, and resets to 30s with violation count 0 on any *allowed*
  request. A client pacing requests at 30s+ never escalates; a script
  hammering the endpoint backs off exponentially.

  **Algorithm (sliding window):** every call to `allow_ip?/1` — whether it
  returns `true` or `false` — writes `last_at = now`. On `true`
  (`now - last_at >= cooldown_ms`), also reset `cooldown_ms = 30_000` and
  `violation_count = 0`. On `false`, also set
  `cooldown_ms = min(cooldown_ms * 2, 1_800_000)` and increment
  `violation_count`. Because `last_at` advances on every call, a burst of
  rapid requests keeps pushing the "earliest next allowed" time forward —
  the caller must go quiet for the full (escalated) cooldown before getting
  through. `violation_count` doesn't drive the cooldown math; it's carried
  for the log line so repeated-violation patterns are visible in logs.

### Limitations

ETS state is per-node and cleared on restart/deploy/crash (the GenServer
recreates empty tables on init — fail open, matching `RateLimiter`'s existing
behavior). If Speechwave ever runs multiple machines concurrently, an
attacker distributing requests across machines gets a higher effective rate.
Acceptable at current scale (`fly.toml` has `min_machines_running = 0`); the
goal is raising the cost of casual abuse, not building a hard security
boundary.

---

## Integration into `UserLive.Login`

### Deriving the client IP

LiveView sockets currently expose no IP/peer info — `endpoint.ex` only
configures `connect_info: [session: @session_options]`. Behind Fly.io's
proxy, the raw transport peer (`:peer_data`) would be Fly's edge, not the
real client, so the IP must come from forwarded headers instead.

- Add dependency `{:remote_ip, "~> 1.2"}` to `mix.exs`.
- Add `:x_headers` to the LiveView socket's `connect_info` in `endpoint.ex`:

  ```elixir
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:x_headers, session: @session_options]],
    longpoll: [connect_info: [:x_headers, session: @session_options]]
  ```

- In `mount/3`, derive the IP once and assign it to the socket:

  ```elixir
  ip =
    socket
    |> get_connect_info(:x_headers)
    |> RemoteIp.from(headers: ~w[fly-client-ip x-forwarded-for])
  ```

  `RemoteIp.from/2` is a pure header-parsing function from the `remote_ip`
  package — no plug required.

### `handle_event("submit_magic", ...)` flow

1. Normalize the submitted email (`String.trim/1` + `String.downcase/1`) —
   matches the changeset's normalization, done here so the throttle key is
   consistent regardless of changeset validity.
2. If `ip` is present, call `AuthThrottle.allow_ip?(ip)`. If `false`, log and
   skip to step 5.
3. Call `AuthThrottle.allow_email?(email)`. If `false`, log and skip to step 5.
4. Otherwise, proceed exactly as today:
   `register_or_get_user_by_email/1` + `deliver_login_instructions/2`.
5. Always `assign(socket, link_sent: true, submitted_email: email)` —
   identical response whether throttled or not. This matches the existing
   behavior where `register_or_get_user_by_email` errors are already
   swallowed silently, and avoids revealing rate-limit state, account
   existence, or throttle thresholds to the caller.

   Note: `email` here is the *normalized* (trimmed/downcased) form from step
   1, so "Check your inbox, we sent a link to `<email>`" may now display in
   lowercase even if the user typed mixed case. This is a minor, intentional
   change from current behavior (which echoes back the raw input) — it
   matches how the address is actually stored and used.

### Fail-open for missing IP

If `RemoteIp.from/2` returns `nil` (local dev, misconfigured headers, or any
environment without the expected forwarded-IP headers), skip the IP check
entirely and rely on the email cooldown alone. This is logged at `:info` so a
header-configuration regression is visible without breaking signups.

### Logging on throttle

- IP violation:
  `Logger.warning("auth_throttle: ip cooldown", ip: ip, cooldown_ms: ms, violation_count: n)`
- Email cooldown:
  `Logger.warning("auth_throttle: email cooldown", email_domain: domain)` —
  only the domain is logged, not the full address, to avoid putting raw
  emails into logs.

---

## Configuration & Testing

### Config flag

Following the existing `local_mail_adapter?()` / `oauth_provider_configured?()`
pattern (`Application.get_env`):

- `config/config.exs`: `config :speechwave, :auth_throttle_enabled, true`
- `config/test.exs`: `config :speechwave, :auth_throttle_enabled, false`

`UserLive.Login` checks this flag and skips both throttle calls entirely when
disabled. This means **no existing tests need to change** — `login_test.exs`
continues to exercise the full registration/email-delivery path exactly as it
does today.

### Why this is needed

`AuthThrottle`'s ETS tables are global (BEAM-wide), but `login_test.exs` runs
`async: true`. The IP path is naturally inert in tests (test conns carry no
`x-forwarded-for`/`fly-client-ip` headers, so `RemoteIp.from/2` returns `nil`
and the IP table is never touched). The email path is the real risk: the 60s
cooldown is wall-clock, not mocked, so any test that submits the same email
twice within a run would have the second submission silently swallowed —
confusing and hard to reproduce. The config flag sidesteps this entirely for
existing and future LiveView tests.

### New tests

- **`test/speechwave/auth_throttle_test.exs`** (new, `async: false`, mirrors
  `test/speechwave/rate_limiter_test.exs`): clears both ETS tables in
  `setup`, and directly tests `allow_email?/1` and `allow_ip?/1` — including
  the escalating/doubling/cap/reset behavior of the IP cooldown via backdated
  ETS timestamps. Runs independent of the config flag, so the throttle logic
  itself is fully covered regardless of environment.
- **One integration test** in `login_test.exs` (`async: false`, isolated
  `describe` block): temporarily sets `auth_throttle_enabled: true` via
  `Application.put_env/3` with an `on_exit` revert, submits the same email
  twice in quick succession, and asserts only one `UserToken` is created.
  This confirms the LiveView actually calls `AuthThrottle` when enabled —
  proving the wiring, not just the flag's existence.

---

## Files touched

- `mix.exs` — add `{:remote_ip, "~> 1.2"}`
- `lib/speechwave/auth_throttle.ex` — new module
- `lib/speechwave/application.ex` — add `Speechwave.AuthThrottle` to
  supervision tree
- `lib/speechwave_web/endpoint.ex` — add `:x_headers` to LiveView socket
  `connect_info`
- `lib/speechwave_web/live/user_live/login.ex` — derive IP in `mount/3`,
  throttle checks in `handle_event("submit_magic", ...)`
- `config/config.exs`, `config/test.exs` — `:auth_throttle_enabled` flag
- `test/speechwave/auth_throttle_test.exs` — new unit tests
- `test/speechwave_web/live/user_live/login_test.exs` — new integration test
