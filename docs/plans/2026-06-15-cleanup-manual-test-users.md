# Manual-Test User Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `cleanup_manual_test_users.exs` script (with a bash wrapper) that deletes all `manual-test-*@example.com` users at the end of every `run_all_dev.sh` run.

**Architecture:** A single Ecto `delete_all` call on the `users` table with a `LIKE` predicate; existing DB-level `on_delete: :delete_all` foreign keys cascade the delete to `users_tokens`, `user_identities`, `talks`, `talk_sessions`, and `reactions` automatically. A thin bash wrapper handles the `cd` to project root required by `mix run`. `run_all_dev.sh` registers the wrapper as the last `run_script` entry so it appears in the pass/fail summary.

**Tech Stack:** Elixir/Ecto (`Repo.delete_all`, `Ecto.Query.like/2`), bash

---

### Task 1: Create the Elixir cleanup script

**Files:**
- Create: `scripts/manual_tests/cleanup_manual_test_users.exs`

- [ ] **Step 1: Create the script**

```elixir
alias Speechwave.{Accounts.User, Repo}
import Ecto.Query

{count, _} = Repo.delete_all(from u in User, where: like(u.email, "manual-test-%@example.com"))
IO.puts("Deleted #{count} manual-test user(s).")
```

The pattern `manual-test-%@example.com` covers both `manual-test-<ts>@example.com` (created
by all scripts) and `manual-test-<ts>-new@example.com` (the renamed email from
`account_settings.sh`).

- [ ] **Step 2: Verify it runs (zero-delete case is fine)**

From the project root with the DB available (dev server does not need to be running):

```bash
mix run scripts/manual_tests/cleanup_manual_test_users.exs
```

Expected output when no manual-test users exist:
```
Deleted 0 manual-test user(s).
```

If you get a module-not-found error, confirm the schema module path with:
```bash
mix run -e "IO.inspect(Speechwave.Accounts.User.__schema__(:fields))"
```
Expected: a list that includes `:email`.

- [ ] **Step 3: Commit**

```bash
git add scripts/manual_tests/cleanup_manual_test_users.exs
git commit -m "feat: add cleanup_manual_test_users.exs script"
```

---

### Task 2: Create the bash wrapper

**Files:**
- Create: `scripts/manual_tests/cleanup_manual_test_users.sh`

`mix run` must be invoked from the project root (not from within `scripts/manual_tests/`).
The wrapper handles this the same way `session_analytics.sh` does: deriving `PROJECT_ROOT`
from `SCRIPT_DIR`.

- [ ] **Step 1: Create the wrapper**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"
exec mix run "$SCRIPT_DIR/cleanup_manual_test_users.exs"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/manual_tests/cleanup_manual_test_users.sh
```

- [ ] **Step 3: Verify the wrapper runs**

```bash
scripts/manual_tests/cleanup_manual_test_users.sh
```

Expected output:
```
Deleted 0 manual-test user(s).
```

- [ ] **Step 4: Commit**

```bash
git add scripts/manual_tests/cleanup_manual_test_users.sh
git commit -m "feat: add cleanup_manual_test_users.sh wrapper"
```

---

### Task 3: Wire cleanup into run_all_dev.sh and update roadmap

**Files:**
- Modify: `scripts/manual_tests/run_all_dev.sh`
- Modify: `docs/roadmap.md`

- [ ] **Step 1: Add the cleanup entry to run_all_dev.sh**

The current tail of the `run_script` block in `run_all_dev.sh` is:

```bash
run_script "reaction_flow.sh"       "$SCRIPT_DIR/reaction_flow.sh" --base-url "$BASE_URL"
run_script "account_settings.sh"    "$SCRIPT_DIR/account_settings.sh" --base-url "$BASE_URL"

echo
echo "==== Summary ===="
```

Add the cleanup entry immediately after `account_settings.sh`:

```bash
run_script "reaction_flow.sh"       "$SCRIPT_DIR/reaction_flow.sh" --base-url "$BASE_URL"
run_script "account_settings.sh"    "$SCRIPT_DIR/account_settings.sh" --base-url "$BASE_URL"
run_script "cleanup_manual_test_users.sh" "$SCRIPT_DIR/cleanup_manual_test_users.sh"

echo
echo "==== Summary ===="
```

- [ ] **Step 2: Remove the completed item from roadmap.md**

In `docs/roadmap.md`, delete the entire "### Clean up manual-test user data in dev"
subsection (from the `###` heading through the paragraph ending "...any stragglers from
prior failed/manual runs."). The "## Manual/Live-Environment Testing" section heading and
sibling items remain untouched.

- [ ] **Step 3: Run mix precommit and fix any issues**

```bash
mix precommit
```

Fix any warnings or formatting issues it reports before proceeding.

- [ ] **Step 4: Verify the full suite runs end-to-end**

With the dev server running (`mix phx.server` in a separate terminal):

```bash
scripts/manual_tests/run_all_dev.sh
```

Expected summary at the end:
```
==== Summary ====
PASS  auth_throttle.sh email
PASS  dashboard.sh
PASS  session_analytics.sh
PASS  reaction_flow.sh
PASS  account_settings.sh
PASS  cleanup_manual_test_users.sh
```

Confirm no manual-test users remain after the run:

```bash
mix run -e "
import Ecto.Query
alias Speechwave.{Accounts.User, Repo}
count = Repo.aggregate(from(u in User, where: like(u.email, \"manual-test-%@example.com\")), :count)
IO.puts(\"manual-test users remaining: \#{count}\")
"
```

Expected:
```
manual-test users remaining: 0
```

- [ ] **Step 5: Commit**

```bash
git add scripts/manual_tests/run_all_dev.sh docs/roadmap.md
git commit -m "feat: wire cleanup_manual_test_users.sh into run_all_dev.sh"
```
