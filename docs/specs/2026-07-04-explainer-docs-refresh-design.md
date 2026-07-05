# Explainer & Administration Docs Refresh — Design

**Date:** 2026-07-04
**Source:** "Onboarding docs and help pages" follow-ups in `docs/roadmap.md`
("`docs/explainer.md` is stale: it predates API-key auth on the reaction
channel").
**Scope:** `docs/explainer.md` (full accuracy pass) and `docs/administration.md`
(one stale runbook section). No app code changes — this is a documentation
correction pass only.

## Goals

`docs/explainer.md` is a from-scratch architecture walkthrough for engineers
new to the codebase. An audit against the current codebase found it stale in
far more places than the roadmap's one-line flag: the entire auth/admin model
it describes was replaced, the Chrome extension's internal architecture
changed, and the production domain changed. Left as-is, a reader would be
actively misled by roughly half the document. This pass brings every section
back in sync with the current code, with no restructuring beyond what's
needed to describe what changed (i.e., no new sections invented, no
reordering, aside from renaming "Admin flow" since there is no admin flow
anymore).

`docs/administration.md` has one section (`update_user_password/2`) that
calls a function that no longer exists, because auth is now passwordless.
That section gets replaced with the equivalent passwordless operation.

## `docs/explainer.md` changes, by section

### 1. Project structure (lines 34–74)

Remove from the tree: `speechwave_web/plugs/admin_auth.ex`,
`speechwave_web/live/admin_live.ex` (neither exists anymore).

Add to the tree:
- `speechwave/accounts.ex` + `speechwave/accounts/{scope,user,user_token,user_identity,user_consent,user_notifier}.ex` — auth/accounts context
- `speechwave/plans.ex` — tier limits (`:free`/`:pro`/`:org`)
- `speechwave/auth_throttle.ex` — magic-link send throttling
- `speechwave_web/live/dashboard_live.ex` (replaces `admin_live.ex`)
- `speechwave_web/live/user_live/{login,settings}.ex`
- `speechwave_web/user_auth.ex` (replaces the `admin_auth.ex` plug)
- `speechwave_web/presence.ex` — Phoenix.Presence, used by the channel for capacity checks
- `speechwave_web/controllers/user_session_controller.ex`

Update the `qr_code.ex` comment from "QR code generation for admin" to
reflect it's invoked from `DashboardLive`.

Chrome extension tree: add `background/background.js` (MV3 service worker
that now owns the socket/channel) and `lib/phoenix.js` (vendored Phoenix
client, loaded via `importScripts` in the service worker).

### 2. The data model (lines 78–126)

- Change "There are three database tables" to note there are more (mention
  `users`, `users_tokens`, `identities`, `user_consents` exist for the
  auth/accounts side — one sentence, not full schemas; this doc's focus stays
  on the reaction-flow tables).
- Add `belongs_to :user, Speechwave.Accounts.User` to the `talks` schema
  snippet — this is the owner field that gates dashboard listing, channel
  join, and session-analytics access everywhere else in the doc.
- Change "renamed from the admin panel" (line 111) to "renamed from the
  Dashboard."

### 3. Routing (lines 129–145)

Replace the route table wholesale with the actual current structure:

```elixir
# Public attendee page
scope "/", SpeechwaveWeb do
  pipe_through :browser
  live "/t/:slug", TalkLive
end

# Requires login
scope "/", SpeechwaveWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{SpeechwaveWeb.UserAuth, :require_authenticated}] do
    live "/dashboard",                       DashboardLive
    live "/sessions/:id",                    SessionAnalyticsLive, :show
    live "/sessions/:id/compare/:other_id",   SessionAnalyticsLive, :compare
    live "/users/settings",                  UserLive.Settings, :edit
    live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
  end
end

# Works with or without login
scope "/", SpeechwaveWeb do
  live_session :current_user,
    on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
    live "/users/log-in", UserLive.Login, :new
    live "/pricing",      PricingLive
  end

  get "/users/magic_link/:token", UserSessionController, :magic_link
  delete "/users/log-out",        UserSessionController, :delete
end

# OAuth
scope "/auth", SpeechwaveWeb do
  get "/:provider",          UserSessionController, :oauth_authorize
  get "/:provider/callback", UserSessionController, :oauth_callback
end
```

No `/admin` scope, no HTTP Basic Auth pipeline exists. Session-analytics
access is gated by ownership inside the LiveView (`Talks.get_talk!/2` raises
if the session's talk isn't owned by `current_scope.user`), not by a separate
plug — call this out since it's a meaningfully different security model than
"admin-only."

### 4. Channel join / `ReactionChannel` (the "two websocket connections" section, lines 236–298)

This is the section the roadmap explicitly flagged, and it's bigger than "add
an api_key param." Rewrite the `user_socket.ex`/join description to describe
the actual handshake in `ReactionChannel.join/3`:

1. Talk must exist (`Talks.get_talk_by_slug/1`)
2. `api_key` param must resolve to a user (`Accounts.get_user_by_api_key/1`)
3. That user must own the talk (`talk.user_id == user.id`)
4. Capacity check via `Plans.check(:max_participants, user.plan, Presence.list(...) |> map_size())`

Failure returns `{:error, %{reason: reason}}` with `reason` one of
`:not_found`, `:unauthorized`, `:capacity_reached`. Add a short paragraph
explaining each failure mode in plain language (talk doesn't exist / API key
doesn't match / plan's participant limit reached) since these map directly to
what a Chrome-extension user would see in the popup.

### 5. "Admin flow" section (lines 447–459) → rename to "Dashboard flow"

Replace entirely. New content:

- Login is magic-link (email a one-time token) or OAuth (Google/Microsoft/
  GitHub via `/auth/:provider`); no username/password.
- From the Dashboard (`/dashboard`, requires login), a speaker creates a talk
  (title → auto-generated slug, scoped to `current_scope.user.id` via
  `Talks.create_talk(scope, attrs)`) and gets a QR code.
- The QR code encodes `SpeechwaveWeb.Endpoint.url() <> "/t/#{talk.slug}"` —
  i.e. `https://speechwave.live/t/my-talk`.
- One-sentence forward-looking note: `User.is_admin` exists as a boolean and
  the dashboard has a placeholder "Super-admin controls coming soon" banner,
  but the super-admin panel itself is a roadmap item, not yet built. Don't
  describe it as a working feature.

### 6. Supervision tree (lines 462–479)

Add to the mermaid diagram and prose: `Speechwave.AuthThrottle`,
`SpeechwaveWeb.Presence`, and the conditional `Speechwave.DbBackup` (only
started when a storage bucket env var is configured — hourly SQLite backup,
see `docs/administration.md`).

### 7. Talk sessions (lines 483–495)

Keep the existing description of `start_session/1`, `stop_session/1`,
`get_active_session/1`, `list_sessions/1`, `rename_session/2`,
`delete_session/1` — all accurate, unchanged. Add:

- `Talks.count_full_sessions_this_month/1` and the `Plans.check(:full_sessions_per_month, ...)` gate in `ReactionChannel.handle_in("start_session", ...)`, which can reject with `session_limit_reached` before the session is created.
- `ReactionChannel` tracks Presence for capacity enforcement and subscribes to `"user:#{user.id}:disconnect"` so that logging out or regenerating an API key force-disconnects the extension's channel (`{:stop, :normal, socket}` on that broadcast).
- Reword "admin operations" (rename/delete) → "dashboard operations."

### 8. Chrome extension (lines 343–410)

Rewrite the ownership model: the doc currently says the content script owns
the `Socket`/channel. It now doesn't — `background/background.js` (an MV3
service worker) owns the socket and channel lifecycle:

