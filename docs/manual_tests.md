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

## Quick start

To run everything that's fully automated against a local dev server in one
go:

```sh
scripts/manual_tests/run_all_dev.sh [--base-url URL]
```

(default `http://localhost:4000`). This runs `auth_throttle.sh email`,
`dashboard.sh`, `session_analytics.sh`, and `reaction_flow.sh` back-to-back,
printing each script's output as it goes, then a PASS/FAIL summary line per
script. Exits non-zero if any failed.

Checks `rodney` is on `PATH` and the dev server is reachable at `--base-url`
before starting, with actionable error messages if not.

**Dev-only** — refuses a non-local `--base-url`, since three of the four
scripts depend on `/dev/mailbox` and `mix run` for seeding. The `ip`-cooldown
mode of `auth_throttle.sh` isn't included here since it's production-only and
needs a manual `fly logs` check afterward — run it separately per the
"Magic-link auth throttle" section below.

## Conventions for new sections

Each feature gets its own `##` section: a one-line description of what it
tests, the script invocation, then either flat content or a `###`
subsection per mode (as the auth-throttle section below does for `email`
vs. `ip`).

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

## Speaker dashboard

Tests the speaker dashboard (`SpeechwaveWeb.DashboardLive`, `/dashboard`):
magic-link login, plan-usage display, talk creation, link copying, and talk
deletion.

Script: `scripts/manual_tests/dashboard.sh [--base-url URL]` (default
`http://localhost:4000`)

**Dev-only** — exits with an error against a non-local `--base-url`, since
`complete_magic_link_login` depends on `/dev/mailbox`. See "SSH/eval
magic-link-token helper for production runs" in `docs/roadmap.md` for the
planned production path.

As a fresh free-tier user (`manual-test-<timestamp>@example.com`, a new
email each run):

1. Logs in via magic link (`complete_magic_link_login`), landing on
   `/dashboard` with `#talk-list` present.
2. Checks the plan-usage summary: `#sessions-used` is `0`, `#session-limit`
   is `10`, `#participant-limit` is `50` (the `:free` plan defaults for a
   brand-new account).
3. Creates a talk titled `manual-test-<timestamp>`. Checks `#created-talk`
   appears and `#selected-talk-qr` renders with `#talk-link` (matching
   `<base_url>/t/<slug>`) and `#no-sessions`.
4. Checks the copy-link button (`#copy-talk-link`) renders with its idle
   icon visible and its "copied" icon hidden, and that clicking it doesn't
   error. The icon swap itself isn't verified — headless Chrome has no
   clipboard permission, so `navigator.clipboard.writeText()` never resolves
   and the hook's `.then()` callback never runs. This is a headless-browser
   limitation, not an app bug.
5. Deletes the talk (`#delete-talk-<id>`, via `confirm_and_click`). Checks
   the talk is gone from `#talk-list` and `#selected-talk-qr` no longer
   renders.
6. Signs out and checks that `/dashboard` then redirects to `/users/log-in`.

## Session analytics

Tests session analytics (`SpeechwaveWeb.SessionAnalyticsLive`,
`/sessions/:id` and `/sessions/:id/compare/:other_id`) and the dashboard's
sessions panel: viewing reaction totals, comparing two sessions, renaming,
and deleting.

Scripts:
- `scripts/manual_tests/seed_sessions.exs` — seeds a talk with two finished
  sessions and reactions. Run directly with
  `mix run scripts/manual_tests/seed_sessions.exs <email>`, or via
  `session_analytics.sh` below. Prints `email=`, `talk_id=`, `session1_id=`,
  `session2_id=` on stdout (interleaved with `[debug]` SQL logs on stderr).
- `scripts/manual_tests/session_analytics.sh [--base-url URL]` (default
  `http://localhost:4000`)

**Dev-only** — same constraint as `dashboard.sh` (depends on
`complete_magic_link_login` and on `mix run` for seeding). See "SSH/eval
magic-link-token helper for production runs" in `docs/roadmap.md`.

