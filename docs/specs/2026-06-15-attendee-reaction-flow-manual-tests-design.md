# Attendee Reaction Flow Manual Tests Design

**Date:** 2026-06-15
**Status:** Approved

## Overview

`docs/specs/2026-06-13-dashboard-session-analytics-manual-tests-design.md` left
"Manual test: attendee reaction flow (`/t/:slug`)" as a roadmap item
(`docs/roadmap.md`, "Manual/Live-Environment Testing"). This spec actively
plans that item: a new script exercises the anonymous attendee-facing
reaction page (`SpeechwaveWeb.TalkLive`, `/t/:slug`), covering:

- the real-time floating-emoji feedback (`#emoji-stream` /
  `.floating-emoji`, driven by a PubSub broadcast + the `EmojiStream` JS hook)
- the rate-limit cooldown UI (`#emoji-buttons` `cooling-down` class,
  `.cooldown-label`, disabled buttons — `Speechwave.RateLimiter`'s 3s window)
- **cross-device delivery** — a reaction tapped on one browser tab is
  broadcast to *every* tab subscribed to `reactions:#{slug}`, not just the
  tapping tab
- reaction **persistence** to an active `TalkSession`
  (`Talks.get_active_session/1` must be non-nil — `TalkLive.handle_event("react", ...)`
  only inserts a `Reaction` when this holds)

This is the first manual-test script to require **two simultaneous rodney
tabs**. No production code or template changes are needed — all required
selectors already exist (`phx-value-emoji`, `.floating-emoji`,
`.cooldown-label`, `cooling-down`, `#total-reactions`, `#slide-row-0`,
`#delete-talk-<id>`).

**Dev-only** — same constraint as `dashboard.sh`/`session_analytics.sh`: the
persistence-verification step uses `complete_magic_link_login`, which depends
on `/dev/mailbox`.

### Out of scope (considered and rejected / deferred elsewhere)

- **Channel-driven `start_session`** (via `ReactionChannel`, API-key-authenticated
  WebSocket join) as the way to get an active session. Rejected in favor of a
  seed script calling `Talks.start_session/1` directly — the same approach
  `seed_sessions.exs` already uses, far simpler to script than joining a
  Phoenix Channel with an API key from bash/rodney.
- **Slide-stamped reactions** (`current_slide` tracking via the presenter's
  `slide_changed` broadcast). `current_slide` stays `0` for this whole flow,
  so both reactions land under `#slide-row-0` ("General"). Slide-stamping
  itself is already covered by `mix test` (`talk_live_test.exs`,
  "slide-stamped reaction persistence").
- **Production runs.** Tracked under the existing "SSH/eval magic-link-token
  helper for production runs" roadmap item, which already covers
  `dashboard.sh`/`session_analytics.sh`'s same constraint.

---

## `scripts/manual_tests/seed_active_session.exs` (new)

Invoked via `mix run scripts/manual_tests/seed_active_session.exs <email>`
from the project root, mirroring `seed_sessions.exs`'s structure but simpler:
one talk, one **active** (unstopped) session, **no pre-seeded reactions** —
the reactions in this flow come from the live UI taps.

Using `Speechwave.{Accounts, Talks}`:

1. `Accounts.register_or_get_user_by_email(email)` → build a
   `Speechwave.Accounts.Scope.for_user(user)`.
2. `title = "manual-test-<timestamp>"`, `slug = Talks.generate_slug(title)`,
   then `Talks.create_talk(scope, %{title: title, slug: slug})`.
3. `Talks.start_session(talk)` — **do not** call `stop_session`, so
   `Talks.get_active_session/1` returns this session for the rest of the run.
4. Print results as `KEY=value` lines on stdout for the calling script to
   parse: `email=...`, `talk_id=...`, `talk_slug=...`, `session_id=...`.

---

## `scripts/manual_tests/reaction_flow.sh` (new, dev-only)

Usage: `scripts/manual_tests/reaction_flow.sh [--base-url URL]` (default
`http://localhost:4000`; errors if `--base-url` isn't local, per
`complete_magic_link_login` — same guard as `dashboard.sh`).

One continuous PASS/FAIL run as a fresh free-tier user
(`manual-test-<timestamp>@example.com`):

1. **Seed** — run `seed_active_session.exs`, capturing `email`, `talk_id`,
   `talk_slug`, `session_id`.
2. **Open two anonymous tabs on `/t/<talk_slug>`** — "Device A" (tab 0, will
   tap reactions) and "Device B" (tab 1, observer that never taps),
   simulating two attendees viewing the same talk. Assert `#emoji-buttons` is
   present on both tabs.
3. **First tap (Device A)** — on tab 0, click the ❤️ button
   (`[phx-value-emoji="❤️"]`). Assert:
   - a `.floating-emoji` element with text "❤️" appears (within its 2.5s
     animation window) — confirms the broadcast + `EmojiStream` hook
     round-trip back to the tapping tab
   - `#emoji-buttons` gains `cooling-down`, its buttons become `disabled`,
     and `.cooldown-label` shows "Cooling down…"
4. **Cross-device check #1** — switch to tab 1 (Device B). Assert:
   - a `.floating-emoji` element with text "❤️" appears on tab 1 too —
     confirms the PubSub broadcast reached a *second* client in real time,
     even though Device B never tapped
   - Device B's `#emoji-buttons` is **not** in cooldown (`.cooldown-label`
     still "Tap to react", buttons enabled) — confirms the rate limiter is
     per-attendee (keyed by LiveView socket id), not global