- Popup messages go to the background worker (`chrome.runtime.sendMessage`), not the content script.
- Background worker joins `reactions:#{slug}` with `{api_key: apiKey}`, and on `new_reaction` relays to all open Slides tabs via `chrome.tabs.sendMessage({type: "RENDER_EMOJI", emoji})`.
- Content script's role shrinks to: render (`RENDER_EMOJI` → `spawnEmoji()`), report slide changes up to the background (`chrome.runtime.sendMessage({type: "SLIDE_CHANGED", ...})`), and toggle fireworks.
- One paragraph on why: MV3 service workers can restart independently of the rest of the extension, so the background worker has explicit reconnect/rejoin logic and zombie-socket guards — worth a sentence so a reader isn't confused by that code if they go looking.
- Update `wss://speechwave.fly.dev/socket` → `wss://speechwave.live/socket`, and note the join now requires the api_key from the popup's "API key setup" flow (64-char hex, validated client-side).

Fireworks subsection (lines 365–410): **no changes** — verified accurate.

### 9. Slide tracking (lines 499–566)

- Server-side handling (`handle_in("slide_changed", ...)`): **no changes**, verified accurate.
- Client-side detection: replace the `MutationObserver` description with the actual 500ms poll (`setInterval(checkSlide, 500)` calling `adapter.getSlide()` each tick).
- Update the Google Slides adapter description: it no longer reads `input[aria-label*="Slide"]`. It now searches the document and same-origin iframes for `.punch-viewer-svgpage-a11yelement[aria-label*="Slide"]`, parsing `"Slide N"` via regex. Add the important behavioral caveat: this only works once the slideshow is in presentation/fullscreen mode, not in the editor view.
- Delivery path: content script now does `chrome.runtime.sendMessage({type: "SLIDE_CHANGED", slide})` to the background worker, which does the actual `channel.push("slide_changed", ...)`.

