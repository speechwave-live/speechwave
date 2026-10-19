# Migrating manual integration scripts to browser tests

## Why

The scripts in `scripts/manual_tests` drive a running dev server with rodney.
They work, but each one carries its own login dance through `/dev/mailbox`,
its own seeding via `mix run`, its own timestamped users that need cleaning up,
and hand-rolled `if ... echo FAIL` assertions. We expect many more integration
tests, so that cost grows with every flow we add.

A spike (branch `spike/phoenix-test-playwright`) ported `dashboard.sh` to
`test/e2e/dashboard_test.exs` using `phoenix_test` and
`phoenix_test_playwright`. It runs real Chromium against the app in about 1.4
seconds, uses the Ecto sandbox instead of leaving users behind, and reads the
login email straight from Swoosh's test adapter. The test is about half the
length of the script. This spec lays out how to move everything else over.

## Decisions

- **Framework:** `phoenix_test` with the Playwright driver. Tests can drop down
  to plain `Phoenix.LiveViewTest` style where no browser is needed, using the
  same `visit |> click_button |> assert_has` calls.
- **Location:** `test/e2e/`, one file per flow, each tagged `@moduletag :e2e`.
- **Running:** `mix test` skips `:e2e`. `mix test.browser` runs only those.
  Not CI-gated at first (same stance as the extension suite). Revisit once the
  suite is stable and fast enough to gate on.
- **Setup requirement:** `npm install` in `assets/`, then
  `npx playwright install chromium`. This needs a line in the README and in
  `docs/manual_tests.md`.
- **Test port:** 4002, so browser tests can run while `mix phx.server` is up.
- **The Chrome extension suite stays in the `chrome-extension` repo.** It needs
  the unpacked extension loaded, which is a different job.
- **No new rodney scripts** from this point on.

## Shared test support

Built in the first pass so every later port reuses it:

- `log_in_with_magic_link/2` in `test/support` (currently inline in the spike).
  It submits the login form, takes the link from the Swoosh email, and lands
  on `/dashboard`. Sets `:swoosh, :shared_test_process` for the test and
  clears it on exit.
- Fixture helpers that replace the `seed_*.exs` scripts. They already mostly
  exist as context functions and fixtures (`user_fixture`, and so on). The
  seeding for active sessions and analytics sessions needs equivalents.
- A `Case` module wrapping `use PhoenixTest.Playwright.Case`, the `:e2e` tag,
  and the login helper, so each test file starts with one `use` line.

## Gotchas learned in the spike

- Playwright's `assert_has` requires the element to be visible. rodney's
  `exists` did not. An empty `<ul id="talk-list">` has zero height and counts as
  hidden, so assert on something with content.
- Inputs that only have placeholders can't be reached with `fill_in`. Use
  `type("#selector", text)` or add real labels (better for accessibility too).
- Confirm dialogs are accepted automatically. Use `with_dialog/3` to assert
  on the message or to dismiss one.
- A compile error in a test file prints a noisy Node `EPIPE` trace. Ignore it
  and read the Elixir error above it.
- Test URLs now include port 4002. Assertions should use `Endpoint.url()`,
  never a hardcoded host.

## Migration order

Ordered by how much each one teaches us and how little new machinery it needs.

| # | Script | What it needs beyond the helpers | Notes |
|---|--------|----------------------------------|-------|
| 0 | `dashboard.sh` | nothing | Done in the spike. |
| 1 | `account_settings.sh` | reading an input's value | API key regeneration (confirm dialog) and email change. Many assertions may not need a browser. |
| 2 | `email_consent.sh` | marketing consent checkbox, consent export | Largest script (217 lines). Check overlap with existing LiveView tests first and only port what needs a real browser. |
| 3 | `session_analytics.sh` | session seeding fixtures | Replaces `seed_sessions.exs`. Charts render server side, so mostly plain assertions. |
| 4 | `reaction_flow.sh` | seeding, two browser contexts | The hard one. See below. |
| 5 | `auth_throttle.sh` | throttle enabled for one test | The `email` mode ports. The production-only `ip` mode stays manual. |

### Open question: two devices in one test

`reaction_flow.sh` checks that a reaction on one device shows up on another,
plus the cooldown UI and persistence. That needs two browser contexts in one
test. The README for `phoenix_test_playwright` doesn't describe a multi-session
API, so the first thing to do in pass 4 is check whether the library exposes
one (or whether `PlaywrightEx` underneath does). If not, fall back to asserting
the broadcast with a second `Phoenix.LiveViewTest` view alongside the browser
session. Decide when we get there.

### Open question: auth throttle in test

`:auth_throttle_enabled` is false in the test env so other tests don't trip
the limiter. The throttle test needs it on for one test and must reset the
limiter state afterward. Check whether `Speechwave.AuthThrottle` has a reset
function or ETS table we can clear in `setup`.

## Finishing the migration

When the last script is ported:

- Delete `scripts/manual_tests/` (including the `seed_*.exs` and cleanup
  scripts) and `run_all_dev.sh`.
- Rewrite `docs/manual_tests.md` to cover only what is still manual: the
  production-only `ip` throttle check, real email delivery, and Fly logs.
- Add the browser tests to the `precommit` alias if they are fast and stable
  by then, or document why not.

## SQLite and parallelism

Browser tests run with `async: false` because `ecto_sqlite3` uses one database
file and a shared sandbox. That is fine for a few dozen tests. If the suite
gets slow, the option is multiple database files, one per OS process:

- Use `mix test --partitions N`. ExUnit sets `MIX_TEST_PARTITION` for each
  partition, and `config/test.exs` already puts it in the database file name
  (`priv/repo/test<N>.db`). Each partition gets its own file and its own
  sandbox, so no two processes contend for a lock. The separate deletions
  database is partitioned the same way.
- Each partition also needs its own endpoint port (for example
  `4002 + partition`), or they will collide.
- The `test` alias runs `ecto.migrate` first, so each partition's file should
  be created and migrated on startup. Verify with a two-partition run.
- The repo is configured with `pool_size: 1`. That is fine for the sandbox,
  but worth revisiting if LiveView processes and the test both need
  connections at once.
- This parallelizes across files, not within one. Tests inside a single
  partition still run one at a time.

True in-VM parallelism with separate files per test would mean dynamic Ecto
repos and a routing plug, which is far more machinery than partitions. Don't
build it unless partitions turn out to be too coarse.

Do none of this until the suite is slow enough to justify it.

## Status

Update this table at the end of each implementation pass.

| Pass | Scope | Status |
|------|-------|--------|
| 0 | Spike: dependencies, config, `dashboard.sh` port | Done on branch `spike/phoenix-test-playwright`, not yet merged |
| 1 | Merge the spike, extract shared helpers and `Case` module, README and `docs/manual_tests.md` setup notes | Not started |
| 2 | Port `account_settings.sh` | Not started |
| 3 | Port `email_consent.sh` | Not started |
| 4 | Port `session_analytics.sh` (seeding fixtures) | Not started |
| 5 | Port `reaction_flow.sh` (two-device question) | Not started |
| 6 | Port `auth_throttle.sh` email mode | Not started |
| 7 | Delete old scripts, rewrite `docs/manual_tests.md`, decide on gating | Not started |
| later | Partitioned test databases, if the suite gets slow | Deferred |
