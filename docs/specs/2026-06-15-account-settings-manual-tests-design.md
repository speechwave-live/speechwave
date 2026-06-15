# Account Settings Manual Tests Design

**Date:** 2026-06-15
**Status:** Approved

## Overview

`docs/specs/2026-06-13-dashboard-session-analytics-manual-tests-design.md` established
`scripts/manual_tests/lib.sh` with a `complete_magic_link_login` helper and explicitly
deferred account-settings coverage. That spec noted email change and API key regeneration
as "natural next steps once `complete_magic_link_login` exists."

This spec adds a new `account_settings.sh` script covering `SpeechwaveWeb.UserLive.Settings`
(`/users/settings`): a light-touch render check of the Connected Accounts section, API key
regeneration, and a full email-change round trip (form submit → confirmation email →
click link → email updated in the UI). OAuth connect/disconnect remains a separate
deferred roadmap item — it requires real provider credentials and driving a third-party
consent UI, a genuinely different category.

**Out of scope (tracked in `docs/roadmap.md`):**
- OAuth connect/disconnect
- Cleanup of `manual-test-%@example.com` users left behind in the dev DB after runs
- Running `account_settings.sh` against production (blocked on the SSH/eval magic-link-token
  helper, same as `dashboard.sh`/`session_analytics.sh`)

---

## `scripts/manual_tests/lib.sh` changes

### New: `clear_dev_mailbox`

```sh
clear_dev_mailbox "$BASE_URL"
```

Extracts the 5-line "open `/dev/mailbox`, clear if non-empty" block that is currently
copy-pasted verbatim in both `auth_throttle.sh` (email mode) and `complete_magic_link_login`.
No behavior change to either. `account_settings.sh` becomes the third caller (used once,
before submitting the email-change form, so the resulting confirmation email is the only
message in the mailbox when we go to read it).

Steps:
1. `rodney open "$base_url/dev/mailbox"`.
2. If `rodney count 'a[href^="/dev/mailbox/"]'` is greater than 0, click
   `'form[action="/dev/mailbox/clear"] button'` and wait for load.

### Refactor: `auth_throttle.sh` and `complete_magic_link_login`

Both callers are updated to call `clear_dev_mailbox` in place of the inline block.
No behavior change.

---

## `scripts/manual_tests/account_settings.sh` (new, dev-only)

Usage: `scripts/manual_tests/account_settings.sh [--base-url URL]` (default
`http://localhost:4000`). Errors if `--base-url` is not local — `/dev/mailbox` is
required for both the initial login and the email-change confirmation.

**Email vars computed once** at the top from a single `$(date +%s)` capture, so both
addresses share the same timestamp:

```sh
TS="$(date +%s)"
EMAIL="manual-test-${TS}@example.com"
NEW_EMAIL="manual-test-${TS}-new@example.com"
```

One continuous PASS/FAIL run:

1. **Log in** — `complete_magic_link_login "$BASE_URL" "$EMAIL"`, which lands on
   `/dashboard` with `#talk-list` present.

2. **Navigate to settings** — `rodney open "$BASE_URL/users/settings"`. Assert `#email_form`,
   `#api-key-display`, and `#connected-accounts` all exist. This confirms the page rendered
   and that the freshly-authenticated session passed the `require_sudo_mode` check (within
   10 minutes of `authenticated_at`).

3. **Connected accounts (light touch)** — assert `#connect-google`, `#connect-microsoft`,
   and `#connect-github` all exist. A brand-new user has no OAuth identities, so all three
   "Connect" links (not "Disconnect" buttons) should be present. This verifies the section
   renders without driving any OAuth flow.

4. **API key regeneration** —
   - Read `old_key` via `rodney attr "#api-key-display" value`.
   - `confirm_and_click "#regenerate-api-key-btn"` (the button has `data-confirm`), then
     `rodney waitstable`.
   - Read `new_key` via `rodney attr "#api-key-display" value`.
   - Assert `new_key` is non-empty and `new_key != old_key`.

