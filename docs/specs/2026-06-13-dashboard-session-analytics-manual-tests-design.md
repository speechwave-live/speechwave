# Speaker Dashboard & Session Analytics Manual Tests Design

**Date:** 2026-06-13
**Status:** Approved

## Overview

`docs/specs/2026-06-12-manual-integration-tests-design.md` established
`docs/manual_tests.md` and `scripts/manual_tests/` with one script
(`auth_throttle.sh`), and explicitly called for factoring shared pieces into
`scripts/manual_tests/lib.sh` once a second script arrived.

This spec adds the next two sections — covering the core "speaker" flows: the
dashboard (login → talk CRUD) and session analytics (viewing/comparing
sessions, renaming/deleting them). Together these are the first scripts to
exercise an **authenticated** flow, so the main new piece of shared
infrastructure is a magic-link login helper.

**Out of scope** (tracked in `docs/roadmap.md`, see "Deferred" below):
- Running `dashboard.sh`/`session_analytics.sh` against production — their
  rodney-driven UI steps need a logged-in browser session, which is blocked
  on a login helper (see "Deferred" below). `seed_sessions.exs` itself can
  already run against production via SSH/eval — see its section below.
- OAuth connect/disconnect
- Account settings (email change, API key regen)
- The attendee reaction flow (`/t/:slug`)

---

## `scripts/manual_tests/lib.sh` (new)

### Extracted from `auth_throttle.sh` (no behavior change)

- `is_local()` — checks `$BASE_URL` for `localhost`/`127.0.0.1`
- `--base-url` argument-parsing scaffold
- `rodney start` / `rodney stop` lifecycle (the `trap ... EXIT` setup)

`auth_throttle.sh` is updated to `source lib.sh` for these three pieces.
Its `email`/`ip` mode logic and `submit_magic_link` helper stay where they
are — they're specific to that script.

### New: `complete_magic_link_login`

```sh
complete_magic_link_login "$BASE_URL" "$EMAIL"
```

Dev-only (calls `is_local`; exits with an error if the base URL isn't
local — `/dev/mailbox` and the magic-link flow it drives don't exist in
production). Steps:

