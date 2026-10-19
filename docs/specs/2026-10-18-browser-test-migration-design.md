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

## What the dashboard port covers

The port keeps every assertion from `dashboard.sh` except one: after clicking
the copy-link button, the script looked for a flash message and dismissed it,
and downgraded the check to a note when the clipboard was unavailable. The port
checks the idle and copied icon states but does not click copy. It can come
back when we want to cover the copy hook, using a Playwright clipboard
permission.

## Decisions

- **Framework:** `phoenix_test` with the Playwright driver. Tests can drop down
  to plain `Phoenix.LiveViewTest` style where no browser is needed, using the
  same `visit |> click_button |> assert_has` calls.
- **Location:** `test/e2e/`, one file per flow, each tagged `@moduletag :e2e`.
- **Running:** `mix test` skips `:e2e`. `mix test.browser` runs only those.
  Not CI-gated at first (same stance as the extension suite). Revisit once the
  suite is stable and fast enough to gate on.
- **Setup requirement:** `npm install --prefix assets`, then
  `npx --prefix assets playwright install chromium`. Documented in the README
  (the migration notice in `docs/manual_tests.md` points there). A plain `mix test` must keep working without it:
  `test_helper.exs` only starts the Playwright supervisor when `:e2e` is
  included.
- **Test port:** 4002 + `MIX_TEST_PARTITION`, set in `config/runtime.exs`, so
  browser tests can run while `mix phx.server` is up and partitions don't
  collide. The endpoint runs with `server: true` in all tests (see deferred
  items).
- **E2E modules must be `async: false`.** The shared Swoosh test process
  (`:shared_test_process`) is global app env, and without the
  `Phoenix.Ecto.SQL.Sandbox` plug in the endpoint the sandbox only works in
  shared mode. Making a module async would break both.
- **The Chrome extension suite stays in the `chrome-extension` repo.** It needs
  the unpacked extension loaded, which is a different job.
- **No new rodney scripts** from this point on.

## Shared test support

Built in the first pass so every later port reuses it:

- `log_in_with_magic_link/2` in `test/support/e2e_case.ex`.
  It submits the login form, takes the link from the Swoosh email, and lands
  on `/dashboard`. Sets `:swoosh, :shared_test_process` for the test and
  clears it on exit.
- `log_in_as/2`: plants a session cookie so tests that are not about logging
  in skip the form. Needs `config :phoenix_test, endpoint: ...` and
  `Endpoint.session_options/0`.
- Fixture helpers that replace the `seed_*.exs` scripts. They already mostly
  exist as context functions and fixtures (`user_fixture`, and so on). The
  seeding for active sessions and analytics sessions needs equivalents.
- `SpeechwaveWeb.E2ECase`: wraps `use PhoenixTest.Playwright.Case`, adds the
  `:e2e` tag, forces `async: false`, imports the fixtures and the login helpers,
  so each test file starts with one `use` line.

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
- Text assertions are substring matches by default. Pass `exact: true` when
  the value matters (`"0"` would otherwise match `"50"`).
- Assertions inside a `with_dialog/3` callback run in the browser event
  process. A failure there shows up as a timeout on the following click, not
  as a clean assertion error. The message is still printed above it.
- Test URLs now include port 4002. Assertions should use `Endpoint.url()`,
  never a hardcoded host.

## Migration order

Ordered by how much each one teaches us and how little new machinery it needs.

| # | Script | What it needs beyond the helpers | Notes |
|---|--------|----------------------------------|-------|
| 0 | `dashboard.sh` | nothing | Ported in the spike, script deleted in pass 2. |
| 1 | `account_settings.sh` | reading an input's value (`assert_has(..., value: ...)`) | API key regeneration (confirm dialog) and email change. Many assertions may not need a browser. |
| 2 | `email_consent.sh` | marketing consent checkbox, consent export | Largest script (217 lines). Check overlap with existing LiveView tests first and only port what needs a real browser. |
| 3 | `session_analytics.sh` | session seeding fixtures | Replaces `seed_sessions.exs`. Charts render server side, so mostly plain assertions. |
| 4 | `reaction_flow.sh` | seeding, two browser sessions (`new_session/2`), rate limiter state | The hard one. See below. |
| 5 | `auth_throttle.sh` | throttle enabled for one test, ETS tables cleared | The `email` mode ports. The production-only `ip` mode stays manual. |

