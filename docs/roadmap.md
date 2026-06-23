# Roadmap

Deferred work identified while working on other projects. Items here are
acknowledged but intentionally not in scope for the work that surfaced them.
Move an item out (with a link to its spec/plan) once it's actively planned.

## Pre-launch Tasks

Work required before the free tier can be publicly launched. Items large enough
to warrant a spec/plan should get one when they're ready to be worked.

### Must-haves

#### Chrome extension: Web Store submission

API key auth, service worker architecture, and production readiness are
complete. See `docs/specs/2026-06-18-extension-service-worker-design.md` and
`docs/specs/2026-06-17-chrome-extension-production-submission-design.md`.

**Done:**
- API key setup screen in popup (save/change key flow)
- Service worker manages Phoenix WebSocket (works from any tab)
- Connection, session, slide tracking, fireworks all functional
- Stale-connection race condition fixed (auto-reconnect safe)
- Automated test suite (64 tests across popup, content, background)
- Consistent branding (mic icon across app and extension)
- Final manual tests: slide tracking, fireworks, multi-tab Slides, error paths
- Create Chrome Web Store developer account ($5 one-time fee)

**Remaining for submission:**
- Prepare store listing screenshots and description
- Package extension zip
- Submit for review (can take days to weeks)

**Soft launch option:** if Web Store review is delayed, the web app is fully
launchable on its own. The pricing/home pages could note "Chrome extension
coming soon" and direct early users to the waitlist email consent flow.

#### Terms of Service and Privacy Policy review

Both pages exist (`/terms`, `/privacy`) but content has only been lightly
updated from template text. Requires a final review and update before launch.

#### Code cleanup for public repositories

Orphaned templates deleted and 404/500 error pages styled. Still needs:

- Review `README.md` — still lists PostgreSQL as a prerequisite (uses SQLite),
  and may have other stale content from the initial Phoenix generator
- Error pages use the 🎤 emoji instead of the SVG logo (static HTML can't use
  `~p` paths — needs an absolute URL or inline SVG)
- General content review of docs and comments for stale references

### Nice-to-haves

#### Super-admin panel (own spec/plan needed)

A LiveView behind the existing `is_admin` guard for tracking initial traction
post-launch. Two core views:

1. **User stats** — confirmed user count, junk user count (no session token,
   no identity), total signups
2. **Email consent export** — filter consented users by `source` / date range,
   CSV download; this directly unblocks the "Super admin email export UI"
   item in the Email & Marketing section below

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

## Chrome Extension Troubleshooting / FAQ

Common issues encountered during development and testing. This section should
eventually become a user-facing help page or be included in the Web Store
listing description.

### No emojis appearing on Google Slides

**After installing, updating, or reloading the extension**, you must refresh
any Google Slides tabs that were already open. Chrome does not automatically
reinject content scripts into existing tabs — the overlay and message listener
only activate after a page load.

### "Invalid API key" error after regenerating key

After regenerating your API key in Account Settings:
1. Click "Change API key" in the extension popup
2. Copy the new key from the settings page (use the copy button)
3. Paste and save in the extension
4. Click Connect

The extension's service worker may briefly attempt to reconnect with the old
key from storage. This auto-reconnect error is suppressed and should not
appear in the popup. If you see a flash of "Invalid API key," it resolves
once the new key is saved and Connect is clicked.

### Extension shows "Connected" but no emojis on Slides

- Verify a Google Slides presentation tab is open and was loaded **after**
  the extension was installed
- Check that the emoji overlay hasn't been hidden behind the Slides UI —
  it's positioned fixed at the bottom-right of the viewport
- In Slides presentation mode (fullscreen), the overlay automatically
  re-parents into the fullscreen element

### Extension not connecting

- Verify the slug matches a talk you own (check the Dashboard)
- Verify your API key matches the one shown in Account Settings
- If you see "Talk is at capacity," the plan's connection limit was reached
- If you see "Please confirm your email," complete email verification first

### Duplicate emojis on Slides

If each reaction produces two emojis on the same Slides tab, the most likely
cause is an **old content script still running** from a previous version of
the extension. This happens when the extension code is updated (during
development or via Chrome auto-update) but the Slides tab was not refreshed.
Refresh the Slides tab to resolve.

