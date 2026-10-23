# Suspicious Deletions Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show, under the Suspicious Users line chart on `/admin/stats`, a strip of bars counting suspicious users the reaper deleted each day.

**Architecture:** `Stats.suspicious_deletions/1` buckets `DeletionLog.deletions_by_source/0` rows with source `:suspicious` into the same 30 UTC days as every other history, and `dashboard/1` attaches the result to the `:suspicious` metric as `:deletions`. `Chart.render_bar_svg/2` renders it as a small server-side SVG. `admin_stat_card/1` shows it, only when the 30-day total is above zero.

**Tech Stack:** Elixir, Phoenix LiveView 1.8, Contex 0.5 (SVG charts), ExUnit.

**Spec:** `docs/specs/2026-10-23-suspicious-deletions-strip-design.md`

## Global Constraints

- Branch is `feat/suspicious-deletions-strip`. No git worktrees. Conventional commit messages.
- Days are UTC, the same 30 days as every other history (`Stats.history_days/0`), oldest first, zero-filled.
- Count only source `:suspicious`. Rows older than the window and `:self` / `:inactive` rows are ignored. Rows whose `user_id` has been scrubbed still count.
- Reading the log must never create or modify `deletions.db`; use only `DeletionLog.deletions_by_source/0`.
- Only the `:suspicious` metric gets a `:deletions` key. Shared helpers (`metric/1`, the card component, `StatsLive`) must not assume every metric has it.
- The strip is hidden when the 30-day total is 0; the card must then render exactly as today.
- Label text is exactly `"Deleted by the reaper, per day. N in the last 30 days."` with `N` the sum of the same 30 zero-filled days the bars show.
- Strip container DOM id is `stat-suspicious-deletions`, inside `#stat-suspicious`.
- Tests that touch the deletion log are non-async (the default for `DataCase`/`ConnCase` here, so do not add `async: true`) and `File.rm(DeletionLog.path())` in a `setup`.
- Prose in `docs/decisions.md` has no dash-separated phrases. Run `mix precommit` before the last task is done.

## Review Focus

- A deletion at `23:59:59Z` and one at `00:00:00Z` the next day land on different days (Task 1).
- A missing `deletions.db` yields 30 zeros and the file is still absent afterward (Task 1).
- Only `:self` deletions, or only deletions older than 30 days, leave the strip hidden (Task 3).
- A history with a single non-zero day renders a bar chart without raising (Task 2).
- A row whose `user_id` was scrubbed still counts on its `deleted_at` day (Task 1).
- No other card gains a strip, and a card with no strip renders as before (Task 3).

---

### Task 1: `Stats.suspicious_deletions/1` and the `:deletions` key

**Files:**
- Modify: `lib/speechwave/admin/stats.ex` (new public function, `dashboard/1`, moduledoc, `dashboard/1` doc)
- Test: `test/speechwave/admin/stats_test.exs` (new `describe "suspicious_deletions/1"`, extend `describe "dashboard/1"`)

**Interfaces:**
- Consumes: `Speechwave.DeletionLog.deletions_by_source() :: [{DateTime.t(), :self | :suspicious | :inactive}]`.
- Produces: `Stats.suspicious_deletions(now :: DateTime.t() \\ DateTime.utc_now()) :: [{Date.t(), non_neg_integer}]`, exactly `history_days/0` entries, oldest first. `Stats.dashboard/1`'s `:suspicious` metric is `%{current: _, history: _, deletions: [{Date.t(), non_neg_integer}]}`; every other metric is unchanged.

- [ ] **Step 1: Write the failing tests**

