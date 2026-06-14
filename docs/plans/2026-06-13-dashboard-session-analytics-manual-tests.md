# Dashboard & Session Analytics Manual Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/manual_tests/lib.sh` (shared helpers + a magic-link login helper), `scripts/manual_tests/dashboard.sh`, `scripts/manual_tests/seed_sessions.exs`, `scripts/manual_tests/session_analytics.sh`, and two new `docs/manual_tests.md` sections, per `docs/specs/2026-06-13-dashboard-session-analytics-manual-tests-design.md`. Also refactor `scripts/manual_tests/auth_throttle.sh` to source the new shared helpers (no behavior change).

**Architecture:** `lib.sh` centralizes `--base-url` parsing, the `is_local`/`start_rodney` helpers (extracted from `auth_throttle.sh`), a `confirm_and_click` helper for `data-confirm` dialogs, and `complete_magic_link_login` — a dev-only helper that drives `/dev/mailbox` to complete a magic-link sign-in and lands on `/dashboard`. `dashboard.sh` and `session_analytics.sh` source `lib.sh` and drive `rodney` against the live dashboard/analytics LiveViews, asserting on rendered elements. `seed_sessions.exs` is a `mix run` script that seeds a talk with two finished sessions and reactions via `Speechwave.{Accounts, Talks, Reactions}`, used by `session_analytics.sh`.

**Tech Stack:** Bash (macOS default `/bin/bash` 3.2), `rodney` CLI, Phoenix dev server (`mix phx.server`), `/dev/mailbox` (Swoosh `Plug.Swoosh.MailboxPreview`), `mix run` for `seed_sessions.exs`.

**Verified against the running dev server (`http://localhost:4000`) during planning:**

