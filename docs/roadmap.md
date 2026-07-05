# Roadmap

Deferred work identified while working on other projects. Items here are
acknowledged but intentionally not in scope for the work that surfaced them.
Move an item out (with a link to its spec/plan) once it's actively planned.

## Pre-launch Tasks

Work required before the free tier can be publicly launched. Items large enough
to warrant a spec/plan should get one when they're ready to be worked.

### Should haves

#### screenshots for docs site (../docs)

Docs served at https://docs.speechwave.live is live, a Jekyll/just-the-docs
site in the `speechwave-live/docs` repo, auto-deployed to Dreamhost via GitHub
Actions on push to main. See `docs/specs/2026-07-04-docs-site-design.md` if
needed.

Screenshot sources:

- `seed_screenshots.exs` can stage data
- screenshots that were submitted for the Chrome Web Store listing. See `tmp/store_0*.png`.
- screenshots can be taken with rodney (see `rodney --help` for usage)
- Tracy can take manual screenshots as needed

### Nice-to-haves

#### Super-admin panel (own spec/plan needed)

A LiveView behind the existing `is_admin` guard for tracking initial traction
post-launch. Two core views:

1. **User stats** — total user count, confirmed user count, junk user count (no session token, no identity), notification signups
2. **Email consent export** — filter consented users by `source` / date range,
   CSV download; this directly unblocks the "Super admin email export UI"
   item in the Email & Marketing section below

#### Account deletion and consent revocation features for GDPR compliance


#### OG / SEO meta tags

Add `<meta name="description">` and Open Graph / Twitter card tags to public
pages (`/`, `/pricing`) so links share well and search engines have context.

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

