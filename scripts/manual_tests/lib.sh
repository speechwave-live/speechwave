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
