# Speechwave — How it works

Speechwave lets conference attendees send live emoji reactions that float up on
the speaker's screen in real time. This document walks through how the whole
system fits together, with a focus on the communications plumbing.

---

## The big picture

There are three actors in the system:

1. **Attendee** — opens a URL on their phone (`/t/:slug`), taps an emoji
2. **Phoenix server** — receives the tap, rate-limits it, and broadcasts it
3. **Speaker** — has a Chrome extension running on their laptop that receives
   the broadcast and overlays emojis onto their slide presentation

```mermaid
graph LR
    A["📱 Attendee\n(browser)"] -->|"LiveView WebSocket\n/live"| S["⚡ Phoenix Server"]
    S -->|"Channel WebSocket\n/socket"| E["💻 Speaker\n(Chrome extension)"]
    S -->|"push_event → same\nLiveView WebSocket"| A
```

Two different WebSocket connections are used:

| Connection      | Path      | Protocol         | Used by            |
| --------------- | --------- | ---------------- | ------------------ |
| LiveView socket | `/live`   | Phoenix LiveView | Attendee's browser |
| Channel socket  | `/socket` | Phoenix Channel  | Chrome extension   |

---

## Project structure

```
lib/
  speechwave/
    application.ex              # OTP supervision tree
    accounts.ex                 # Auth/accounts context (users, tokens, identities, api keys)
    accounts/
      scope.ex                  # Scope struct wrapping the current user
      user.ex                   # User Ecto schema (email, api_key, plan, is_admin)
      user_token.ex             # Magic-link / session tokens
      user_identity.ex          # OAuth identity records (Google/Microsoft/GitHub)
      user_consent.ex           # Marketing-email consent records
      user_notifier.ex          # Login-instructions / notification emails
    plans.ex                    # Tier limits (:free/:pro/:org) + capacity checks
    auth_throttle.ex            # Rate-limits magic-link sends per email/IP
    talks.ex                    # Talk + session context (CRUD, lifecycle)
    talks/talk.ex               # Talk Ecto schema (owned by a user)
    talks/talk_session.ex       # TalkSession Ecto schema
    reactions.ex                # Reactions context (create, totals query)
    reactions/reaction.ex       # Reaction Ecto schema
    rate_limiter.ex             # GenServer + ETS rate limiting
    qr_code.ex                  # QR code generation for the dashboard
  speechwave_web/
    live/
      talk_live.ex              # Attendee reaction page (LiveView)
      dashboard_live.ex         # Speaker dashboard: talks, sessions panel
      session_analytics_live.ex # Per-session analytics (LiveView)
      user_live/
        login.ex                # Magic-link login page
        settings.ex             # Account settings, API key, OAuth connect/disconnect
    channels/
      user_socket.ex            # Socket definition for Chrome extension
      reaction_channel.ex       # Channel: reactions, sessions, slide_changed
    user_auth.ex                # Auth plugs + live_session on_mount hooks
    presence.ex                 # Phoenix.Presence, used for capacity checks
    controllers/
      user_session_controller.ex # Magic-link consumption, log-out, OAuth callback
    endpoint.ex                 # Mounts both socket types
    router.ex                   # Route definitions

chrome-extension/  (github.com/speechwave-live/chrome-extension)
  background/
    background.js        # MV3 service worker: owns the Socket/Channel lifecycle
  adapters/
    google_slides.js    # Reads current slide number from Google Slides DOM
    index.js            # Adapter registry (returns adapter for current URL)
  lib/
    fireworks.js        # Pure trigger logic for fireworks animation (dual-export: CJS + window global)
    phoenix.js          # Vendored Phoenix client, loaded via importScripts in the service worker
  content/content.js    # Content script: overlay, slide polling, fireworks spawner
  popup/popup.{html,js} # Extension popup UI (connection, API key, session, fireworks toggle)
  manifest.json
  tests/                # Jest tests for adapters, fireworks trigger logic, background worker, popup

assets/js/hooks/
  emoji_buttons.js      # Disables buttons + shows cooldown countdown
  emoji_stream.js       # Animates incoming emojis in the browser
```

---

## The data model

There are three database tables for the reaction flow (plus an auth/accounts
side — `users`, `users_tokens`, `identities`, `user_consents` — covered in
the "Dashboard flow" section below).

