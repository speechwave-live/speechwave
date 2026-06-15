# Account Settings Manual Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/manual_tests/account_settings.sh` covering `SpeechwaveWeb.UserLive.Settings` (API key regeneration, email change round-trip, connected-accounts render check), refactor `lib.sh` to extract a `clear_dev_mailbox` helper, wire `account_settings.sh` into `run_all_dev.sh`, add a `docs/manual_tests.md` section, and update `docs/roadmap.md`, per `docs/specs/2026-06-15-account-settings-manual-tests-design.md`.

**Architecture:** `clear_dev_mailbox` replaces three copies of the same 5-line inline block (in `auth_throttle.sh`, in `complete_magic_link_login`, and in the new script's email-change step). `account_settings.sh` sources `lib.sh`, runs as a fresh free-tier user created by `complete_magic_link_login`, exercises `/users/settings` — API key regen via `#regenerate-api-key-btn`, then a full email-change round trip through `/dev/mailbox` and the `/users/settings/confirm-email/:token` route — then signs out.

**Tech Stack:** Bash (macOS `/bin/bash` 3.2), `rodney` CLI, Phoenix dev server (`mix phx.server`), `/dev/mailbox` (`Plug.Swoosh.MailboxPreview`).

**Implementation notes (from source inspection — verify against the running dev server during Task 3):**

- `/users/settings` is inside `live_session :require_authenticated_user` with `on_mount {SpeechwaveWeb.UserAuth, :require_sudo_mode}`. Sudo mode requires `authenticated_at` within the last 10 minutes; since `complete_magic_link_login` sets it to "now," navigating to `/users/settings` immediately after login will pass.
- `#email_form` has one button (`<.button variant="primary" phx-disable-with="Changing...">Change Email</.button>`), rendered as `<button>` inside `<form id="email_form">`. Selector `#email_form button` matches it.
- `#api-key-display` is a `readonly` `<input type="text">` whose `value` attribute is updated by LiveView morphdom when `regenerate_api_key` fires. Use `rodney js "document.querySelector('#api-key-display').value"` (reads the DOM property, not the HTML attribute) to reliably capture the post-update value.
- `#regenerate-api-key-btn` has `data-confirm` — must use `confirm_and_click`.
- The "Update email instructions" email is sent to the **new** email address (the `UserNotifier.deliver_update_email_instructions` call receives the changeset-applied user, whose `email` field is already the new address). After `clear_dev_mailbox` + form submit, `/dev/mailbox` auto-redirects to the single new message. `#email-details__subject` and `#email-details__to` each contain both a `<dt>` label and `<dd>` value — `rodney text` returns both concatenated, so use `grep -q` rather than exact string equality for assertions.
- The `/users/settings/confirm-email/:token` URL is in `#text-body-content`. Extract with `grep -o 'https\?://[^[:space:]]*/users/settings/confirm-email/[^[:space:]]*'` — same pattern as `complete_magic_link_login` uses for magic links.
- After `rodney open "$confirm_url"`, the LiveView mounts, calls `push_navigate(to: ~p"/users/settings")` via the WebSocket (async after initial page load). Use `rodney waitstable` (not just `waitload`) to cover this async hop. If `#flash-info` or the updated `#user_email` value is not present after `waitstable` during testing, add `rodney waitload >/dev/null` immediately before `rodney waitstable >/dev/null`.
- `#user_email` value after confirm-email redirect: the re-mount calls `Accounts.change_user_email(user, %{}, validate_unique: false)` where `user` is now the updated user with new email; the form's initial value reflects the new email. Read with `rodney attr "#user_email" value` (safe here — this is a fresh full-page render, not a LiveView patch, so the HTML attribute and DOM property are in sync).
- `#flash-info` only exists in the DOM when an `:info` flash is set (the `<div :if={msg = ...}>` renders conditionally). `rodney exists "#flash-info"` is sufficient; no need to assert the exact text.
- OAuth section: for a brand-new user with no identities, the template renders `<.link id={"connect-#{provider}"}` (not a disconnect button) for all three providers. Selector `#connect-google`, `#connect-microsoft`, `#connect-github`.
- Sign-out selector: `a[href="/users/log-out"]` (two matches in nav — desktop and mobile; `rodney click` hits the first). After sign-out, browser lands on `/`. A subsequent `rodney open "$BASE_URL/dashboard"` redirects to `/users/log-in` (same pattern as all other scripts).

---

### Task 1: Add `clear_dev_mailbox` to `lib.sh` and update `complete_magic_link_login`

**Files:**
- Modify: `scripts/manual_tests/lib.sh`

- [ ] **Step 1: Add `clear_dev_mailbox` helper and update `complete_magic_link_login`**

Replace the entire contents of `scripts/manual_tests/lib.sh` with:

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

# clear_dev_mailbox BASE_URL
#
# Opens /dev/mailbox and clears it if any messages are present. Callers are
# responsible for ensuring BASE_URL is local before calling.
clear_dev_mailbox() {
  local base_url="$1"
  rodney open "$base_url/dev/mailbox" >/dev/null
  rodney waitload >/dev/null
  if [ "$(rodney count 'a[href^="/dev/mailbox/"]')" -gt 0 ]; then
    rodney click 'form[action="/dev/mailbox/clear"] button' >/dev/null
    rodney waitload >/dev/null
  fi
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

  clear_dev_mailbox "$base_url"

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

- [ ] **Step 2: Check syntax**

```bash
bash -n scripts/manual_tests/lib.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/manual_tests/lib.sh
git commit -m "refactor: extract clear_dev_mailbox helper into lib.sh"
```

---

### Task 2: Refactor `auth_throttle.sh` to use `clear_dev_mailbox`

**Files:**
- Modify: `scripts/manual_tests/auth_throttle.sh`

The only change is replacing the 5-line inline clear block (inside `if is_local; then`) with a `clear_dev_mailbox` call. Everything else stays identical.

- [ ] **Step 1: Replace the inline clear block**

In `scripts/manual_tests/auth_throttle.sh`, find this block in the `email)` case:

```bash
    if is_local; then
      rodney open "$BASE_URL/dev/mailbox" >/dev/null
      rodney waitload >/dev/null
      if [ "$(rodney count 'a[href^="/dev/mailbox/"]')" -gt 0 ]; then
        rodney click 'form[action="/dev/mailbox/clear"] button' >/dev/null
        rodney waitload >/dev/null
      fi
    fi
```

Replace it with:

```bash
    if is_local; then
      clear_dev_mailbox "$BASE_URL"
    fi
```

- [ ] **Step 2: Check syntax**

```bash
bash -n scripts/manual_tests/auth_throttle.sh
```

Expected: no output, exit code 0.

- [ ] **Step 3: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`. If not, start it with `mix phx.server` in another terminal before continuing.

- [ ] **Step 4: Run the refactored script (regression check)**

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

Exit code 0. This confirms `clear_dev_mailbox` behaves identically to the inline block.

- [ ] **Step 5: Commit**

```bash
git add scripts/manual_tests/auth_throttle.sh
git commit -m "refactor: use clear_dev_mailbox helper in auth_throttle.sh"
```

---

### Task 3: Create `scripts/manual_tests/account_settings.sh`

**Files:**
- Create: `scripts/manual_tests/account_settings.sh`

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# Manual integration test for account settings (API key regen, email change).
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_base_url "$@"

if ! is_local; then
  echo "ERROR: account_settings.sh requires a local --base-url (uses /dev/mailbox" >&2
  echo "via complete_magic_link_login and for the email-change confirmation)." >&2
  echo "Re-run with --base-url http://localhost:4000" >&2
  exit 1
fi

start_rodney

TS="$(date +%s)"
EMAIL="manual-test-${TS}@example.com"
NEW_EMAIL="manual-test-${TS}-new@example.com"
echo "Testing account settings as $EMAIL (new email: $NEW_EMAIL)"

complete_magic_link_login "$BASE_URL" "$EMAIL"
echo "PASS: logged in via magic link, #talk-list present on /dashboard"

rodney open "$BASE_URL/users/settings" >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#email_form" >/dev/null \
  || ! rodney exists "#api-key-display" >/dev/null \
  || ! rodney exists "#connected-accounts" >/dev/null; then
  echo "FAIL: /users/settings did not render #email_form, #api-key-display, and #connected-accounts" >&2
  exit 1
fi
echo "PASS: /users/settings renders with #email_form, #api-key-display, and #connected-accounts (sudo mode passed)"

for provider in google microsoft github; do
  if ! rodney exists "#connect-$provider" >/dev/null; then
    echo "FAIL: #connect-$provider not present (expected no providers connected for a new user)" >&2
    exit 1
  fi
done
echo "PASS: #connect-google, #connect-microsoft, #connect-github all present (no providers connected)"

old_key=$(rodney js "document.querySelector('#api-key-display').value")
confirm_and_click "#regenerate-api-key-btn"
rodney waitstable >/dev/null
new_key=$(rodney js "document.querySelector('#api-key-display').value")
if [ -n "$new_key" ] && [ "$new_key" != "$old_key" ]; then
  echo "PASS: #api-key-display updated after regeneration (old and new keys differ)"
else
  echo "FAIL: expected #api-key-display to change after regeneration; old=$old_key new=$new_key" >&2
  exit 1
fi

clear_dev_mailbox "$BASE_URL"

rodney clear "#user_email" >/dev/null
rodney input "#user_email" "$NEW_EMAIL" >/dev/null
rodney click "#email_form button" >/dev/null
rodney waitstable >/dev/null
if ! rodney exists "#flash-info" >/dev/null; then
  echo "FAIL: #flash-info did not appear after submitting email change to $NEW_EMAIL" >&2
  exit 1
fi
echo "PASS: #flash-info appeared after submitting email change for $NEW_EMAIL"

rodney open "$BASE_URL/dev/mailbox" >/dev/null
rodney waitload >/dev/null
subject_text=$(rodney text "#email-details__subject")
to_text=$(rodney text "#email-details__to")
if ! echo "$subject_text" | grep -q "Update email instructions"; then
  echo "FAIL: expected subject to contain 'Update email instructions', got '$subject_text'" >&2
  exit 1
fi
if ! echo "$to_text" | grep -q "$NEW_EMAIL"; then
  echo "FAIL: expected #email-details__to to contain '$NEW_EMAIL', got '$to_text'" >&2
  exit 1
fi
echo "PASS: /dev/mailbox has 'Update email instructions' email addressed to $NEW_EMAIL"

confirm_url=$(rodney text "#text-body-content" | grep -o 'https\?://[^[:space:]]*/users/settings/confirm-email/[^[:space:]]*' || true)
if [ -z "$confirm_url" ]; then
  echo "FAIL: could not find /users/settings/confirm-email/ URL in email body" >&2
  exit 1
fi

rodney open "$confirm_url" >/dev/null
rodney waitstable >/dev/null
if ! rodney exists "#flash-info" >/dev/null; then
  echo "FAIL: #flash-info did not appear after visiting confirm-email URL" >&2
  exit 1
fi
confirmed_email=$(rodney attr "#user_email" value)
if [ "$confirmed_email" = "$NEW_EMAIL" ]; then
  echo "PASS: email changed to $NEW_EMAIL (#flash-info present, #user_email reflects new address)"
else
  echo "FAIL: expected #user_email value '$NEW_EMAIL' after email change, got '$confirmed_email'" >&2
  exit 1
fi

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
chmod +x scripts/manual_tests/account_settings.sh
```

- [ ] **Step 3: Check syntax**

```bash
bash -n scripts/manual_tests/account_settings.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`.

- [ ] **Step 5: Run it against the dev server**

```bash
scripts/manual_tests/account_settings.sh
```

Expected output (timestamps differ each run):

```
Testing account settings as manual-test-<timestamp>@example.com (new email: manual-test-<timestamp>-new@example.com)
PASS: logged in via magic link, #talk-list present on /dashboard
PASS: /users/settings renders with #email_form, #api-key-display, and #connected-accounts (sudo mode passed)
PASS: #connect-google, #connect-microsoft, #connect-github all present (no providers connected)
PASS: #api-key-display updated after regeneration (old and new keys differ)
PASS: #flash-info appeared after submitting email change for manual-test-<timestamp>-new@example.com
PASS: /dev/mailbox has 'Update email instructions' email addressed to manual-test-<timestamp>-new@example.com
PASS: email changed to manual-test-<timestamp>-new@example.com (#flash-info present, #user_email reflects new address)
PASS: signed out, /dashboard redirects to /users/log-in
```

Exit code 0.

- [ ] **Step 6: If the confirm-email step fails**

The `push_navigate` from the confirm-email mount happens over the WebSocket, asynchronously after the initial page load. If `#flash-info` or the updated `#user_email` value isn't present after `waitstable`, add a `rodney waitload >/dev/null` immediately before `rodney waitstable >/dev/null` in the confirm-email block and re-run:

```bash
rodney open "$confirm_url" >/dev/null
rodney waitload >/dev/null   # <-- add this line
rodney waitstable >/dev/null
```

- [ ] **Step 7: If any other step fails**

The browser stays open (trap fires on script exit only). Inspect live state:

```bash
rodney url
rodney html "#email_form"
rodney html "#api-key-display"
```

Fix the script, then `rodney stop` before re-running.

- [ ] **Step 8: Commit**

```bash
git add scripts/manual_tests/account_settings.sh
git commit -m "feat: add manual integration test script for account settings"
```

---

### Task 4: Update `scripts/manual_tests/run_all_dev.sh`

**Files:**
- Modify: `scripts/manual_tests/run_all_dev.sh`

Two changes: add the fifth script to the `run_script` chain, and update the error message that names the scripts.

- [ ] **Step 1: Add `account_settings.sh` to the run chain**

Find this block:

```bash
run_script "auth_throttle.sh email" "$SCRIPT_DIR/auth_throttle.sh" --base-url "$BASE_URL" email
run_script "dashboard.sh"           "$SCRIPT_DIR/dashboard.sh" --base-url "$BASE_URL"
run_script "session_analytics.sh"   "$SCRIPT_DIR/session_analytics.sh" --base-url "$BASE_URL"
run_script "reaction_flow.sh"       "$SCRIPT_DIR/reaction_flow.sh" --base-url "$BASE_URL"
```

Replace it with:

```bash
run_script "auth_throttle.sh email" "$SCRIPT_DIR/auth_throttle.sh" --base-url "$BASE_URL" email
run_script "dashboard.sh"           "$SCRIPT_DIR/dashboard.sh" --base-url "$BASE_URL"
run_script "session_analytics.sh"   "$SCRIPT_DIR/session_analytics.sh" --base-url "$BASE_URL"
run_script "reaction_flow.sh"       "$SCRIPT_DIR/reaction_flow.sh" --base-url "$BASE_URL"
run_script "account_settings.sh"    "$SCRIPT_DIR/account_settings.sh" --base-url "$BASE_URL"
```

- [ ] **Step 2: Update the error message**

Find:

```bash
  echo "(auth_throttle.sh email mode, dashboard.sh, session_analytics.sh," >&2
  echo "reaction_flow.sh)." >&2
```

Replace with:

```bash
  echo "(auth_throttle.sh email mode, dashboard.sh, session_analytics.sh," >&2
  echo "reaction_flow.sh, account_settings.sh)." >&2
```

- [ ] **Step 3: Check syntax**

```bash
bash -n scripts/manual_tests/run_all_dev.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/manual_tests/run_all_dev.sh
git commit -m "feat: add account_settings.sh to run_all_dev.sh chain"
```

---

### Task 5: Update `docs/manual_tests.md` and `docs/roadmap.md`

**Files:**
- Modify: `docs/manual_tests.md`
- Modify: `docs/roadmap.md`

- [ ] **Step 1: Update the Quick-start paragraph in `docs/manual_tests.md`**

Find:

```markdown
(default `http://localhost:4000`). This runs `auth_throttle.sh email`,
`dashboard.sh`, `session_analytics.sh`, and `reaction_flow.sh` back-to-back,
```

Replace with:

```markdown
(default `http://localhost:4000`). This runs `auth_throttle.sh email`,
`dashboard.sh`, `session_analytics.sh`, `reaction_flow.sh`, and
`account_settings.sh` back-to-back,
```

- [ ] **Step 2: Update the `run_all_dev.sh` dev-only note**

Find:

```markdown
**Dev-only** — refuses a non-local `--base-url`, since three of the four
scripts depend on `/dev/mailbox` and `mix run` for seeding. The `ip`-cooldown
```

Replace with:

```markdown
**Dev-only** — refuses a non-local `--base-url`, since four of the five
scripts depend on `/dev/mailbox` and `mix run` for seeding. The `ip`-cooldown
```

- [ ] **Step 3: Add the `## Account settings` section to `docs/manual_tests.md`**

Add this new section after the `## Attendee reaction flow` section (at the end of the file):

```markdown
## Account settings

Tests `SpeechwaveWeb.UserLive.Settings` (`/users/settings`): a light-touch
render check of the Connected Accounts section, API key regeneration, and a
full email-change round trip (form submit → confirmation email → click link →
email updated in the UI).

Script: `scripts/manual_tests/account_settings.sh [--base-url URL]` (default
`http://localhost:4000`)

**Dev-only** — exits with an error against a non-local `--base-url`, since
`complete_magic_link_login` depends on `/dev/mailbox` for the initial login
and the email-change step reads the confirmation email from `/dev/mailbox` as
well. See "SSH/eval magic-link-token helper for production runs" in
`docs/roadmap.md` for the planned production path.

OAuth connect/disconnect is out of scope — it requires real provider
credentials and driving a third-party consent UI. It has its own entry in
`docs/roadmap.md`.

As a fresh user (`manual-test-<timestamp>@example.com`, and
`manual-test-<timestamp>-new@example.com` for the new address):

1. Logs in via magic link (`complete_magic_link_login`), landing on
   `/dashboard` with `#talk-list` present.
2. Opens `/users/settings`. Checks `#email_form`, `#api-key-display`, and
   `#connected-accounts` all render (confirms the page loaded and the
   freshly-authenticated session passed the `require_sudo_mode` check).
3. Checks `#connect-google`, `#connect-microsoft`, and `#connect-github` all
   exist — no OAuth providers connected for a brand-new user.
4. Reads the current API key from `#api-key-display`, clicks
   `#regenerate-api-key-btn` (auto-accepting the `data-confirm` dialog),
   re-reads the key. Checks it changed and is non-empty.
5. Clears `/dev/mailbox`, then submits `#email_form` with the new address.
   Checks `#flash-info` appears (the "A link to confirm your email change has
   been sent to the new address." flash).
6. Opens `/dev/mailbox` (auto-redirects to the single new message). Checks
   `#email-details__subject` contains "Update email instructions" and
   `#email-details__to` contains the new address.
7. Extracts the `/users/settings/confirm-email/:token` URL from
   `#text-body-content` and navigates to it. The LiveView mounts, updates the
   email, and `push_navigate`s back to `/users/settings`. Checks `#flash-info`
   appears ("Email changed successfully.") and `#user_email`'s value is the
   new address.
8. Signs out and checks that `/dashboard` then redirects to `/users/log-in`.
```

- [ ] **Step 4: Remove the completed entry from `docs/roadmap.md`**

In `docs/roadmap.md`, find and remove the entire "### Manual test: account settings (email change, API key regen)" subsection (including its body text).

- [ ] **Step 5: Add the cleanup roadmap item to `docs/roadmap.md`**

In `docs/roadmap.md`, under the "## Manual/Live-Environment Testing" section, add this new subsection after the existing ones:

```markdown
### Clean up manual-test user data in dev

Every dev run of `dashboard.sh`, `session_analytics.sh`, `reaction_flow.sh`,
and `account_settings.sh` creates a `manual-test-<timestamp>@example.com` user
via `complete_magic_link_login`. Each script already deletes the talk-level
data it creates, but the `users` row itself (plus its session token) is never
removed — it accumulates across runs. These users do **not** qualify as "junk"
under the unconfirmed-junk-user rule above: they have a `users_tokens` row with
`context: "session"` from completing the magic-link login. (`account_settings.sh`
additionally renames its user's email to `manual-test-<timestamp>-new@example.com`
during the email-change step.)

Proposed mechanism: a `scripts/manual_tests/cleanup_manual_test_users.exs` script
that deletes all `users` rows where `email LIKE 'manual-test-%@example.com'`
(covers both the plain and `-new` forms), with cascade to associated tokens, talks,
sessions, and reactions. Run via `mix run` and wired as a final step in
`run_all_dev.sh` (which already requires a local `--base-url`). Running it at the
end of each `run_all_dev.sh` invocation sweeps up users from the current run and
any stragglers from prior failed or manual-only runs.
```

- [ ] **Step 6: Commit**

```bash
git add docs/manual_tests.md docs/roadmap.md
git commit -m "docs: add account settings manual test section and cleanup roadmap item"
```

---

### Task 6: Final precommit check

**Files:** none (verification only)

- [ ] **Step 1: Run `mix precommit`**

```bash
mix precommit
```

Expected: all checks pass. None of this plan's files are Elixir source under `lib/` or `test/`, so this is a regression check that nothing else broke.

- [ ] **Step 2: If `mix precommit` fails**

Fix the reported issue, re-run Step 1, then commit the fix.

---

## Files touched

| File | Change |
|---|---|
| `scripts/manual_tests/lib.sh` | Add `clear_dev_mailbox`; refactor `complete_magic_link_login` to call it |
| `scripts/manual_tests/auth_throttle.sh` | Replace inline clear block with `clear_dev_mailbox` call (no behavior change) |
| `scripts/manual_tests/account_settings.sh` | **New** |
| `scripts/manual_tests/run_all_dev.sh` | Add 5th script entry + update error message |
| `docs/manual_tests.md` | New `## Account settings` section + Quick-start updates |
| `docs/roadmap.md` | Remove completed entry; add cleanup roadmap item |
