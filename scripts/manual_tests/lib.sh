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

  rodney open "$base_url/dev/mailbox" >/dev/null
  rodney waitload >/dev/null
  if [ "$(rodney count 'a[href^="/dev/mailbox/"]')" -gt 0 ]; then
    rodney click 'form[action="/dev/mailbox/clear"] button' >/dev/null
    rodney waitload >/dev/null
  fi

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
