# Speechwave

Live emoji reactions for conference talks. Attendees send reactions from their
phones; emojis float on their screens and overlay the speaker's Google Slides
presentation via a Chrome extension.

## How it works

1. Speaker creates a talk in the dashboard → gets a QR code
2. Attendees scan the QR code → land on `/t/<slug>` → tap emojis
3. Reactions broadcast in real time via Phoenix PubSub
4. Chrome extension connected to the same talk slug shows floating emoji overlay on Google Slides — when enough attendees send the same emoji at once, a fireworks burst animation plays
5. Speaker starts a session from the extension (or via the channel) — reactions are persisted with a slide number
6. After the talk, the analytics view shows per-slide reaction breakdowns; sessions from the same talk can be compared side-by-side

For a full explainer on the technical implementation see [this explainer](https://docs.speechwave.live/dev/explainer/index.html).
For the story of writing the project (the whys and the bugs), see [this blog post](https://tracyatteberry.com/posts/speechwave/).

---

![Architecture](docs/architecture.png)

---

![Chrome extension](docs/chrome_extension.png)

---

## Running locally

### Prerequisites

- Elixir 1.14+ / Erlang 26+
- Node.js (for asset building, handled by Mix)

No separate database server needed — Speechwave uses SQLite (file-based, via `ecto_sqlite3`).

### Setup

```bash
mix setup        # installs deps, creates & migrates DB, builds assets
mix phx.server   # starts the server at http://localhost:4000
```

Log in at `http://localhost:4000/users/log-in` via magic link (email sent to
`/dev/mailbox`) or use the dev backdoor at `http://localhost:4000/dev/login`
to authenticate instantly without email. The main dashboard is at
`http://localhost:4000/dashboard`.

### Running tests

```bash
mix test                        # run all Elixir tests
mix test test/path/to/file.exs  # run a single test file
mix test --failed               # re-run only previously failing tests
```

The Chrome extension lives in a separate repo ([speechwave-live/chrome-extension](https://github.com/speechwave-live/chrome-extension)) and has its own Jest test suite — see that repo's README for instructions.

### End-to-end test flow

1. Start the server: `mix phx.server`
2. Go to `http://localhost:4000/dev/login` and log in (or create a new user by entering any email)
3. Go to `http://localhost:4000/dashboard` and create a new talk
4. Enter a title (slug auto-generates from title), click **Create Talk**
5. A QR code appears — note the slug (e.g. `my-talk`)
6. Open `http://localhost:4000/t/my-talk` in another tab
7. Tap an emoji — it should float up on the attendee page
8. (Optional) Load the Chrome extension pointed at `my-talk` and open a Google Slides presentation. Connect the extension, then start the slideshow (click **Slideshow** or press F5 — it stays on the same tab and goes fullscreen). Open the extension popup — it shows the current slide number ("Slide 3") updating in real time, confirming the adapter is reading the DOM correctly. The slide number only appears once the slideshow is running; it shows "Slide —" in the editor view.
9. (Optional) In the extension popup, click **Start Session** — reactions are now persisted with slide numbers
10. After tapping some emojis, go to `http://localhost:4000/dashboard` → select the talk → click **Analytics** next to the session to see the per-slide breakdown

---

## Chrome extension

The Chrome extension lives in its own repo: [speechwave-live/chrome-extension](https://github.com/speechwave-live/chrome-extension).

See that repo's README for install instructions, local dev setup, and troubleshooting.

---

## Changing the emoji set

Edit the `@emojis` module attribute in `lib/speechwave_web/live/talk_live.ex`:

```elixir
@emojis ["❤️", "😂", "🔥", "👏", "🤯"]
```

Add, remove, or reorder emojis here. No other changes needed — the template loops over this list.

---

## Deploying to Fly.io

### First-time setup

```bash
fly auth login
fly launch --name speechwave --region iad --no-deploy
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set ADMIN_PASSWORD=choose-a-strong-password
fly secrets set RESEND_API_KEY=re_...
fly deploy
```

### OAuth providers (optional)

To enable Google, GitHub, and/or Microsoft sign-in, set the corresponding
secrets before deploying. Any provider whose `CLIENT_ID` is absent is silently
omitted from the login page.

```bash
# Google
fly secrets set GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=...

# GitHub
fly secrets set GITHUB_CLIENT_ID=... GITHUB_CLIENT_SECRET=...

# Microsoft
fly secrets set MICROSOFT_CLIENT_ID=... MICROSOFT_CLIENT_SECRET=...
# Optionally restrict to a single tenant (default is "common"):
fly secrets set MICROSOFT_TENANT_ID=...
```

### Subsequent deploys

```bash
fly deploy
```

Migrations run automatically on each deploy (configured in `fly.toml` via `[deploy] release_command`).

### Setting / resetting the admin password

```bash
fly secrets set ADMIN_PASSWORD=new-strong-password
fly deploy   # restart the app to pick up the new secret
```

The password takes effect after the next deploy (Fly restarts the app when
secrets change, but the config is read at boot via `Application.get_env`).

To verify the current secret is set (without revealing it):

```bash
fly secrets list
```

---

## Project structure

| Path                                              | What it does                                                   |
| ------------------------------------------------- | -------------------------------------------------------------- |
| `lib/speechwave/talks.ex`                            | Context: talks + session lifecycle (start, stop, rename, etc.) |
| `lib/speechwave/talks/talk.ex`                       | Ecto schema + changeset validation                             |
| `lib/speechwave/talks/talk_session.ex`               | TalkSession schema (label, started_at, ended_at)               |
| `lib/speechwave/reactions.ex`                        | Context: create reactions, per-slide totals query              |
| `lib/speechwave/reactions/reaction.ex`               | Reaction schema (emoji, slide_number, talk_session_id)         |
| `lib/speechwave/accounts.ex`                         | Context: users, magic link tokens, OAuth identity upsert       |
| `lib/speechwave/accounts/user.ex`                    | User schema (email, api_key, plan, is_admin)                   |
| `lib/speechwave/accounts/user_identity.ex`           | OAuth identity link (provider + uid → user)                    |
| `lib/speechwave/rate_limiter.ex`                     | ETS-backed GenServer: 1 reaction per session per 5s            |
| `lib/speechwave/qr_code.ex`                          | Wraps `eqrcode` → base64 PNG data URI                          |
| `lib/speechwave_web/live/dashboard_live.ex`          | Speaker dashboard: create talks, QR codes, sessions panel      |
| `lib/speechwave_web/live/session_analytics_live.ex`  | Per-session analytics: slide breakdown + comparison mode       |
| `lib/speechwave_web/live/talk_live.ex`               | Attendee page: emoji buttons, stamps reactions with slide      |
| `lib/speechwave_web/live/user_live/login.ex`         | Magic link + OAuth login/signup page                           |
| `lib/speechwave_web/live/user_live/settings.ex`      | User settings: connected OAuth accounts                        |
| `lib/speechwave_web/channels/reaction_channel.ex`    | Channel: reactions, session start/stop, slide_changed          |
| `lib/speechwave_web/controllers/user_session_controller.ex` | Magic link verification, OAuth initiation + callback    |
| `lib/speechwave_web/controllers/dev_login_controller.ex`    | Dev-only login bypass (never compiled in prod)          |
| `lib/speechwave_web/plugs/admin_auth.ex`             | HTTP Basic Auth plug for admin routes                          |
| `assets/js/hooks/emoji_buttons.js`                | Client-side 5s cooldown UI                                     |
| `assets/js/hooks/emoji_stream.js`                 | Floating emoji animation on `new_reaction` event               |
| [speechwave-live/chrome-extension](https://github.com/speechwave-live/chrome-extension) | Chrome Manifest V3 extension (separate repo) |
