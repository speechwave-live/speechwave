#!/usr/bin/env bash
# Manual integration test for email consent collection.
# See docs/manual_tests.md for how to read the results.
#
# Scenario A: Login WITH consent checkbox → magic link carries ?updates=true
#             → /users/settings shows data-consented=true → revoke works
# Scenario B: Login WITHOUT consent checkbox → magic link has no ?updates
#             → /users/settings shows data-consented=false, no revoke button
# Scenario C: Pricing "Notify me" modal (logged-out) → submit email → magic
#             link carries ?updates=true&notify=pro → clicking it shows flash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_base_url "$@"

if ! is_local; then
  echo "ERROR: email_consent.sh requires a local --base-url (uses /dev/mailbox)." >&2
  echo "Re-run with --base-url http://localhost:4000" >&2
  exit 1
fi

start_rodney

TS="$(date +%s)"
EMAIL_CONSENT="manual-test-${TS}-consent@example.com"
EMAIL_NO_CONSENT="manual-test-${TS}-noconsent@example.com"
EMAIL_PRICING="manual-test-${TS}-pricing@example.com"

echo "Consent user:    $EMAIL_CONSENT"
echo "No-consent user: $EMAIL_NO_CONSENT"
echo "Pricing user:    $EMAIL_PRICING"

# ---------------------------------------------------------------------------
# Scenario A: Login with consent checkbox checked
# ---------------------------------------------------------------------------
echo
echo "=== Scenario A: Login with consent ==="

clear_dev_mailbox "$BASE_URL"

rodney open "$BASE_URL/users/log-in" >/dev/null
rodney waitload >/dev/null
rodney input "#user_email" "$EMAIL_CONSENT" >/dev/null
rodney click "#marketing-consent-checkbox" >/dev/null
rodney click "#magic-link-form button" >/dev/null
rodney waitstable >/dev/null
if ! rodney exists "#magic-link-sent" >/dev/null; then
  echo "FAIL: #magic-link-sent did not appear after submitting with consent" >&2
  exit 1
fi

rodney open "$BASE_URL/dev/mailbox" >/dev/null
rodney waitload >/dev/null
magic_url=$(rodney text "#text-body-content" | grep -o 'https\?://[^[:space:]]*/users/magic_link/[^[:space:]]*' || true)
if [ -z "$magic_url" ]; then
  echo "FAIL: could not find magic link URL in email body" >&2
  exit 1
fi
if ! echo "$magic_url" | grep -q "updates=true"; then
  echo "FAIL: magic link missing 'updates=true' when consent was checked: $magic_url" >&2
  exit 1
fi
echo "PASS: magic link contains 'updates=true' when consent checkbox was checked"

rodney open "$magic_url" >/dev/null
rodney waitload >/dev/null
rodney open "$BASE_URL/users/settings" >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#email-prefs-section" >/dev/null; then
  echo "FAIL: #email-prefs-section not found on /users/settings" >&2
  exit 1
fi
consented=$(rodney attr "#email-prefs-section" data-consented)
if [ "$consented" != "true" ]; then
  echo "FAIL: expected data-consented=true, got '$consented'" >&2
  exit 1
fi
echo "PASS: /users/settings shows data-consented=true after login with consent"

if ! rodney exists "#revoke-consent-btn" >/dev/null; then
  echo "FAIL: #revoke-consent-btn not present when user has consent" >&2
  exit 1
fi
rodney click "#revoke-consent-btn" >/dev/null
rodney waitstable >/dev/null
consented=$(rodney attr "#email-prefs-section" data-consented)
if [ "$consented" != "false" ]; then
  echo "FAIL: expected data-consented=false after revoke, got '$consented'" >&2
  exit 1
fi
if rodney exists "#revoke-consent-btn" >/dev/null; then
  echo "FAIL: #revoke-consent-btn still present after revoke" >&2
  exit 1
fi
echo "PASS: revoke updates #email-prefs-section to data-consented=false and removes revoke button"

rodney click 'a[href="/users/log-out"]' >/dev/null
rodney waitload >/dev/null

# ---------------------------------------------------------------------------
# Scenario B: Login without consent checkbox
# ---------------------------------------------------------------------------
echo
echo "=== Scenario B: Login without consent ==="

clear_dev_mailbox "$BASE_URL"

