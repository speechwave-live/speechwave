# Manual & Live-Environment Integration Tests

`mix test` exercises the app in-process: sandboxed DB, no real sockets,
`:auth_throttle_enabled` forced off (see `config/test.exs`). It can't catch
things that only show up against a *running* server — real connect_info
headers, real `RemoteIp` parsing, real email delivery, real Fly logs.

This is a living index of scripted/manual checks for those cases, run
against dev or production (e.g. before/after a deploy). It does not replace
`mix test` and isn't CI-gated — it's ad-hoc verification.

> **Migration in progress.** These rodney scripts are being replaced by browser
> tests in `test/e2e` (run with `mix test.browser`). `dashboard.sh`,
> `account_settings.sh`, `email_consent.sh`, `session_analytics.sh`,
> `reaction_flow.sh` and the email mode of `auth_throttle.sh` have been ported
> and removed. Don't add new scripts here. See
> [the migration plan](specs/2026-10-18-browser-test-migration-design.md) for
> the order and current status.

## Principles

1. **Prefer full automation with UI-based assertions.** Most flows show
   their result in the UI (a success message, an error, a redirect) — script
   the whole thing with `rodney` and assert on rendered elements. This
   should be the default for any new section added below.
2. **Fall back to logs or manual steps only when the UI doesn't expose the
   result.** Document exactly what to look for and where.

## Environments

|              | Dev                               | Production                  |
| ------------ | --------------------------------- | --------------------------- |
| Base URL     | `http://localhost:4000`           | `https://speechwave.live`   |
| Start server | `mix phx.server`                  | already running             |
| Sent emails  | `/dev/mailbox`                    | real inbox (Resend)         |
| Logs         | terminal running `mix phx.server` | `fly logs --app speechwave` |

## Requirements

- [`rodney`](https://github.com/simonw/rodney) (Chrome automation CLI)
  installed and on `PATH`. Run `rodney --help` to confirm it's available and
  see all subcommands.

## Conventions for new sections

Each feature gets its own `##` section: a one-line description of what it
tests, the script invocation, then either flat content or a `###`
subsection per mode.

`scripts/manual_tests/lib.sh` provides shared helpers — source it from new
scripts:

- `parse_base_url "$@"` — parses `--base-url URL`, setting `BASE_URL`
  (default `http://localhost:4000`) and leaving any other arguments in the
  `REMAINING_ARGS` array.
- `is_local` — true if `$BASE_URL` is `localhost`/`127.0.0.1`.
- `start_rodney` — starts `rodney` and registers an `EXIT` trap to stop it.
- `confirm_and_click SELECTOR` — clicks an element with a `data-confirm`
  attribute, auto-accepting the resulting dialog.
- `complete_magic_link_login BASE_URL EMAIL` — dev-only; completes a
  magic-link sign-in via `/dev/mailbox` and lands on `/dashboard`.

## Magic-link auth throttle

Tests `Speechwave.AuthThrottle` (see
`docs/specs/2026-06-11-magic-link-auth-throttle-design.md`): repeated
magic-link requests for the same email, or from the same IP, are throttled.

### Email cooldown

Ported to a browser test: `test/e2e/auth_throttle_test.exs` (run with
`mix test.browser`). It submits the sign-in form twice for one email and
checks that exactly one message is delivered, then submits a different email
to show that one still goes out.

### IP cooldown (`auth_throttle.sh --base-url https://speechwave.live`), production only

Script: `scripts/manual_tests/auth_throttle.sh --base-url URL`

Dev has no reverse proxy, so `:x_headers` never carries `x-forwarded-for`,
`RemoteIp.from/1` returns `nil`, `client_ip` is always `nil`, and
`maybe_send_magic_link/2`'s `is_nil(ip)` branch always fires — `allow_ip?/1`
is never called locally. This is documented fail-open behavior, not a bug.
The script refuses to run against a `localhost`/`127.0.0.1` base URL.

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

## Speaker dashboard

Ported to a browser test: `test/e2e/dashboard_test.exs` (run with
`mix test.browser`). It covers magic-link login, plan usage, talk creation, the
copy-link button's initial state, talk deletion through the confirm dialog, and
sign out.

## Session analytics

Ported to a browser test: `test/e2e/session_analytics_test.exs` (run with
`mix test.browser`). It views a session's totals and per-slide rows, compares
two sessions, then renames a session, deletes a session and deletes the talk
from the dashboard. The seed data comes from
`Speechwave.TalksFixtures.talk_with_two_finished_sessions_fixture/1`.

## Attendee reaction flow

Ported to a browser test: `test/e2e/reaction_flow_test.exs` (run with
`mix test.browser`). Two attendees (separate browser contexts) open the same
`/t/:slug` page. One taps a reaction, and it floats up on both pages while only
the tapper's buttons cool down. After the cooldown a second reaction is sent
and both reactions show up in the session's analytics as general (slide 0).
The seed data comes from
`Speechwave.TalksFixtures.talk_with_active_session_fixture/1`.

## Email consent collection

Ported to a browser test: `test/e2e/email_consent_test.exs` (run with
`mix test.browser`). It covers the three consent surfaces end to end: login
with the consent checkbox, login without it, and the pricing page Notify Me
modal. Each one checks the query params in the emailed magic link, then the
consent state on `/users/settings` (plus the revoke button, and the
"on the list" flash for Notify Me).

## Account settings

Ported to a browser test: `test/e2e/account_settings_test.exs` (run with
`mix test.browser`). It regenerates the API key through the confirm dialog,
changes the email through the emailed confirmation link, and signs out.

## Welcome banner

Tests the first-login welcome banner (`Layouts.app/1`, dismissed through the
hook in `UserAuth.mount_current_scope/2`). There is no script; this is a
manual check in a browser.

**Dev-only.** It relies on `/dev/login`, which does not exist in production.

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
