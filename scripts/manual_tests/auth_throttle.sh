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
