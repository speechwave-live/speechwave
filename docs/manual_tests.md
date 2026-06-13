# Manual & Live-Environment Integration Tests

`mix test` exercises the app in-process: sandboxed DB, no real sockets,
`:auth_throttle_enabled` forced off (see `config/test.exs`). It can't catch
things that only show up against a *running* server — real connect_info
headers, real `RemoteIp` parsing, real email delivery, real Fly logs.

This is a living index of scripted/manual checks for those cases, run
against dev or production (e.g. before/after a deploy). It does not replace
`mix test` and isn't CI-gated — it's ad-hoc verification.

## Principles

1. **Prefer full automation with UI-based assertions.** Most flows show
   their result in the UI (a success message, an error, a redirect) — script
   the whole thing with `rodney` and assert on rendered elements. This
   should be the default for any new section added below.
2. **Fall back to logs or manual steps only when the UI doesn't expose the
   result.** Document exactly what to look for and where.

## Environments

| | Dev | Production |
|---|---|---|
| Base URL | `http://localhost:4000` | `https://speechwave.live` |
| Start server | `mix phx.server` | already running |
| Sent emails | `/dev/mailbox` | real inbox (Resend) |
| Logs | terminal running `mix phx.server` | `fly logs --app speechwave` |

## Requirements

- [`rodney`](https://github.com/simonw/rodney) (Chrome automation CLI)
  installed and on `PATH`. Run `rodney --help` to confirm it's available and
  see all subcommands.

## Conventions for new sections

Each feature gets its own `##` section: a one-line description of what it
tests, the script invocation, then either flat content or a `###`
subsection per mode (as the auth-throttle section below does for `email`
vs. `ip`).

`scripts/manual_tests/auth_throttle.sh` is the first script and currently
owns its full `rodney` lifecycle (start/stop trap), `--base-url`/mode
argument parsing, and `is_local()` helper inline. When a second script is
added, factor those shared pieces into `scripts/manual_tests/lib.sh` so both
scripts source it instead of duplicating.

## Magic-link auth throttle

Tests `Speechwave.AuthThrottle` (see
`docs/specs/2026-06-11-magic-link-auth-throttle-design.md`): repeated
magic-link requests for the same email, or from the same IP, are throttled.

Script: `scripts/manual_tests/auth_throttle.sh [--base-url URL] {email|ip}`
(defaults: `http://localhost:4000`, `email`)

### Email cooldown (`auth_throttle.sh email`)

- Submits the magic-link form twice in a row with the same generated test
  email, asserting `#magic-link-sent` appears both times (the UI looks
  identical whether the second send was throttled or not).
- **Dev:** clears `/dev/mailbox` first, then after both submissions checks
  that exactly one email was delivered. Prints `PASS`/`FAIL`. This counts
  every message in `/dev/mailbox`, not just ones matching the test email —
  clearing first keeps this accurate as long as nothing else delivers mail
  to the local mailbox during the run.
- **Production:** `/dev/mailbox` doesn't exist, so confirm via one of:
  - a real inbox you control as the test email, checking it arrives exactly
    once, or
  - `fly logs --app speechwave | grep "auth_throttle: ip cooldown"`. The two
    submissions are seconds apart from the same IP, and
    `maybe_send_magic_link/2` checks `allow_ip?/1` (30s cooldown) before
    `allow_email?/1` (60s cooldown) — so the second submission is blocked by
    the IP cooldown first, and `"auth_throttle: email cooldown"` never
    appears. One `ip cooldown` line for this machine's IP is equally valid
    proof the second send was blocked.

### IP cooldown (`auth_throttle.sh ip --base-url https://speechwave.live`) — production only

Dev has no reverse proxy, so `:x_headers` never carries `x-forwarded-for`,
`RemoteIp.from/1` returns `nil`, `client_ip` is always `nil`, and
`maybe_send_magic_link/2`'s `is_nil(ip)` branch always fires — `allow_ip?/1`
is never called locally. This is documented fail-open behavior, not a bug.
The script refuses to run in `ip` mode against a `localhost`/`127.0.0.1`
base URL.

- Submits the magic-link form 4 times in quick succession, each with a
  distinct generated email (so only the IP path is exercised, not the email
  cooldown), asserting `#magic-link-sent` each time.
- To confirm the cooldown escalated:

  ```sh
  fly logs --app speechwave | grep "auth_throttle: ip cooldown"
  ```

  Expect 3 escalating warnings for this machine's IP: `cooldown_ms=60000
  violation_count=1`, `cooldown_ms=120000 violation_count=2`,
  `cooldown_ms=240000 violation_count=3` (the 1st submission is never
  logged — `allow_ip?/1` only warns on violations).

  If `email` mode was run against this same `--base-url` shortly before
  (from this machine), its second submission already recorded one `ip
  cooldown` violation against this IP, so this run's warnings will start
  from a higher `violation_count`/`cooldown_ms` than shown above — each one
  is still a further doubling, confirming escalation continues.
