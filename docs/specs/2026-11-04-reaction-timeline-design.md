# Reaction timeline and people counts: design

Date: 2026-11-04
Status: draft for approval
Size: a project (new charting library, new analytics query, new hook, plus a
small bundle of tech-debt fixes for the same release)

## Intent and why

The session analytics page (`SessionAnalyticsLive`) tells a speaker how many
reactions came in, which slide and emoji won, and how each slide did. It does
not show **when** the audience reacted. Speechwave's pitch is continuous
engagement plus post-talk analytics, and "when did engagement peak, and what was
on screen" is the question a speaker asks first after a talk.

This release adds:

1. A **reaction timeline** chart on the session analytics page: reactions over
   the course of the talk, with the peak called out and the first reaction on
   each slide labelled with its slide number.
2. A **people reacting** count on each slide card, so a speaker can tell broad
   reaction from a few enthusiastic people.
3. **ECharts** as the project's charting library, so later visualizations are
   declarative option objects, not hand-drawn SVG.
4. Three small fixes from `docs/techdebt.md` (data export), per the rule of at
   least one known issue fixed per release.

The feature is also meant to be demo-able: the timeline should make a good
screenshot for the weekly announcement.

## Goals

- A speaker opening a finished session sees a timeline of reactions against time
  since the start of the talk.
- The busiest moment is visibly highlighted and labelled.
- Slide numbers appear on the timeline where the audience first reacted to that
  slide.
- Each slide card shows how many distinct people reacted on that slide.
- The chart is readable at phone width (the stats page charts are not, see
  `docs/techdebt.md`).
- Charting is declarative and reusable, so the next chart is mostly an options
  object.

## Non-goals

- Recording slide changes from the extension. Changing the extension and adding a
  table was judged too costly. Slide markers come from reactions only.
- Showing the timeline on the comparison view. Comparison keeps its current
  per-slide cards.
- Live-updating the chart while a session is active. The analytics page is not
  live today and stays that way.
- Replacing the stats page charts (`Speechwave.Admin.Chart`, Contex). They stay as
  they are.
- Heatmaps, session overlays, export to image or PDF. Possible later uses of
  ECharts, not part of this work.
- Per-emoji people counts (they mostly repeat the reaction count).

## Anti-goals

- Nothing about an individual audience member may reach the page or the chart
  data. Only aggregate counts. `audience_id` is stored as a one-way hash per
  session (see 0.4.0 changelog and the privacy policy) and must not become
  linkable or visible.
- No new data collection and no schema change. The privacy policy stays accurate
  as written.
- No third-party requests from the browser. ECharts is bundled into our own JS,
  not loaded from a CDN.

## Constraints from the project

- Reactions already have `inserted_at` (UTC, whole seconds), `slide_number`
  (0 means "General", no slide tracking) and a nullable `audience_id`. Sessions
  have `started_at` and a nullable `ended_at`. There is an index on
  `reactions.talk_session_id`.
- Sessions left open are closed by `Talks.close_stale_sessions/0` with
  `ended_at = started_at + session_timeout_hours` (default 4). So `ended_at` can
  be hours after the last reaction. The chart axis must not stretch to it.
- The production image runs only `mix assets.deploy` (see `Dockerfile`). There is
  no `npm install` step, and `assets/package.json` has no runtime dependencies.
  JS libraries are vendored as files in `assets/vendor` (as with `topbar.js`).
- CLAUDE.md: colocated hooks for inline JS, never raw `<script>`; a `phx-hook`
  needs a unique DOM id and `phx-update="ignore"` if the hook manages its own
  DOM; Tailwind classes only for new markup; light theme only.
- LiveView tests cannot see what a chart library draws. Server-side tests assert
  on the data handed to the hook; one Playwright test in `test/e2e` checks that
  the chart renders.

## Approaches considered

| Approach | Trade-off | Decision |
|---|---|---|
| A. Hand-drawn server-side SVG bars, like the stats page deletions strip | No JS, fits SSR style. But all future charts become more hand-managed SVG, labels need manual collision handling, no tooltips. | Rejected |
| B. Contex chart | Already a dependency. Fixed 70px margins and no good way to place text labels inside the plot, which is why the deletions strip was hand-built. | Rejected |
| C. Client-side library via a colocated hook | Browser renders, server only aggregates. Adds a vendored library. | **Chosen** |

