# Roadmap

Deferred work identified while working on other projects. Items here are
acknowledged but intentionally not in scope for the work that surfaced them.
Move an item out (with a link to its spec/plan) once it's actively planned.

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

### Real-mailbox login helper for production runs

`scripts/manual_tests/dashboard.sh` and `session_analytics.sh` are dev-only
because their shared `complete_magic_link_login` helper depends on
`/dev/mailbox`, which doesn't exist in production. Their own logic (talk CRUD,
session analytics) has no environment-specific branching — only the
login/email-delivery step is genuinely production-sensitive.

A **real-mailbox login helper** (e.g. Mailosaur-style disposable inboxes, or
the Gmail API against a real test account) would let a sibling of
`complete_magic_link_login` run in production: submit the magic-link form,
poll the real inbox for the delivered email, extract the
`/users/magic_link/:token` link, and continue. This would unblock production
runs of both scripts above, and any future authenticated-flow script.

**Considered and rejected:** a "secret test-email-domain" allow-listed for a
login bypass in production. Rejected because (1) it's a standing auth bypass
whose secret would have to live in scripts/CI secrets — a larger, persistent
exposure than rotating real test-account credentials, and (2) every account
created under that domain becomes a "junk user" (see "Clean up unconfirmed
junk users" above) that future super-admin analytics would have to filter
out indefinitely, turning a one-off testing concern into a routine,
permanent analytics carve-out.

Related: `docs/specs/2026-06-13-dashboard-session-analytics-manual-tests-design.md`.

### Manual test: attendee reaction flow (`/t/:slug`)

The attendee-facing reaction page (`TalkLive`, `/t/:slug`) has no manual-test
coverage yet. It's independent of login — anonymous attendees scan a QR code
and tap emoji reactions — so it can be designed and scripted without
depending on `complete_magic_link_login`.

Note `TalkLive.handle_event("react", ...)` only persists a `Reaction` if
`Talks.get_active_session/1` is non-nil, so this test needs an active
session — e.g. via `scripts/manual_tests/seed_sessions.exs` without calling
`stop_session`, or the channel-driven `start_session` flow.

### Manual test: account settings (email change, API key regen)

`UserLive.Settings` (email change, API key regeneration, OAuth identity
connect/disconnect) has no manual-test coverage. The email-change and
API-key-regen pieces are natural next steps once `complete_magic_link_login`
exists (see the dashboard/session-analytics spec above), since they just need
an authenticated session plus — for email change — a second pass through the
magic-link/email flow to confirm the new address.

### Manual test: OAuth connect/disconnect

Connecting/disconnecting Google/Microsoft/GitHub identities from
`UserLive.Settings` requires real provider credentials and driving each
provider's own hosted consent UI — a genuinely different category from the
rest of `docs/manual_tests.md`, not just a sequencing question. Deferred
until there's a concrete need to test this path.
