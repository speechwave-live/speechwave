# Architectural Decisions

## 2026-05-05 — Passwordless authentication (magic links + OAuth)

**Decision:** Replace password-based `phx.gen.auth` with a passwordless system
using email magic links as the primary flow and OAuth SSO (Google, GitHub,
Microsoft via Assent) as a secondary flow.

**Why:** Speakers are occasional users who forget passwords; magic links remove
that friction entirely. Magic link doubles as registration, eliminating the
separate signup form. No passwords means no bcrypt overhead, no password-reset
flow, and nothing for an attacker to steal from the `users` table.

**What changed:**
- Removed `hashed_password` and `confirmed_at` columns from `users`
- Removed `bcrypt_elixir` dependency; added `assent` for OAuth
- Added `user_identities` table — one row per linked OAuth provider account,
  with a unique constraint on `{provider, uid}` to prevent spoofing
- Magic link tokens use the existing `users_tokens` table under a new
  `"magic_link"` context (15-minute TTL, single-use)
- Unified login/signup page at `/users/log-in` — email submission sends a
  magic link; OAuth buttons redirect through Assent; no separate registration
  screen
- `find_or_create_user_from_oauth/2` upserts by email so a user who signs in
  via magic link and later via Google with the same address gets one account
- Dev-only backdoor at `/dev/login` — lists existing users as clickable links
  and accepts any email, bypassing all auth (never compiled in production)

**Trade-offs:** Rate limiting on magic link sends is deferred; the login page
is currently unprotected against enumeration-at-volume. Post-launch concern.

## 2026-07-06 — Super-admin stats dashboard: reconstructed history, not a snapshot table

**Decision:** Compute each of the 11 dashboard metrics (`Speechwave.Admin.Stats`)
as a current aggregate `COUNT` plus a 30-day history reconstructed in Elixir by
subtracting/adjusting for within-window events from that current total, rather
than maintaining a daily snapshot table and a scheduler.

**Why:** A snapshot table + cron job is correct at any scale but adds a new
schema and a scheduler before either is needed for a pre-launch, single-admin
page. The reconstruction approach ships with no new tables and keeps only
recently-changed rows in memory when rebuilding history.

**What changed:**
- New `Speechwave.Admin.Stats` context computing total/confirmed/unconfirmed/
  onboarding/suspicious user counts, pro/enterprise/total notification
  signups, and talks/talks-with-sessions/sessions counts.
- `Speechwave.Admin.Chart` renders each 30-day history as a server-side SVG
  (Contex) — no JS charting dependency.
- Admin gating via `SpeechwaveWeb.UserAuth.on_mount(:require_admin, ...)` and
  a `:require_admin` live_session; new `/admin/stats` route.

**Trade-offs / known limitations (accepted, not bugs — see code comments in
`lib/speechwave/admin/stats.ex` for the exact mechanics of each):**

- **"Confirmed" is not strictly monotonic.** A user counts as confirmed if
  they currently have a session-context token or a linked OAuth identity.
  Logging out deletes the session token (`Accounts.delete_user_session_token/1`),
  so a magic-link-only user (no linked identity) who logs out of their only
  session drops out of the confirmed count — it can decrease, and a returning
  user's reconstructed confirmation date can drift forward to their next
  login. The history-reconstruction technique above assumes monotonic or
  single-event state transitions; this is the one metric where that
  assumption doesn't fully hold. Accepted because this dashboard is a
  traction gauge, not an audit trail, and the effect is small at current
  scale.
- **Notification-consent source reattribution.** `Accounts.grant_consent/3`
  updates only the `source` field (not `granted_at`) when an already-granted
  user re-triggers consent via a different source (e.g. clicks "Notify me"
  on the pro tier, then later on the enterprise tier). That user's row then
  moves entirely into the new source's history, backdated to the original
  `granted_at` — misattributing which plan they were interested in during
  the earlier period. `total_signups` (pro + enterprise combined) stays
  accurate throughout; only the pro/enterprise split is affected for users
  who switch. Accepted: this dashboard tracks new notification-interest
  signups, not a full source-change audit log.
- **Notification-consent repeated-toggle undercount.** `grant_consent/3`/
  `revoke_consent/2` overwrite `granted_at`/`revoked_at` in place rather than
  keeping full history, so a user who grants and revokes more than once
  within the 30-day window has earlier cycles overwritten — repeated
  toggling can undercount very old activity.
- **The onboarding/suspicious split is not time-bounded.** Unlike every other
  metric, distinguishing onboarding from suspicious unconfirmed users
  requires every *currently* unconfirmed user's signup date (their age
  bucket can change with no DB write, purely from time passing), so this one
  query scans the full `users` table and materializes the entire
  unconfirmed population into memory. That population grows monotonically
  until the roadmap's "clean up unconfirmed junk users" item is built, so
  this is the one metric whose cost scales with cumulative table history
  rather than recent activity — acceptable at launch scale, worth revisiting
  if a bot-signup flood or long-lived unconfirmed backlog grows it large.
- **Every metric's SQL query is a full base-table scan, not an indexed range
  seek.** No index exists yet on the `inserted_at`/`source`/`context`
  columns these queries filter on, so the "bounded" guarantee above applies
  to the Elixir-side result set, not the underlying SQL scan cost. Cheap at
  today's table sizes (sub-millisecond); see the roadmap for the indexing
  follow-up before this matters at scale.
