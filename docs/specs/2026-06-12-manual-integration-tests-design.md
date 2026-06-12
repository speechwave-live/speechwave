# Manual & Live-Environment Integration Tests Design

**Date:** 2026-06-12
**Status:** Approved

## Overview

`mix test` exercises the application in-process (LiveView test process,
sandboxed DB, `:auth_throttle_enabled` forced off). It can't catch issues
that only show up against a *running* dev or production server: real socket
connect_info (`:x_headers`), real `RemoteIp` parsing, real email delivery,
real Logger output captured by Fly.

This establishes a general practice — `docs/manual_tests.md` plus
`scripts/manual_tests/` — for smoke-testing live environments, starting with
the magic-link auth throttle (`docs/specs/2026-06-11-magic-link-auth-throttle-design.md`).

**Out of scope:**
- Replacing or duplicating `mix test` coverage. These scripts check
  environment-level wiring (headers, config, real email/log delivery), not
  business logic — that's already covered by the ExUnit suite.
- A general E2E test framework. This is lightweight, ad-hoc tooling for
  manual verification before/after deploys, not CI-gated tests.

---

## Principles (for `docs/manual_tests.md`'s intro)

1. **Prefer full automation with UI-based assertions.** Most flows show
   their result in the UI (success message, error, redirect) — script the
   whole thing with `rodney` and assert on rendered elements. This should be
   the default for any new section added to the doc.
2. **Fall back to logs or manual steps only when the UI doesn't expose the
   result.** Auth-throttle's IP-cooldown path is a deliberate exception: per
   its design, the UI shows the same "check your inbox" message whether a
   request was throttled or not, so the only signal is the `AuthThrottle`
   `Logger.warning` lines, which only reach `fly logs` in production (dev has
   no `Logger.warning`-to-visible-output gap, but also no IP to throttle —
   see below).

---

## `docs/manual_tests.md`

A new top-level index doc, structured as:

1. **Intro** — purpose (above) and the two principles.
2. **Environments table:**

   | | Dev | Production |
   |---|---|---|
   | Base URL | `http://localhost:4000` | `https://speechwave.live` |
   | Start server | `mix phx.server` | already running |
   | Sent emails | `/dev/mailbox` | real inbox (Resend) |
   | Logs | terminal running `mix phx.server` | `fly logs --app speechwave` |

3. **One section per feature**, each documenting: what it tests, how to run
   it, and how to read the result in dev vs. production. First section:
   "Magic-link auth throttle" (detailed below).

This doc is a living index — future features add their own section following
the same shape (what/how to run/how to read results).

---

## Magic-link auth throttle section

### Email cooldown (`scripts/manual_tests/auth_throttle.sh email`)

- Opens `/users/log-in`, fills in a generated test email
  (`manual-test-<timestamp>@example.com`), submits via `#magic-link-form`,
  asserts `#magic-link-sent` appears.
- Submits the **same** email again the same way, asserts `#magic-link-sent`
  again (UI looks identical either way — this just confirms the form doesn't
  error).
- **Dev-only automatic check:** opens `/dev/mailbox`, counts entries whose
  recipient matches the test email and whose subject is "Sign in to
  Speechwave" (per `UserNotifier.deliver_login_instructions/2`). Asserts the
  count is exactly `1`. Prints `PASS`/`FAIL`.
- **Production:** the two submissions still run, but `/dev/mailbox` doesn't
  exist. The doc documents two ways to confirm only one email was sent:
  - Use a real inbox address you control as the test email and check it
    arrives once, or
  - `fly logs --app speechwave | grep "auth_throttle: email cooldown"` —
    expect one line with `email_domain=<your domain>`.

### IP cooldown (`scripts/manual_tests/auth_throttle.sh ip`) — production only

Dev has no reverse proxy, so `:x_headers` never includes `x-forwarded-for`,
`RemoteIp.from/1` returns `nil`, `client_ip` is always `nil`, and
`maybe_send_magic_link/2`'s `is_nil(ip)` branch always fires — `allow_ip?/1`
is never called locally. This is the documented fail-open behavior from the
auth-throttle plan, not a bug. So this mode requires `--base-url
https://speechwave.live` (the script can warn/refuse if given a `localhost`
base URL).

- Submits the magic-link form **4 times in quick succession**, each with a
  distinct generated email (`manual-test-<timestamp>-N@example.com`, avoiding
  the email cooldown so only the IP path is exercised), all from this
  machine's IP, asserting `#magic-link-sent` each time.
- Prints the command to verify:

  ```sh
  fly logs --app speechwave | grep "auth_throttle: ip cooldown"
  ```

  Expect 3 escalating warnings for the same `ip=`: `cooldown_ms=60000
  violation_count=1`, `cooldown_ms=120000 violation_count=2`,
  `cooldown_ms=240000 violation_count=3` (call 1 is never logged — `allow_ip?/1`
  only warns on violations).

---

## `scripts/manual_tests/auth_throttle.sh`

- Location: new top-level `scripts/manual_tests/` directory (sibling to
  `lib/`, `test/`, `docs/`) — kept out of `test/` so it's clearly not part of
  the `mix test` / ExUnit suite, which tests the app in-process rather than a
  running server.
- Bash script using the `rodney` CLI (`rodney start`, `open`, `input`,
  `submit`, `wait`, `exists`, `count`, `text`, `stop`).
- Usage: `scripts/manual_tests/auth_throttle.sh [--base-url URL] {email|ip}`
  - `--base-url` defaults to `http://localhost:4000`.
  - `email` is the default mode if omitted.
  - `ip` mode errors out if `--base-url` resolves to `localhost`/`127.0.0.1`,
    with a message explaining why (see above).
- Manages its own `rodney` browser lifecycle (`start`/`stop`) so it's
  self-contained and re-runnable.
- Exact selectors to confirm against a running dev server while writing the
  script: `#magic-link-form`, `#magic-link-sent` (already used by
  `test/speechwave_web/live/user_live/login_auth_throttle_test.exs`), and the
  email input's id (expected `#user_email` per Phoenix's
  `to_form(%{"email" => ""}, as: "user")` convention, field `:email`).

---

## Sequencing & deploy

The IP-cooldown mode and the production side of the email-cooldown mode
require the auth-throttle code to be live on `speechwave.live`. Order of
operations:

1. Implement this spec (doc + script) on the current feature branch.
2. Run `scripts/manual_tests/auth_throttle.sh email` against dev — fully
   automated, no deploy needed.
3. Merge `feat/magic-link-auth-throttle` → `main`.
4. Deploy (`fly deploy --app speechwave`) — **requires explicit go-ahead
   immediately before running**, since this affects the live production
   service.
5. After deploy, run `auth_throttle.sh email --base-url
   https://speechwave.live` and `auth_throttle.sh ip --base-url
   https://speechwave.live`, then check `fly logs` as documented.

---

## Files touched

- `docs/manual_tests.md` — new index doc
- `scripts/manual_tests/auth_throttle.sh` — new script
