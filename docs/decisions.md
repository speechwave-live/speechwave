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

- **"Confirmed" is now monotonic.** Originally inferred from session-token/
  identity existence (volatile — logout deleted the evidence), this was
  fixed on 2026-07-06 by adding a dedicated `users.confirmed_at` column, set
  once on first login and never cleared. See
  `docs/specs/2026-07-06-confirmed-at-column-design.md`.
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

## 2026-07-27 — Chrome extension: overlay anchored to `.punch-present-iframe`, not the viewport/fullscreen assumption

**Decision:** Position and stack the emoji-reaction overlay
(`chrome-extension/content/content.js`) relative to Google Slides' own
`.punch-present-iframe` element — the actual slide-rendering iframe —
instead of assuming the presentation always fills the browser viewport.

**Why:** The overlay was `position: fixed; bottom: 40px; right: 20px`, a
corner pinned to the browser viewport. That only ever looked "anchored to
the slide" by coincidence: in true OS-fullscreen Present mode the slide
iframe happens to fill the entire viewport, and a pre-existing
`fullscreenchange` listener re-parents the overlay into
`document.fullscreenElement` so it can compete for stacking within the
browser's fullscreen top layer. Neither condition holds in Google Slides'
"windowed" present mode (Presenter options → uncheck "Full screen" →
Slideshow, or exiting fullscreen via the browser's back button): no
`fullscreenchange` event ever fires there (the Fullscreen API is never
engaged), so the overlay stayed a plain sibling of `.punch-present-iframe`
in `document.body` — and that iframe carries its own z-index higher than
the overlay's, so the overlay rendered completely invisible underneath it,
not just misaligned.

Root cause was confirmed by direct instrumentation during a live debugging
session (chrome://extensions service-worker console + present-tab console):
`document.elementFromPoint()` at the overlay's own on-screen coordinates
returned the `.punch-present-iframe` element itself, proving the iframe was
painting on top despite the overlay's `z-index: 999999`.

A first pass anchored the overlay to `.punch-present-iframe`'s own
`getBoundingClientRect()` and fixed the invisibility, but live testing
surfaced a second, distinct problem: Google **letterboxes** the rendered
slide inside that iframe to preserve its aspect ratio (black bars above/
below or beside it depending on window shape), so the iframe's outer rect
is not the visible slide's rect — the overlay landed correctly stacked but
in the wrong spot (inside a letterbox bar, off the visible slide). Live
inspection of the iframe's contents found that
`.punch-viewer-svgpage-a11yelement[aria-label*="Slide"]` — the same element
`adapters/google_slides.js` already reads for slide-number tracking — is
sized and positioned to match the *visible* slide exactly (confirmed: its
rect and `.punch-viewer-svgpage-svgcontainer`'s rect were identical, and
the vertical offset matched the letterbox centering math precisely,
e.g. a 741×889 iframe letterboxing a 741×417 slide at y=236 —
`(889 - 417) / 2 = 236`). The fix reuses that element instead of inventing
new letterbox-math or a new selector.

**What changed:**
- `getPresentIframe()` locates `iframe.punch-present-iframe` if present.
- `getSlideRect()` reaches into that (same-origin) iframe's
  `contentDocument`, finds the `.punch-viewer-svgpage-a11yelement`, and
  returns its rect offset by the iframe's own rect — i.e. the visible
  slide's bounds in top-document coordinates, not the iframe's outer
  letterboxed bounds.
- `syncOverlayPosition()` anchors the overlay's `left`/`top` to that rect's
  bottom-right corner (initially the same 20px/40px margins as the original
  viewport-corner design — the bottom margin was later halved to 20px, see
  part 3 below) and sets `z-index` to `2147483647` (max signed
  32-bit int) — a value no ordinary page content can outrank. Falls back to
  the iframe's own rect if the slide element isn't found inside it (e.g.
  present mode still loading), and falls back further to the original
  fixed-viewport-corner behavior when no presentation iframe exists at all
  (plain editor view, not presenting).
- `getOrCreateOverlay()` re-syncs position on every call, which happens on
  both initial load and immediately before every emoji/fireworks spawn — so
  placement tracks iframe/slide resizing without a dedicated observer or
  timer.
- The existing `fullscreenchange`-based reparenting into
  `document.fullscreenElement` was **kept, not replaced** — see trade-offs.
- **Follow-up (same day, part 1):** live testing after the above found the
  overlay correctly positioned but not *scaled* — box size, margins, and
  emoji font size were all fixed pixel values, so a small/resized present
  window made emoji look oversized relative to the slide (and vice versa
  for a large window). Added `overlayScale = clamp(slideWidth /
  SLIDE_REFERENCE_WIDTH, MIN_OVERLAY_SCALE, MAX_OVERLAY_SCALE)` (reference
  width 960px, clamped to [0.4, 2]), computed in `syncOverlayPosition()`
  from the resolved slide/iframe rect and applied to overlay
  width/height/margins in that same function, and to emoji/firework font
  size and firework center/spread in `spawnEmoji()`/`spawnFireworks()`.
- **Follow-up (same day, part 2 — tried and reverted):** first reaction to
  "the box sits higher than it used to" was to stop scaling the margin at
  all (treat it as fixed framing/padding, only scale the box and its
  contents). Live-tested and rejected: the user's actual design intent is
  that the overlay should cover roughly the *same proportion* of the slide
  at any size — a fixed-pixel margin works against that, since it shrinks
  as a fraction of the slide the bigger the slide gets. Reverted to scaling
  the margin proportionally like everything else.
- **Follow-up (same day, part 3):** the real issue with part 1 wasn't that
  the margin scaled — it's that the *base* bottom margin (40px, inherited
  unchanged from the original unscaled design) was simply too large once
  actually scaled up for a real, larger-than-960px slide. Halved
  `OVERLAY_BOTTOM_MARGIN` from 40 to 20; `OVERLAY_RIGHT_MARGIN` (20)
  unchanged. Both still scale proportionally with `overlayScale`.
  The 960px reference, the clamp bounds, and this halved margin are all
  still first guesses, not measured against real conference-room screen
  sizes — tune `SLIDE_REFERENCE_WIDTH`/`MIN_OVERLAY_SCALE`/
  `MAX_OVERLAY_SCALE`/`OVERLAY_BOTTOM_MARGIN` in `content.js` by eye if the
  proportions look off in practice.

**Trade-offs / things to know:**
- **Two overlay-placement mechanisms now coexist, deliberately.**
  `requestFullscreen()` promotes an element (and its subtree) into the
  browser's "top layer," which paints above *all* regular content — no
  z-index, however large, can beat it from outside that subtree.
  `document.querySelectorAll(':modal')` (matches anything currently in the
  top layer) returned empty during windowed-mode testing, confirming normal
  z-index rules apply there, which is why the max-z-index fix works for
  windowed mode. But if true OS-fullscreen mode promotes an element that
  *contains* `.punch-present-iframe` into that same top layer, the overlay
  would need to be physically reparented inside that subtree to compete at
  all, regardless of z-index — which is exactly what the pre-existing
  `fullscreenchange` listener already does. Both mechanisms were left in
  place rather than consolidated into one, since only the windowed case was
  reproduced and fixed this session; removing the fullscreen-specific path
  without live-verifying fullscreen mode against the new code would risk an
  unverified regression in the one mode already known to work. **Update:**
  live testing after shipping this fix confirmed emoji render correctly in
  *both* windowed and OS-fullscreen present mode, so the two-mechanism
  approach is verified, not just theorized.
- **`.punch-present-iframe` and `.punch-viewer-svgpage-a11yelement` are
  undocumented Google Slides implementation details** — the overlay-position
  fix now depends on the same selector `adapters/google_slides.js` already
  relied on for slide-number tracking, plus the iframe class name and the
  fact that the a11y element happens to be sized to match the visible
  slide. All of this is brittle to Google changing their DOM; no upstream
  contract. If `getSlideRect()` starts returning `null` (selector no longer
  matches), the code silently falls back to the iframe's own — possibly
  letterboxed — rect, so a future regression here would look like "overlay
  is visible but positioned wrong again," not a crash.
- **The root cause took an extended live-debugging session to isolate**
  because several red herrings looked causal along the way: an "Extension
  context invalidated" scare (ruled out — no such error ever appeared), a
  "message port closed before a response was received" error on every
  `chrome.tabs.sendMessage` call (still unexplained and apparently cosmetic
  — the content script's listener ran to completion with no thrown
  exception every time, so this never actually blocked functionality, but
  the sender-side error's own cause was never identified), and a
  window-focus/throttling theory (disproven — dispatching from an
  already-focused present-tab console failed identically to popup-clicking,
  before the real fix). The actual fix came from
  `document.elementFromPoint()` at the overlay's own coordinates, which
  named the covering element directly instead of requiring further
  inference.