- **Magic-link login lands on `/`, not `/dashboard`.** `UserAuth.signed_in_path/1` falls back to `~p"/"` for the magic-link redirect (`conn.assigns.current_scope` doesn't yet match `%Scope{user: %Accounts.User{}}` at that point). The session cookie *is* set correctly — an explicit follow-up `rodney open "$BASE_URL/dashboard"` succeeds and shows `#talk-list`. `complete_magic_link_login` must do this explicit navigation as its final step. (This corrects the spec, which has been updated to match.)
- Mailbox/login selectors (reused from `auth_throttle.sh`, all confirmed): `a[href^="/dev/mailbox/"]` (used only via `rodney count` to check the mailbox is non-empty before clearing), `form[action="/dev/mailbox/clear"] button` (only renders if mailbox non-empty), `#user_email`, `#magic-link-form button`, `#magic-link-sent`. After clearing the mailbox and sending exactly one magic link, `/dev/mailbox` itself — with no click into a specific message — directly renders `#email-details` and `#text-body-content` for that email (it auto-selects the most recent message). The magic-link URL is extracted from `#text-body-content` with `grep -o 'https\?://[^[:space:]]*/users/magic_link/[^[:space:]]*'`. The full `complete_magic_link_login` flow — clear mailbox, submit the form, extract the link from `/dev/mailbox`, follow it, then `rodney open "$BASE_URL/dashboard"` and confirm `#talk-list` — was re-run end-to-end immediately before writing this plan and works.
- Fresh free-tier user on `/dashboard`: `#sessions-used` = `0`, `#session-limit` = `10`, `#participant-limit` = `50`.
- Talk creation: typing into `#talk_title` and clicking `#talk-form button` (the only `<button>` in `#talk-form`) is sufficient — `phx-change="validate"` auto-fills `#talk_slug` via `Talks.generate_slug/1`. After submit: `#created-talk` appears, `#selected-talk-qr` renders containing `#talk-link` (text = `<base_url>/t/<slug>`), a QR code `<img>` plus `#download-qr-code` link, and `#no-sessions`. The new talk is auto-selected, so `#delete-talk-<id>` is present immediately — extract `<id>` with `rodney html "#talk-list" | grep -o 'id="delete-talk-[0-9]*"' | grep -o '[0-9]*'`.
- **`Talks.generate_slug/1` strips hyphens** (its regex `[^a-z0-9\s]` removes `-` along with other punctuation), so e.g. title `manual-test-1781410423` → slug `manualtest1781410423`. Don't assert a slug containing hyphens.
- **The `#copy-talk-link` icon toggle cannot be verified.** Its hook calls `navigator.clipboard.writeText(text).then(...)` with no `.catch()`. In headless Chrome (rodney's default), the Clipboard API has no permission grant, so the promise never resolves — `rodney js "navigator.clipboard.writeText('x')"` itself returns `error: JS error: context deadline exceeded` (exit 2). The `.then()` callback that swaps `.copy-icon-idle`/`.copy-icon-copied` never runs. `rodney click "#copy-talk-link"` itself does *not* hang (the click handler returns immediately; the unresolved promise is harmless), so the script can still click it, but must not assert on the icon classes changing. This is a headless-browser limitation, not an app bug.
- **`data-confirm` dialogs hang `rodney click` (and then the whole browser) forever.** `phx-click` elements with `data-confirm` (`#delete-talk-<id>`, `#delete-session-<id>`) trigger a native `window.confirm()`, which blocks the CDP connection with no handler — `rodney click` never returns, and subsequently even `rodney status`/`rodney stop`... no, `rodney stop` *does* still work and is the only recovery (kills the Chrome process). **Fix:** run `rodney js "(window.confirm = () => true)"` — a single assignment *expression* (not `;`-separated statements; `rodney js` evaluates one expression and a `SyntaxError` from multiple statements leaves `window.confirm` un-overridden, silently, with no visible error in a script that redirects stdout) — immediately before the click. Verified end-to-end: talk and session deletes both work this way, with the entry disappearing from the DOM afterward.
- **Sign-out**: the link is `<.link href="/users/log-out" method="delete">Log out</.link>` (text is "Log out", not "Sign out"; no `id`). Selector `a[href="/users/log-out"]` matches 2 elements (desktop/mobile nav); `rodney click 'a[href="/users/log-out"]'` clicks the first and works (Phoenix's JS intercepts and submits a hidden DELETE form). After clicking, the page lands on `/`. A subsequent `rodney open "$BASE_URL/dashboard"` redirects to `/users/log-in`.
- Talk selection on the dashboard: the talk-list button has no `id`, only `phx-click="show_qr"` — for a script that creates/seeds exactly one talk, `#talk-list li button` (single match) selects it, revealing `#selected-talk-qr` and `#sessions-panel`.
- Session rename: clicking `#rename-session-<id>` reveals `#rename-form-<id>`, which contains a *non-namespaced* `#rename_label` text input and a `button[type="submit"]`. After `rodney clear "#rename_label"`, `rodney input "#rename_label" "<new label>"`, and clicking `#rename-form-<id> button[type="submit"]`, the form disappears and `#session-label-<id>` shows the new text.
- `/sessions/<id>`: for the seeded session 1, `#total-reactions` text is `"3"`, `#slide-row-1` text contains both `🔥` and `❤️` (its `<span>`s render `Slide 1`, `❤️`, `1`, `🔥`, `1` — order between tied counts isn't guaranteed), and `#slide-row-2` text contains `🎉` (`Slide 2`, `🎉`, `1`).
- `/sessions/<id>/compare/<other_id>`: `#compare-section` renders with text containing "Comparing Session 1 vs Session 2", "Session 1", and "Session 2", followed by both sessions' slide breakdowns.
- `seed_sessions.exs` logic verified end-to-end via `mix run`: `Accounts.register_or_get_user_by_email/1` → `Scope.for_user/1` → `Talks.create_talk(scope, %{title: title, slug: Talks.generate_slug(title)})` → `Talks.start_session/1` (auto-labels "Session 1", then "Session 2" for the next one on the same talk) → `Reactions.create_reaction(session, emoji, slide_number)` → `Talks.stop_session/1`. `mix run scripts/manual_tests/seed_sessions.exs <email>` forwards `<email>` via `System.argv()`. `[debug]` SQL logs go to stderr, so `2>/dev/null` isolates the `KEY=value` stdout lines for parsing with `grep '^talk_id='` etc. `mix run` does not bind the HTTP port, so it's safe to run alongside `mix phx.server`.
- Bash 3.2 (macOS default `/bin/bash`, confirmed via `bash --version`) under `set -euo pipefail`: `arr=(); set -- "${arr[@]+"${arr[@]}"}"` correctly expands to zero arguments for an empty array (and to the array's elements for a non-empty one) — this is the safe idiom for `lib.sh`'s `parse_base_url`/`REMAINING_ARGS` design.

---

### Task 1: Create `scripts/manual_tests/lib.sh`

**Files:**
- Create: `scripts/manual_tests/lib.sh`

- [ ] **Step 1: Write the file**

```bash
# Shared helpers for scripts/manual_tests/*.sh.
# Source this file; it is not meant to be executed directly.
# See docs/manual_tests.md.

BASE_URL="http://localhost:4000"

# Parses --base-url URL out of "$@", setting BASE_URL. Any other arguments
# are left (in order) in the REMAINING_ARGS array for the caller to process.
parse_base_url() {
  REMAINING_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --base-url)
        BASE_URL="$2"
        shift 2
        ;;
      *)
        REMAINING_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

is_local() {
  case "$BASE_URL" in
    *localhost*|*127.0.0.1*) return 0 ;;
    *) return 1 ;;
  esac
}

start_rodney() {
  rodney start >/dev/null
  trap 'rodney stop >/dev/null' EXIT
}

# confirm_and_click SELECTOR
#
# Clicks an element with a data-confirm attribute, first overriding
# window.confirm so the native dialog (which would otherwise hang headless
# Chrome forever) is auto-accepted.
confirm_and_click() {
  local selector="$1"
  rodney js "(window.confirm = () => true)" >/dev/null
  rodney click "$selector" >/dev/null
}

# complete_magic_link_login BASE_URL EMAIL
#
# Dev-only: drives /dev/mailbox, which doesn't exist in production. On
# success, the browser is authenticated and on /dashboard with #talk-list
# present.
complete_magic_link_login() {
  local base_url="$1"
  local email="$2"

  case "$base_url" in
    *localhost*|*127.0.0.1*) ;;
    *)
      echo "ERROR: complete_magic_link_login requires a local --base-url (uses /dev/mailbox)." >&2
      echo "Re-run with --base-url http://localhost:4000" >&2
      exit 1
      ;;
  esac

  rodney open "$base_url/dev/mailbox" >/dev/null
  rodney waitload >/dev/null
  if [ "$(rodney count 'a[href^="/dev/mailbox/"]')" -gt 0 ]; then
    rodney click 'form[action="/dev/mailbox/clear"] button' >/dev/null
    rodney waitload >/dev/null
  fi

  rodney open "$base_url/users/log-in" >/dev/null
  rodney waitload >/dev/null
  rodney input "#user_email" "$email" >/dev/null
  rodney click "#magic-link-form button" >/dev/null
  rodney waitstable >/dev/null
  if ! rodney exists "#magic-link-sent" >/dev/null; then
    echo "FAIL: #magic-link-sent did not appear for $email at $base_url/users/log-in" >&2
    exit 1
  fi

  rodney open "$base_url/dev/mailbox" >/dev/null
  rodney waitload >/dev/null

  local magic_url
  magic_url=$(rodney text "#text-body-content" | grep -o 'https\?://[^[:space:]]*/users/magic_link/[^[:space:]]*' || true)
  if [ -z "$magic_url" ]; then
    echo "FAIL: could not find magic link URL in email body" >&2
    exit 1
  fi

  rodney open "$magic_url" >/dev/null
  rodney waitload >/dev/null

  rodney open "$base_url/dashboard" >/dev/null
  rodney waitload >/dev/null
  if ! rodney exists "#talk-list" >/dev/null; then
    echo "FAIL: #talk-list not present on $base_url/dashboard after magic-link login" >&2
    exit 1
  fi
}
```

- [ ] **Step 2: Check the file's syntax**

```bash
bash -n scripts/manual_tests/lib.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/manual_tests/lib.sh
git commit -m "feat: add shared lib.sh with magic-link login helper for manual tests"
```

---

### Task 2: Refactor `scripts/manual_tests/auth_throttle.sh` to source `lib.sh`

**Files:**
- Modify: `scripts/manual_tests/auth_throttle.sh`

- [ ] **Step 1: Rewrite the file**

Replace the entire contents of `scripts/manual_tests/auth_throttle.sh` with:

```bash
#!/usr/bin/env bash
# Manual integration test for Speechwave.AuthThrottle (magic-link sign-in).
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

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

parse_base_url "$@"
set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"

while [ $# -gt 0 ]; do
  case "$1" in
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

if [ "$MODE" = "ip" ] && is_local; then
  echo "ERROR: ip mode requires a production --base-url." >&2
  echo "Dev has no reverse proxy, so client_ip is always nil locally and" >&2
  echo "allow_ip?/1 is never called (documented fail-open behavior)." >&2
  echo "Re-run with --base-url https://speechwave.live" >&2
  exit 1
fi

start_rodney

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

- [ ] **Step 2: Check the file's syntax**

```bash
bash -n scripts/manual_tests/auth_throttle.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`. If not, start it with `mix phx.server` (in another terminal/background) before continuing.

- [ ] **Step 4: Run the refactored script in email mode (regression check)**

```bash
scripts/manual_tests/auth_throttle.sh email
```

Expected output (timestamp differs each run):

```
Testing email cooldown with manual-test-<timestamp>@example.com
PASS: first submission shows #magic-link-sent
PASS: second submission shows #magic-link-sent
PASS: exactly 1 email in /dev/mailbox
```

Exit code 0. This confirms the `lib.sh` refactor didn't change behavior.

- [ ] **Step 5: Commit**

```bash
git add scripts/manual_tests/auth_throttle.sh
git commit -m "refactor: source shared lib.sh from auth_throttle.sh"
```

---

### Task 3: Create `scripts/manual_tests/seed_sessions.exs`

**Files:**
- Create: `scripts/manual_tests/seed_sessions.exs`

- [ ] **Step 1: Write the file**

```elixir
# Manual integration test fixture: seeds a talk with two finished sessions
# and reactions, for scripts/manual_tests/session_analytics.sh.
# See docs/manual_tests.md.
#
# Usage: mix run scripts/manual_tests/seed_sessions.exs <email>
#
# Prints email=, talk_id=, session1_id=, session2_id= on stdout.

alias Speechwave.{Accounts, Talks, Reactions}
alias Speechwave.Accounts.Scope

[email | _] = System.argv()

{:ok, user} = Accounts.register_or_get_user_by_email(email)
scope = Scope.for_user(user)

title = "manual-test-#{System.system_time(:second)}"
slug = Talks.generate_slug(title)
{:ok, talk} = Talks.create_talk(scope, %{title: title, slug: slug})

{:ok, session1} = Talks.start_session(talk)
Reactions.create_reaction(session1, "🔥", 1)
Reactions.create_reaction(session1, "❤️", 1)
Reactions.create_reaction(session1, "🎉", 2)
{:ok, session1} = Talks.stop_session(session1)

{:ok, session2} = Talks.start_session(talk)
Reactions.create_reaction(session2, "🔥", 1)
Reactions.create_reaction(session2, "👏", 2)
{:ok, session2} = Talks.stop_session(session2)

IO.puts("email=#{email}")
IO.puts("talk_id=#{talk.id}")
IO.puts("session1_id=#{session1.id}")
IO.puts("session2_id=#{session2.id}")
```

- [ ] **Step 2: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`.

- [ ] **Step 3: Run it against the dev database**

```bash
mix run scripts/manual_tests/seed_sessions.exs "manual-test-$(date +%s)@example.com" 2>/dev/null
```

Expected output (numbers will differ):

```
email=manual-test-<timestamp>@example.com
talk_id=<N>
session1_id=<M>
session2_id=<M+1>
```

- [ ] **Step 4: Commit**

```bash
git add scripts/manual_tests/seed_sessions.exs
git commit -m "feat: add seed_sessions.exs manual-test fixture script"
```

---

### Task 4: Create `scripts/manual_tests/dashboard.sh`

**Files:**
- Create: `scripts/manual_tests/dashboard.sh`

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# Manual integration test for the speaker dashboard (login, talk CRUD).
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_base_url "$@"

if ! is_local; then
  echo "ERROR: dashboard.sh requires a local --base-url (uses /dev/mailbox via complete_magic_link_login)." >&2
  echo "Re-run with --base-url http://localhost:4000" >&2
  exit 1
fi

start_rodney

EMAIL="manual-test-$(date +%s)@example.com"
echo "Testing dashboard flow as $EMAIL"

complete_magic_link_login "$BASE_URL" "$EMAIL"
echo "PASS: logged in via magic link, #talk-list present on /dashboard"

sessions_used=$(rodney text "#sessions-used")
session_limit=$(rodney text "#session-limit")
participant_limit=$(rodney text "#participant-limit")
if [ "$sessions_used" = "0" ] && [ "$session_limit" = "10" ] && [ "$participant_limit" = "50" ]; then
  echo "PASS: plan usage shows 0/10 sessions, 50 participant limit"
else
  echo "FAIL: expected sessions_used=0 session_limit=10 participant_limit=50, got $sessions_used/$session_limit/$participant_limit" >&2
  exit 1
fi

TITLE="manual-test-$(date +%s)"
rodney input "#talk_title" "$TITLE" >/dev/null
rodney click "#talk-form button" >/dev/null
rodney waitstable >/dev/null

if ! rodney exists "#created-talk" >/dev/null; then
  echo "FAIL: #created-talk did not appear after creating talk" >&2
  exit 1
fi

if ! rodney exists "#selected-talk-qr" >/dev/null; then
  echo "FAIL: #selected-talk-qr did not render after creating talk" >&2
  exit 1
fi

talk_link=$(rodney text "#talk-link")
case "$talk_link" in
  "$BASE_URL"/t/*) ;;
  *)
    echo "FAIL: #talk-link was '$talk_link', expected $BASE_URL/t/<slug>" >&2
    exit 1
    ;;
esac

if ! rodney exists "#no-sessions" >/dev/null; then
  echo "FAIL: #no-sessions did not appear for a brand-new talk" >&2
  exit 1
fi

if ! rodney exists "#download-qr-code" >/dev/null; then
  echo "FAIL: #download-qr-code (QR code) did not render after creating talk" >&2
  exit 1
fi
echo "PASS: #created-talk appears, #selected-talk-qr renders with #talk-link ($talk_link), QR code, and #no-sessions"

talk_id=$(rodney html "#talk-list" | grep -o 'id="delete-talk-[0-9]*"' | grep -o '[0-9]*' || true)
if [ -z "$talk_id" ]; then
  echo "FAIL: could not find delete-talk-<id> in #talk-list" >&2
  exit 1
fi

if rodney visible ".copy-icon-idle" >/dev/null && ! rodney visible ".copy-icon-copied" >/dev/null; then
  echo "PASS: copy-link button renders with idle icon visible, copied icon hidden"
else
  echo "FAIL: unexpected initial state for #copy-talk-link icons" >&2
  exit 1
fi
rodney click "#copy-talk-link" >/dev/null
echo "NOTE: #copy-talk-link clicked; icon-toggle on successful clipboard write is not verified -- headless Chrome has no clipboard permission, so navigator.clipboard.writeText() never resolves"

confirm_and_click "#delete-talk-$talk_id"
rodney waitstable >/dev/null
if rodney exists "#delete-talk-$talk_id" >/dev/null || rodney exists "#selected-talk-qr" >/dev/null; then
  echo "FAIL: talk $talk_id (or #selected-talk-qr) still present after delete" >&2
  exit 1
fi
echo "PASS: talk $talk_id deleted, #talk-list no longer shows it and #selected-talk-qr is gone"

rodney click 'a[href="/users/log-out"]' >/dev/null
rodney waitload >/dev/null
rodney open "$BASE_URL/dashboard" >/dev/null
rodney waitload >/dev/null
url=$(rodney url)
case "$url" in
  "$BASE_URL"/users/log-in*)
    echo "PASS: signed out, /dashboard redirects to /users/log-in"
    ;;
  *)
    echo "FAIL: expected /dashboard to redirect to /users/log-in after sign out, got $url" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/manual_tests/dashboard.sh
```

- [ ] **Step 3: Check the file's syntax**

```bash
bash -n scripts/manual_tests/dashboard.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`.

- [ ] **Step 5: Run it against the dev server**

```bash
scripts/manual_tests/dashboard.sh
```

Expected output (timestamps/ids differ each run):

```
Testing dashboard flow as manual-test-<timestamp>@example.com
PASS: logged in via magic link, #talk-list present on /dashboard
PASS: plan usage shows 0/10 sessions, 50 participant limit
PASS: #created-talk appears, #selected-talk-qr renders with #talk-link (http://localhost:4000/t/manualtest<timestamp>), QR code, and #no-sessions
PASS: copy-link button renders with idle icon visible, copied icon hidden
NOTE: #copy-talk-link clicked; icon-toggle on successful clipboard write is not verified -- headless Chrome has no clipboard permission, so navigator.clipboard.writeText() never resolves
PASS: talk <id> deleted, #talk-list no longer shows it and #selected-talk-qr is gone
PASS: signed out, /dashboard redirects to /users/log-in
```

Exit code 0.

- [ ] **Step 6: If Step 5 fails**

The browser stays open (the `trap` only fires on script exit), so inspect live state:

```bash
rodney url
rodney html "#talk-list"
```

Compare against the selectors verified in this plan's header. Fix the script, then `rodney stop` and re-run Step 5.

- [ ] **Step 7: Commit**

```bash
git add scripts/manual_tests/dashboard.sh
git commit -m "feat: add manual integration test script for the speaker dashboard"
```

---

### Task 5: Create `scripts/manual_tests/session_analytics.sh`

**Files:**
- Create: `scripts/manual_tests/session_analytics.sh`

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# Manual integration test for session analytics (view, compare, rename, delete).
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_base_url "$@"

if ! is_local; then
  echo "ERROR: session_analytics.sh requires a local --base-url (uses /dev/mailbox via complete_magic_link_login, and mix run for seeding)." >&2
  echo "Re-run with --base-url http://localhost:4000" >&2
  exit 1
fi

EMAIL="manual-test-$(date +%s)@example.com"
echo "Seeding sessions for $EMAIL"

seed_output=$(cd "$PROJECT_ROOT" && mix run scripts/manual_tests/seed_sessions.exs "$EMAIL" 2>/dev/null)
talk_id=$(echo "$seed_output" | grep '^talk_id=' | cut -d= -f2 || true)
session1_id=$(echo "$seed_output" | grep '^session1_id=' | cut -d= -f2 || true)
session2_id=$(echo "$seed_output" | grep '^session2_id=' | cut -d= -f2 || true)

if [ -z "$talk_id" ] || [ -z "$session1_id" ] || [ -z "$session2_id" ]; then
  echo "FAIL: could not parse seed_sessions.exs output:" >&2
  echo "$seed_output" >&2
  exit 1
fi
echo "Seeded talk_id=$talk_id session1_id=$session1_id session2_id=$session2_id"

start_rodney

complete_magic_link_login "$BASE_URL" "$EMAIL"
echo "PASS: logged in via magic link, #talk-list present on /dashboard"

rodney open "$BASE_URL/sessions/$session1_id" >/dev/null
rodney waitload >/dev/null
total_reactions=$(rodney text "#total-reactions")
slide1=$(rodney text "#slide-row-1")
slide2=$(rodney text "#slide-row-2")
if [ "$total_reactions" = "3" ] \
  && echo "$slide1" | grep -q "🔥" && echo "$slide1" | grep -q "❤️" \
  && echo "$slide2" | grep -q "🎉"; then
  echo "PASS: /sessions/$session1_id shows #total-reactions=3, #slide-row-1 (🔥 ❤️) and #slide-row-2 (🎉)"
else
  echo "FAIL: expected #total-reactions=3, #slide-row-1 with 🔥+❤️, #slide-row-2 with 🎉; got total_reactions=$total_reactions slide1='$slide1' slide2='$slide2'" >&2
  exit 1
fi

rodney open "$BASE_URL/sessions/$session1_id/compare/$session2_id" >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#compare-section" >/dev/null; then
  echo "FAIL: #compare-section did not render" >&2
  exit 1
fi
compare_text=$(rodney text "#compare-section")
if echo "$compare_text" | grep -q "Session 1" && echo "$compare_text" | grep -q "Session 2"; then
  echo "PASS: #compare-section renders for /sessions/$session1_id/compare/$session2_id, showing Session 1 and Session 2"
else
  echo "FAIL: #compare-section did not show both Session 1 and Session 2 labels: $compare_text" >&2
  exit 1
fi

rodney open "$BASE_URL/dashboard" >/dev/null
rodney waitload >/dev/null
rodney click "#talk-list li button" >/dev/null
rodney waitstable >/dev/null
if rodney exists "#session-$session1_id" >/dev/null && rodney exists "#session-$session2_id" >/dev/null; then
  echo "PASS: #sessions-panel lists #session-$session1_id and #session-$session2_id"
else
  echo "FAIL: expected both sessions in #sessions-panel" >&2
  exit 1
fi

rodney click "#rename-session-$session1_id" >/dev/null
rodney waitstable >/dev/null
rodney clear "#rename_label" >/dev/null
rodney input "#rename_label" "Opening Keynote" >/dev/null
rodney click "#rename-form-$session1_id button[type=\"submit\"]" >/dev/null
rodney waitstable >/dev/null
label=$(rodney text "#session-label-$session1_id")
if [ "$label" = "Opening Keynote" ]; then
  echo "PASS: #session-label-$session1_id updated to 'Opening Keynote'"
else
  echo "FAIL: expected #session-label-$session1_id='Opening Keynote', got '$label'" >&2
  exit 1
fi

confirm_and_click "#delete-session-$session2_id"
rodney waitstable >/dev/null
if rodney exists "#session-$session2_id" >/dev/null; then
  echo "FAIL: #session-$session2_id still present after delete" >&2
  exit 1
fi
echo "PASS: #session-$session2_id deleted"

confirm_and_click "#delete-talk-$talk_id"
rodney waitstable >/dev/null
if rodney exists "#delete-talk-$talk_id" >/dev/null; then
  echo "FAIL: #delete-talk-$talk_id still present after delete" >&2
  exit 1
fi
echo "PASS: talk $talk_id deleted (cleanup)"

rodney click 'a[href="/users/log-out"]' >/dev/null
rodney waitload >/dev/null
rodney open "$BASE_URL/dashboard" >/dev/null
rodney waitload >/dev/null
url=$(rodney url)
case "$url" in
  "$BASE_URL"/users/log-in*)
    echo "PASS: signed out, /dashboard redirects to /users/log-in"
    ;;
  *)
    echo "FAIL: expected /dashboard to redirect to /users/log-in after sign out, got $url" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/manual_tests/session_analytics.sh
```

- [ ] **Step 3: Check the file's syntax**

```bash
bash -n scripts/manual_tests/session_analytics.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`.

- [ ] **Step 5: Run it against the dev server**

```bash
scripts/manual_tests/session_analytics.sh
```

Expected output (timestamps/ids differ each run):

```
Seeding sessions for manual-test-<timestamp>@example.com
Seeded talk_id=<N> session1_id=<M> session2_id=<M+1>
PASS: logged in via magic link, #talk-list present on /dashboard
PASS: /sessions/<M> shows #total-reactions=3, #slide-row-1 (🔥 ❤️) and #slide-row-2 (🎉)
PASS: #compare-section renders for /sessions/<M>/compare/<M+1>, showing Session 1 and Session 2
PASS: #sessions-panel lists #session-<M> and #session-<M+1>
PASS: #session-label-<M> updated to 'Opening Keynote'
PASS: #session-<M+1> deleted
PASS: talk <N> deleted (cleanup)
PASS: signed out, /dashboard redirects to /users/log-in
```

Exit code 0.

- [ ] **Step 6: If Step 5 fails**

The browser stays open (the `trap` only fires on script exit), so inspect live state:

```bash
rodney url
rodney html "#sessions-panel"
```

Compare against the selectors verified in this plan's header. Fix the script, then `rodney stop` and re-run Step 5.

- [ ] **Step 7: Commit**

```bash
git add scripts/manual_tests/session_analytics.sh
git commit -m "feat: add manual integration test script for session analytics"
```

---

### Task 6: Update `docs/manual_tests.md`

**Files:**
- Modify: `docs/manual_tests.md`

- [ ] **Step 1: Update the "Conventions for new sections" paragraph**

Find this paragraph (currently the last paragraph of the "Conventions for new sections" section):

```markdown
`scripts/manual_tests/auth_throttle.sh` is the first script and currently
owns its full `rodney` lifecycle (start/stop trap), `--base-url`/mode
argument parsing, and `is_local()` helper inline. When a second script is
added, factor those shared pieces into `scripts/manual_tests/lib.sh` so both
scripts source it instead of duplicating.
```

Replace it with:

```markdown
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
```

- [ ] **Step 2: Add the "Speaker dashboard" section**

Add this new `##` section after the "Magic-link auth throttle" section (after its "IP cooldown" subsection, at the end of the file before this edit):

```markdown
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
```

- [ ] **Step 3: Add the "Session analytics" section**

Add this new `##` section after the "Speaker dashboard" section:

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
git add docs/manual_tests.md
git commit -m "docs: add manual test sections for speaker dashboard and session analytics"
```

---

### Task 7: Final precommit check

**Files:** none (verification only)

- [ ] **Step 1: Run `mix precommit`**

```bash
mix precommit
```

Expected: all checks pass (compile, deps.unlock, format, test, lint, static).
None of this plan's files are Elixir source under `lib/`/`test/`, so this is
a regression check that nothing else broke.

- [ ] **Step 2: If `mix precommit` fails**

Fix the reported issue, re-run Step 1, then commit the fix with a message
describing what was fixed.

---

## Files touched

- `scripts/manual_tests/lib.sh` — new
- `scripts/manual_tests/auth_throttle.sh` — refactored to source `lib.sh`
- `scripts/manual_tests/seed_sessions.exs` — new
- `scripts/manual_tests/dashboard.sh` — new
- `scripts/manual_tests/session_analytics.sh` — new
- `docs/manual_tests.md` — two new sections, "Conventions" paragraph updated
