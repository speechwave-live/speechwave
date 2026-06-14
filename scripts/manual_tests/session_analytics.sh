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
