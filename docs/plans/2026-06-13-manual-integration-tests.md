# Manual Integration Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/manual_tests/auth_throttle.sh` and `docs/manual_tests.md` so the magic-link auth-throttle behavior can be smoke-tested against a running dev or production server, per `docs/specs/2026-06-12-manual-integration-tests-design.md`.

**Architecture:** A self-contained bash script drives the `rodney` Chrome-automation CLI against the live `/users/log-in` page, asserting on rendered elements (`#magic-link-sent`) for both the email-cooldown and IP-cooldown paths. In dev it also drives `/dev/mailbox` to count delivered emails. `docs/manual_tests.md` is a living index doc explaining how to run the script and how to read results in dev vs. production.

**Tech Stack:** Bash, `rodney` CLI (already installed, verified via `rodney --help`), Phoenix dev server (`mix phx.server`), `/dev/mailbox` (Swoosh `Plug.Swoosh.MailboxPreview`).

**Verified against the running dev server (`http://localhost:4000`) during planning:**
- `#magic-link-form` contains `#user_email` (email input) and a `<button>` (no explicit `id`/`type`, defaults to `type="submit"`).
- LiveView's `phx-submit` only fires on a real `submit` event. `rodney submit "#magic-link-form"` calls the legacy `HTMLFormElement.submit()`, which does **not** fire `submit` and instead causes a full page reload (bypassing LiveView entirely). `rodney click "#magic-link-form button"` works correctly — it fires a real click → submit event that LiveView intercepts.
- After `rodney click ... && rodney waitstable`, `rodney exists "#magic-link-sent"` returns `true`.
- `/dev/mailbox`: the "Empty mailbox" button is `form[action="/dev/mailbox/clear"] button`. Each message in the list is `a[href^="/dev/mailbox/"]`. `rodney count 'a[href^="/dev/mailbox/"]'` returns a plain integer. The message detail page has `#email-details__to` and `#email-details__subject`.
- **The "Empty mailbox" button/form only renders when the mailbox has ≥1 message.** If the mailbox is already empty, `rodney click 'form[action="/dev/mailbox/clear"] button'` fails with `error: element not found: context deadline exceeded` (exit 2). The script must check `rodney count 'a[href^="/dev/mailbox/"]'` first and only click clear when the count is > 0.
- End-to-end dry run (clear mailbox → submit same email twice → both show `#magic-link-sent` → mailbox count == 1, recipient and subject correct) passed.

---

### Task 1: Create `scripts/manual_tests/auth_throttle.sh`

**Files:**
- Create: `scripts/manual_tests/auth_throttle.sh`

- [ ] **Step 1: Create the directory and script file**

```bash
mkdir -p scripts/manual_tests
```

Write `scripts/manual_tests/auth_throttle.sh` with this content:

```bash
#!/usr/bin/env bash
# Manual integration test for Speechwave.AuthThrottle (magic-link sign-in).
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

BASE_URL="http://localhost:4000"
MODE="email"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--base-url URL] {email|ip}

  --base-url URL   Base URL of a running Speechwave instance
                   (default: http://localhost:4000)
  email            Test the email-cooldown path (default mode)
  ip               Test the IP-cooldown path (production only)
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    email|ip)
      MODE="$1"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

is_local() {
  case "$BASE_URL" in
    *localhost*|*127.0.0.1*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$MODE" = "ip" ] && is_local; then
  echo "ERROR: ip mode requires a production --base-url." >&2
  echo "Dev has no reverse proxy, so client_ip is always nil locally and" >&2
  echo "allow_ip?/1 is never called (documented fail-open behavior)." >&2
  echo "Re-run with --base-url https://speechwave.live" >&2
  exit 1
fi

rodney start >/dev/null
trap 'rodney stop >/dev/null' EXIT

submit_magic_link() {
  local email="$1"
  rodney open "$BASE_URL/users/log-in" >/dev/null
  rodney waitload >/dev/null
  rodney input "#user_email" "$email" >/dev/null
  rodney click "#magic-link-form button" >/dev/null
  rodney waitstable >/dev/null
  if ! rodney exists "#magic-link-sent" >/dev/null; then
    echo "FAIL: #magic-link-sent did not appear for $email at $BASE_URL/users/log-in" >&2
    exit 1
  fi
}

case "$MODE" in
  email)
    email="manual-test-$(date +%s)@example.com"
    echo "Testing email cooldown with $email"

    if is_local; then
      rodney open "$BASE_URL/dev/mailbox" >/dev/null
      rodney waitload >/dev/null
      if [ "$(rodney count 'a[href^="/dev/mailbox/"]')" -gt 0 ]; then
        rodney click 'form[action="/dev/mailbox/clear"] button' >/dev/null
        rodney waitload >/dev/null
      fi
    fi

    submit_magic_link "$email"
    echo "PASS: first submission shows #magic-link-sent"

    submit_magic_link "$email"
    echo "PASS: second submission shows #magic-link-sent"

    if is_local; then
      rodney open "$BASE_URL/dev/mailbox" >/dev/null
      rodney waitload >/dev/null
      count=$(rodney count 'a[href^="/dev/mailbox/"]')
      if [ "$count" -eq 1 ]; then
        echo "PASS: exactly 1 email in /dev/mailbox"
      else
        echo "FAIL: expected 1 email in /dev/mailbox, found $count" >&2
        exit 1
      fi
    else
      cat <<EOF

Both submissions returned #magic-link-sent (the UI looks the same whether
the second send was throttled). To confirm only one email was actually sent:
  - use a real inbox you control as the test email and check it arrives
    exactly once, or
  - run: fly logs --app speechwave | grep "auth_throttle: email cooldown"
    and expect one line with email_domain=example.com
EOF
    fi
    ;;

  ip)
    echo "Submitting 4 magic-link requests with distinct emails from this IP..."
    for i in 1 2 3 4; do
      email="manual-test-$(date +%s)-${i}@example.com"
      submit_magic_link "$email"
      echo "PASS: submission $i ($email) shows #magic-link-sent"
    done

    cat <<EOF

To confirm the IP cooldown escalated, run:
  fly logs --app speechwave | grep "auth_throttle: ip cooldown"

Expect 3 escalating warnings for this machine's IP:
  cooldown_ms=60000  violation_count=1
  cooldown_ms=120000 violation_count=2
  cooldown_ms=240000 violation_count=3
(the 1st submission is never logged - allow_ip?/1 only warns on violations)
EOF
    ;;
esac
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/manual_tests/auth_throttle.sh
```

