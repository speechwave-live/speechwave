# Overlay size setting and remote extension config

## Problem

The Chrome extension's emoji-reaction overlay (`chrome-extension/content/content.js`)
is a fixed-shape box anchored to the slide's bottom-right corner, sized by a
handful of hardcoded constants (`OVERLAY_WIDTH`, `OVERLAY_HEIGHT`,
`SLIDE_REFERENCE_WIDTH`, `MIN_OVERLAY_SCALE`, `MAX_OVERLAY_SCALE`, margins,
emoji/firework font sizes and spread). Users have no way to adjust how much
of their slide the overlay covers, and every one of those constants can only
be changed by shipping a new extension version — which requires Chrome Web
Store review, an unpredictable-turnaround external dependency, unlike a
backend deploy.

This spec covers two related additions:

1. A user-facing setting letting a user choose overlay size as a percentage
   of slide coverage (100% = covers the whole slide), always anchored to the
   bottom-right corner, with a reasonable enforced minimum.
2. Moving the extension's internal tuning constants (today hardcoded in
   `content.js`) to a backend-delivered config, so they can be adjusted via
   a backend deploy — or, for local dev, a code change picked up by the
   Phoenix code reloader — without a new extension version.

Both ride the same delivery mechanism: the existing `reactions:{slug}`
channel join.

## Current state

- `SpeechwaveWeb.ReactionChannel` (`lib/speechwave_web/channels/reaction_channel.ex`)
  handles `join("reactions:" <> slug, %{"api_key" => api_key}, socket)`,
  authenticating via `Accounts.get_user_by_api_key/1`. On success it returns
  `{:ok, assign(socket, talk: talk, user: user)}` — **no payload** is sent to
  the client; Phoenix replies with an empty `{}`.
- There is no REST/JSON API in this app. The router defines an `:api` pipeline
  but nothing is mounted under it — the channel is the only api_key-authenticated
  surface today.
- `Speechwave.Accounts.User` (`lib/speechwave/accounts/user.ex`) has `email`,
  `api_key`, `plan` (enum), `is_admin`, `confirmed_at`, timestamps. No
  settings/preferences field of any kind. **The app uses SQLite via
  `ecto_sqlite3`**, not Postgres — no jsonb column type is available or used
  anywhere in this schema; every field is a plain typed column.
- `SpeechwaveWeb.Live.UserLive.Settings` is the existing account-settings
  LiveView (password/email today).
- In the extension: `fireworksEnabled` and `debugEnabled` are each stored in
  `chrome.storage.sync`/`chrome.storage.local` and toggled via checkboxes in
  `popup/popup.html`, read directly by both `popup.js` and `content.js`
  independently. `content.js` reads `fireworksEnabled` from storage itself at
  startup, with no involvement from `background/background.js`.
- `background.js`'s `connect()` calls `channel.join().receive('ok', () => {...})`
  — the success callback currently takes no payload argument.

## Scope

**In scope:**
- `overlay_size_percent` (integer, user-editable) and `fireworks_enabled`
  (boolean, user-editable) as new columns on `users`, edited on the existing
  account Settings page.
- A new `Speechwave.ExtensionTuning` module holding today's hardcoded
  content.js constants (reference values, margin, font-size ratios, firework
  spread/center, minimum size), in the new percent-of-slide-dimension shape
  (see Sizing math below).
- `ReactionChannel.join/3` returns both bundled in the join reply.
- Extension changes to consume this payload instead of local
  constants/storage: `content.js` sizing math, `background.js` relay/cache,
  `popup.js`/`popup.html` UI removal for the fireworks toggle.
- One extension version bump to ship the config-consuming code itself — this
  is the one unavoidable store submission; tuning iteration after that does
  not require another one.

**Explicitly out of scope (see "Out of scope" section for the full list and
why):** per-talk settings, live-push of settings to an already-connected
session, migrating existing local `fireworksEnabled` values, any DB-backed
admin UI for tuning constants, moving `debugEnabled` to the backend.