5. **Email change** —
   - `clear_dev_mailbox "$BASE_URL"` (ensures the confirmation email will be the only
     message when we read the mailbox).
   - `rodney clear "#user_email"`, then `rodney input "#user_email" "$NEW_EMAIL"`, then
     `rodney click "#email_form button"`, then `rodney waitstable`.
   - Assert `#flash-info` exists — the "A link to confirm your email change has been sent
     to the new address." flash (sent to `$NEW_EMAIL`).
   - `rodney open "$BASE_URL/dev/mailbox"` — `Plug.Swoosh.MailboxPreview`'s `GET /`
     auto-redirects to the most-recently-pushed message (the only one after the clear),
     so this opens the email-change confirmation email directly. Assert
     `#email-details__subject` text is "Update email instructions" and `#email-details__to`
     text contains `$NEW_EMAIL`.
   - Extract the `/users/settings/confirm-email/:token` URL from `#text-body-content`
     using the same `grep -o` regex approach as `complete_magic_link_login`:
     ```sh
     confirm_url=$(rodney text "#text-body-content" | \
       grep -o 'https\?://[^[:space:]]*/users/settings/confirm-email/[^[:space:]]*' || true)
     ```
   - `rodney open "$confirm_url"`, then `rodney waitstable`. The LiveView mounts with the
     token param, calls `Accounts.update_user_email/2`, sets the `:info` flash ("Email
     changed successfully."), then calls `push_navigate` to `/users/settings`. The push
     happens over the WebSocket after the initial page load, so `waitstable` (rather than
     just `waitload`) is the appropriate wait here — confirmed against the running dev
     server during implementation.
   - Assert `#flash-info` exists ("Email changed successfully.") and
     `rodney attr "#user_email" value` equals `$NEW_EMAIL`.

6. **Sign out** — `rodney click 'a[href="/users/log-out"]'`, `rodney waitload`, open
   `/dashboard`, assert the resulting URL is `$BASE_URL/users/log-in`. Identical pattern
   to the other scripts.

---

## `scripts/manual_tests/run_all_dev.sh` changes

- Add `run_script "account_settings.sh" "$SCRIPT_DIR/account_settings.sh" --base-url "$BASE_URL"`
  as the fifth entry (after `reaction_flow.sh`).
- Update the existing error message that names the four scripts to include
  `account_settings.sh`.

---

## `docs/manual_tests.md` changes

- New `## Account settings` section, following the existing format: one-line description,
  script invocation, dev-only note (with link to the SSH/eval roadmap item), then numbered
  PASS steps matching the flow above.
- Update the Quick-start paragraph to name five scripts instead of four (add
  `account_settings.sh` to the list and update the `run_all_dev.sh` description).

---

## `docs/roadmap.md` changes

### Remove

The "Manual test: account settings (email change, API key regen)" entry under
"Manual/Live-Environment Testing" — completed by this spec.

### Add

Under "Manual/Live-Environment Testing":

**Clean up manual-test user data in dev**

Every dev run of `dashboard.sh`, `session_analytics.sh`, `reaction_flow.sh`, and
`account_settings.sh` creates a `manual-test-<timestamp>@example.com` user via
`complete_magic_link_login`. Each script already deletes the talk-level data it creates
(where applicable), but the `users` row itself is never removed — it accumulates in the
dev DB across runs. Note that these users do NOT qualify as "junk" under the
unconfirmed-junk-user cleanup rule (see "Auth & Accounts" above): they have a
`users_tokens` row with `context: "session"` from completing the magic-link login.
(`account_settings.sh` additionally renames its user's email to
`manual-test-<timestamp>-new@example.com` during the email-change step.)

Proposed mechanism: a `scripts/manual_tests/cleanup_manual_test_users.exs` script that
deletes all `users` rows where `email LIKE 'manual-test-%@example.com'` (covers both the
plain and `-new` forms), with cascade to associated tokens, talks, sessions, and reactions.
Run via `mix run scripts/manual_tests/cleanup_manual_test_users.exs` and wired as a final
step in `run_all_dev.sh`. Running it at the end of each `run_all_dev.sh` invocation sweeps
up users from the current run and any stragglers from prior failed/manual runs.

Dev-only by construction (`run_all_dev.sh` already requires a local `--base-url`).

---

## Files touched

| File | Change |
|---|---|
| `scripts/manual_tests/lib.sh` | Add `clear_dev_mailbox` helper |
| `scripts/manual_tests/auth_throttle.sh` | Refactor email-mode clear to call `clear_dev_mailbox` (no behavior change) |
| `scripts/manual_tests/account_settings.sh` | **New** |
| `scripts/manual_tests/run_all_dev.sh` | Add 5th script entry + update error message |
| `docs/manual_tests.md` | New `## Account settings` section + Quick-start update |
| `docs/roadmap.md` | Remove completed entry, add new cleanup roadmap item |
