# Run-All-Dev Manual Tests Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/manual_tests/run_all_dev.sh`, a single command that chains the three fully-automated dev manual-test scripts (`auth_throttle.sh email`, `dashboard.sh`, `session_analytics.sh`) and prints a combined PASS/FAIL summary, and document it in `docs/manual_tests.md`.

**Architecture:** A thin bash runner under `scripts/manual_tests/` that sources the existing `lib.sh` for `parse_base_url`/`is_local`, runs pre-flight checks (local URL, `rodney` on `PATH`, dev server reachable), then invokes the three sub-scripts as subprocesses (each manages its own `rodney` lifecycle), capturing each exit code without aborting the runner.

**Tech Stack:** Bash 3.2 (macOS default — no associative arrays, no `mapfile`), `curl`, `rodney`.

---

### Task 1: Create `scripts/manual_tests/run_all_dev.sh`

**Files:**
- Create: `scripts/manual_tests/run_all_dev.sh`

- [ ] **Step 1: Create the script**

Create `scripts/manual_tests/run_all_dev.sh` with exactly this content:

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

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/manual_tests/run_all_dev.sh
```

- [ ] **Step 3: Check syntax**

```bash
bash -n scripts/manual_tests/run_all_dev.sh && echo "SYNTAX OK"
```

Expected: `SYNTAX OK`

- [ ] **Step 4: Confirm prerequisites for a live run**

```bash
curl -fsS -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
rodney status
```

Expected: `200`, and `rodney status` shows `No active browser session` (a clean
slate — if a session is active from a previous interrupted run, run
`rodney stop` first).

If `curl` doesn't return `200`, start the dev server in another terminal with
`mix phx.server` before continuing.

- [ ] **Step 5: Run it live and verify the happy path**

```bash
./scripts/manual_tests/run_all_dev.sh --base-url http://localhost:4000
echo "exit=$?"
```

This takes a couple of minutes (it runs all three sub-scripts end to end,
including `session_analytics.sh`'s `mix run` seeding step). Expected: each
sub-script's own output streams under an `==== <label> ====` banner, all
three line up as `PASS` lines (emails/IDs will differ from the example since
they're timestamp- and DB-state-dependent), then:

```
==== Summary ====
PASS  auth_throttle.sh email
PASS  dashboard.sh
PASS  session_analytics.sh
```

and `exit=0`.

- [ ] **Step 6: Verify the pre-flight error paths**

```bash
./scripts/manual_tests/run_all_dev.sh --base-url https://speechwave.live; echo "exit=$?"
```

Expected:

```
ERROR: run_all_dev.sh only runs scripts that require a local dev server
(auth_throttle.sh email mode, dashboard.sh, session_analytics.sh).
Re-run with --base-url http://localhost:4000 (or omit --base-url).
exit=1
```

```bash
./scripts/manual_tests/run_all_dev.sh --base-url http://localhost:4999; echo "exit=$?"
```

Expected (the `curl: (7) ...` line comes from `curl`'s own stderr output,
shown because of `-S`):

```
curl: (7) Failed to connect to localhost port 4999 after 0 ms: Couldn't connect to server
ERROR: http://localhost:4999 is not reachable.
Start the dev server with: mix phx.server
exit=1
```

- [ ] **Step 7: If Step 5 or Step 6 fails**

Run `rodney status` — if a session is stuck active, run `rodney stop` and
retry. For output mismatches, compare against the selectors/behavior already
verified for `auth_throttle.sh`, `dashboard.sh`, and `session_analytics.sh`
individually (see `docs/manual_tests.md`); the issue is most likely in
`run_all_dev.sh`'s own pre-flight checks or `run_script` exit-code handling,
not the sub-scripts themselves (those are independently tested elsewhere).

- [ ] **Step 8: Commit**

```bash
git add scripts/manual_tests/run_all_dev.sh
git commit -m "feat: add run_all_dev.sh to chain the automated manual test scripts"
```

---

### Task 2: Update `docs/manual_tests.md`

**Files:**
- Modify: `docs/manual_tests.md`

- [ ] **Step 1: Add the "Quick start" section**

In `docs/manual_tests.md`, find this point — the end of the "## Requirements"
section, right before the "## Conventions for new sections" heading:

```markdown
## Requirements

- [`rodney`](https://github.com/simonw/rodney) (Chrome automation CLI)
  installed and on `PATH`. Run `rodney --help` to confirm it's available and
  see all subcommands.

## Conventions for new sections
```

Insert a new `## Quick start` section between them, so the result reads:

`````markdown
## Requirements

- [`rodney`](https://github.com/simonw/rodney) (Chrome automation CLI)
  installed and on `PATH`. Run `rodney --help` to confirm it's available and
  see all subcommands.

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

## Conventions for new sections
`````

- [ ] **Step 2: Commit**

```bash
git add docs/manual_tests.md
git commit -m "docs: add quick-start section for run_all_dev.sh"
```

---

### Task 3: Final precommit check

**Files:** none (verification only)

- [ ] **Step 1: Run `mix precommit`**

```bash
mix precommit
```

Expected: all checks pass (compile, deps.unlock, format, test, lint, static).
Neither of this plan's files are Elixir source under `lib/`/`test/`, so this
is a regression check that nothing else broke.

- [ ] **Step 2: If `mix precommit` fails**

Fix the reported issue, re-run Step 1, then commit the fix with a message
describing what was fixed.

---

## Files touched

- `scripts/manual_tests/run_all_dev.sh` — new
- `docs/manual_tests.md` — new "Quick start" section