**`talks`** — one row per conference talk, owned by a user:

```elixir
schema "talks" do
  field :title, :string   # e.g. "My talk"
  field :slug,  :string   # e.g. "my-talk"  ← used in URL and PubSub topic
  has_many :talk_sessions, TalkSession
  belongs_to :user, Speechwave.Accounts.User
  timestamps(type: :utc_datetime)
end
```

Slugs are auto-generated from the title (lowercase, spaces → hyphens, special
chars stripped) and are unique. The slug is the key that ties all three actors
together: it's in the URL, the PubSub topic, and the Channel topic. The
`user` association is the owner — it gates dashboard listing, Channel join
(see "The two websocket connections in detail" below), and session-analytics
access.

**`talk_sessions`** — a recording window within a talk (e.g. "Session 1", "Denver Practice"):

```elixir
schema "talk_sessions" do
  field :label,      :string
  field :started_at, :utc_datetime
  field :ended_at,   :utc_datetime   # nil while active
  belongs_to :talk, Talk
  has_many :reactions, Reaction, on_delete: :delete_all
end
```

Sessions are started and stopped by the speaker via the Chrome extension.
`label` auto-increments ("Session 1", "Session 2", …) but can be renamed from
the Dashboard.

**`reactions`** — one row per emoji tap:

```elixir
schema "reactions" do
  field :emoji,       :string
  field :slide_number, :integer, default: 0   # 0 = unknown/before session start
  belongs_to :talk_session, TalkSession
end
```

`slide_number` is `0` when no adapter could read the current slide (e.g. before
a session starts, or on a non-Google-Slides presentation). All slide-`0`
reactions group under a "General" label in the analytics view.

---

## Routing

```elixir
# Public — no auth required
scope "/", SpeechwaveWeb do
  pipe_through :browser

  get "/", PageController, :home
  get "/terms", PageController, :terms
  get "/privacy", PageController, :privacy
  live "/t/:slug", TalkLive
end

# Requires login
scope "/", SpeechwaveWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{SpeechwaveWeb.UserAuth, :require_authenticated}] do
    live "/dashboard", DashboardLive
    live "/sessions/:id", SessionAnalyticsLive, :show
    live "/sessions/:id/compare/:other_id", SessionAnalyticsLive, :compare
    live "/users/settings", UserLive.Settings, :edit
    live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
  end
end

# Login itself — works whether or not you're already logged in
scope "/", SpeechwaveWeb do
  pipe_through [:browser]

  live_session :current_user,
    on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
    live "/users/log-in", UserLive.Login, :new
    live "/pricing", PricingLive
  end

  get "/users/magic_link/:token", UserSessionController, :magic_link
  delete "/users/log-out", UserSessionController, :delete
end

# OAuth login + connect flows
scope "/auth", SpeechwaveWeb do
  pipe_through :browser

  get "/:provider", UserSessionController, :oauth_authorize
  get "/:provider/callback", UserSessionController, :oauth_callback
end
```

There is no `/admin` scope and no HTTP Basic Auth pipeline. Session-analytics
access is gated by ownership *inside* `SessionAnalyticsLive.mount/3` (it
raises if the session's talk isn't owned by `current_scope.user`), not by a
separate plug — see "Analytics dashboard" below.

---

## The full emoji journey

This is the core flow. What happens from tap to floating emoji on the speaker's screen.

```mermaid
sequenceDiagram
    participant Phone as 📱 Attendee (Browser)
    participant LV as TalkLive (Server)
    participant RL as RateLimiter (GenServer)
    participant PS as Phoenix.PubSub
    participant CH as ReactionChannel
    participant EXT as Chrome Extension

    Phone->>LV: phx-click="react" (emoji="🔥")
    LV->>RL: allow?(session_id)?
    alt rate limited (< 3s since last tap)
        RL-->>LV: false
        LV-->>Phone: (silently ignored)
    else allowed
        RL-->>LV: true
        LV->>PS: Endpoint.broadcast!("reactions:my-talk",\n"new_reaction", %{emoji: "🔥"})
        PS-->>LV: handle_info({:new_reaction, "🔥"})
        PS-->>CH: push("new_reaction", %{emoji: "🔥"})
        LV->>Phone: push_event("new_reaction", %{emoji: "🔥"})
        Phone->>Phone: EmojiStream hook → animate emoji
        CH->>EXT: channel message "new_reaction"
        EXT->>EXT: spawnEmoji() → animate emoji on slides
    end
```