## Sizing math

Box dimensions are computed directly from the slide's actual rendered size
(via the existing `.punch-present-iframe` / `getSlideRect()` mechanism
already in `content.js`), not from a normalized reference width:

```
overlayWidth  = slideWidth  * (overlaySizePercent / 100)
overlayHeight = slideHeight * (overlaySizePercent / 100)
```

At `overlaySizePercent = 100`, width and height exactly equal the slide's
own dimensions regardless of its aspect ratio — a literal reading of "100%
overlays the entire slide." At any other value the box scales down
proportionally in both dimensions, so it's always shaped like a smaller copy
of the slide itself. This **replaces** `SLIDE_REFERENCE_WIDTH` /
`MIN_OVERLAY_SCALE` / `MAX_OVERLAY_SCALE` entirely — those existed only to
normalize a fixed base size across different render sizes, which computing
directly from slide dimensions makes unnecessary. Net simplification of
`content.js`, not just an addition.

Position is unchanged from today's anchoring logic: bottom-right corner,
`left = slideRect.right - overlayWidth - marginPx`,
`top = slideRect.bottom - overlayHeight - marginPx`.

- **Margin**: a small *fixed* pixel value (`ExtensionTuning.overlay_margin_px`),
  not scaled — stays snug at low percentages, becomes visually negligible at
  high ones, avoids re-deriving the proportional-margin logic this session
  already iterated on for the old fixed-box design.
- **Minimum**: `ExtensionTuning.min_overlay_size_percent` (starting guess:
  10) is enforced as the Settings-page slider's `min` attribute *and*
  defensively clamped in `content.js` in case a stale/bad value ever arrives.