Within C, the libraries compared were ECharts, Chart.js with the annotation
plugin, Observable Plot, Vega-Lite and uPlot. ECharts was chosen because
annotations (`markLine`, `markPoint`) are built in and later chart types
(heatmap, multi-series, linked charts) are options changes. Chart.js with the
annotation plugin is the fallback if bundle size becomes a problem. Vega-Lite is
too heavy, uPlot is time series only, D3 is not declarative.

## Decisions made together

- Client-side charting with **ECharts**, tree-shaken to only the pieces used.
- Slide markers: label the **first reaction on each slide** with its slide
  number. No extension changes.
- The x-axis is **time since the start of the session** ("0:00" to "45:00"), not
  clock time, which avoids time zone questions.
- Bucket size adapts to session length so any session gets roughly 30 to 60 bars.
- The chart sits under the stat boxes and above the per-slide cards.
- People counts go on the **slide cards**, not on each emoji line.

## Design

### Data (server)

Add to `Speechwave.Reactions`:

- A function returning timeline data for a session: bucket size in seconds, a
  list of per-bucket reaction counts covering the axis, the peak bucket, and the
  first-reaction offset (in seconds from session start) for each real slide
  (slide 0 excluded). Bucketing is a grouped SQL query on `inserted_at` relative
  to `started_at`, not Elixir-side iteration over rows.
- A function returning, per slide number, the count of distinct `audience_id`
  values. A slide where no reaction has an `audience_id` gets no count (nil), so
  old sessions show nothing instead of a misleading "0 people".

The return values are plain maps and numbers, suitable for `Jason.encode!`. They
contain no `audience_id` values.

### Axis range

The axis runs from 0 to the last reaction, rounded up to a whole bucket, and
never past `ended_at` when it is set. It does not run to `ended_at` itself,
because a stale-closed session would show a 4 hour axis. Reactions timestamped
before `started_at` (clock skew) are clamped to offset 0.

### Bucket size

Chosen from the axis length, from a short list of round sizes (for example 10s,
15s, 30s, 1m, 2m, 5m) so the bar count lands near 30 to 60. Exact list is the
builder's call.

### Page and hook

- The LiveView computes the timeline data in `mount` alongside the existing
  assigns and renders a container with a unique id (for example
  `reaction-timeline`), the JSON in a data attribute, `phx-hook=".ReactionTimeline"`
  and `phx-update="ignore"`.
- The colocated hook creates the ECharts instance, builds the options from the
  data attribute, handles resize (a `ResizeObserver` or ECharts' own resize on
  window resize) and disposes the instance in `destroyed`.
- Chart contents: bars per bucket in the brand mint colour; the peak bucket in a
  stronger colour with a label such as "Peak: 14 reactions at 23:00"; slide
  labels ("Slide 12") at the bucket where that slide first got a reaction; a
  tooltip with the time range and count; the y axis showing whole reactions.
- Slide labels must not pile up. When many slides start within a few buckets, the
  chart should hide overlapping labels (ECharts `labelLayout.hideOverlap`) rather
  than overprint them. A label that has to be hidden is acceptable; unreadable
  text is not.
- A session with no reactions shows no chart. The existing "No reactions recorded
  in this session." message stays.
- Phone width: the chart uses the real container width, with legible axis text
  and a sensible height. This is a stated requirement, not left to chance.
- Accessibility: the container carries an `aria-label` that summarizes the chart
  (for example total reactions and the peak), and ECharts' `aria` option is on.

### People counts

Each slide card header gets "N people" next to "Slide 12", shown only when the
count is known. The "General" card may show it too. The comparison cards are
unchanged.

### Bundling ECharts

- Build a tree-shaken ESM bundle of only the ECharts pieces used (core, bar chart,
  the mark and tooltip components, grid, title if used, the renderer and the aria
  component) and commit the result in `assets/vendor/`, matching how `topbar.js`
  is handled.
- Because the production image does not run `npm install`, the build must not
  depend on `node_modules` at deploy time. Add a short note (comment at the top
  of the file or in the README) saying how to regenerate it and which ECharts
  version it is from.
- Import it from `app.js` and keep it out of the way of pages that do not need
  it if that is practical (for example a dynamic `import()` inside the hook).
  Whether to do that depends on the final bundle size and is the builder's call.
