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
- The strip is hidden when there were no suspicious deletions in the 30-day
  window, so the card looks exactly as it does today until the reaper has
  deleted someone.
- Bars line up with the days of the line chart above as closely as the chart
  library allows. Exact pixel alignment is not required.

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
  returning `[{Date.t(), non_neg_integer}]` for the same 30 days as every other
  history, oldest first, zero-filled. `dashboard/1` attaches it to the
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
- `SpeechwaveWeb.AdminComponents.admin_stat_card/1` gains optional attributes
  for the strip (its SVG and its label text). When the strip SVG is nil the card
  renders exactly as today.
- `StatsLive.mount/3` renders the strip SVG for the `:suspicious` stat when its
  deletions total is above zero, and passes it with the label to the card.
- DOM ids: the strip container is `stat-suspicious-deletions`, inside the
  existing `stat-suspicious` card.

## Tests

- `stats_test.exs` (log-touching, so `async: false` with the log removed in
  setup, as that file's other log tests do):
  - Counts only `:suspicious` rows, bucketed by UTC day, zero-filled to 30
    days, oldest first.
  - Ignores `:self` rows and rows older than the window.
  - Includes rows whose `user_id` has been scrubbed.
  - Returns 30 zeros and creates no file when `deletions.db` is missing.
  - A deletion at 23:59:59 UTC and one at 00:00:00 UTC the next day land on
    different days.
  - `dashboard/1`'s `:suspicious` metric has `:deletions`; no other metric does.
- `chart_test.exs`: the bar renderer returns an SVG string for a normal
  history and for one with a single bar.
- `stats_live_test.exs`: with at least one suspicious deletion, the page has
  `#stat-suspicious-deletions`; with none, it does not; no other card has a
  strip.

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

- The card must not look different from today when there is nothing to show.
- Reading the log must never create or modify `deletions.db`.