### 10. Analytics dashboard (lines 570–597)

Mostly accurate — `slide_reaction_totals/1` and comparison mode are
unchanged. Fix the route references: `/sessions/:id` and
`/sessions/:id/compare/:other_id`, not `/admin/sessions/:id[...]`. Fix the
access description: authenticated + ownership-checked, not "admin-only."

### 11. Closing glossary table (lines 602–621)

Fix the `SessionAnalyticsLive` row: "owner-only, authenticated-user
LiveView," not "Admin-only." Add rows: `Scope`/`current_scope`, `api_key`,
`Plans` (tier limits), `Presence` (capacity tracking), background service
worker (owns the extension's socket).

### 12. Domain (cross-cutting)

Global find/replace `speechwave.fly.dev` → `speechwave.live` everywhere it
appears (mermaid diagrams, prose, code comments).

### 13. Minor code-sample conformance (low priority, bundle into whichever task touches these)

- LiveView mount snippet (lines 421–429): the real code uses `redirect(socket, to: "/")` for a missing slug, not `push_navigate(socket, to: ~p"/")` as currently shown.
- The emoji-journey code samples call `Phoenix.PubSub.subscribe(Speechwave.PubSub, ...)` directly rather than an `Endpoint.subscribe` wrapper — conform the sample to match.

## `docs/administration.md` change

Replace the "How to manually reset a user's password" section (lines 20–36),
which calls `Speechwave.Accounts.update_user_password/2` — a function that no
longer exists now that auth is passwordless — with "How to send a user a
fresh login link":

```elixir
user = Speechwave.Accounts.get_user_by_email("user@example.com")
url_fun = fn token -> "https://speechwave.live/users/magic_link/#{token}" end
Speechwave.Accounts.deliver_login_instructions(user, url_fun)
```

This calls the same `deliver_login_instructions/2` the app itself uses on
every login (`user_live/login.ex`), just with a manually-built `url_fun`
since there's no `~p` sigil/router helper available in a bare remote
console. Note in the doc that this sends the user a real email — same as a
normal login attempt — rather than invalidating anything (there's no
password/session to invalidate in this model).

## Testing / verification approach

This is a documentation change with no automated test suite. Verification
is a fact-check pass instead:

- After each section rewrite, grep the actual source for every module name,
  function name, and route path mentioned in the new text, confirming each
  one exists and matches (e.g. `grep -n "def deliver_login_instructions"
  lib/speechwave/accounts.ex`).
- Final pass: `grep -rn "fly.dev" docs/explainer.md` must return nothing.
  `grep -rn "admin" docs/explainer.md` should only match the forward-looking
  `is_admin`/super-admin-panel note, nothing describing a working admin
  panel/HTTP Basic Auth flow.
- `grep -n "update_user_password" docs/administration.md` must return
  nothing.
- `mix precommit` must still pass (no app code changes expected, but this
  confirms nothing was accidentally touched outside the two doc files).

## Implementation approach

One task per doc section group, each independently reviewable (a fact-check
against the live source, not a code review). Sections are mostly
independent edits to the same file, so tasks run sequentially rather than in
parallel to avoid diff conflicts within `explainer.md`. The `administration.md`
fix is a separate, independent task.

## Out of scope

- Any app code changes — this is a docs-only pass.
- The dead-code note (`Talks.get_talk_with_owner/1`, referenced only from
  tests) — not something the doc currently claims, so not "stale"; a
  separate cleanup concern if ever addressed.
- Screenshots pass for the docs.speechwave.live site (separate roadmap item).
