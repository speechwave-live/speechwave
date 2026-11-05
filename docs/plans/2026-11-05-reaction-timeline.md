# Reaction Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reaction timeline chart and per-slide "people reacting" counts to the session analytics page, using ECharts, and fix three data-export tech-debt items in the same release.

**Architecture:** `Speechwave.Reactions` gains two aggregate queries (timeline buckets with slide starts, and distinct people per slide) that return plain maps. `SessionAnalyticsLive` passes the timeline as JSON in a data attribute to a colocated `.ReactionTimeline` hook, which draws an ECharts bar chart (SVG renderer). ECharts is a tree-shaken bundle committed under `assets/vendor/`, built by a dev-only npm + esbuild script, because the production image has no npm step.

**Tech Stack:** Elixir/Phoenix LiveView 1.8, Ecto + SQLite, ECharts 6 (vendored), esbuild, Tailwind v4, ExUnit, PhoenixTest (E2E).

**Spec:** `docs/specs/2026-11-04-reaction-timeline-design.md` (read it first; it is short).

## Global Constraints

- No schema change and no new data collection. Nothing in the chart data may contain an `audience_id` value or anything derived per person.
- ECharts is bundled into our own JS. No CDN, no third-party browser requests.
- Colocated hooks only (`<script :type={Phoenix.LiveView.ColocatedHook} name=".Name">`), never raw `<script>`. The hook element needs a unique `id` and `phx-update="ignore"`.
- Tailwind classes only for new markup, light theme only. Chart colours are hex copies of `--color-mint` `#00d4a4`, `--color-mint-deep` `#00b48a`, `--color-ink` `#0a0a0a`, `--color-steel` `#5a5a5c`, `--color-hairline` `#e5e5e5` from `assets/css/app.css`.
- x-axis is time since session start, formatted `m:ss`. Slide markers use the earliest reaction per slide (`MIN(inserted_at)`), slide 0 ("General") never gets a marker.
- Axis ends at the last reaction (rounded up to a whole bucket), never past `ended_at` when set. Bucket size is chosen so a session gets roughly 30 to 60 bars.
- Forms use `<.form>`; unique DOM ids on new elements; LiveView tests use `has_element?/2` and ids, not raw HTML.
- Commits use conventional commit format. Run `mix precommit` before the final commit and fix what it reports.
- Branch: `feat/reaction-timeline` (never a git worktree).

## Review Focus

Inputs the spec implies but no obvious test covers, most likely first. Each has a test in the task that owns the code.

- A session whose reactions all share the start second (single bucket, offset 0) still draws one bar. (Task 4)
- A stale-closed session (`ended_at` hours after the last reaction) does not stretch the axis. (Task 4)
- A reaction stamped before `started_at` clamps to offset 0, and one stamped after `ended_at` lands in the last bucket instead of overflowing the list. (Task 4)
- A session with reactions only on slide 0 (no slide tracking) shows the timeline with no slide labels, and no people count unless audience IDs exist. (Tasks 3 and 4)
- A slide with exactly one person reads "1 person", not "1 people". (Task 3)

## File structure

- `lib/speechwave/accounts.ex`: modify `list_user_identities/1` (Task 1).
- `lib/speechwave_web/controllers/user_data_export_controller.ex`, `router.ex`, `live/user_live/settings.ex`, matching tests: export fixes (Task 2).
- `lib/speechwave/reactions.ex`: add `slide_audience_counts/1` (Task 3) and `timeline/1` (Task 4).
- `lib/speechwave/reactions/timeline.ex` (new): pure helper `bucket_seconds/1` (Task 4).
- `test/support/fixtures/talks_fixtures.ex`: add `timed_reaction_fixture/5` (Task 4).
- `assets/package.json`, `assets/scripts/build_echarts.mjs` (new), `assets/vendor/echarts.custom.js` (new, generated, committed) (Task 5).
- `lib/speechwave_web/live/session_analytics_live.ex` and `.html.heex`: people counts (Task 3), chart container and hook (Task 6).
- `test/e2e/session_analytics_test.exs`: chart renders (Task 6).
- `docs/techdebt.md`, `CHANGELOG.md`: cleanup and release notes (Tasks 2, 1, 7).

---

### Task 1: Stable order for sign-in providers

**Files:**
- Modify: `lib/speechwave/accounts.ex:416` (`list_user_identities/1`)
- Test: `test/speechwave/accounts_test.exs`
- Modify: `docs/techdebt.md` (delete the `sign_in_providers has no explicit order` bullet)