1. Clear `/dev/mailbox` if non-empty (reusing the existing clear-if-nonempty
   logic from `auth_throttle.sh`'s email mode).
2. Submit the magic-link form for `$EMAIL` (reusing `submit_magic_link`),
   asserting `#magic-link-sent`.
3. Open `/dev/mailbox`, open the (single) resulting message.
4. Extract the `/users/magic_link/:token` URL from the message body. The
   exact selector/approach is confirmed against the running dev server during
   implementation, the same way `auth_throttle.sh`'s plan verified
   `/dev/mailbox` selectors (`#email-details__to`, `#email-details__subject`,
   etc.).
5. Navigate to the extracted URL. This authenticates the session, but
   `UserAuth.signed_in_path/1` falls back to `/` (not `/dashboard`) for this
   redirect — confirmed against the running dev server.
6. Explicitly open `$BASE_URL/dashboard` and assert `#talk-list` is present,
   confirming the session is authenticated.

This is the foundational helper every authenticated script (this spec's two,
and future ones per the roadmap) builds on.

---

## `scripts/manual_tests/dashboard.sh` (new, dev-only)

Usage: `scripts/manual_tests/dashboard.sh [--base-url URL]` (default
`http://localhost:4000`; errors if `--base-url` isn't local, per
`complete_magic_link_login`).

One continuous PASS/FAIL run as a fresh free-tier user
(`manual-test-<timestamp>@example.com` — a new email each run, so plan-usage
numbers below are deterministic for a brand-new account):

1. **Log in** — `complete_magic_link_login`, which lands on `/dashboard`
   with `#talk-list` present (see its corrected steps above).
2. **Plan-usage check** — assert `#sessions-used` is `0`, `#session-limit` is
   `10`, `#participant-limit` is `50` (confirmed against
   `Speechwave.Plans.limit/2` for `:free`, the default plan for new users).
3. **Create a talk** — title `manual-test-<timestamp>`, submit `#talk-form`.
   Assert:
   - `#created-talk` success message appears
   - an entry for the talk appears in `#talk-list`
   - `#selected-talk-qr` panel renders, containing `#talk-link` (matching
     `<base_url>/t/<slug>`), a QR code `<img>`, and `#no-sessions` in the
     sessions panel
4. **Copy link** — click `#copy-talk-link`. Assert the icon classes toggle:
   `.copy-icon-idle` gains `hidden`, `.copy-icon-copied` loses `hidden`.
5. **Delete the talk** — click `#delete-talk-<id>` (handles the
   `data-confirm` dialog; exact rodney mechanism confirmed during
   implementation). Assert the entry is gone from `#talk-list` and
   `#selected-talk-qr` no longer renders.
6. **Sign out** — click the "Sign out" link (`/users/log-out`, `method="delete"`).
   Assert that subsequently opening `/dashboard` redirects to `/users/log-in`.

---

## `scripts/manual_tests/seed_sessions.exs` (new)

Invoked via `mix run scripts/manual_tests/seed_sessions.exs <email>` from the
project root for dev runs.

Using `Speechwave.{Accounts, Talks, Reactions}`:

1. `Accounts.register_or_get_user_by_email(email)` → build a
   `Speechwave.Accounts.Scope.for_user(user)`.
2. `title = "manual-test-<timestamp>"`, `slug = Talks.generate_slug(title)` (same
   pattern `DashboardLive` uses), then
   `Talks.create_talk(scope, %{title: title, slug: slug})`.
3. **Session 1**: `Talks.start_session(talk)` → record reactions via
   `Reactions.create_reaction/3`: 🔥 and ❤️ on slide 1, 🎉 on slide 2 (3
   total) → `Talks.stop_session/1`.
4. **Session 2**: `Talks.start_session(talk)` (auto-labeled "Session 2" since
   session 1 is now stopped) → record 🔥 on slide 1, 👏 on slide 2 (2 total)
   → `Talks.stop_session/1`.
5. Print results as `KEY=value` lines on stdout for the calling script to
   parse: `email=...`, `talk_id=...`, `session1_id=...`, `session2_id=...`.

### Also runnable against production

The production image is a `mix release` build with no `mix`/source in the
runner stage (confirmed via `Dockerfile`/`fly.toml`), so `mix run` won't work
there — but this script only calls compiled `Speechwave.{Accounts, Talks,
Reactions}` functions, all present in the release. It can run against the
production DB via the release's "remote console" mechanism (the same one
`fly.toml`'s `console_command = '/app/bin/speechwave remote'` uses):

```sh
flyctl ssh sftp shell --app speechwave    # put seed_sessions.exs to /tmp/
flyctl ssh exec --app speechwave --command \
  "/app/bin/speechwave eval 'Code.eval_file(\"/tmp/seed_sessions.exs\")'"
```

No script in this spec runs against production, so this isn't part of its
scope — it's noted here as the foundation for the SSH/eval login-token helper
tracked in `docs/roadmap.md`. The exact mechanism for passing `<email>` to
`Code.eval_file` (e.g. an env var read via `System.get_env/1`, since
`System.argv/0` won't carry it the way `mix run` does) is confirmed during
implementation if/when that roadmap item is picked up.

---

## `scripts/manual_tests/session_analytics.sh` (new, dev-only)

Usage: `scripts/manual_tests/session_analytics.sh [--base-url URL]` (same
local-only constraint as `dashboard.sh`).

1. Run `seed_sessions.exs` with a fresh `manual-test-<timestamp>@example.com`,
   capture `email`, `talk_id`, `session1_id`, `session2_id`.
2. `complete_magic_link_login` as that email → `/dashboard`.
3. Open `/sessions/<session1_id>`. Assert `#total-reactions` is `3`, and
   `#slide-row-1` / `#slide-row-2` show the seeded emoji/counts (slide 1: 🔥
   and ❤️ at 1 each; slide 2: 🎉 at 1).
4. Open `/sessions/<session1_id>/compare/<session2_id>`. Assert
   `#compare-section` renders, showing both session labels ("Session 1" and
   "Session 2").
5. Return to `/dashboard`, select the seeded talk in `#talk-list`. Assert
   `#sessions-panel` lists both `#session-<session1_id>` and
   `#session-<session2_id>`.
6. **Rename session 1** — click `#rename-session-<session1_id>`, fill in the
   `#rename-form-<session1_id>` label input, submit. Assert
   `#session-label-<session1_id>` shows the new label.
7. **Delete session 2** — click `#delete-session-<session2_id>` (handles
   `data-confirm`). Assert `#session-<session2_id>` no longer exists.
8. **Delete the talk** — click `#delete-talk-<talk_id>` (cleanup; cascades to
   the remaining session and all reactions).
9. **Sign out**.

---

## `docs/manual_tests.md` updates

Two new `##` sections, following the existing format (one-line description,
script invocation, dev-only note, PASS/FAIL meaning per step):

- **"Speaker dashboard"** — describes `dashboard.sh` per the steps above.
- **"Session analytics"** — describes `session_analytics.sh` and
  `seed_sessions.exs` per the steps above.

Both sections note they're dev-only and link to the roadmap entry covering a
future SSH/eval login-token helper that would unblock production runs.

---

## Deferred (tracked in `docs/roadmap.md`)

A new "Manual/Live-Environment Testing" section is added to
`docs/roadmap.md` with four items:

1. **SSH/eval magic-link-token helper for production** — would let
   `complete_magic_link_login` (or a sibling) run against production by
   generating a valid magic-link token via the same SSH/eval mechanism
   `seed_sessions.exs` can use (see above) and printing its URL for rodney to
   navigate to directly — no email delivery involved. Also records why a
   "secret test-email-domain" *bypass* was considered and rejected in favor
   of this approach.
2. **Manual test: Attendee reaction flow** (`/t/:slug`) — independent of
   login, can be designed next.
3. **Manual test: Account settings** (email change, API key regen) — natural
   follow-on once `complete_magic_link_login` exists.
4. **Manual test: OAuth connect/disconnect** — needs real provider
   credentials and driving Google/Microsoft/GitHub's own consent UI; a
   genuinely different category, not just sequencing.

---

## Files touched

- `scripts/manual_tests/lib.sh` — new
- `scripts/manual_tests/auth_throttle.sh` — refactored to source `lib.sh`
- `scripts/manual_tests/dashboard.sh` — new
- `scripts/manual_tests/seed_sessions.exs` — new
- `scripts/manual_tests/session_analytics.sh` — new
- `docs/manual_tests.md` — two new sections
- `docs/roadmap.md` — new "Manual/Live-Environment Testing" section
