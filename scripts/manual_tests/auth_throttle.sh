#!/usr/bin/env bash
# Manual integration test for the IP cooldown in Speechwave.AuthThrottle
# (magic-link sign-in). Production only: dev has no reverse proxy, so there is
# no client IP to throttle. The email cooldown is covered by
# test/e2e/auth_throttle_test.exs.
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") --base-url URL

  --base-url URL   Base URL of the production Speechwave instance
                   (for example: https://speechwave.live)
EOF
  exit 1
}

parse_base_url "$@"
if [ "${#REMAINING_ARGS[@]}" -gt 0 ]; then
  usage
fi

if is_local; then
  echo "ERROR: this script needs a production --base-url." >&2
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
