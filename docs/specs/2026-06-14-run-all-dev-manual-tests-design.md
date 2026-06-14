# Run-All-Dev Manual Tests Runner Design

**Date:** 2026-06-14
**Status:** Approved

## Overview

`docs/manual_tests.md` now documents four scripts under
`scripts/manual_tests/`: `auth_throttle.sh` (with `email` and `ip` modes),
`dashboard.sh`, `session_analytics.sh`, and the `seed_sessions.exs` fixture
used by `session_analytics.sh`.

Three of these are fully automated against a local dev server with no
follow-up steps: `auth_throttle.sh email`, `dashboard.sh`, and
`session_analytics.sh`. The fourth, `auth_throttle.sh ip`, is production-only
and requires a manual `fly logs` grep afterward — it doesn't fit "run without
intervention".

This spec adds `scripts/manual_tests/run_all_dev.sh`, a thin runner that
chains the three fully-automated scripts and reports a combined summary, so a
developer can exercise all of them with a single command.

**Out of scope**: `auth_throttle.sh ip` mode (production-only, needs manual
log-checking — run it separately per the existing "Magic-link auth throttle"
section).

---

## `scripts/manual_tests/run_all_dev.sh` (new)

Mode `755`. Lives alongside the other scripts and sources `lib.sh`.

Usage: `scripts/manual_tests/run_all_dev.sh [--base-url URL]` (default
`http://localhost:4000`, same `--base-url` convention as the other scripts).

### Pre-flight checks

Each prints an actionable error to stderr and exits 1 if it fails:

1. **`is_local`** — refuses a non-local `--base-url` with one clear message,
   since two of the three scripts depend on `/dev/mailbox` and `mix run` for
   seeding. Points the developer at the existing "Magic-link auth throttle"
   section for the production-only `ip` mode.
2. **`rodney` on `PATH`** — via `command -v rodney`.
3. **Dev server reachable** — `curl -fsS -o /dev/null "$BASE_URL/users/log-in"`;
   if it fails, suggests `mix phx.server`.

### Running the scripts

Runs, in order:

1. `auth_throttle.sh --base-url "$BASE_URL" email`
2. `dashboard.sh --base-url "$BASE_URL"`
3. `session_analytics.sh --base-url "$BASE_URL"`

Each runs as its own subprocess (so each manages its own `rodney`
start/stop lifecycle via `lib.sh`'s `start_rodney`). A `run_script` helper
prints a banner (`==== <label> ====`) before each, temporarily disables
`set -e` to capture the exit status without aborting the runner, and records
a `PASS`/`FAIL` result per script.

### Summary

After all three have run, prints:

```
==== Summary ====
PASS  auth_throttle.sh email
PASS  dashboard.sh
PASS  session_analytics.sh
```

(or `FAIL  <label> (exit <N>)` for any that failed). Exits non-zero if any
script failed, 0 if all passed.

### Full script content

```bash
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
  echo "(auth_throttle.sh email mode, dashboard.sh, session_analytics.sh)." >&2
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
```

---

## `docs/manual_tests.md` updates

New `## Quick start` section, placed after `## Requirements` and before
`## Conventions for new sections`:

```markdown
## Quick start

To run everything that's fully automated against a local dev server in one
go:

```sh
scripts/manual_tests/run_all_dev.sh [--base-url URL]
```

(default `http://localhost:4000`). This runs `auth_throttle.sh email`,
`dashboard.sh`, and `session_analytics.sh` back-to-back, printing each
script's output as it goes, then a PASS/FAIL summary line per script. Exits
non-zero if any failed.

Checks `rodney` is on `PATH` and the dev server is reachable at `--base-url`
before starting, with actionable error messages if not.

**Dev-only** — refuses a non-local `--base-url`, since two of the three
scripts depend on `/dev/mailbox` and `mix run` for seeding. The `ip`-cooldown
mode of `auth_throttle.sh` isn't included here since it's production-only and
needs a manual `fly logs` check afterward — run it separately per the
"Magic-link auth throttle" section below.
```

---

## Files touched

- `scripts/manual_tests/run_all_dev.sh` — new
- `docs/manual_tests.md` — new "Quick start" section