5. **Wait for cooldown** — switch back to tab 0, `rodney sleep` ~4s (cooldown
   is 3s). Assert `#emoji-buttons` returns to idle: `cooling-down` gone,
   buttons enabled, `.cooldown-label` back to "Tap to react".
6. **Second tap (Device A)** — click the 😂 button
   (`[phx-value-emoji="😂"]`) on tab 0. Assert `.floating-emoji` with text
   "😂" appears on tab 0.
7. **Cross-device check #2** — switch to tab 1. Assert `.floating-emoji` with
   text "😂" appears there too.
8. **Close tab 1** (Device B) — `rodney closepage`.
9. **Verify persistence** — on tab 0, `complete_magic_link_login` as
   `$email` → `/dashboard`. Open `/sessions/<session_id>`. Assert
   `#total-reactions` is `2`, and `#slide-row-0` ("General") shows both ❤️
   and 😂 at `1` each — confirming both taps persisted to the active session
   started by `seed_active_session.exs`.
10. **Delete the talk** — back on `/dashboard`,
    `confirm_and_click "#delete-talk-<talk_id>"` (cascades to the session and
    its reactions).
11. **Sign out**.

### Confirmed during implementation

- Exact rodney mechanics for asserting `disabled` (`rodney attr <selector>
  disabled`) and the `cooling-down` class
  (`rodney assert "document.querySelector('#emoji-buttons').classList.contains('cooling-down')"`
  or similar).
- Multi-tab mechanics: whether `rodney newpage <url>` auto-focuses the new
  tab, and the exact `rodney page <index>` / `rodney pages` sequence for
  switching between Device A and Device B.
- Timing margin between a click and checking `.floating-emoji` (must be well
  under its 2.5s `floatUp` animation, but after the `push_event` round-trip
  completes) — likely a short `rodney sleep` rather than `rodney waitstable`,
  since `waitstable` could wait past the animation's removal.

---

## `docs/manual_tests.md` updates

New `## Attendee reaction flow` section, following the existing format (one-line
description, script invocations, dev-only note, PASS/FAIL meaning per step),
covering `seed_active_session.exs` and `reaction_flow.sh` per the steps above.

### Quick start update

The "Quick start" section's description of `run_all_dev.sh` is updated to
mention the new fourth script (currently lists `auth_throttle.sh email`,
`dashboard.sh`, and `session_analytics.sh`).

---

## `scripts/manual_tests/run_all_dev.sh` updates

Add `reaction_flow.sh` as a fourth chained script, after `session_analytics.sh`:

```sh
run_script "reaction_flow.sh"       "$SCRIPT_DIR/reaction_flow.sh" --base-url "$BASE_URL"
```

Update the non-local error message (currently lists the three existing
scripts by name) to include `reaction_flow.sh`.

---

## `docs/roadmap.md` updates

Remove the "### Manual test: attendee reaction flow (`/t/:slug`)" item from
the "Manual/Live-Environment Testing" section — it's now actively planned via
this spec. The remaining two items in that section (account settings, OAuth
connect/disconnect) are unaffected.

---

## Files touched

- `scripts/manual_tests/seed_active_session.exs` — new
- `scripts/manual_tests/reaction_flow.sh` — new
- `scripts/manual_tests/run_all_dev.sh` — add `reaction_flow.sh` to the chain,
  update error message
- `docs/manual_tests.md` — new "Attendee reaction flow" section, update Quick
  start description
- `docs/roadmap.md` — remove "Manual test: attendee reaction flow" item
