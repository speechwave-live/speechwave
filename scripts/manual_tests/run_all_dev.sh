#!/usr/bin/env bash
# Runs all manual-test scripts that are fully automated against a local dev
# server (no production steps or manual log-checking required).
# See docs/manual_tests.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_base_url "$@"

if ! is_local; then
  echo "ERROR: run_all_dev.sh only runs scripts that require a local dev server" >&2
  echo "(auth_throttle.sh email mode, dashboard.sh, session_analytics.sh," >&2
  echo "reaction_flow.sh, account_settings.sh)." >&2
  echo "Re-run with --base-url http://localhost:4000 (or omit --base-url)." >&2
  exit 1
fi

if ! command -v rodney >/dev/null 2>&1; then
  echo "ERROR: rodney is not installed or not on PATH." >&2
  echo "See docs/manual_tests.md > Requirements." >&2
  exit 1
fi

if ! curl -fsS -o /dev/null "$BASE_URL/users/log-in"; then
  echo "ERROR: $BASE_URL is not reachable." >&2
  echo "Start the dev server with: mix phx.server" >&2
  exit 1
fi

RESULTS=()

run_script() {
  local label="$1"
  shift
  echo
  echo "==== $label ===="
  set +e
  "$@"
  local status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    RESULTS+=("PASS  $label")
  else
    RESULTS+=("FAIL  $label (exit $status)")
  fi
}

run_script "auth_throttle.sh email" "$SCRIPT_DIR/auth_throttle.sh" --base-url "$BASE_URL" email
run_script "dashboard.sh"           "$SCRIPT_DIR/dashboard.sh" --base-url "$BASE_URL"
run_script "session_analytics.sh"   "$SCRIPT_DIR/session_analytics.sh" --base-url "$BASE_URL"
run_script "reaction_flow.sh"       "$SCRIPT_DIR/reaction_flow.sh" --base-url "$BASE_URL"
run_script "account_settings.sh"    "$SCRIPT_DIR/account_settings.sh" --base-url "$BASE_URL"
run_script "cleanup_manual_test_users.sh" "$SCRIPT_DIR/cleanup_manual_test_users.sh"

echo
echo "==== Summary ===="
overall_status=0
for result in "${RESULTS[@]}"; do
  echo "$result"
  case "$result" in
    FAIL*) overall_status=1 ;;
  esac
done

exit "$overall_status"
