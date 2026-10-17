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

#### GDPR: download my data (access and portability)

Split out of the account deletion work. GDPR also gives people a right to get
a copy of the personal data held about them (Articles 15 and 20), in a
structured, commonly used, machine-readable format. Today that would be a manual
request to admin@speechwave.live.

A "Download my data" button in Settings could return one file (JSON, or a zip
of CSVs) containing the account row (email, plan, signup date, settings),
talks, sessions, reaction counts per session, consent records and linked
sign-in providers. It must never include secrets (session tokens, the API key)
and should be rate limited. Decide whether the
privacy policy should promise this self-service export once it exists.

#### Uniform `DeletionLog` API and shared test helpers

Also from the maintainability review. `DeletionLog.logged_ids/1` takes a path,
but `record/2`, `scrub/1`, `deleted_ats/0` and `snapshot_to/1` always use the
configured one, so tests swap the global `:deletions_db_path` to build a second
log file. Give every public function an optional `log_path` (default `path()`).
Then add test support helpers: `with_deletion_log_path/2` or
`unwritable_deletion_log/0` (the unwritable-directory `put_env` block is copied
into three test files) and an `sqlite_query(path, sql)` helper for the raw
Exqlite open/prepare/fetch/close boilerplate that appears three times.

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

