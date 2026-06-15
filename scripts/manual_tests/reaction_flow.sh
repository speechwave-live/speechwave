#!/usr/bin/env bash
# Manual integration test for the attendee reaction flow (TalkLive, /t/:slug):
# real-time emoji broadcast across devices, the rate-limit cooldown UI, and
# reaction persistence to an active session.
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_base_url "$@"

if ! is_local; then
  echo "ERROR: reaction_flow.sh requires a local --base-url (uses /dev/mailbox via complete_magic_link_login, and mix run for seeding)." >&2
  echo "Re-run with --base-url http://localhost:4000" >&2
  exit 1
fi

EMAIL="manual-test-$(date +%s)@example.com"
echo "Seeding active session for $EMAIL"

seed_output=$(cd "$PROJECT_ROOT" && mix run scripts/manual_tests/seed_active_session.exs "$EMAIL" 2>/dev/null)
talk_id=$(echo "$seed_output" | grep '^talk_id=' | cut -d= -f2 || true)
talk_slug=$(echo "$seed_output" | grep '^talk_slug=' | cut -d= -f2 || true)
session_id=$(echo "$seed_output" | grep '^session_id=' | cut -d= -f2 || true)

if [ -z "$talk_id" ] || [ -z "$talk_slug" ] || [ -z "$session_id" ]; then
  echo "FAIL: could not parse seed_active_session.exs output:" >&2
  echo "$seed_output" >&2
  exit 1
fi
echo "Seeded talk_id=$talk_id talk_slug=$talk_slug session_id=$session_id"

start_rodney

# assert_floating_emoji EMOJI LABEL
#
# Checks that a .floating-emoji element with the given text exists on the
# currently-focused tab. Uses a "some" check (not count+text) because a
# backgrounded tab pauses the floatUp animation, so a stale element from an
# earlier tap may still be present alongside the new one.
assert_floating_emoji() {
  local emoji="$1"
  local label="$2"
  if rodney assert "Array.from(document.querySelectorAll('.floating-emoji')).some(el => el.textContent.trim() === '$emoji')" >/dev/null 2>&1; then
    echo "PASS: $label shows .floating-emoji $emoji"
  else
    echo "FAIL: $label did not show .floating-emoji $emoji" >&2
    exit 1
  fi
}

# assert_cooldown_active LABEL EMOJI
#
# Checks #emoji-buttons is in its cooling-down state for the given emoji
# button (cooling-down class, disabled button, "Cooling down… 3s" label).
assert_cooldown_active() {
  local label="$1"
  local emoji="$2"
  local class label_text
  class=$(rodney attr "#emoji-buttons" class)
  label_text=$(rodney text ".cooldown-label")
  if echo "$class" | grep -q "cooling-down" \
    && rodney attr "[phx-value-emoji=\"$emoji\"]" disabled >/dev/null 2>&1 \
    && [ "$label_text" = "Cooling down… 3s" ]; then
    echo "PASS: $label cooldown active (cooling-down class, buttons disabled, '$label_text')"
  else
    echo "FAIL: $label cooldown not active as expected (class='$class', label='$label_text')" >&2
    exit 1
  fi
}

# assert_cooldown_idle LABEL EMOJI
#
# Checks #emoji-buttons is idle for the given emoji button (no cooling-down
# class, button enabled, "Tap to react" label).
assert_cooldown_idle() {
  local label="$1"
  local emoji="$2"
  local class label_text
  class=$(rodney attr "#emoji-buttons" class)
  label_text=$(rodney text ".cooldown-label")
  if ! echo "$class" | grep -q "cooling-down" \
    && ! rodney attr "[phx-value-emoji=\"$emoji\"]" disabled >/dev/null 2>&1 \
    && [ "$label_text" = "Tap to react" ]; then
    echo "PASS: $label cooldown idle (no cooling-down class, buttons enabled, '$label_text')"
  else
    echo "FAIL: $label cooldown not idle as expected (class='$class', label='$label_text')" >&2
    exit 1
  fi
}

TALK_URL="$BASE_URL/t/$talk_slug"

# --- Open both devices on the talk page ---

rodney open "$TALK_URL" >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#emoji-buttons" >/dev/null; then
  echo "FAIL: #emoji-buttons did not render on Device A ($TALK_URL)" >&2
  exit 1
fi
echo "PASS: Device A opened $TALK_URL, #emoji-buttons present"

rodney newpage "$TALK_URL" >/dev/null
rodney page 1 >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#emoji-buttons" >/dev/null; then
  echo "FAIL: #emoji-buttons did not render on Device B ($TALK_URL)" >&2
  exit 1
fi
echo "PASS: Device B opened $TALK_URL, #emoji-buttons present"

# --- First tap (Device A): heart ---

rodney page 0 >/dev/null
rodney click '[phx-value-emoji="❤️"]' >/dev/null
rodney sleep 0.2 >/dev/null
assert_floating_emoji "❤️" "Device A"
assert_cooldown_active "Device A" "❤️"

# --- Cross-device check #1: Device B sees the same broadcast ---

rodney page 1 >/dev/null
assert_floating_emoji "❤️" "Device B"
assert_cooldown_idle "Device B" "❤️"

# --- Wait for cooldown, then second tap (Device A): laughing ---

rodney page 0 >/dev/null
rodney sleep 4 >/dev/null
assert_cooldown_idle "Device A" "❤️"

rodney click '[phx-value-emoji="😂"]' >/dev/null
rodney sleep 0.2 >/dev/null
assert_floating_emoji "😂" "Device A"

# --- Cross-device check #2: Device B sees the second broadcast ---

rodney page 1 >/dev/null
assert_floating_emoji "😂" "Device B"

rodney closepage 1 >/dev/null
rodney page 0 >/dev/null

# --- Verify persistence ---

complete_magic_link_login "$BASE_URL" "$EMAIL"
echo "PASS: logged in via magic link, #talk-list present on /dashboard"

rodney open "$BASE_URL/sessions/$session_id" >/dev/null
rodney waitload >/dev/null
total_reactions=$(rodney text "#total-reactions")
slide0=$(rodney text "#slide-row-0")
if [ "$total_reactions" = "2" ] \
  && echo "$slide0" | grep -q "General" \
  && echo "$slide0" | grep -q "❤️" \
  && echo "$slide0" | grep -q "😂"; then
  echo "PASS: /sessions/$session_id shows #total-reactions=2, #slide-row-0 (General, ❤️, 😂)"
else
  echo "FAIL: expected #total-reactions=2 and #slide-row-0 with General/❤️/😂; got total_reactions=$total_reactions slide0='$slide0'" >&2
  exit 1
fi

# --- Cleanup: delete the seeded talk ---

rodney open "$BASE_URL/dashboard" >/dev/null
rodney waitload >/dev/null
rodney click "#talk-list li button" >/dev/null
rodney waitstable >/dev/null
confirm_and_click "#delete-talk-$talk_id"
rodney waitstable >/dev/null
if rodney exists "#delete-talk-$talk_id" >/dev/null; then
  echo "FAIL: #delete-talk-$talk_id still present after delete" >&2
  exit 1
fi
echo "PASS: talk $talk_id deleted (cleanup)"

# --- Sign out ---

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