### Step by step

**1. Attendee taps a button**

The template uses `phx-click="react"` and `phx-value-emoji="🔥"`. Phoenix
LiveView sends this over the existing WebSocket to `TalkLive.handle_event/3` on
the server. No HTTP request is made.

**2. Rate limiting and persistence**

```elixir
def handle_event("react", %{"emoji" => emoji}, socket) do
  if RateLimiter.allow?(socket.id) do
    slug = socket.assigns.talk.slug
    if session = Talks.get_active_session(socket.assigns.talk.id) do
      Reactions.create_reaction(session, emoji, socket.assigns.current_slide)
    end
    Endpoint.broadcast!("reactions:#{slug}", "new_reaction", %{emoji: emoji})
  end
  {:noreply, socket}
end
```

If a session is active, the reaction is persisted to the database with the current slide number. `current_slide` is tracked in the socket assigns and updated whenever a `slide_changed` message arrives over PubSub (see the Slide Tracking section below).

`RateLimiter` uses an ETS table (an in-memory key/value store built into the
BEAM) to track the last reaction time per session. If less than 3 seconds have
passed, the event is silently dropped.

**3. Broadcasting**

`Endpoint.broadcast!/3` sends the message through `Phoenix.PubSub` to *all
subscribers* of the topic `"reactions:my-talk"`. Two things are subscribed:

- **The LiveView process itself** (subscribed during `mount/3`)
- **Any ReactionChannel processes** (subscribed when the extension joins)

**4a. Back to the attendee's browser**

`TalkLive.handle_info/2` receives the broadcast and pushes a client-side event:

```elixir
def handle_info({:new_reaction, emoji}, socket) do
  {:noreply, push_event(socket, "new_reaction", %{emoji: emoji})}
end
```

The `EmojiStream` JS hook picks this up and animates a floating emoji in the attendee's browser.

**4b. To the speaker's Chrome extension**

`ReactionChannel` also receives the PubSub broadcast and relays it directly to
the WebSocket channel. The extension's content script receives it and calls
`spawnEmoji()`, which creates a floating `<span>` over the slide presentation.

---

## The two websocket connections in detail

### LiveView socket (`/live`)

This powers the attendee's interactive page. Phoenix LiveView manages it
automatically so no manual setup is needed. It handles:

- Sending `phx-click` events from the browser to the server
- Receiving `push_event` calls from the server to run client-side JS hooks
- Keeping the page in sync (diffs)

Configured in `endpoint.ex`:
```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [session: @session_options]]
```

### Channel socket (`/socket`)

This is a bare Phoenix Channel socket, lower-level than LiveView. It's used by
the Chrome extension because the extension isn't a web page; it can't use
LiveView. It only needs to *receive* messages, which Channels handle perfectly.

```elixir
# user_socket.ex
defmodule SpeechwaveWeb.UserSocket do
  use Phoenix.Socket
  channel "reactions:*", SpeechwaveWeb.ReactionChannel

  def connect(_params, socket, _info), do: {:ok, socket}
  def id(_socket), do: nil
end
```

The `"reactions:*"` pattern means the extension can join any topic matching
that prefix (e.g. `"reactions:my-talk"`).

Joining a topic isn't as open as the socket-level pattern above implies —
`ReactionChannel.join/3` requires an `api_key` param and enforces four checks
before accepting the join:

```elixir
def join("reactions:" <> slug, %{"api_key" => api_key}, socket) do
  with {:talk, %Talks.Talk{} = talk} <- {:talk, Talks.get_talk_by_slug(slug)},
       {:user, %Accounts.User{} = user} <- {:user, Accounts.get_user_by_api_key(api_key)},
       {:owner, true} <- {:owner, talk.user_id == user.id},
       {:capacity, :ok} <-
         {:capacity,
          Plans.check(
            :max_participants,
            user.plan,
            Presence.list("reactions:#{slug}") |> map_size()
          )} do
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "user:#{user.id}:disconnect")
    send(self(), :after_join)
    {:ok, assign(socket, talk: talk, user: user)}
  else
    {:talk, nil} -> {:error, %{reason: "not_found"}}
    {:user, nil} -> {:error, %{reason: "unauthorized"}}
    {:owner, false} -> {:error, %{reason: "unauthorized"}}
    {:capacity, {:error, :limit_reached}} -> {:error, %{reason: "capacity_reached"}}
  end
end
```

