# Manual and live-environment checks

Most integration testing now runs as code:

- `mix test` runs the fast suite in-process (sandboxed DB, no real sockets,
  `:auth_throttle_enabled` off, see `config/test.exs`).
- `mix test.browser` (or `mise run test-e2e`) drives a real Chromium through
  Playwright against a local test server. Setup is in the README under
  "Browser tests". These tests live in `test/e2e` and share helpers from
  `SpeechwaveWeb.E2ECase`.

This file covers what those can't: checks that need a *running production
server* (real proxy headers, real email delivery, real Fly logs) or a person
looking at a screen.

## Browser tests

The old rodney scripts for these flows have been replaced:

| Flow                                         | Test                                   |
| -------------------------------------------- | -------------------------------------- |
| Login, talk create and delete, sign out      | `test/e2e/dashboard_test.exs`          |
| API key regeneration, email change           | `test/e2e/account_settings_test.exs`   |
| Marketing consent: login box and pricing modal | `test/e2e/email_consent_test.exs`    |
| Session analytics, compare, rename, delete   | `test/e2e/session_analytics_test.exs`  |
| Attendee reactions across two devices        | `test/e2e/reaction_flow_test.exs`      |
| Magic-link email cooldown                    | `test/e2e/auth_throttle_test.exs`      |

The history and reasoning behind the move are in
[the migration plan](specs/2026-10-18-browser-test-migration-design.md). Add new
integration tests there, not as scripts.

## Environments

|              | Dev                               | Production                  |
| ------------ | --------------------------------- | --------------------------- |
| Base URL     | `http://localhost:4000`           | `https://speechwave.live`   |
| Start server | `mix phx.server`                  | already running             |
| Sent emails  | `/dev/mailbox`                    | real inbox (Resend)         |
| Logs         | terminal running `mix phx.server` | `fly logs --app speechwave` |

## Magic-link IP cooldown (production only)

Script: `scripts/manual_tests/auth_throttle.sh --base-url https://speechwave.live`

Checks the IP half of `Speechwave.AuthThrottle` (see
`docs/specs/2026-06-11-magic-link-auth-throttle-design.md`). The email half is
covered by `test/e2e/auth_throttle_test.exs`.

This can only be checked in production. Dev has no reverse proxy, so
`:x_headers` never carries `x-forwarded-for`, `RemoteIp.from/1` returns `nil`,
and `client_ip` is always `nil`. `maybe_send_magic_link/2` then skips the IP
check entirely (documented fail-open behavior, not a bug). The script refuses
to run against a `localhost` or `127.0.0.1` base URL.

It needs [`rodney`](https://github.com/simonw/rodney) (Chrome automation CLI)
on your `PATH`. Run `rodney --help` to confirm.

What it does: submits the sign-in form 4 times in quick succession, each with a
different generated email (so only the IP path is exercised), and asserts that
`#magic-link-sent` appears each time. The page looks the same whether or not a
request was throttled, so confirm in the logs:

```sh
fly logs --app speechwave | grep "auth_throttle: ip cooldown"
```

Expect 3 escalating warnings for this machine's IP: `cooldown_ms=60000
violation_count=1`, `cooldown_ms=120000 violation_count=2`, and
`cooldown_ms=240000 violation_count=3`. The first submission is never logged,
because `allow_ip?/1` only warns on violations.

A request that the throttle lets through creates a
`manual-test-<timestamp>-<n>@example.com` user in production (usually just the
first one, since the rest are blocked). Delete those by hand when you're done.

## Welcome banner

Tests the first-login welcome banner (`Layouts.app/1`, dismissed through the
hook in `UserAuth.mount_current_scope/2`). There is no script; this is a
manual check in a browser.

**Dev only.** It relies on `/dev/login`, which does not exist in production.

1. Go to `http://localhost:4000/dev/login`, enter an email that has never been
   used (for example `banner-check-<timestamp>@example.com`) and log in. A new
   email creates a new user with `welcomed_at` empty. Existing dev users were
   marked as welcomed by the migration and will not show the banner.
2. Go to `/users/settings`. The banner (`#welcome-banner`) sits directly under
   the header. "Getting Started" (`#welcome-banner-link`) opens
   `getting-started.html` on the docs site in a new tab, and "Help" is plain
   bold text.
3. Resize to about 375px wide. The text wraps, nothing overlaps the header, and
   the close button (`#welcome-banner-dismiss`) is easy to tap.
4. Click the close button. The banner disappears at once with no page reload.
5. Reload, then go to `/dashboard`. The banner stays gone.
6. To see it again for the same user, clear the flag in the dev database
   (`UPDATE users SET welcomed_at = NULL WHERE email = '...'`).
