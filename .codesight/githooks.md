# Git Hooks

> **Note for agents:** These hooks fire automatically on git operations and will block the operation if they fail.

## `pre-commit` — raw git hook

- **npx**: `npx codesight --wiki -o .codesight`
- **git**: `git add .codesight/`

## `pre-push` — raw git hook

- **echo**: `echo "Running Credo to check for code consistency..."`
- **mix**: `mix credo --strict --all`
- **CREDO_EXIT_CODE=$?**: `CREDO_EXIT_CODE=$?`
- **if**: `if [ $CREDO_EXIT_CODE -ne 0 ]; then`
- **echo**: `echo "Credo found issues."`
- **echo**: `echo "Run `credo --strict --all --format json` for details."`
- **echo**: `echo "Please fix them before pushing!"`
- **exit**: `exit 1`
- **fi**: `fi`
- **echo**: `echo "No issues found by Credo. Proceeding with push."`
- **exit**: `exit 0`

_Source: .git/hooks/pre-commit, .git/hooks/pre-push_