In plain terms, joining fails with:
- `"not_found"` — the slug doesn't match any talk
- `"unauthorized"` — the API key doesn't resolve to a user, or resolves to a
  user who doesn't own this talk
- `"capacity_reached"` — the talk owner's plan-based participant limit
  (`Plans.limit(:max_participants, plan)`) has already been reached, tracked
  via `Presence.list/1`

These map directly to what the Chrome extension's popup shows when a
connection attempt fails. A successful join also subscribes the channel
process to `"user:#{user.id}:disconnect"` — if the owner logs out or
regenerates their API key elsewhere, the app broadcasts on that topic and the
channel stops itself (`{:stop, :normal, socket}`), forcing the extension to
reconnect with a fresh key.

`check_origin: false` is set on this socket (in `endpoint.ex`) so that the
Chrome extension, which runs from a `chrome-extension://` origin, is allowed
to connect.

```elixir
# endpoint.ex
socket "/socket", SpeechwaveWeb.UserSocket,
  websocket: [check_origin: false]
```

### Why does PubSub connect them?

`Endpoint.broadcast!/3` doesn't know or care whether subscribers are LiveView
processes or Channel processes. It just sends a message to everyone subscribed
to the topic. This is what makes the architecture clean. The `handle_event` in
`TalkLive` doesn't need to know the extension exists.

```mermaid
graph TD
    HE["TalkLive.handle_event\n(react)"] --> BC["Endpoint.broadcast!\nreactions:my-talk\nnew_reaction"]
    BC --> PS["Phoenix.PubSub"]
    PS --> LV["TalkLive process\n(handle_info)"]
    PS --> RC["ReactionChannel process\n(push to extension)"]
    LV --> PEV["push_event to browser\n→ EmojiStream JS hook"]
    RC --> WS["WebSocket message\n→ Chrome extension"]
```

---

## Rate limiting

The `RateLimiter` is a `GenServer` that owns an ETS table. ETS (Erlang Term
Storage) is like a very fast, in-memory hash map built into the BEAM runtime.

```elixir
defmodule Speechwave.RateLimiter do
  use GenServer

  @cooldown_ms 3_000
  @table :rate_limiter

  def allow?(session_id) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, session_id) do
      [{^session_id, last_at}] when now - last_at < @cooldown_ms ->
        false   # too soon
      _ ->
        :ets.insert(@table, {session_id, now})
        true    # allowed — record the timestamp
    end
  end
end
```

The key design choice here is `:public` + `read_concurrency: true` on the ETS
table. This means any process can call `allow?/1` directly without going
through the GenServer. The GenServer just owns the table's lifetime. This
avoids making the GenServer a bottleneck when many attendees are tapping at
once.

The session ID used is `socket.id`, which Phoenix assigns to each LiveView
connection. This means each browser tab gets its own rate limit bucket.

There's also a *client-side* rate limit in `emoji_buttons.js`. Buttons are
disabled for 3 seconds with a visible countdown. This is just UX; the real
enforcement is server-side.

---

## The Chrome extension

The extension has two parts:

**Popup (`popup.html` + `popup.js`)** — A small UI that appears when you click
the extension icon. The speaker enters the talk slug and clicks "Connect". The
popup sends a message to the content script via `chrome.runtime.sendMessage`.

**Content script (`content.js`)** — Injected into Google Slides pages. It:

1. Connects a Phoenix `Socket` to `wss://speechwave.fly.dev/socket`
2. Joins the `reactions:${slug}` channel
3. Listens for `"new_reaction"` messages and calls `spawnEmoji()`

```mermaid
graph LR
    PP["Popup UI\n(enters slug)"] -->|chrome.runtime\n.sendMessage| CS["Content Script\n(runs in Slides tab)"]
    CS -->|"Phoenix Socket\n/socket"| PH["Phoenix Server\nReactionChannel"]
    PH -->|"new_reaction\n{emoji}"| CS
    CS --> OV["Overlay div\n(floats over slides)"]
```

### Fireworks animation

When the crowd converges on a single emoji, a radial burst animation fires in the overlay instead of individual floaters. The trigger condition is intentionally compound:

```
count(emoji) >= FIREWORKS_MIN_COUNT  &&  count(emoji) / total_in_flight >= FIREWORKS_MIN_PERCENT
```

The absolute count guard (`MIN_COUNT = 5`) prevents bursts from firing with tiny audiences. The percentage guard (`MIN_PERCENT = 0.4`) prevents bursts from firing when the crowd is sending many different emojis — it requires this emoji to be dominant, not merely frequent. A global cooldown (`FIREWORKS_COOLDOWN_MS = 8000`) prevents back-to-back bursts, and only one burst can play at a time (`fireworksActive` flag).

**In-flight tracking** — `spawnEmoji()` increments a per-emoji counter (`inFlight["❤️"]++`) when an element is created, and decrements it in the `animationend` listener when the element is removed. The 2.5s animation duration acts as a natural sliding window: `total_in_flight` reflects reactions from the last ~2.5 seconds, making it a real-time proxy for current crowd engagement.

**Trigger logic** is extracted to `lib/fireworks.js` in the [chrome-extension repo](https://github.com/speechwave-live/chrome-extension) as a pure function (`checkFireworksTrigger(inFlight, emoji, opts)`) that is easy to unit test with Jest without a browser environment. The file uses the same dual-export pattern as the adapter modules — `module.exports` for Jest, `window.SpeechwaveFireworks` for the browser.

**Burst animation** — `spawnFireworks()` creates `FIREWORKS_BURST_COUNT` (16) `<span>` elements at the overlay center, each animated outward at a unique angle using the Web Animations API:

```javascript
el.animate(
  [
    { transform: "translate(0, 0) scale(1)", opacity: 1 },
    { transform: `translate(${tx}px, ${ty}px) scale(0.3)`, opacity: 0 },
  ],
  { duration: 1200, delay, easing: "ease-out", fill: "forwards" }
);
```

The Web Animations API is used (rather than CSS `@keyframes`) because each element needs a unique computed `translate(tx, ty)` target. A safety timeout resets `fireworksActive` after 2 seconds in case `finish` events fail to fire (e.g., when the overlay is re-parented during a fullscreen transition).

**Presenter toggle** — The popup's "Fireworks animations" checkbox writes to `chrome.storage.sync` and sends a `SET_FIREWORKS` message to the content script. `content.js` reads the stored value on init so the preference survives page reloads.

One tricky detail: when the speaker enters fullscreen mode in Google Slides,
the browser creates a new stacking context for the fullscreen element.  Any
`position: fixed` elements on `<body>` become invisible. The extension handles
this by re-parenting the overlay `<div>` into the fullscreen element when a
`fullscreenchange` event fires:

```javascript
document.addEventListener("fullscreenchange", () => {
  const overlay = document.getElementById("speechwave-overlay");
  if (document.fullscreenElement) {
    document.fullscreenElement.appendChild(overlay); // move into fullscreen
  } else {
    document.body.appendChild(overlay);              // move back
  }
});
```

---

## LiveView mount and subscription

When an attendee navigates to `/t/my-talk`, Phoenix renders `TalkLive`. The
`mount/3` callback runs twice: once server-side for the initial HTML render,
and once after the WebSocket connects:

```elixir
def mount(%{"slug" => slug}, _session, socket) do
  talk = Talks.get_talk_by_slug(slug)

  if connected?(socket) do
    Endpoint.subscribe("reactions:#{slug}")
  end

  {:ok, assign(socket, talk: talk, emojis: ["❤️", "😂", "🔥", "👏", "🤯"])}
end
```

`connected?(socket)` is `false` on the first (HTTP) render and `true` after the
WebSocket upgrades. Subscribing only when connected avoids duplicate
subscriptions and wasted work during the initial render.

If the slug doesn't exist in the database, the LiveView redirects to the home page:

```elixir
case Talks.get_talk_by_slug(slug) do
  nil  -> {:ok, push_navigate(socket, to: ~p"/")}
  talk -> {:ok, assign(socket, talk: talk, ...)}
end
```

---

## Dashboard flow

There's no HTTP Basic Auth admin panel anymore — the Dashboard at
`/dashboard` requires a logged-in user. Login is magic-link (the app emails a
one-time token) or OAuth (Google, Microsoft, or GitHub, via `/auth/:provider`
— see the Routing section above); there's no username/password.

From the Dashboard, a speaker can:

1. Create a talk: enter a title, the slug is auto-generated, and the talk is
   scoped to the logged-in user (`Talks.create_talk(scope, attrs)` sets
   `user_id` from `scope.user.id`)
2. Get a QR code: the `QRCode` module wraps `EQRCode` to generate a PNG
   encoded as a base64 data URI, ready to embed in an `<img>` tag or download

The QR code encodes the talk's full attendee URL via
`SpeechwaveWeb.Endpoint.url() <> "/t/#{talk.slug}"` (e.g.
`https://speechwave.live/t/my-talk`), so speakers can display it on their
first slide.

`User` has an `is_admin` boolean field, and the Dashboard shows a "Super-admin
controls coming soon" placeholder banner to admins — but the super-admin
panel itself isn't built yet (it's a roadmap item). Don't take that banner as
a sign a working admin panel exists.