rodney open "$BASE_URL/users/log-in" >/dev/null
rodney waitload >/dev/null
rodney input "#user_email" "$EMAIL_NO_CONSENT" >/dev/null
# Do NOT check the consent checkbox — submit directly
rodney click "#magic-link-form button" >/dev/null
rodney waitstable >/dev/null
if ! rodney exists "#magic-link-sent" >/dev/null; then
  echo "FAIL: #magic-link-sent did not appear after submitting without consent" >&2
  exit 1
fi

rodney open "$BASE_URL/dev/mailbox" >/dev/null
rodney waitload >/dev/null
magic_url=$(rodney text "#text-body-content" | grep -o 'https\?://[^[:space:]]*/users/magic_link/[^[:space:]]*' || true)
if [ -z "$magic_url" ]; then
  echo "FAIL: could not find magic link URL in email body" >&2
  exit 1
fi
if echo "$magic_url" | grep -q "updates"; then
  echo "FAIL: magic link unexpectedly contains 'updates' when consent was not checked: $magic_url" >&2
  exit 1
fi
echo "PASS: magic link has no 'updates' param when consent checkbox was not checked"

rodney open "$magic_url" >/dev/null
rodney waitload >/dev/null
rodney open "$BASE_URL/users/settings" >/dev/null
rodney waitload >/dev/null
consented=$(rodney attr "#email-prefs-section" data-consented)
if [ "$consented" != "false" ]; then
  echo "FAIL: expected data-consented=false for unconsented user, got '$consented'" >&2
  exit 1
fi
if rodney exists "#revoke-consent-btn" >/dev/null; then
  echo "FAIL: #revoke-consent-btn present when user has no consent" >&2
  exit 1
fi
echo "PASS: /users/settings shows data-consented=false and no revoke button for unconsented user"

rodney click 'a[href="/users/log-out"]' >/dev/null
rodney waitload >/dev/null

# ---------------------------------------------------------------------------
# Scenario C: Pricing Notify Me modal (logged-out user)
# ---------------------------------------------------------------------------
echo
echo "=== Scenario C: Pricing Notify Me modal (logged-out) ==="

clear_dev_mailbox "$BASE_URL"

rodney open "$BASE_URL/pricing" >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#notify-pro-btn" >/dev/null; then
  echo "FAIL: #notify-pro-btn not found on /pricing" >&2
  exit 1
fi
rodney click "#notify-pro-btn" >/dev/null
rodney waitstable >/dev/null
if ! rodney exists "#notify-modal" >/dev/null; then
  echo "FAIL: #notify-modal did not appear after clicking #notify-pro-btn" >&2
  exit 1
fi
echo "PASS: #notify-modal appears after clicking #notify-pro-btn"

rodney input "#notify-email-input" "$EMAIL_PRICING" >/dev/null
rodney click '#notify-form button[type="submit"]' >/dev/null
rodney waitstable >/dev/null
if ! rodney exists "#notify-sent-message" >/dev/null; then
  echo "FAIL: #notify-sent-message did not appear after submitting Notify Me form" >&2
  exit 1
fi
echo "PASS: #notify-sent-message appears after submitting Notify Me form"

rodney open "$BASE_URL/dev/mailbox" >/dev/null
rodney waitload >/dev/null
magic_url=$(rodney text "#text-body-content" | grep -o 'https\?://[^[:space:]]*/users/magic_link/[^[:space:]]*' || true)
if [ -z "$magic_url" ]; then
  echo "FAIL: could not find magic link URL in Notify Me email" >&2
  exit 1
fi
if ! echo "$magic_url" | grep -q "updates"; then
  echo "FAIL: Notify Me magic link missing 'updates' param: $magic_url" >&2
  exit 1
fi
if ! echo "$magic_url" | grep -q "notify"; then
  echo "FAIL: Notify Me magic link missing 'notify' param: $magic_url" >&2
  exit 1
fi
echo "PASS: Notify Me magic link contains 'updates' and 'notify' query params"

rodney open "$magic_url" >/dev/null
rodney waitload >/dev/null
rodney waitstable >/dev/null
if ! rodney exists "#flash-info" >/dev/null; then
  echo "FAIL: #flash-info not present after clicking Notify Me magic link" >&2
  exit 1
fi
echo "PASS: #flash-info appears after clicking Notify Me magic link (consent granted)"

rodney click 'a[href="/users/log-out"]' >/dev/null
rodney waitload >/dev/null
