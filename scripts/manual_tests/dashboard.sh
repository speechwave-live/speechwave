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
if [ "$sessions_used" = "0" ] && [ "$session_limit" = "50" ] && [ "$participant_limit" = "15" ]; then
  echo "PASS: plan usage shows 0/50 sessions, 15 participant limit"
else
  echo "FAIL: expected sessions_used=0 session_limit=50 participant_limit=15, got $sessions_used/$session_limit/$participant_limit" >&2
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