---

## Supervision tree

Every long-lived process in Elixir/OTP lives under a supervisor. Here's
Speechwave's:

```mermaid
graph TD
    APP["Speechwave.Application\n(supervisor)"] --> TEL["Telemetry supervisor"]
    APP --> REPO["Speechwave.Repo\n(Ecto / SQLite)"]
    APP --> DNS["DNSCluster\n(multi-node discovery)"]
    APP --> PS["Phoenix.PubSub\n(name: Speechwave.PubSub)"]
    APP --> RL["Speechwave.RateLimiter\n(GenServer + ETS)"]
    APP --> AT["Speechwave.AuthThrottle\n(magic-link send throttling)"]
    APP --> EP["SpeechwaveWeb.Endpoint\n(HTTP + WebSockets)"]
    APP --> PR["SpeechwaveWeb.Presence\n(Channel capacity tracking)"]
    APP -.->|"if STORAGE_BUCKET set"| DB["Speechwave.DbBackup\n(hourly SQLite backup)"]
```

If `RateLimiter` crashes, the supervisor restarts it automatically. When it
restarts, the ETS table is recreated empty and this is fine, it just means the
cooldown state is lost and everyone gets a fresh window to react.

`Speechwave.DbBackup` only starts when a `STORAGE_BUCKET` environment
variable is configured (production); see `docs/administration.md` for the
backup/restore runbook.

---

## Talk sessions

A *session* is a recording window. The speaker starts one (via the extension popup or `start_session` channel message) before presenting, and stops it afterward. Reactions recorded while a session is active are persisted with a slide number for later analytics.

Session lifecycle is managed in `Speechwave.Talks`:

- `start_session/1` — idempotent: returns the existing active session if one is open, otherwise creates a new one labeled "Session N" where N is one more than the total number of sessions for that talk.
- `stop_session/1` — idempotent: if `ended_at` is already set, returns the session unchanged.
- `get_active_session/1` — queries for a session with `ended_at IS NULL`.
- `list_sessions/1` — returns sessions with reaction counts, newest first.
- `rename_session/2`, `delete_session/1` — admin operations.

The `ReactionChannel` exposes `start_session` and `stop_session` as channel messages so the Chrome extension can control sessions without going through the web UI.

---

## Slide tracking

When the speaker's Chrome extension is connected, it detects the current slide number and sends `slide_changed` messages to the server so reactions can be stamped with slide context.

### Adapter registry