### Two devices in one test

`reaction_flow.sh` checks that a reaction on one device shows up on another,
plus the cooldown UI and persistence. The review of the spike found that
`PhoenixTest.Playwright.Case.new_session/2` is public and its Ecto checkout
code handles a second session in the same test, with each session in its own
browser context. So two real browser sessions should work. Pass 5 should wrap
it in a helper on our `Case` module (it needs the validated Playwright config
and the context) and confirm it with a real run.

### Global state to reset

- **Auth throttle:** `:auth_throttle_enabled` is false in the test env. There
  is no reset function, but `Speechwave.AuthThrottle` keeps its state in two
  public named ETS tables, `:auth_throttle_email` and `:auth_throttle_ip`. A
  test can enable the throttle with `Application.put_env/3` (restoring it in
  `on_exit`) and clear those tables with `:ets.delete_all_objects/1`, or just
  use a fresh email, since the cooldown is keyed by email and lasts 60 seconds.
- **Reaction rate limiter:** `reaction_flow.sh` also exercises
  `Speechwave.RateLimiter`, another global ETS table with no reset. Use unique
  session ids per test, or clear the table.

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

## Docker build context

Adding Playwright put `assets/node_modules` in the build context, which
prompted a `.dockerignore`. It uses an allowlist (ignore everything, then allow
what the Dockerfile copies). Measured with the legacy builder: the context
dropped from 418.5 MB to 2.1 MB, and the image from 233 MB to 232 MB. The
release also no longer contains `priv/repo/test.db*` and `.DS_Store`, which
used to ride along from the developer's checkout. Booting both images with
dummy env vars gave identical responses for the sign-in page, pricing, CSS, JS
and logo, and `/dashboard` redirected. If the Dockerfile starts copying a new
top-level path, add it to the allowlist in `.dockerignore`. `fly deploy` reads
`.dockerignore` from the working directory by default.

## Deferred items

Things found along the way that are not part of a pass yet. Move each into a
pass (or delete it) when someone picks it up.

- **`server: true` only for E2E:** every `mix test` run now binds a port, so
  two concurrent runs on the same machine collide. `PHX_SERVER` (already
  honoured by `runtime.exs`) could enable it for `mix test.browser` only, but
  an alias can't set the environment before runtime config loads, and the
  obvious workaround (`mix cmd`) drops file arguments. Revisit if the
  collision actually bites.
- **Copy-link click coverage:** see above.
- **Partitioned runs:** verify `mix test --partitions 2` once the suite is big
  enough to want it.
- **CI gating:** decide in the final pass.

## Status

Update this table at the end of each implementation pass.

| Pass | Scope | Status |
|------|-------|--------|
| 0 | Spike: dependencies, config, `dashboard.sh` port | Done, reviewed by a fresh subagent (fixes applied) and merged to main |
| 1 | Merge the spike, extract shared helpers and `Case` module, README and `docs/manual_tests.md` setup notes | Done and merged. `SpeechwaveWeb.E2ECase`, `log_in_with_magic_link/2` and `log_in_as/2` (session cookie), docs updated. Seeding fixtures belong to the passes that need them |
| 2 | Port `account_settings.sh`; delete the already-ported `dashboard.sh` | Done and merged. Both scripts deleted |
| 3 | Port `email_consent.sh` | Not started |
| 4 | Port `session_analytics.sh` (seeding fixtures) | Not started |
| 5 | Port `reaction_flow.sh` (two-device question) | Not started |
| 6 | Port `auth_throttle.sh` email mode | Not started |
| 7 | Delete old scripts, rewrite `docs/manual_tests.md`, decide on gating | Not started |
| later | Partitioned test databases, if the suite gets slow | Deferred |
