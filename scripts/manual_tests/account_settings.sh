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

# clear_dev_mailbox leaves the browser on /dev/mailbox; navigate back to the form
rodney open "$BASE_URL/users/settings" >/dev/null
rodney waitload >/dev/null
rodney js "document.querySelector('#user_email').value = ''" >/dev/null
rodney input "#user_email" "$NEW_EMAIL" >/dev/null
rodney click "#email_form button" >/dev/null
# LiveView pushes the flash update after the form submit; waitload ensures it's rendered
rodney waitload >/dev/null
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
rodney waitload >/dev/null
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

# push_navigate from confirm-email leaves the browser in an unstable state; navigate
# to a stable page with the nav bar before clicking sign-out
rodney open "$BASE_URL/dashboard" >/dev/null
rodney waitload >/dev/null
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
