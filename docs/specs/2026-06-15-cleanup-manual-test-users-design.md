# Cleanup Manual-Test Users in Dev

**Date:** 2026-06-15
**Status:** Approved

## Background

Every dev run of `dashboard.sh`, `session_analytics.sh`, `reaction_flow.sh`, and
`account_settings.sh` creates a `manual-test-<timestamp>@example.com` user via
`complete_magic_link_login`. Each script cleans up its talk-level data, but the `users`
row itself accumulates across runs. `account_settings.sh` additionally renames its user's
email to `manual-test-<timestamp>-new@example.com` during the email-change step.

These users do not qualify as "junk" under the unconfirmed-user cleanup rule (they have a
`users_tokens` row with `context: "session"`), so a separate sweep is needed.

## Goal

Delete all `manual-test-*@example.com` users at the end of every `run_all_dev.sh` run,
sweeping up users from the current run and any stragglers from prior failed or manual runs.

## Files

| File | Change |
|---|---|
| `scripts/manual_tests/cleanup_manual_test_users.exs` | New — Elixir deletion logic |
| `scripts/manual_tests/cleanup_manual_test_users.sh` | New — thin bash wrapper |
| `scripts/manual_tests/run_all_dev.sh` | Add cleanup as last `run_script` entry |

## Implementation

### `cleanup_manual_test_users.exs`

Uses `Repo.delete_all/1` with a single `like/2` predicate:

```elixir
alias Speechwave.{Accounts.User, Repo}
import Ecto.Query

{count, _} = Repo.delete_all(from u in User, where: like(u.email, "manual-test-%@example.com"))
IO.puts("Deleted #{count} manual-test user(s).")
```

The pattern `manual-test-%@example.com` covers both `manual-test-<ts>@example.com` and
`manual-test-<ts>-new@example.com`. All child data cascades automatically via existing
DB-level `on_delete: :delete_all` foreign keys on `users_tokens`, `user_identities`,
`talks`, `talk_sessions`, and `reactions` — no explicit child deletions needed.

### `cleanup_manual_test_users.sh`

Thin wrapper that handles `cd` to project root (required for `mix run`) and calls the
`.exs` script. Follows the same PROJECT_ROOT derivation pattern as `session_analytics.sh`.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"
exec mix run "$SCRIPT_DIR/cleanup_manual_test_users.exs"
```

### `run_all_dev.sh`

Add cleanup as the last `run_script` entry, before the summary block:

```bash
run_script "cleanup_manual_test_users.sh" "$SCRIPT_DIR/cleanup_manual_test_users.sh"
```

### Expected output

```
==== cleanup_manual_test_users.sh ====
Deleted 4 manual-test user(s).

==== Summary ====
PASS  auth_throttle.sh email
PASS  dashboard.sh
PASS  session_analytics.sh
PASS  reaction_flow.sh
PASS  account_settings.sh
PASS  cleanup_manual_test_users.sh
```

## Dev-only constraint

The `.sh` wrapper is invoked only by `run_all_dev.sh`, which already enforces a local
`--base-url` check at startup. No additional environment guard is needed in the cleanup
script itself.

## Out of scope

- Production cleanup: see the "SSH/eval magic-link-token helper" roadmap item for
  production-run considerations (production manual-test users need separate handling
  since they complete login and won't be junk-user-eligible).
- Scheduled/automated dev DB cleanup: this is a run-time sweep, not a cron job.
