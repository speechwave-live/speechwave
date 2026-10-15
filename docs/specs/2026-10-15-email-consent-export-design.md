# Email consent export (super-admin)

## Why

Until there are enough users to justify an email marketing platform (see
`docs/roadmap.md`, "Email marketing platform integration"), Tracy will send
the occasional update or promotion by hand. He needs a list of users who
consented to marketing email, with enough context in each row to segment it
in a spreadsheet (for example new users vs. older or inactive users) before
pasting or importing addresses into his own mail client.

Consent is stored in `user_consents` (`consent_type: "marketing_email"`).
This spec covers only the manual export. It is the first half of the
roadmap items "Super-admin panel: email consent export" and "Super admin
email export UI".

## What it does

The existing `/admin/stats` page (`SpeechwaveWeb.Admin.StatsLive`) gains an
"Email consent export" section with:

- an optional `source` filter,
- an optional consent date range (`granted_at`, from and to, inclusive),
- a "Download CSV" button.

The section is admin-only because the page already sits in the
`:require_admin` live_session.

### Who is included

Users whose `marketing_email` consent is currently granted
(`granted = true`, `revoked_at` is nil) **and** who have confirmed their
email (`users.confirmed_at` is not nil).

Excluding unconfirmed users is a design call, not a requirement from the
brief. Magic-link signup creates a user row on the first submission of any
email, so unconfirmed rows can hold addresses nobody has verified.

### CSV columns

In this order:

| Column | Source |
|---|---|
| `email` | `users.email` |
| `source` | `user_consents.source` |
| `consented_at` | `user_consents.granted_at` |
| `plan` | `users.plan` |
| `signed_up_at` | `users.inserted_at` |
| `talk_count` | count of the user's talks |
| `session_count` | count of sessions across the user's talks |
| `last_session_at` | max `talk_sessions.started_at`, blank if none |

Dates are ISO 8601 UTC. Users with no talks get `0`, `0`, and a blank
`last_session_at`. Rows are ordered by `consented_at` ascending, then email.

Segmenting (new vs. inactive, by plan, and so on) is done by Tracy in a
spreadsheet. The page deliberately has no plan, signup-date or activity
filters.

## Goals, non-goals, anti-goals

- Goal: one click to a CSV that is safe to open in a spreadsheet.
- Non-goal: platform sync, unsubscribe handling, double opt-in, per-topic
  preferences, sending email from the app.
- Non-goal: the DB indexes listed under "Super-admin stats dashboard
  follow-ups". The export is a bounded admin-only query, not a hot path.
- Anti-goal: leaking the list to a non-admin. The download route must be
  guarded as strongly as the page, not just hidden.
- Anti-goal: a spreadsheet executing user-supplied text as a formula.

## How it gets built

Marked as the author's calls, not decisions Tracy made:

- **Context function.** A new function in the `Speechwave.Admin` area (next
  to `Speechwave.Admin.Stats`) takes `%{source: ..., from: ..., to: ...}`
  and returns the rows. Talk and session counts and the last session date
  come from aggregate subqueries joined to users, so the query stays one
  round trip and does not load talks or sessions into memory.
- **Download is a controller action, not a LiveView event.** A LiveView
  cannot serve a file download by itself. Add a `get` route inside an admin
  scope that pipes through `:browser` and `:require_authenticated_user` plus
  an admin check (reuse the existing `require_admin` logic from
  `SpeechwaveWeb.UserAuth`; add a plug form if only the `on_mount` form
  exists). The filter form in the LiveView is a plain GET form targeting
  that route, so the filters travel as query params.
- **CSV writing.** Build the CSV by hand or with a small helper module with
  its own tests; do not add a dependency unless asked. Quote any field
  containing a comma, quote, CR or LF, and double embedded quotes. Prefix
  any field that begins with `=`, `+`, `-`, `@`, tab or CR with a single
  quote to defuse spreadsheet formula injection. This applies to `email` and
  `source`, which originate from user input.
- **Response.** `text/csv; charset=utf-8`, `content-disposition: attachment`
  with a dated filename such as `marketing-consent-2026-10-15.csv`.
- **Invalid filters.** Unparseable dates are ignored by the form's input
  type in the browser; on the server, treat an unparseable date param as
  "no bound" rather than raising.
- **Source filter UI.** A text input or a select of distinct existing
  `source` values; pick whichever is simpler with the page's current form
  components. Exact match on `source`.

## Tests

- Context: granted vs. revoked vs. never-granted users; unconfirmed
  excluded; `source` filter; date range inclusive on both ends; counts and
  last session date for a user with talks and sessions, and zeros/blank for
  one without; ordering.
- CSV helper: quoting of commas, quotes and newlines; formula-prefix
  neutralization; header row.
- Controller: admin gets 200 and `text/csv`; non-admin and logged-out
  requests are rejected and receive no data.
- LiveView: the export section and its form and button render on
  `/admin/stats`, using element IDs.

## Roadmap upkeep

When this ships, update `docs/roadmap.md`: remove the two items it
completes, and edit the IEx fallback note under "Super admin email export
UI" accordingly. Add a `docs/decisions.md` entry only if the build exposes a
reporting limitation worth recording.