- [ ] **Step 3: Check the script's syntax**

```bash
bash -n scripts/manual_tests/auth_throttle.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/manual_tests/auth_throttle.sh
git commit -m "feat: add manual integration test script for auth throttle"
```

---

### Task 2: Verify the script against the dev server (email mode)

**Files:** none (verification only)

- [ ] **Step 1: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`. If not `200`, start the server in another terminal/background with `mix phx.server` and re-check before continuing.

- [ ] **Step 2: Run the script in email mode**

```bash
scripts/manual_tests/auth_throttle.sh email
```

Expected output (the generated email/timestamp will differ each run):

```
Testing email cooldown with manual-test-<timestamp>@example.com
PASS: first submission shows #magic-link-sent
PASS: second submission shows #magic-link-sent
PASS: exactly 1 email in /dev/mailbox
```

Exit code 0.

- [ ] **Step 3: If Step 2 fails**

Re-run the failing portion manually with `rodney` (browser stays open since the script's `trap` only fires on exit):

```bash
rodney start
rodney open http://localhost:4000/users/log-in && rodney waitload
rodney html "#magic-link-form"
```

Compare against the verified selectors in this plan's header (`#user_email`, `#magic-link-form button`, `#magic-link-sent`). Fix the script and re-run Step 2. Once it passes, `rodney stop`.

---

### Task 3: Create `docs/manual_tests.md`

**Files:**
- Create: `docs/manual_tests.md`

- [ ] **Step 1: Write the doc**

Write `docs/manual_tests.md` with this content:

```markdown
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
  that exactly one email was delivered. Prints `PASS`/`FAIL`.
- **Production:** `/dev/mailbox` doesn't exist, so confirm via one of:
  - a real inbox you control as the test email, checking it arrives exactly
    once, or
  - `fly logs --app speechwave | grep "auth_throttle: email cooldown"` —
    expect one line with `email_domain=example.com`.

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
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual_tests.md
git commit -m "docs: add manual integration test index for auth throttle"
```

---

### Task 4: Merge, deploy, and validate in production

**Files:** none (operational)

- [ ] **Step 1: Run `mix precommit`**

```bash
mix precommit
```

Expected: all checks pass (tests, credo, dialyzer).

- [ ] **Step 2: Merge `feat/magic-link-auth-throttle` into `main`**

Use the `superpowers:finishing-a-development-branch` flow (verify tests →
merge locally, per the user's earlier preference for this branch).

- [ ] **Step 3: STOP — get explicit go-ahead before deploying**

Do not run the next step until the user explicitly confirms. This deploys
to the live production service at `https://speechwave.live`.

```bash
fly deploy --app speechwave
```

- [ ] **Step 4: Validate in production**

```bash
scripts/manual_tests/auth_throttle.sh email --base-url https://speechwave.live
scripts/manual_tests/auth_throttle.sh ip --base-url https://speechwave.live
```

Both should print `PASS` lines for every `#magic-link-sent` assertion.

- [ ] **Step 5: Check logs**

```bash
fly logs --app speechwave | grep "auth_throttle: email cooldown"
fly logs --app speechwave | grep "auth_throttle: ip cooldown"
```

Expected: one `email cooldown` line (`email_domain=example.com`), and three
escalating `ip cooldown` lines (`cooldown_ms=60000 violation_count=1`,
`cooldown_ms=120000 violation_count=2`, `cooldown_ms=240000
violation_count=3`).

---

## Files touched

- `scripts/manual_tests/auth_throttle.sh` — new
- `docs/manual_tests.md` — new