**Interfaces:**
- Produces: `Accounts.list_user_identities(%User{}) :: [%UserIdentity{}]`, now ordered by provider name ascending, then `id` ascending.

- [ ] **Step 1: Write the failing test** in `accounts_test.exs`: `"list_user_identities/1 returns identities ordered by provider then id"`. Create identities for one user with providers inserted in the order `"google"`, `"github"`, `"microsoft"` (copy how existing tests in this file create a `UserIdentity`), then assert `Enum.map(list, & &1.provider) == ["github", "google", "microsoft"]`.
- [ ] **Step 2: Run** `mix test test/speechwave/accounts_test.exs` and confirm the new test fails on ordering.
- [ ] **Step 3: Add** `order_by: [asc: ui.provider, asc: ui.id]` to the query.
- [ ] **Step 4: Run** `mix test test/speechwave/accounts_test.exs test/speechwave/data_export_test.exs`; all pass.
- [ ] **Step 5: Commit**: `git add lib/speechwave/accounts.ex test/speechwave/accounts_test.exs docs/techdebt.md && git commit -m "fix: list sign-in providers in a stable order"`

---

### Task 2: Data export as a POST that releases its cooldown on failure

**Files:**
- Modify: `lib/speechwave_web/router.ex:55`, `lib/speechwave_web/controllers/user_data_export_controller.ex`, `lib/speechwave_web/live/user_live/settings.ex:211-227`
- Test: `test/speechwave_web/controllers/user_data_export_controller_test.exs`, `test/speechwave_web/live/user_live/settings_test.exs:20-37`
- Modify: `docs/techdebt.md` (delete the `GET with a side effect` and `cooldown is claimed before the zip is sent` bullets)

**Interfaces:**
- Produces: route `post "/users/settings/export", UserDataExportController, :create` in the same authenticated scope as today. The GET route is removed. `~p"/users/settings/export"` still names the path.

- [ ] **Step 1: Update and add controller tests** (change every `get(conn, ~p"/users/settings/export")` to `post`):
  - `"GET /users/settings/export is no longer routed"`: `assert_error_sent 404, fn -> get(conn, ~p"/users/settings/export") end`.
  - `"a build that returns {:error, _} releases the cooldown and redirects with a flash"`: set `:data_export_zip_fun` to `fn _scope -> {:error, :boom} end`; assert `redirected_to(conn) == ~p"/users/settings"`, an `:error` flash containing `"try again"`, and that after deleting the env override a second `post` returns 200.
  - `"a send that raises releases the cooldown"`: zip fun returns a value that makes `send_download` raise (try `{:ok, :not_a_binary}`; if the test adapter accepts it, use another and confirm it raises before relying on it); `assert_raise` on the post (any exception), then with the override removed a second post returns 200.
  - Keep the existing sends-zip, cooldown-flash, other-user and failed-build tests, switched to `post`.
- [ ] **Step 2: Update `settings_test.exs`**: replace the two download-link tests with `"has a download my data form that posts to the export route"` asserting `has_element?(lv, "#download-my-data-form[action='/users/settings/export'][method='post']")` and `has_element?(lv, "#download-my-data-form button#download-my-data")`.
- [ ] **Step 3: Run** both files and confirm they fail.
- [ ] **Step 4: Implement.** Router: `post ... :create`. Controller: rename `show/2` to `create/2`; after a successful `claim/1`, call the zip builder, and on `{:error, _}` or any raise from building or from `send_download/3`, call `DataExportThrottle.release(user_id)`; `{:error, _}` redirects to settings with the flash `"We could not build your download. Please try again."`; a raise is re-raised after releasing. Update the `@doc`. Settings: replace the `<a>` with `<.form for={%{}} id="download-my-data-form" action={~p"/users/settings/export"} method="post">` containing a `<button id="download-my-data" type="submit">` with the same classes and icon.
- [ ] **Step 5: Run** `mix test test/speechwave_web`; all pass. Then `grep -rn "settings/export" lib test README.md docs/*.md` to confirm nothing still describes a GET link.
- [ ] **Step 6: Commit**: `git commit -am "fix: make the data export a POST and release the cooldown when it fails"`

---

### Task 3: People reacting per slide

**Files:**
- Modify: `lib/speechwave/reactions.ex`, `lib/speechwave_web/live/session_analytics_live.ex`, `lib/speechwave_web/live/session_analytics_live.html.heex`
- Test: `test/speechwave/reactions_test.exs`, `test/speechwave_web/live/session_analytics_live_test.exs`

