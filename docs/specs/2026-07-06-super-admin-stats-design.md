# Super-admin stats dashboard

## Problem

Speechwave has no way to observe post-launch traction: signup volume, how many
signups actually confirm, how much of the `users` table is unconfirmed
clutter, notification-list interest, or how much talk/session activity is
happening. `docs/roadmap.md` calls for a super-admin panel to surface this,
gated behind the existing `is_admin` field on `User`.

This spec covers the **stats dashboard only**. Email consent CSV export
(also on the roadmap) is deferred — its UI footprint is small enough that it
may later be added to this same page rather than needing its own route, but
that's a follow-on decision once this ships.

## Current state

- `User.is_admin` (`lib/speechwave/accounts/user.ex`) is a boolean field with
  no authorization mechanism attached to it anywhere. There is no admin
  `on_mount`, no admin plug, no admin-guarded route. This spec adds that
  mechanism as part of building the dashboard — there is no existing pattern
  to reuse.
- `User.plan` is `Ecto.Enum, values: [:free, :pro, :org]`. The roadmap's
  "enterprise" language refers to the `:org` value; there is no literal
  `:enterprise` atom.
- There is no `confirmed_at` field on `User`. Confirmation is inferred from
  related data (see Definitions below).
- The app uses **SQLite** (not Postgres) via `ecto_sqlite3`. Query strategies
  that assume Postgres-only features (e.g. `generate_series`) are not
  available.
- No charting library or JS charting dependency exists in the app today.
- No admin-user test fixture exists in `test/support/fixtures/accounts_fixtures.ex`.

## Definitions

These replace the roadmap's original "confirmed / unconfirmed / junk"
wording, which was ambiguous (as originally worded, "unconfirmed" and "junk"
would always be numerically identical). Categories:

- **Confirmed user**: has a `users_tokens` row with `context: "session"`, OR
  has a linked `user_identities` row (OAuth). Confirmation is monotonic — a
  user does not lose confirmed status once gained.
- **Unconfirmed user**: `total users - confirmed users`.
- **Onboarding user**: unconfirmed, account age < 3 days (configurable
  threshold, see below).
- **Suspicious user**: unconfirmed, account age >= 3 days. Replaces the
  roadmap's "junk" terminology.
- **Inactive user**: confirmed, but no activity (new talks, sessions,
  reactions) for more than N months. **Out of scope for this spec** — no
  query, no chart. Defined here only so the term is reserved for later.

The onboarding/suspicious boundary (3 days) and the inactive threshold
(N months, unused for now) are module attributes on `Speechwave.Admin.Stats`,
not hardcoded literals, so they're easy to tune later.

## Scope

11 metrics, each shown as a stat card with its current value and a 30-day
trend chart:

1. Confirmed users
2. Unconfirmed users
3. Onboarding users
4. Suspicious users
5. Total users (confirmed + unconfirmed)
6. Pro notification signups
7. Enterprise (`:org`) notification signups
8. Total notification signups (pro + enterprise)
9. Talks count
10. Talks-with-sessions count
11. Sessions count