`session_analytics.sh`:

1. Seeds data via `seed_sessions.exs` for a fresh
   `manual-test-<timestamp>@example.com`: Session 1 gets 3 reactions (🔥 and
   ❤️ on slide 1, 🎉 on slide 2), Session 2 gets 2 reactions (🔥 on slide 1,
   👏 on slide 2).
2. Logs in via magic link.
3. Opens `/sessions/<session1_id>`. Checks `#total-reactions` is `3` and
   `#slide-row-1` / `#slide-row-2` render.
4. Opens `/sessions/<session1_id>/compare/<session2_id>`. Checks
   `#compare-section` renders.
5. Returns to `/dashboard`, selects the seeded talk. Checks `#sessions-panel`
   lists both `#session-<session1_id>` and `#session-<session2_id>`.
6. Renames session 1 to "Opening Keynote" via `#rename-session-<id>` /
   `#rename-form-<id>`. Checks `#session-label-<id>` updates.
7. Deletes session 2 (`#delete-session-<id>`, via `confirm_and_click`).
8. Deletes the talk (cleanup).
9. Signs out.

## Attendee reaction flow

Tests the anonymous attendee-facing reaction page
(`SpeechwaveWeb.TalkLive`, `/t/:slug`): real-time emoji broadcast across
devices, the rate-limit cooldown UI, and reaction persistence to an active
session.

Scripts:
- `scripts/manual_tests/seed_active_session.exs` — seeds a talk with one
  active (unstopped) session and no reactions. Run directly with
  `mix run scripts/manual_tests/seed_active_session.exs <email>`, or via
  `reaction_flow.sh` below. Prints `email=`, `talk_id=`, `talk_slug=`,
  `session_id=` on stdout (interleaved with `[debug]` SQL logs on stderr).
- `scripts/manual_tests/reaction_flow.sh [--base-url URL]` (default
  `http://localhost:4000`)

**Dev-only** — same constraint as `dashboard.sh`/`session_analytics.sh`
(depends on `complete_magic_link_login` and on `mix run` for seeding). See
"SSH/eval magic-link-token helper for production runs" in `docs/roadmap.md`.

`reaction_flow.sh` opens **two** rodney tabs on the same `/t/:slug` page —
"Device A" (taps reactions) and "Device B" (observes only) — simulating two
attendees viewing the same talk:

1. Seeds an active session via `seed_active_session.exs` for a fresh
   `manual-test-<timestamp>@example.com`.
2. Opens Device A and Device B on `/t/<talk_slug>`. Checks `#emoji-buttons`
   renders on both.
3. Device A taps ❤️. Checks a `.floating-emoji` "❤️" appears (the
   broadcast + `EmojiStream` hook round-trip back to the tapping tab) and
   that `#emoji-buttons` enters its cooldown state (`cooling-down` class,
   disabled buttons, `.cooldown-label` shows "Cooling down… 3s").
4. **Cross-device check** — switches to Device B and checks a
   `.floating-emoji` "❤️" appears there too (the PubSub broadcast reached a
   second client in real time), while Device B's cooldown stays idle
   ("Tap to react", buttons enabled) — confirming the rate limiter is
   per-attendee, not global.
5. Waits ~4s (cooldown is 3s) and checks Device A's `#emoji-buttons` returns
   to idle.
6. Device A taps 😂. Checks a `.floating-emoji` "😂" appears.
7. **Cross-device check** — switches to Device B and checks a
   `.floating-emoji` "😂" appears there too.
8. Closes Device B's tab.
9. Logs in as the seeded user via magic link, opens
   `/sessions/<session_id>`. Checks `#total-reactions` is `2` and
   `#slide-row-0` ("General" — `current_slide` stays `0` for this whole
   flow) shows both ❤️ and 😂.
10. Deletes the talk (cleanup).
11. Signs out.