**Interfaces:**
- Produces: `Reactions.slide_audience_counts(session_id :: integer) :: %{optional(integer) => pos_integer}`. Keys are slide numbers (0 included). Counts are distinct non-null `audience_id`. A slide with no non-null IDs is absent from the map.
- Produces: assign `slide_people :: %{integer => pos_integer}` on `SessionAnalyticsLive`; DOM id `slide-people-<n>` on each slide card header.

- [ ] **Step 1: Write failing tests.** Reactions: `"slide_audience_counts/1 counts distinct audience ids per slide"` (slide 1: ids "a","a","b" gives 2; slide 2: id "a" gives 1; slide 3: only nil ids is absent; slide 0 with "c" gives 1; another session's reactions are ignored). LiveView: `"shows people reacting on each slide card"` asserts `has_element?(view, "#slide-people-1", "2 people")` and `"1 person"` for the singular slide, and `refute has_element?(view, "#slide-people-3")` for the slide with no IDs.
- [ ] **Step 2: Run** both files; expect failures.
- [ ] **Step 3: Implement** the query (one grouped query on `slide_number`, `count(r.audience_id, :distinct)`, filtering counts above zero), assign `slide_people` in `mount/3`, and render `<span id={"slide-people-#{slide_number}"}>` next to the slide title only when the map has the key. Wording: `"1 person"`, `"N people"`.
- [ ] **Step 4: Run** `mix test test/speechwave test/speechwave_web/live/session_analytics_live_test.exs`; all pass.
- [ ] **Step 5: Commit**: `git commit -am "feat: show how many people reacted on each slide"`

---

### Task 4: Timeline data

**Files:**
- Create: `lib/speechwave/reactions/timeline.ex`
- Modify: `lib/speechwave/reactions.ex`, `test/support/fixtures/talks_fixtures.ex`
- Test: `test/speechwave/reactions/timeline_test.exs` (new), `test/speechwave/reactions_test.exs`

**Interfaces:**
- Produces: `Speechwave.Reactions.Timeline.bucket_seconds(axis_seconds :: non_neg_integer) :: pos_integer`. Returns the smallest of `[10, 15, 30, 60, 120, 300, 600]` for which `div(axis_seconds, size) + 1 <= 60` (at most 60 buckets), else `600`.
- Produces: `Reactions.timeline(%TalkSession{}) :: nil | %{bucket_seconds: pos_integer, counts: [non_neg_integer], peak: %{index: non_neg_integer, count: pos_integer}, slide_starts: [%{slide: pos_integer, offset_seconds: non_neg_integer}]}`. `nil` when the session has no reactions. `counts` has one entry per bucket from bucket 0; `peak` is the highest count, ties to the earliest bucket; `slide_starts` is sorted by `offset_seconds` then `slide`. All values are integers, so the map encodes with `Jason`.
- Produces (test support): `timed_reaction_fixture(session, offset_seconds :: integer, emoji \\ "❤️", slide_number \\ 1, audience_id \\ nil)` inserting a `Reaction` whose `inserted_at` is `session.started_at` plus the offset.

- [ ] **Step 1: Write failing tests.**
  - `timeline_test.exs`: `bucket_seconds/1` for 0 → 10, 599 → 10, 600 → 15, 1200 → 30, 2700 → 60, 3600 → 120, 14_400 → 300, 100_000 → 600.
  - `reactions_test.exs` `describe "timeline/1"`, using `session_fixture(talk, %{started_at: ~U[2026-01-01 10:00:00Z]})` and the new fixture:
    - no reactions → `nil`.
    - counts and peak: reactions at offsets 0, 3, 12, 14, 15 give `bucket_seconds: 10`, `counts: [2, 3]`, `peak: %{index: 1, count: 3}`.
    - peak tie goes to the earliest bucket.
    - `slide_starts` use the earliest reaction per slide, a later return to a slide adds no second entry, slide 0 is excluded, sorted by offset.
    - **Review focus:** all reactions at offset 0 → `counts: [n]`, one bucket.
    - **Review focus:** `ended_at` four hours after start but last reaction at 600 s → axis length comes from the last reaction: `bucket_seconds == 15` and `length(counts) == 41`.
    - **Review focus:** reaction at offset -5 counts in bucket 0; with `ended_at` at offset 100 a reaction at offset 130 counts in the last bucket and `length(counts) == 11` (axis capped at 100 s, 10 s buckets).
    - **Review focus:** only slide 0 reactions → `slide_starts: []`, counts present.
    - active session (`ended_at: nil`) works.
    - the map has no audience data: with `audience_id` set on reactions, `Jason.encode!(timeline)` does not contain those ids.
- [ ] **Step 2: Run** both test files; expect failures (undefined functions).
- [ ] **Step 3: Implement `Timeline.bucket_seconds/1`.**
- [ ] **Step 4: Implement `Reactions.timeline/1`.** Do the bucketing in SQL: offset seconds per reaction is `CAST(strftime('%s', inserted_at) AS INTEGER)` minus the epoch of `started_at`, via an Ecto `fragment`. Query 1 finds the last offset (and returns `nil` if no rows); derive `axis_seconds` as `max(last_offset, 0)` capped at `ended_at - started_at` when `ended_at` is set, pick `bucket_seconds`, then query 2 groups `max(offset, 0) / bucket` and counts; clamp any index beyond the last bucket into the last bucket, then fill missing buckets with 0. Query 3 (or the same pass) takes `min(offset)` per `slide_number > 0`, clamped at 0.
- [ ] **Step 5: Add `timed_reaction_fixture/5`** to `talks_fixtures.ex`.
- [ ] **Step 6: Run** `mix test test/speechwave`; all pass.
- [ ] **Step 7: Commit**: `git add lib/speechwave/reactions.ex lib/speechwave/reactions test && git commit -m "feat: aggregate reactions into a timeline with slide starts"`

---

### Task 5: Vendored ECharts bundle

**Files:**
- Modify: `assets/package.json` (add `echarts` and `esbuild` as `devDependencies`, add script `"build:echarts": "node scripts/build_echarts.mjs"`), `assets/package-lock.json`
- Create: `assets/scripts/build_echarts.mjs`, `assets/scripts/echarts_entry.js`, `assets/vendor/echarts.custom.js` (generated)

**Interfaces:**
- Produces: ES module `assets/vendor/echarts.custom.js` with named export `init(dom, theme?, opts?)` (ECharts' `init`) with these pieces registered: `BarChart`, `GridComponent`, `TooltipComponent`, `MarkPointComponent`, `AriaComponent`, `SVGRenderer`, and `LabelLayout` (needed for `labelLayout.hideOverlap`). Nothing else.

- [ ] **Step 1: Write `echarts_entry.js`** importing those pieces from `echarts/core`, `echarts/charts`, `echarts/components`, `echarts/renderers`, `echarts/features`, calling `use([...])`, and `export { init } from "echarts/core"`.
- [ ] **Step 2: Write `build_echarts.mjs`**: esbuild `build` with `bundle: true, minify: true, format: "esm"`, entry `scripts/echarts_entry.js`, outfile `vendor/echarts.custom.js`, and a banner comment `// Generated by assets/scripts/build_echarts.mjs from echarts@<version>. Do not edit; run "npm run build:echarts" in assets/.` (read the version from `node_modules/echarts/package.json`).
- [ ] **Step 3: Run** `cd assets && npm install && npm run build:echarts`.
- [ ] **Step 4: Verify**: `ls -l assets/vendor/echarts.custom.js` (expect a few hundred KB, record the size in the commit message; investigate if over about 600 KB), and `node --input-type=module -e "import('./assets/vendor/echarts.custom.js').then(m => console.log(typeof m.init))"` prints `function`.
- [ ] **Step 5: Confirm** `git status` lists `assets/vendor/echarts.custom.js` as a new tracked file (not ignored).
- [ ] **Step 6: Commit**: `git add assets/package.json assets/package-lock.json assets/scripts assets/vendor/echarts.custom.js && git commit -m "build: vendor a tree-shaken ECharts bundle"`

---

### Task 6: Timeline chart on the analytics page

**Files:**
- Modify: `lib/speechwave_web/live/session_analytics_live.ex`, `lib/speechwave_web/live/session_analytics_live.html.heex`
- Test: `test/speechwave_web/live/session_analytics_live_test.exs`, `test/e2e/session_analytics_test.exs`

**Interfaces:**
- Consumes: `Reactions.timeline/1` (Task 4), `Reactions.slide_audience_counts/1` (Task 3), `echarts.custom.js` `init` (Task 5).
- Produces: assign `timeline` (map or `nil`); element `#reaction-timeline` with `phx-hook=".ReactionTimeline"`, `phx-update="ignore"`, `role="img"`, `aria-label`, and `data-timeline` holding `Jason.encode!(@timeline)`; rendered only when `@timeline` is not nil, between `#stats` and the per-slide cards.

- [ ] **Step 1: Write failing LiveView tests** (using `timed_reaction_fixture`): `"renders the timeline container with its data"`: `has_element?(view, "#reaction-timeline")`, and decoding the element's `data-timeline` (read it with `LazyHTML` from `render(element(view, "#reaction-timeline"))`, then `Jason.decode!`) has `"counts"`, `"peak"`, `"slide_starts"`, and `"bucket_seconds"` keys with expected values; `"aria-label mentions the total and the peak"`; `"has no timeline for an empty session"` (`refute has_element?(view, "#reaction-timeline")`, existing "No reactions recorded" message still shown); `"data attribute never includes audience ids"`; **Review focus:** a session with only slide 0 reactions renders the container with `"slide_starts": []`.
- [ ] **Step 2: Extend the E2E test** `view, compare, rename and delete sessions`: after the first `visit("/sessions/#{session1.id}")`, add `assert_has("#reaction-timeline svg")`.
- [ ] **Step 3: Run** the LiveView tests; expect failures. (E2E later: `mix test.browser`.)
- [ ] **Step 4: Assign `timeline`** in `mount/3` and render the container with the attributes above. `aria-label` reads like `"Reactions over time: N reactions, busiest at m:ss"`.
- [ ] **Step 5: Add the colocated hook `.ReactionTimeline`** to the template: imports `init` from `"@/vendor/echarts.custom"` (the esbuild alias `@` already points at `assets`), parses `data-timeline` on `mounted()`, creates the chart with `init(this.el, null, {renderer: "svg"})`, applies an options object built as follows, observes size with `ResizeObserver` to call `chart.resize()`, and in `destroyed()` disconnects the observer and calls `chart.dispose()`:
  - x axis: category labels `m:ss` of each bucket start (`index * bucket_seconds`); y axis: whole numbers (`minInterval: 1`); `aria: {enabled: true}`.
  - One bar series of `counts` in `#00d4a4`; the peak bar in `#00b48a`; a `markPoint` on the peak labelled `Peak: N` and `markPoint` entries for each slide start at that bucket's bar top labelled `Slide N`; series `labelLayout: {hideOverlap: true}`.
  - Tooltip (axis trigger) shows the time range, the count, and a line `Slide N starts here` for every slide whose first reaction falls in that bucket, so a label hidden by overlap is never lost.
  - Fonts and axis colours use the hex values from Global Constraints; the chart has a fixed height of about 240 px and the container is `w-full`; no horizontal scroll at 375 px.
- [ ] **Step 6: Run** `mix test test/speechwave_web/live/session_analytics_live_test.exs`, then `mix assets.build` (must succeed with `assets/node_modules/echarts` absent: `mv assets/node_modules/echarts /tmp/echarts_hold` first and move it back after), then `mix test.browser`; all pass.
- [ ] **Step 7: Check by eye** at 1000 px and 375 px wide: use the Playwright screenshot recipe noted in project memory (`reference_dev_server_reload`); confirm bars, the peak label, slide labels, tooltip and no horizontal page scroll. Fix any overlap before committing.
- [ ] **Step 8: Commit**: `git commit -am "feat: add a reaction timeline to session analytics"`

---

### Task 7: Release notes and final checks

**Files:**
- Modify: `CHANGELOG.md`, `docs/techdebt.md` (confirm the three export items are gone, and drop the section if now empty)

- [ ] **Step 1: Add an `## [Unreleased]` section** to `CHANGELOG.md` above 0.5.0 with: **Added**: the reaction timeline and the per-slide people count; **Fixed**: "Download my data" is now a button that sends a POST, a failed download no longer leaves you waiting out the five-minute cooldown, and sign-in providers in the export always appear in the same order. Write it in plain, direct language; run `node ~/.claude/skills/writing-tracy/scripts/lint.js CHANGELOG.md` and fix any hits.
- [ ] **Step 2: Run** `mix precommit`; fix anything it reports.
- [ ] **Step 3: Run** `mix test.browser`; all pass.
- [ ] **Step 4: Commit**: `git commit -am "docs: add unreleased notes for the reaction timeline"`
- [ ] **Step 5 (not part of this repo's commit):** note for after release: update the analytics page in the docs repo (`../docs`), and draft the announcement into `docs/internal/` (gitignored).