In a new `describe "suspicious_deletions/1"` with `setup do File.rm(DeletionLog.path()); :ok end`, using a fixed `now = ~U[2026-11-15 12:00:00Z]` and `DeletionLog.record(id, source, deleted_at)`:
  - `"counts only :suspicious rows per UTC day, zero-filled, oldest first"`: two `:suspicious` on `~D[2026-11-14]`, one on `~D[2026-11-15]`, one `:self` on `~D[2026-11-14]`. Assert the result has 30 entries, the first date is `~D[2026-10-17]`, the last is `~D[2026-11-15]`, the count on 11-14 is 2, on 11-15 is 1, and the sum is 3.
  - `"ignores rows older than the window"`: a `:suspicious` row on `~D[2026-10-16]` (day 31) is not counted; one on `~D[2026-10-17]` (day 30) is.
  - `"splits days at UTC midnight"`: `:suspicious` at `~U[2026-11-13 23:59:59Z]` and `~U[2026-11-14 00:00:00Z]` count on different days.
  - `"counts rows whose user_id has been scrubbed"`: record a `:suspicious` row at `~U[2026-11-01 10:00:00Z]`, call `DeletionLog.scrub(~U[2026-12-15 00:00:00Z])` so its `user_id` becomes NULL, and assert the Nov 1 count is still 1.
  - `"returns 30 zeros and creates no file when the log is missing"`: `File.rm` first; sum is 0, length 30, `refute File.exists?(DeletionLog.path())`.
  - In `describe "dashboard/1"`: the `:suspicious` metric has a `:deletions` list of `Stats.history_days()` entries and no other metric has the `:deletions` key.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: FAIL with `undefined function suspicious_deletions/1` and the missing `:deletions` key.

- [ ] **Step 3: Implement**

`suspicious_deletions/1` in `lib/speechwave/admin/stats.ex`: truncate `now` to seconds, build `days` with the existing `last_n_days/2`, read `DeletionLog.deletions_by_source/0`, keep `:suspicious` rows, count by `DateTime.to_date/1`, and map each day to its count (0 if absent); rows outside `days` fall away naturally. `dashboard/1` adds `deletions: suspicious_deletions(now)` to the `:suspicious` entry only (`Map.update!(metrics, :suspicious, &Map.put(&1, :deletions, ...))`). Update the moduledoc and the `dashboard/1` doc to describe the `:deletions` key, and add an `alias Speechwave.DeletionLog`.

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/speechwave/admin/stats_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave/admin/stats.ex test/speechwave/admin/stats_test.exs
git commit -m "feat: count suspicious deletions per day for the stats page"
```

---

### Task 2: `Chart.render_bar_svg/2`

**Files:**
- Modify: `lib/speechwave/admin/chart.ex`
- Test: `test/speechwave/admin/chart_test.exs`

**Interfaces:**
- Produces: `Chart.render_bar_svg(history :: [{Date.t(), non_neg_integer}], opts \\ []) :: Phoenix.HTML.Safe.t()` with options `:width` (default 680, the same as `render_svg/2`) and `:height` (default about 90; the strip must be much shorter than the 220px line chart). Returns the same kind of value as `render_svg/2` (the tests use `Phoenix.HTML.Safe.to_iodata/1`).

- [ ] **Step 1: Write the failing tests**

In `chart_test.exs` (stays `async: true`; it does no I/O):
  - `"render_bar_svg renders a 30-day history as an SVG"`: `history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), rem(i, 3)}`; the output contains `"<svg"`.
  - `"render_bar_svg renders a history with a single non-zero day without raising"`: 29 zeros and one `1`; contains `"<svg"`.
  - `"render_bar_svg output differs for different data"`: two histories give different strings.
  - `"render_bar_svg output is shorter than the line chart"`: parse nothing; assert the `height="..."` or `viewBox` height of the bar SVG is smaller than that of `render_svg/1` on the same history.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/speechwave/admin/chart_test.exs`
Expected: FAIL with `undefined function render_bar_svg/1`.

- [ ] **Step 3: Implement `render_bar_svg/2` in `lib/speechwave/admin/chart.ex`**

