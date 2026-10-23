# Tech debt

Small known issues found in code review and left alone on purpose. Each one
says why it was deferred. Bigger deferred work lives in `docs/roadmap.md`.
Delete an item when it is fixed.

## Stats page: suspicious deletions strip

Found reviewing the strip (`docs/specs/2026-10-23-suspicious-deletions-strip-design.md`).

- **Axis text is tiny at phone width.** Every stats chart is a 680px wide SVG
  scaled down through its viewBox, so at about 375px the tick labels are around
  5px. The bars and the card's text label are fine. This affects every card, not
  only the strip. Fix by giving the charts a minimum width inside a horizontal
  scroll container, or by drawing larger text on narrow screens.
- **No busy timeout when reading the log.** `DeletionLog.with_read_only/2` sets
  none, while the write path waits up to 5 seconds. A stats page load that lands
  while a deletion is being written fails at once and the strip shows "could not
  read". A `PRAGMA busy_timeout` on the read connection would fix it.
- **The whole log is read on every stats mount**, twice per page load (dead and
  connected render). Scrubbed rows are kept forever, so this grows slowly. Filter
  with `WHERE deleted_at >= ?`, which the existing index supports.
- **`render_bar_svg/2` edge cases the page never hits.** An empty history raises
  a `MatchError`. A history of one or two days draws bars off the canvas, because
  Contex widens the date domain to nice tick boundaries. A very small `:width`
  gives negative geometry.
- **A blank band of about 70px** sits between the line chart's x labels and the
  strip's label, from Contex's fixed bottom margin.
- **Log-touching tests clean up only in `setup`**, not in `on_exit`. Every such
  test deletes the file first, so nothing leaks today.

## Suspicious user reaper

Found reviewing the reaper (`docs/specs/2026-10-22-suspicious-user-reaper-design.md`).

- **One error log line per user per sweep when `deletions.db` cannot be
  written.** A summary line per sweep would be quieter.
- **`DeletionLog.source_atom/1` raises on unknown stored text.** Only reachable
  if a newer release adds a source and is then rolled back.
- **Finding users and deleting each are not atomic.** Each user is re-fetched
  just before deleting, which narrows the race to one user's erase but does not
  close it. A user who confirms in that instant could be erased.
- **The reaper runs in dev too.** The first sweep is a minute after boot and
  deletes local unconfirmed users older than 15 days. Set
  `config :speechwave, :suspicious_user_reaper, initial_delay: ..., sweep_interval: ...`
  in `config/dev.exs` to slow or stop it.
- **No test sits exactly on the 15 day boundary.** The 14 and 16 day tests
  bracket it, and the query uses a strict `<`.
- **`accounts_delete_test.exs` defines `now/0` and `days_ago/1` inside a
  `describe`**, which makes them file-wide.

## Data export (Download my data)

Found reviewing the export (`docs/specs/2026-10-23-gdpr-data-export-design.md`).

- **The cooldown is claimed before the zip is sent.** A failed build releases
  it, but if the download fails afterwards (the browser disconnects or the user
  cancels), the user waits 5 minutes with no file. Releasing the claim from a
  `register_before_send` or after `send_download` fails would close it.
- **The export route is a GET with a side effect.** A cross-site link or a
  browser prefetch can use up someone's cooldown. The attacker cannot read the
  zip, so the impact is small. A POST from a form button would fix it.
- **`audience_size` is a lower bound for old sessions.** Reactions recorded
  before audience tracking have no audience ID and are not counted, the same as
  on the dashboard. The schema explains a null but not a partial count.
- **`sign_in_providers` has no explicit order.** Two exports of the same account
  can list providers in a different order. `Accounts.list_user_identities/1`
  needs an `order_by`.