- **Default for unconfigured users**: `overlay_size_percent` is a **nullable**
  column. When `nil`, the channel join resolves it to
  `ExtensionTuning.default_overlay_size_percent()` (starting guess: 20,
  roughly matching today's effective visual proportions) rather than baking
  a default into the column itself — this keeps the default adjustable for
  all not-yet-configured users without a data migration.
  `fireworks_enabled` is a plain `NOT NULL DEFAULT true` boolean column — it
  doesn't need this same remote-tunability, since it's a stable on/off
  feature, not something under active visual iteration.
- **Emoji/firework sizing**: font size, firework spread, firework center
  point, and emoji rise distance all become ratios of the box's own current
  width/height (e.g. `emoji_font_size_ratio`) rather than fixed pixel
  constants scaled by the old `overlayScale` — so they stay proportional to
  whatever size the user has chosen.

## Architecture

### `Speechwave.ExtensionTuning`

A plain module (not a DB table) — a function returning a map of the current
tuning values, e.g.:

```elixir
def current do
  %{
    default_overlay_size_percent: 20,
    min_overlay_size_percent: 10,
    overlay_margin_px: 8,
    emoji_font_size_ratio: 0.14,
    firework_font_size_ratio: 0.12,
    firework_center_x_ratio: 0.5,
    firework_center_y_ratio: 0.5,
    firework_spread_min_ratio: 0.375,
    firework_spread_range_ratio: 0.25,
    emoji_rise_ratio: 0.3
  }
end
```

To iterate: edit this module. Locally, Phoenix's code reloader picks it up
without a restart. In production, `fly deploy` — no migration, no admin UI,
no new schema. Once a value is settled, it can either stay
backend-delivered indefinitely or be copied back into `content.js` as a
hardcoded constant and dropped from the payload, per-constant, whenever it's
no longer expected to need further tuning.

Considered and rejected: a DB-backed config table with an admin edit page.
The original motivation was avoiding *Chrome Web Store review* specifically
— backend deploys were never the slow part, and are already fast here. A
DB+admin-UI's only real advantage over a plain module would be skipping
even a fast deploy, which doesn't justify a migration, schema, context
module, and LiveView form. It would also be *slower* for the local-dev
iteration this exists to support — editing a file and letting the code
reloader pick it up is faster than clicking through an admin form each time.

### User settings

New columns on `users` (SQLite, plain typed columns — no jsonb type
available or precedented in this schema):

```elixir
add :overlay_size_percent, :integer  # nullable; nil = use ExtensionTuning default
add :fireworks_enabled, :boolean, default: true, null: false
```

Changeset validation: `overlay_size_percent` must be an integer between
`ExtensionTuning.min_overlay_size_percent()` and 100 when present (nil
allowed); `fireworks_enabled` a plain boolean.

### Channel join payload

`ReactionChannel.join/3` changes from today's bare `{:ok, socket}` to:

```elixir
{:ok, %{
  settings: %{
    overlaySizePercent: user.overlay_size_percent || ExtensionTuning.current().default_overlay_size_percent,
    fireworksEnabled: user.fireworks_enabled
  },
  tuning: ExtensionTuning.current()
}, assign(socket, talk: talk, user: user)}
```

**Rollout ordering**: the two repos are decoupled by the same
always-fall-back-to-defaults principle. A pre-this-feature extension talking
to a post-this-feature backend receives the new `settings`/`tuning` payload
but ignores it (its `receive('ok', callback)` takes no parameters) and keeps
using its own local storage/hardcoded values — no error. A
post-this-feature extension talking to a pre-this-feature backend gets an
empty `{}` join reply, finds no `settings`/`tuning` keys, and falls back to
its own hardcoded `DEFAULT_CONFIG` — same code path as any other
missing-field case. Either repo can ship first without breaking the other.

### Extension: consuming remote config

- `background.js`'s `channel.join().receive('ok', payload => ...)` captures
  `settings`/`tuning`, stores them in module-level variables
  (`lastKnownSettings`, `lastKnownTuning`), and calls
  `broadcastToSlidesTabs({ type: 'SET_REMOTE_CONFIG', settings, tuning })` —
  replacing today's popup-triggered `SET_FIREWORKS` message entirely.
- **Edge case this design has to handle**: today `content.js` reads
  `fireworksEnabled` from `chrome.storage.sync` itself at startup,
  independent of `background.js`. Once that value only exists as something
  `background.js` learns from the channel, a content script that loads
  *without* a join happening first — e.g. the user refreshes the Slides tab
  mid-session, no reconnect involved — has no way to get current settings.
  Fix: add `GET_REMOTE_CONFIG`, mirroring the existing `GET_STATUS`
  request/response pattern popup.js already uses against background.js.
  `content.js` sends it once on load; `background.js` replies with
  `lastKnownSettings`/`lastKnownTuning` (or built-in hardcoded fallback
  defaults if never connected). Combined with the join-triggered broadcast
  above, both cases are covered — pushed updates on reconnect, pulled state
  on fresh load — using a pattern already established in this codebase.
- `content.js` keeps a hardcoded `DEFAULT_CONFIG` object (mirroring today's
  tuned values in the new ratio-based shape) as the last-resort fallback,
  used until the first `SET_REMOTE_CONFIG` or `GET_REMOTE_CONFIG` response
  arrives, and for any field ever missing from a payload. A network hiccup
  or a stale/incompatible backend never breaks rendering — it just falls
  back to sane defaults, same principle as today's
  `chrome.storage.sync.get({ fireworksEnabled: true }, ...)` pattern.
- `syncOverlayPosition()` computes width/height per the Sizing math section
  above instead of the old `overlayScale` derivation; `spawnEmoji()`/
  `spawnFireworks()` read font-size/spread/rise/center from the current
  tuning ratios × the box's current dimensions.

### Settings page UI

New section on `UserLive.Settings`: a percent slider (`min` set from
`ExtensionTuning.current().min_overlay_size_percent`, `max` fixed at 100)
with a numeric readout, plus a checkbox for fireworks. Standard
`to_form`/`<.form>`/changeset pattern matching the rest of the app. No live
preview — the effect is only visible inside an actual Slides presentation,
not renderable on this page; a line of copy ("Applies next time you connect
during a talk") sets expectations instead.

### Extension UI removal

`popup/popup.html` and `popup/popup.js`: remove the `fireworks-toggle`
checkbox, its label, and its `chrome.storage.sync`/`SET_FIREWORKS` wiring
entirely. `test-fireworks-btn` (DEV_MODE manual trigger, unrelated to the
enabled/disabled setting — `TEST_FIREWORKS` unconditionally calls
`spawnFireworks` today) and `debug-toggle`/`debug-toggle-label` (dev tool,
not a user preference) are untouched.

## Testing

**Backend:**
- `ReactionChannelTest`: join reply includes `settings`/`tuning` with the
  expected shape; a user with `overlay_size_percent: nil` gets the
  `ExtensionTuning` default in the resolved payload; a user with an explicit
  value gets that value back unchanged.
- Changeset tests: `overlay_size_percent` bounds (rejects below the tuning
  minimum, above 100, non-integer; accepts `nil`); `fireworks_enabled`
  boolean.
- `UserLive.SettingsTest`: renders the new fields with current values;
  submitting valid values persists; submitting an out-of-range percent shows
  a validation error and does not persist (`has_element?`/`element/2` per
  project convention, not raw HTML assertions).
- `Speechwave.ExtensionTuningTest`: asserts `current/0` returns all expected
  keys with correct types.

**Extension (Jest):**
- `content.test.js`: rewrite the scaling describe block for the new
  percent-of-slide-dimension math (same mocked-iframe/slide-rect pattern
  already established this session), covering the minimum clamp, and add
  coverage for `SET_REMOTE_CONFIG` (updates applied on next spawn) and
  `GET_REMOTE_CONFIG` (sent once on load).
- `background.test.js`: join payload capture and caching, `SET_REMOTE_CONFIG`
  broadcast to matching tabs, `GET_REMOTE_CONFIG` response (from cache, and
  from hardcoded defaults when never connected).
- `popup.test.js`: remove the fireworks-toggle tests (UI is gone); dev-mode
  tests (test-fireworks-btn, debug-toggle) added this session are unaffected.

**Manual/live verification** (established this session as unavoidable —
none of the above can verify actual rendering/positioning): the percent
slider at its minimum, ~50%, and 100% in an actual Slides present window,
both windowed and OS-fullscreen, confirming 100% genuinely fills the slide
without overflow and that emoji/firework proportions still look reasonable
across the full range. Also confirm the `GET_REMOTE_CONFIG`/
`SET_REMOTE_CONFIG` flow live: toggling a setting on the web Settings page,
then Disconnect/Connect in the popup, picks up the change without an
extension reload.

## Out of scope (deferred)

- **Per-talk settings.** Global-for-now per explicit product direction;
  flagged as a plausible future paid-tier feature, not built here.
- **Live-push of settings to an already-connected session.** Settings apply
  on next channel join (reconnect), not instantly to a mid-talk session.
  Would reuse the existing `slide_changed`-style broadcast pattern if built
  later.
- **Migrating existing local `fireworksEnabled` values.** Users who
  previously disabled fireworks via the extension popup get reset to the
  new default (`true`) rather than having their local value carried over —
  accepted low-blast-radius trade-off rather than one-time migration code
  that's discarded after everyone's transitioned.
- **DB-backed tuning config / admin UI.** Considered and explicitly
  rejected in favor of the plain `ExtensionTuning` module — see Architecture
  above.
- **Moving `debugEnabled` to the backend.** Stays a local extension dev
  tool, not a user-facing preference.
- **Additional presentation-software clients** (PowerPoint/Keynote add-ins).
  Not built here; this design's preference for backend-hosted settings over
  per-client local storage is chosen partly *because* it anticipates this
  future, but no other client is implemented in this spec.
