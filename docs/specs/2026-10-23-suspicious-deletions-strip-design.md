# Suspicious deletions strip on the admin stats page

## Why

The reaper (`docs/specs/2026-10-22-suspicious-user-reaper-design.md`) now
deletes unconfirmed users who are 15 days old or more. The "Suspicious Users"
card on `/admin/stats` draws its 30-day line from the current `users` table, so
every deletion removes that person from past days too, and the line shrinks
retroactively. Without an explanation, a dip in the line looks like users
confirming, not like the reaper at work.

The fix is to show where the missing people went: a thin strip of bars under
the line, one bar per day, counting suspicious users the reaper deleted that
day. The line says who is still here. The strip says who was removed.

The deletion log (`deletions.db`) already records the deletion time and source
of every deletion, so this needs no new data.

## What it does

The Suspicious Users card keeps its title, its big number and its line chart,
all unchanged. Below the line chart sits a bar strip with these properties:

- One bar per day over the same 30 days as the line, oldest on the left,
  today on the right. A day with no deletions has no visible bar.
- A bar's height is the number of suspicious deletions that day. The strip has
  its own small y scale (0 to the largest day, with a floor so a single
  deletion is visibly a bar).
- Days are UTC, like the rest of the stats page.
- A short label above the strip: "Deleted by the reaper, per day", with the
  30-day total after it, for example "12 in the last 30 days". (The total is
  my call; it gives a screen reader and a quick glance one number.) The total
  is the sum of the same 30 zero-filled days the bars show, so the label and
  the bars cannot disagree.
- The strip area is always shown, in one of three states (changed after the
  first review; it was originally hidden when empty):
  - **Bars:** at least one suspicious deletion in the window. The bars and the
    label above.
  - **Empty:** no suspicious deletions in the window. No chart, only the text
    "No deletions in the last 30 days."
  - **Unavailable:** the deletion log could not be read (corrupt, or locked by
    a writer). No chart, only the text "Could not read the deletion log, it may
    be busy. Reload to try again." The rest of the page still loads, and the
    failure is logged as a warning.
- The strip's date labels sit on the same tick days as the line chart's x axis
  (the same date scale), so a bar can be matched to the line above by its
  label. The SVG has an `aria-label`.
- Bars line up with the days of the line chart above as closely as the chart
  library allows. Exact pixel alignment is not required.
- At phone width (about 375px) both charts scale together through their
  viewBox, so they stay aligned. The bars and the text label stay readable, but
  the axis text shrinks to about 5px, the same as the line charts on every card.
  Fixing that is out of scope (see `docs/techdebt.md`).

Only the Suspicious Users card gets a strip. No other card changes.

## Where the numbers come from

`DeletionLog.deletions_by_source/0` already returns `{DateTime, source}` for
every row, scrubbed or not, and `[]` if `deletions.db` is missing. The strip
counts rows with source `:suspicious` whose `deleted_at` falls on each of the
30 UTC days. Self-service and inactive deletions are never counted. Rows older
than the window are ignored. A missing log file reads as no deletions and must
not create the file.

## Structure

- `Speechwave.Admin.Stats` gains `suspicious_deletions(now \\ DateTime.utc_now())`
  returning `{:ok, [{Date.t(), non_neg_integer}]}` for the same 30 days as every
  other history, oldest first, zero-filled, or `{:error, :unreadable}` (with a
  logged warning) when the log cannot be read. `dashboard/1` attaches it to the
  `:suspicious` metric as a new `:deletions` key. Other metrics are unchanged
  and have no `:deletions` key, so shared helpers such as `metric/1` and the
  card component must not assume every metric has the same keys. Update the
  moduledoc and the `dashboard/1` doc.
- `Speechwave.Admin.Chart` gains a bar renderer for the strip (name left to the
  builder, for example `render_bar_svg/2`) that returns SVG like
  `render_svg/2`. Use Contex's bar chart if it can be made to look right at a
  strip's small height with 30 daily bars and sensible tick labels. If it
  cannot, a small hand-built SVG in the same module is acceptable. The builder
  chooses.
- `SpeechwaveWeb.AdminComponents.admin_stat_card/1` gains an optional `strip`
  attribute (state, label text, and the SVG when there are bars). When it is
  nil the card renders exactly as today, which is the case for every card
  except Suspicious Users.
- `StatsLive.mount/3` builds the strip for the `:suspicious` stat from its
  `:deletions` value: bars, empty, or unavailable.
- DOM ids: the strip container is `stat-suspicious-deletions`, inside the
  existing `stat-suspicious` card, with a `data-state` of `bars`, `empty` or
  `unavailable`.

## Tests

- `stats_test.exs` (log-touching, so `async: false` with the log removed in
  setup, as that file's other log tests do):
  - Counts only `:suspicious` rows, bucketed by UTC day, zero-filled to 30
    days, oldest first.
  - Ignores `:self` rows and rows older than the window.
  - Includes rows whose `user_id` has been scrubbed.
  - Returns 30 zeros and creates no file when `deletions.db` is missing.
  - Returns `{:error, :unreadable}` and does not raise when the log is corrupt.
  - A deletion at 23:59:59 UTC and one at 00:00:00 UTC the next day land on
    different days.
  - `dashboard/1`'s `:suspicious` metric has `:deletions`; no other metric does.
- `chart_test.exs`: the bar renderer returns an SVG string for a normal
  history and for one with a single bar, has an `aria-label`, and labels the
  same tick days as the line chart.
- `stats_live_test.exs`: `#stat-suspicious-deletions` has `data-state="bars"`
  with a suspicious deletion, `"empty"` with none (or only self-service or
  out-of-window ones), and `"unavailable"` when the log is corrupt, in which
  case the rest of the page still renders; no other card has a strip.

Run `mix precommit` when done.

## Docs

- Add an entry to `docs/decisions.md`: the Suspicious Users line still shrinks
  retroactively because it reads the current `users` table, and the strip
  under it is the explanation; a stacked chart reconstructing past suspicious
  users including deleted ones was rejected because the log holds no signup
  time, and adding one would put more about a person in a file that was
  designed to hold nothing but a timestamp and a reason.
- Mention the strip in `docs/specs/2026-07-06-super-admin-stats-design.md` only
  if that spec lists what each card shows; otherwise leave it alone.

## Non-goals

- No signup time or any other new field in the deletion log.
- No stacked or reconstructed "all suspicious users ever" chart.
- No strip for self-service or inactive deletions, and none on other cards.
- The Total Users and Unconfirmed lines also shrink when users are deleted
  (self-service deletions included). That is an existing, accepted limitation
  and is not changed here.
- No interactivity: no tooltips, no clicking a bar.

## Anti-goals

- A failed read of the log must never take the stats page down, and must not look like "no deletions".
- Reading the log must never create or modify `deletions.db`.
