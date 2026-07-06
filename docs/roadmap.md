# Roadmap

Deferred work identified while working on other projects. Items here are
acknowledged but intentionally not in scope for the work that surfaced them.
Move an item out (with a link to its spec/plan) once it's actively planned.

## Pre-launch Tasks

Work required before the free tier can be publicly launched. Items large enough
to warrant a spec/plan should get one when they're ready to be worked.

### Must haves

Done.

### Nice-to-haves

#### Super-admin panel: email consent export

The user-stats half of the super-admin panel is done — see
`docs/specs/2026-07-06-super-admin-stats-design.md` and
`docs/decisions.md` (2026-07-06 entry) for the design and its accepted
reporting limitations. Remaining: an email consent export view.

This allows Tracy to export a list of users who have consented to marketing
emails, so he can send them updates and promotions.

- CSV download
— filter consented users by `source` / date range,

This directly unblocks the "Super admin email export UI" item in the Email &
Marketing section below. May be able to share the `/admin/stats` page rather
than needing its own route, given its small UI footprint.

#### Super-admin stats dashboard follow-ups

Deferred from the 2026-07-06 stats dashboard work (see
`docs/decisions.md` for the reporting limitations these are separate from):

- **Add DB indexes** on `users(inserted_at)`, `talks(inserted_at)`,
  `talk_sessions(inserted_at)`, and `user_consents(consent_type, source)`.
  Every metric's history query currently full-scans its base table (no
  supporting index exists), which is cheap at today's table sizes but worth
  fixing before they reach roughly 10^5+ rows. The two `users_tokens`
  min-timestamp scans (confirmation reconstruction) won't benefit from an
  index alone — that would need a dedicated `confirmed_at` column instead.
- **Unify per-metric display metadata.** `Speechwave.Admin.Stats.@metric_order`
  and `SpeechwaveWeb.Admin.StatsLive.@titles` are two hand-synced lists with
  no compile-time link between them (a key present in one but not the other
  crashes at render via `Map.fetch!`). A single metric-definition list
  (key, title, and eventually chart type) would remove that hazard and make
  per-metric chart-type variation easier if ever needed.
- **Chart sizing is tuned for a 30-day window.** `Speechwave.Admin.Chart`'s
  default width/height assume ~30 x-axis points; changing
  `Stats.history_days/0` to a different window (e.g. 90 days) would need the
  chart dimensions revisited too, since nothing currently ties them together.

#### Account deletion and consent revocation features for GDPR compliance


#### SSH/eval magic link helper for production test scripts

See the Manual/Live-Environment Testing section below.

## Email & Marketing

Deferred from `docs/specs/2026-06-16-email-collection-design.md`.

### Email marketing platform integration

Consent is stored in the `user_consents` table (`consent_type: "marketing_email"`,
`source` encodes origin and plan interest e.g. `"login"`, `"pricing_pro"`).
When ready to send marketing emails, pick a platform (Mailchimp, ConvertKit,
Brevo, Buttondown, etc.) and sync consented users via their API.

Features that depend on the platform choice and are out of scope until then:
double opt-in confirmation emails, unsubscribe links in outbound emails, and
granular per-topic subscription preferences.

### Super admin email export UI

A LiveView form (filter by `source` / date range + CSV download) in the
planned super admin section, behind the `is_admin` guard. Blocked on the
super admin section existing. Until then, engineers can query consented users
directly via IEx in the production console:
`Speechwave.Repo.all(Speechwave.Accounts.UserConsent, consent_type: "marketing_email", granted: true)`

## Auth & Accounts

### Clean up unconfirmed "junk" users

Magic-link signup creates a `users` row on the *first* submission of any
email, before the link is ever clicked. Even with throttling on repeated
submissions (see the 2026-06 auth throttle spec in `docs/specs/`), a trickle
of unconfirmed rows is expected by design.

A "junk" user is a `users` row with:
- no `users_tokens` row with `context: "session"` (magic link never clicked), and
- no linked `identities` (no OAuth login either)

These rows are inert (default `:free` plan, no talks/resources), but they
clutter the `users` table, skew future signup/user-count metrics, and each
carries an unused `api_key`.

**Open questions for later:** grace period before a row counts as cleanup-eligible
(needs to tolerate slow email delivery / people who haven't clicked yet —
30 days suggested as a starting point), and how cleanup runs (mix task on a
schedule vs. a scheduled GenServer).

Related: `docs/decisions.md` (2026-05-05 passwordless auth entry, which
deferred rate limiting on magic link sends).

## Manual/Live-Environment Testing

Follow-on manual-test coverage identified while designing
`docs/specs/2026-06-13-dashboard-session-analytics-manual-tests-design.md`
(speaker dashboard + session analytics sections of `docs/manual_tests.md`).

### SSH/eval magic-link-token helper for production runs

`scripts/manual_tests/dashboard.sh` and `session_analytics.sh` are dev-only
because their shared `complete_magic_link_login` helper depends on
`/dev/mailbox`, which doesn't exist in production. Their own logic (talk CRUD,
session analytics) has no environment-specific branching — only the
login/email-delivery step is genuinely production-sensitive.

Production is a `mix release` build with no `mix`/source in the runner image
(confirmed via `Dockerfile`/`fly.toml`), but `flyctl ssh exec` +
`/app/bin/speechwave eval` — the same "remote console" mechanism `fly.toml`'s
`console_command` already uses — runs arbitrary Elixir against compiled
`Speechwave.*` modules with full DB access. This is how
`scripts/manual_tests/seed_sessions.exs` can already seed data in production
(see the dashboard/session-analytics spec).

The same mechanism can generate a **login token** instead of relying on email:
call `Accounts.deliver_login_instructions/2` (or build a token directly via
`UserToken.build_email_token/2`) and print the resulting
`/users/magic_link/:token` URL. A sibling of `complete_magic_link_login` would
SSH-generate this URL via `flyctl ssh exec` and have rodney navigate straight
to it on `https://speechwave.live` — no email delivery, no polling, no
third-party mailbox service. This would unblock production runs of
`dashboard.sh` and `session_analytics.sh`, and any future authenticated-flow
script.

One new cost worth tracking: unlike dev runs (throwaway local DB), a
production run leaves behind a real `manual-test-<timestamp>@example.com`
user — and because it completes login, it gets a `users_tokens` row with
`context: "session"`, so it won't qualify as a "junk user" under the cleanup
rule above. Production runs should delete this user (not just the talk) as
part of cleanup, or it becomes its own clutter source.

**Considered and rejected:** a "secret test-email-domain" allow-listed for a
login *bypass* in production (skipping token generation/verification
entirely). Rejected in favor of the SSH/eval approach above, which uses the
same token-issuance code real users go through and is gated by `flyctl`
access (already restricted to the Fly org) rather than an app-level secret
that would have to live in scripts/CI.

Related: `docs/specs/2026-06-13-dashboard-session-analytics-manual-tests-design.md`.

### Manual test: OAuth connect/disconnect

Connecting/disconnecting Google/Microsoft/GitHub identities from
`UserLive.Settings` requires real provider credentials and driving each
provider's own hosted consent UI — a genuinely different category from the
rest of `docs/manual_tests.md`, not just a sequencing question. Deferred
until there's a concrete need to test this path.