- Renderer (canvas or SVG) is the builder's call. SVG output is crisp for
  screenshots and easier to assert on in Playwright.

### Tech-debt fixes in this release

All from the "Data export" section of `docs/techdebt.md`. Delete each item from
that file when fixed.

1. **Make the export a POST.** It is a GET with a side effect, so a prefetch or
   cross-site link can use up a user's cooldown. Change the Settings control to a
   form button that posts, and the route to POST. Keep CSRF protection on. Update
   the existing export tests and any docs or privacy text that name the route.
2. **Release the cooldown when the download fails after the claim.** Today a
   failed or cancelled download leaves the user waiting 5 minutes with no file.
3. **Give `Accounts.list_user_identities/1` an explicit `order_by`**, so the
   export lists `sign_in_providers` in a stable order.

Related but not in this release: `busy_timeout` on the deletion log read
connection (left in techdebt.md).

## Testing

- Unit tests for the new `Reactions` functions: bucket counts, peak, first
  reaction per slide (slide 0 excluded), clamping, empty session, people counts
  including the nil case, and that no `audience_id` appears in the output.
- LiveView tests for `SessionAnalyticsLive`: the container element is present
  with the data attribute for a session with reactions; absent for an empty one;
  the people count appears on slide cards when known and not when unknown. Use
  element ids, not raw HTML assertions.
- Playwright test: extend `test/e2e/session_analytics_test.exs` so the chart
  renders for a seeded session.
- Tests for the three export fixes, written first (test-driven).
- `mix precommit` clean.

## Out of scope for the implementer (follow-up)

- User-facing docs for the analytics page live in the separate docs repo
  (`../docs`) and need a short update after release.
- Changelog entry and version bump follow the normal release flow.
- The announcement draft goes in `docs/internal/`.

## Left to the builder

- Exact bucket-size list, colours within the existing palette, chart height.
- Canvas vs SVG renderer.
- Whether ECharts loads eagerly or by dynamic import.
- Function names and where the data shaping lives, provided the SQL does the
  bucketing.
- How best to regenerate and document the vendored bundle.
- Whether the "General" (slide 0) card shows a people count.

## Clarifications from the builder check

- **Slide markers** use the earliest reaction on slide N wherever it falls
  (`MIN(inserted_at) GROUP BY slide_number`), not a label each time the audience
  moves to a different slide. A slide revisited later gets no second label.
- **Two slides in one bucket:** both labels are requested, `hideOverlap` may
  hide one, and the tooltip for that bucket lists every slide whose first
  reaction fell in it, so nothing is lost.
- **People counts** are distinct non-null `audience_id` values for that slide in
  that session, the same rule the existing "People Reacting" stat uses. A slide
  with some reactions carrying an ID and some not shows the partial count, a lower
  bound, as the stat does. Nil (no count shown) only when none carry an ID. A
  small count such as "1 person" is accepted: the page is visible only to the
  speaker who owns the talk and already shows a total people count.
- **Cooldown release** covers server-side failures only (errors while building
  or sending the zip). A download the browser cancels is invisible to the server
  and stays out of scope; the 5 minute wait remains for that case.
- **Bundle tooling:** a dev-only step is fine. Add `echarts` to
  `assets/package.json` as a dev dependency (the directory already has npm for
  Playwright) and a small script that uses esbuild to write the tree-shaken
  bundle to `assets/vendor/`. Production still needs no npm.
- **Playwright seed:** the builder reads the existing e2e seeding and extends it
  so a session has reactions on several slides across time. "Renders" means the
  chart container has a drawn chart inside it (for example an `svg` element with
  bars if the SVG renderer is used).
- A single-bucket axis (all reactions at the same second) still draws one bar.

## Calls I made that you should check

- Axis ends at the last reaction, not at `ended_at`, because of stale-closed
  sessions.
- No timeline on the comparison view.
- No per-emoji people counts.
- A vendored, committed ECharts bundle instead of an npm dependency, because the
  production image has no npm step.
- Accepting small people counts such as "1 person" without suppression.
- Cooldown release for server-side failures only.
- A committed ECharts bundle of a few hundred KB in `assets/vendor/`, generated
  by a dev-only npm plus esbuild script.
- Which three techdebt items to fix. They are the export route POST, the
  cooldown on a failed download and the stable provider order, grouped because
  they touch the same code.