Different presentation tools expose the current slide number differently. The extension uses an **adapter registry** (`adapters/index.js` in the [chrome-extension repo](https://github.com/speechwave-live/chrome-extension)) that picks the right adapter based on the current page URL:

```javascript
// index.js
function getAdapter(url) {
  if (url.includes("docs.google.com/presentation")) {
    return GoogleSlidesAdapter;
  }
  return { getSlide: () => 0 };  // fallback for unknown platforms
}
```

The Google Slides adapter (`adapters/google_slides.js`) reads the slide number from the DOM:

```javascript
function getSlide() {
  const input = document.querySelector('input[aria-label*="Slide"]');
  if (!input) return 0;
  const n = parseInt(input.value, 10);
  return isNaN(n) ? 0 : n;
}
```

This is brittle by nature (Google could change the DOM), but it's the only option without a first-party API. The fixture-based Jest tests in `tests/` (chrome-extension repo) snapshot the relevant DOM so regressions are caught before they ship.

### MutationObserver

The content script sets up a `MutationObserver` to watch for attribute changes on the slide input:

```javascript
function startSlideObserver() {
  const observer = new MutationObserver(() => {
    const slide = getAdapter(window.location.href).getSlide();
    if (slide !== currentSlide && slide > 0) {
      currentSlide = slide;
      channel.push("slide_changed", { slide });
    }
  });
  observer.observe(document.body, {
    subtree: true,
    attributeFilter: ["value", "aria-label"]
  });
}
```

Slide `0` is a sentinel for "unknown" and is never sent — the server silently ignores it too.

The popup also displays the current slide number in real time ("Slide 3" or "Slide —" for unknown). This serves as an immediate sanity check that the adapter is reading the DOM correctly — if the number doesn't update when you advance slides, the DOM structure has changed and the adapter selector needs updating.

### Server-side handling

`ReactionChannel` handles `slide_changed` and broadcasts to a separate `"slides:#{slug}"` PubSub topic:

```elixir
def handle_in("slide_changed", %{"slide" => slide}, socket)
    when is_integer(slide) and slide > 0 do
  Endpoint.broadcast!("slides:#{socket.assigns.talk.slug}", "slide_changed", %{slide: slide})
  {:reply, :ok, socket}
end
```

`TalkLive` subscribes to this topic and updates `current_slide` in its assigns, so the next reaction tap carries the correct slide number.

---

## Analytics dashboard

After a talk, the speaker can review per-slide engagement at `/admin/sessions/:id`.

### The query

`Reactions.slide_reaction_totals/1` aggregates reactions by `(slide_number, emoji)`:

```elixir
def slide_reaction_totals(session_id) do
  from(r in Reaction,
    where: r.talk_session_id == ^session_id,
    group_by: [r.slide_number, r.emoji],
    select: %{slide_number: r.slide_number, emoji: r.emoji, count: count(r.id)},
    order_by: [asc: r.slide_number]
  )
  |> Repo.all()
end
```

`SessionAnalyticsLive` groups these by `slide_number` into a map and renders a Tailwind bar chart per slide — no JS charting library needed.

### Comparison mode

At `/admin/sessions/:id/compare/:other_id`, `SessionAnalyticsLive` loads both sessions and renders two charts side by side. The comparison covers all slides that appeared in *either* session (union of slide numbers), so gaps are visible.

The admin sessions panel links to the analytics view for each session via `navigate={"/admin/sessions/#{session.id}"}`.

---



| Concept                 | What it does in Speechwave                                                         |
| ----------------------- | ------------------------------------------------------------------------------- |
| **LiveView**            | Powers the attendee tap page; manages WebSocket lifecycle automatically         |
| **Phoenix Channel**     | Lower-level WebSocket used by the Chrome extension to receive events            |
| **PubSub**              | The message bus; `broadcast!` sends to all subscribers regardless of type       |
| **GenServer**           | The RateLimiter is a GenServer that owns an ETS table                           |
| **ETS**                 | Fast in-memory storage for rate limit timestamps; bypasses GenServer bottleneck |
| **phx-hook**            | Bridges server events to client-side JavaScript (EmojiStream, EmojiButtons)     |
| **push_event**          | Server → client event delivery over the LiveView socket                         |
| **check_origin: false** | Allows the Chrome extension (different origin) to open a socket                 |
| **TalkSession**         | A recording window; reactions are persisted against the active session          |
| **slide_number**        | Stamped on each reaction; `0` is the sentinel for "unknown slide"               |
| **Adapter registry**    | Picks the right DOM scraper based on the presentation platform URL              |
| **MutationObserver**    | Watches the Google Slides DOM for slide changes without polling                 |
| **slide_changed**       | Channel event from extension → server → PubSub → TalkLive assigns              |
| **SessionAnalyticsLive**| Admin-only LiveView: per-slide bar charts and session comparison mode           |
| **in-flight tracking**  | Per-emoji count of currently animating spans; the 2.5s animation is a sliding window |
| **checkFireworksTrigger** | Pure function: `count >= minCount && count/total >= minPercent`               |
| **fireworksActive**     | Global flag preventing concurrent bursts; safety-reset by timeout after 2s     |
| **Web Animations API**  | Used for fireworks burst so each particle gets a unique computed trajectory     |