The builder picks the technique. Prefer `Contex.BarChart` (single series, `data_labels: false`) if it renders 30 daily bars legibly at about 90px high; the line chart's ~70px axis margins mean you must check the output visually (render it into a scratch HTML file and look at it, or use the dev server). If Contex crowds the 30 category labels or cannot be made short enough, write a small hand-built SVG in the same module instead (rectangles per day, a baseline, and a few day labels). Either way: bars align with the line chart's days as closely as practical (same width, comparable left margin), and an all-zero history must not raise even though the page hides it. Add a short comment on why this technique was chosen.

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/speechwave/admin/chart_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave/admin/chart.ex test/speechwave/admin/chart_test.exs
git commit -m "feat: render a compact bar chart for daily counts"
```

---

### Task 3: Show the strip on the Suspicious Users card, and document it

**Files:**
- Modify: `lib/speechwave_web/components/admin_components.ex` (`admin_stat_card/1`)
- Modify: `lib/speechwave_web/live/admin/stats_live.ex` (`mount/3`)
- Modify: `lib/speechwave_web/live/admin/stats_live.html.heex`
- Modify: `docs/decisions.md` (append an entry)
- Test: `test/speechwave_web/live/admin/stats_live_test.exs`

**Interfaces:**
- Consumes: the `:deletions` key on the `:suspicious` stat (Task 1) and `Chart.render_bar_svg/2` (Task 2).
- Produces: `admin_stat_card/1` gains optional attrs `strip_svg` (`:any`, default `nil`) and `strip_label` (`:string`, default `nil`). When `strip_svg` is nil the card's markup is unchanged. Otherwise the strip renders below the line chart in a container with id `"#{@id}-deletions"` (so `stat-suspicious-deletions`) that shows `strip_label` and then the SVG.

- [ ] **Step 1: Write the failing tests**

In `stats_live_test.exs` add a `describe "suspicious deletions strip"` with `setup do File.rm(Speechwave.DeletionLog.path()); :ok end`, logging in an admin as the existing tests do:
  - `"shows the strip when the reaper has deleted suspicious users"`: `DeletionLog.record(1, :suspicious)`; `has_element?(view, "#stat-suspicious #stat-suspicious-deletions")`, and the container text includes `"1 in the last 30 days"`.
  - `"hides the strip when there are no deletions"`: no records; `refute has_element?(view, "#stat-suspicious-deletions")`.
  - `"hides the strip when only self-service deletions exist"`: `DeletionLog.record(1, :self)`; no strip.
  - `"hides the strip when the only suspicious deletion is older than 30 days"`: `DeletionLog.record(1, :suspicious, DateTime.add(DateTime.utc_now(), -31, :day))`; no strip.
  - `"no other card has a strip"`: with a suspicious deletion recorded, assert no element matches `[id$="-deletions"]` other than `#stat-suspicious-deletions`.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/speechwave_web/live/admin/stats_live_test.exs`
Expected: FAIL (the first test finds no `#stat-suspicious-deletions`).

- [ ] **Step 3: Implement**

  - `admin_stat_card/1`: add the two attrs and the strip block (label as small steel text above the SVG, matching the card's existing classes and spacing; `:if={@strip_svg}`).
  - `StatsLive.mount/3`: after building `chart_svg` for each stat, when the stat map has a `:deletions` key whose entries sum above 0, also put `strip_svg: Chart.render_bar_svg(stat.deletions)` and `strip_label: "Deleted by the reaper, per day. #{total} in the last 30 days."`. Use `Map.get/2` so stats without `:deletions` are untouched.
  - `stats_live.html.heex`: pass `strip_svg={Map.get(stat, :strip_svg)}` and `strip_label={Map.get(stat, :strip_label)}`.

- [ ] **Step 4: Add the `docs/decisions.md` entry**

Heading `## 2026-10-23 — Suspicious Users shows a deletions strip, not a reconstructed history`, in the style of neighbouring entries. Content from the spec: the Suspicious Users line still shrinks retroactively because it reads the current `users` table, and the strip under it is the explanation; a stacked chart rebuilding past suspicious users including deleted ones was rejected because the log holds no signup time and adding one would put more about a person in a file designed to hold only a timestamp and a reason; Total Users and Unconfirmed also shrink on deletion and are left as they are. Spec line: `Spec: docs/specs/2026-10-23-suspicious-deletions-strip-design.md`.

- [ ] **Step 5: Run the full suite and precommit**

Run: `mix test` then `mix precommit`
Expected: all tests pass; precommit reports no issues (fix any it raises).

- [ ] **Step 6: Look at it**

Start the dev server per the project's usual recipe (see the `run` skill and `reference_dev_server_reload` memory), seed a few `DeletionLog.record(n, :suspicious, <recent date>)` rows in dev, open `/admin/stats` as an admin, and confirm the strip appears under the Suspicious Users line, is legible, and lines up reasonably with the line chart above. Remove the dev log rows afterward. Report what you saw.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave_web test/speechwave_web docs/decisions.md
git commit -m "feat: show a deletions strip on the Suspicious Users card"
```