Explicitly out of scope: inactive-user tracking, error/exception metrics
(no existing error-logging table to query, and "errors" wasn't well-defined
in the roadmap's original ask), email consent CSV export, and any UI for
granting/revoking `is_admin` (see Authorization below).

## Architecture

### Authorization

- Add `SpeechwaveWeb.UserAuth.on_mount({:require_admin, ...})` (or a
  similarly named clause alongside the existing `require_sudo_mode` /
  `require_authenticated` clauses) that checks
  `socket.assigns.current_scope.user.is_admin` and halts with a redirect +
  flash error if false.
- Add a new `live_session :require_admin` block in the router (live_session
  names can't repeat, so this can't reuse `:require_authenticated_user`),
  chaining `on_mount: [{UserAuth, :require_authenticated}, {UserAuth, :require_admin}]`.
- Route: `scope "/admin", SpeechwaveWeb.Admin do live "/stats", StatsLive, :index end`,
  resolving to `SpeechwaveWeb.Admin.StatsLive`.
- **Granting `is_admin` stays out of scope.** The existing
  `Speechwave.Release` mix-release task (used for prod bootstrapping) remains
  the only mechanism. No in-app admin-management UI is built here.
- A nav link reading "Admin" appears in the main app layout, shown only when
  `@current_scope.user.is_admin`.

### Data layer: current totals + bounded recent-window deltas

The dashboard must answer "what was this count on each of the last 30 days,"
not "what is the full history of this table." Two naive approaches were
rejected:

- **Daily snapshot table + scheduled job**: correct at any scale, but adds a
  new schema and a scheduler before either is needed. Rejected as premature
  for a pre-launch admin page.
- **Pull every row's timestamp and bucket in Elixir**: works, but pulls
  unbounded historical data (e.g. every user ever) to answer a
  30-day-scoped question — wasteful as the tables grow.

Instead, each metric computes:

1. **Current value** — one cheap aggregate query (`COUNT`, scoped `COUNT`,
   etc.) reflecting right now.
2. **30-day history** — one query scoped to
   `WHERE <relevant timestamp> >= 30 days ago` (recent signups, recent
   confirmations, recent talks/sessions/consents), grouped by day. This set
   is naturally small and bounded by elapsed time, not by table size.
3. Each historical day's count is reconstructed by subtracting later events
   from the current total: `count(day X) = current_total - count(events after day X)`.
   This is valid because confirmation, signups, and consents are monotonic —
   nothing outside the 30-day window can change the last 30 days' story.

**Exception:** onboarding vs. suspicious needs each *currently-unconfirmed*
user's `inserted_at` (to bucket by account age as of each historical day),
not just a time-bounded slice of recent events — a user can flip from
onboarding to suspicious with no DB write at all, purely from time passing.
This query is still naturally bounded: it only touches the currently-unconfirmed
set (the "trickle" `docs/roadmap.md`'s cleanup item already describes), never
the full `users` table.

### Metrics table

| Metric | Current value | History basis |
|---|---|---|
| Confirmed | `COUNT` users with session token or identity | recent confirmations (min token/identity `inserted_at` >= 30d ago) |
| Unconfirmed | `total - confirmed` | derived from total & confirmed history |
| Onboarding | unconfirmed, age < 3 days | currently-unconfirmed users' `inserted_at` |
| Suspicious | unconfirmed, age >= 3 days | currently-unconfirmed users' `inserted_at` |
| Total users | `COUNT` users | recent signups (`inserted_at` >= 30d ago) |
| Pro signups | `COUNT` `user_consents` where `consent_type: "marketing_email"`, `source: "pricing_pro"`, `granted: true` | recent `granted_at`/`revoked_at` >= 30d ago |
| Enterprise signups | same, `source: "pricing_enterprise"` (`pricing_live.ex` passes `phx-value-plan="enterprise"`, not `"org"`, for this button) | same pattern |
| Total signups | pro + enterprise | derived |
| Talks | `COUNT` talks | recent talks (`inserted_at` >= 30d ago) |
| Talks with sessions | `COUNT DISTINCT talk_id` in `talk_sessions` | recent sessions (`inserted_at` >= 30d ago), joined to talk creation date |
| Sessions | `COUNT` talk_sessions | recent sessions (`inserted_at` >= 30d ago) |

All queries live in a new `Speechwave.Admin.Stats` module, kept separate from
`Accounts`/`Talks` so those contexts don't accumulate admin-reporting logic
unrelated to their core responsibilities. Each metric exposes a `current/0`
and a `history/0` (returning a list of `{Date.t(), non_neg_integer()}` for
the last 30 days).

### Rendering

[Contex](https://hex.pm/packages/contex) (new mix dep) renders each trend as
an SVG server-side inside the LiveView. No JS hook, no vendored chart JS —
consistent with the project's SSR-first LiveView style and its constraint
against vendoring external script/link tags into templates.

### UI

`SpeechwaveWeb.Admin.StatsLive` — a single page, a grid of stat cards (one
per metric above). A shared `admin_stat_card` function component (title,
current value, chart data) keeps card markup consistent. Wrapped in
`<Layouts.app flash={@flash} current_scope={@current_scope}>` per the
project's layout convention.

## Testing

- `Speechwave.Admin.StatsTest` — exercises each query function against
  fixtures with explicit, controlled `inserted_at`/`granted_at` timestamps
  (via direct `Repo.insert` with timestamps set, since default fixtures use
  "now") to verify current values and 30-day bucketing, especially the
  onboarding/suspicious 3-day boundary.
- `SpeechwaveWeb.Admin.StatsLiveTest` — logged-out and logged-in-non-admin
  users are redirected away from `/admin/stats`; an admin user sees all 11
  stat cards (asserted via DOM ids, e.g. `#stat-confirmed-users`).
- New `admin_user_fixture/1` in `test/support/fixtures/accounts_fixtures.ex`.

## Out of scope (deferred)

- Email consent CSV export (roadmap item; may later share this page).
- Inactive-user tracking and charting.
- Error/exception metrics.
- Any in-app UI for granting/revoking `is_admin`.
- Account deletion / GDPR consent revocation (separate roadmap item).
