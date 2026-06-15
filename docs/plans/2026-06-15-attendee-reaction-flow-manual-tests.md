# Attendee Reaction Flow Manual Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/manual_tests/seed_active_session.exs` and `scripts/manual_tests/reaction_flow.sh`, wire `reaction_flow.sh` into `run_all_dev.sh`, document it in `docs/manual_tests.md`, and remove the now-actively-planned "Manual test: attendee reaction flow" item from `docs/roadmap.md`, per `docs/specs/2026-06-15-attendee-reaction-flow-manual-tests-design.md`.

**Architecture:** `seed_active_session.exs` is a `mix run` script (same pattern as `seed_sessions.exs`) that seeds one talk with one **active** (unstopped) session and no reactions. `reaction_flow.sh` sources `scripts/manual_tests/lib.sh`, seeds via that script, then drives **two simultaneous rodney tabs** on `/t/<slug>` — "Device A" taps reactions, "Device B" only observes — asserting on the real-time `.floating-emoji` broadcast, the `#emoji-buttons` cooldown UI, cross-device delivery, and finally (via `complete_magic_link_login`) reaction persistence on `/sessions/<id>`.

**Tech Stack:** Bash (macOS default `/bin/bash` 3.2), `rodney` CLI (multi-tab: `newpage`/`page`/`closepage`/`assert`), Phoenix dev server (`mix phx.server`), `/dev/mailbox`, `mix run` for `seed_active_session.exs`.

**Verified against the running dev server (`http://localhost:4000`) during planning:**

- **Emoji buttons:** `lib/speechwave_web/live/talk_live.html.heex:14-27` renders `<div id="emoji-buttons" phx-hook="EmojiButtons" class="flex flex-col gap-2">` containing one `<button phx-click="react" phx-value-emoji={emoji}>` per emoji in `@emojis = ["❤️", "😂", "👏", "🤯", "🙋🏻", "🎉", "💩", "😮", "🎯"]` (`talk_live.ex:6`), plus `<span class="cooldown-label ...">`. `❤️` and `😂` are both valid.
- **Full tap chain confirmed end-to-end** (fresh `rodney start` → `rodney open "$BASE_URL/t/<slug>"` → `rodney waitload`, talk_id=24/slug=`manualtestexplore2`/session_id=24, user `manual-test-explore-2@example.com`): `rodney click '[phx-value-emoji="❤️"]'` → `phx-click="react"` → `RateLimiter.allow?/1` (3000ms cooldown, `lib/speechwave/rate_limiter.ex:10`) → since `Talks.get_active_session(talk.id)` is non-nil, `Reactions.create_reaction/3` persists the reaction → `Endpoint.broadcast!("reactions:<slug>", "new_reaction", %{emoji: emoji})` → `push_event` → `EmojiStream` hook appends `.floating-emoji` (2.5s `floatUp` animation) AND `EmojiButtons` hook's `setTimeout(0)` adds `cooling-down` to `#emoji-buttons`, sets `disabled` on every button, and sets `.cooldown-label` to `"Cooling down… 3s"`, ticking down every 1000ms to `"Tap to react"` at t=3000ms.
- **Timing — combine all post-tap assertions into ONE invocation, immediately after the click + a short `rodney sleep 0.2`.** Confirmed: right after `rodney click '[phx-value-emoji="❤️"]'` + `rodney sleep 0.2`, a single combined check showed `.floating-emoji` count=1/text="❤️", `#emoji-buttons` class=`"flex flex-col gap-2 cooling-down"`, `[phx-value-emoji="❤️"]` has `disabled` (exit 0), `.cooldown-label`=`"Cooling down… 3s"`. A *separate, later* invocation (even ~1-2s later) found `.floating-emoji` already removed (2.5s animation done) and the cooldown already expired (3s done) — both windows are short, so don't split a tap's assertions across multiple `rodney` invocations with gaps.
- **After `rodney sleep 4`,** cooldown fully expires: `#emoji-buttons` class returns to `"flex flex-col gap-2"`, `disabled` is removed (exit 2, "attribute not found"), `.cooldown-label`=`"Tap to react"`.
- **`rodney attr <selector> disabled`:** prints `"true"` + exit 0 when present; prints `error: attribute "disabled" not found` + exit 2 when absent. Under `set -euo pipefail`, only use this inside `if`/`&&`/`!` conditions — never as a bare `var=$(...)` assignment (a non-zero exit there would abort the script).
- **Multi-tab focus is unreliable from `rodney newpage` alone** — across separate calls in this session, the new tab was sometimes auto-focused and sometimes not. **Always call `rodney page <N>` explicitly** before interacting with a tab; never rely on `newpage`'s implicit focus. `rodney pages` lists `  [N] ...` (unfocused) vs `* [N] ...` (focused). `rodney closepage <N>` closes tab N; afterward the remaining tab 0 is left focused automatically (confirmed: `rodney closepage 1` → `rodney pages` shows `* [0] ...`) — the script still calls `rodney page 0` explicitly afterward for clarity.
- **Cross-device broadcast confirmed end-to-end** (fresh `rodney start`, talk_id=24): with Device A (tab 0) focused, `rodney click '[phx-value-emoji="😂"]'` + `rodney sleep 0.2` shows `.floating-emoji`/cooldown active on tab 0. Then `rodney page 1` (no extra sleep/`waitload` needed — tab 1 was already loaded) → an immediate combined check on tab 1 shows `.floating-emoji` count=1/text="😂" (the broadcast reached Device B), `#emoji-buttons` class=`"flex flex-col gap-2"` (no `cooling-down`), `.cooldown-label`=`"Tap to react"`, and `[phx-value-emoji="😂"]` has no `disabled` (exit 2) — confirms the rate limiter is per-attendee (keyed by `socket.id`, `talk_live.ex:20` / `rate_limiter.ex`), not global.
- **Background-tab animation-pause + accumulation risk** (confirmed in an earlier verification pass with talk_id=23): an unfocused tab pauses the `.floating-emoji` `floatUp` CSS animation, so a stale element from an *earlier* tap can still be in the DOM when the *second* broadcast arrives. **Use `rodney assert` with a "some" expression instead of `count`+`text`:**
  ```
  rodney assert "Array.from(document.querySelectorAll('.floating-emoji')).some(el => el.textContent.trim() === '<emoji>')"
  ```
  `rodney assert <expr>` (no expected arg) is a truthy assertion: prints `pass` + exit 0 if truthy, prints `fail: got <value>` + exit non-zero otherwise (confirmed both outcomes).
- **`seed_active_session.exs` logic verified end-to-end via `mix run -e`** with the same pattern as `seed_sessions.exs`: `Accounts.register_or_get_user_by_email/1` → `Scope.for_user/1` → `Talks.create_talk(scope, %{title: title, slug: Talks.generate_slug(title)})` → `Talks.start_session/1` (no `stop_session` call, so `Talks.get_active_session(talk.id)` stays non-nil for the whole run). `Talks.generate_slug("manual-test-explore-2")` → `"manualtestexplore2"` (hyphens stripped, matching the prior plan's documented behavior).
- **`/sessions/<id>` for an ACTIVE (unstopped) session renders identically to a stopped one:** `#total-reactions` (`session_analytics_live.html.heex:20`, plain integer as text) and `#slide-row-0` (id is `slide-row-#{slide_number}`, `session_analytics_live.html.heex:46`) with a "General" label (slide 0) followed by each emoji + its count as text content. Confirmed live (talk_id=24/session_id=24, after several test taps): `#total-reactions`="6", `#slide-row-0` text = "General\n❤️\n2\n😂\n2\n🎉\n1\n👏\n1". For this script's exact 2-tap flow (❤️ once, 😂 once, nothing else), expect `#total-reactions`="2" and `#slide-row-0` containing "General", "❤️", and "😂".
- **Seeded talks are NOT auto-selected on `/dashboard`** (unlike talks created via the UI form) — `#delete-talk-<id>` doesn't exist until the talk is selected via `rodney click "#talk-list li button"` (single match for one seeded talk, `phx-click="show_qr"`, no `id` — same pattern as `session_analytics.sh`) + `rodney waitstable`.
- **Sign-out confirmed end-to-end:** `rodney click 'a[href="/users/log-out"]'` + `rodney waitload`, then `rodney open "$BASE_URL/dashboard"` + `rodney waitload` → redirects to `/users/log-in`.
- **`complete_magic_link_login` works unchanged** for the seeded talk's owner (confirmed end-to-end with `manual-test-explore-2@example.com`).

---

### Task 1: Create `scripts/manual_tests/seed_active_session.exs`

**Files:**
- Create: `scripts/manual_tests/seed_active_session.exs`

- [ ] **Step 1: Write the file**

```elixir
# Manual integration test fixture: seeds a talk with one active (unstopped)
# session and no reactions, for scripts/manual_tests/reaction_flow.sh.
# See docs/manual_tests.md.
#
# Usage: mix run scripts/manual_tests/seed_active_session.exs <email>
#
# Prints email=, talk_id=, talk_slug=, session_id= on stdout.

alias Speechwave.{Accounts, Talks}
alias Speechwave.Accounts.Scope

[email | _] = System.argv()

{:ok, user} = Accounts.register_or_get_user_by_email(email)
scope = Scope.for_user(user)

title = "manual-test-#{System.system_time(:second)}"
slug = Talks.generate_slug(title)
{:ok, talk} = Talks.create_talk(scope, %{title: title, slug: slug})

{:ok, session} = Talks.start_session(talk)

IO.puts("email=#{email}")
IO.puts("talk_id=#{talk.id}")
IO.puts("talk_slug=#{talk.slug}")
IO.puts("session_id=#{session.id}")
```

- [ ] **Step 2: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`. If not, start it with `mix phx.server` (in another terminal/background) before continuing.

- [ ] **Step 3: Run it against the dev database**

```bash
mix run scripts/manual_tests/seed_active_session.exs "manual-test-$(date +%s)@example.com" 2>/dev/null
```

Expected output (numbers/timestamp will differ):

```
email=manual-test-<timestamp>@example.com
talk_id=<N>
talk_slug=manualtest<timestamp>
session_id=<M>
```

- [ ] **Step 4: Commit**

```bash
git add scripts/manual_tests/seed_active_session.exs
git commit -m "feat: add seed_active_session.exs manual-test fixture script"
```

---

### Task 2: Create `scripts/manual_tests/reaction_flow.sh`

**Files:**
- Create: `scripts/manual_tests/reaction_flow.sh`

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# Manual integration test for the attendee reaction flow (TalkLive, /t/:slug):
# real-time emoji broadcast across devices, the rate-limit cooldown UI, and
# reaction persistence to an active session.
# See docs/manual_tests.md for how to read the results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

parse_base_url "$@"

if ! is_local; then
  echo "ERROR: reaction_flow.sh requires a local --base-url (uses /dev/mailbox via complete_magic_link_login, and mix run for seeding)." >&2
  echo "Re-run with --base-url http://localhost:4000" >&2
  exit 1
fi

EMAIL="manual-test-$(date +%s)@example.com"
echo "Seeding active session for $EMAIL"

seed_output=$(cd "$PROJECT_ROOT" && mix run scripts/manual_tests/seed_active_session.exs "$EMAIL" 2>/dev/null)
talk_id=$(echo "$seed_output" | grep '^talk_id=' | cut -d= -f2 || true)
talk_slug=$(echo "$seed_output" | grep '^talk_slug=' | cut -d= -f2 || true)
session_id=$(echo "$seed_output" | grep '^session_id=' | cut -d= -f2 || true)

if [ -z "$talk_id" ] || [ -z "$talk_slug" ] || [ -z "$session_id" ]; then
  echo "FAIL: could not parse seed_active_session.exs output:" >&2
  echo "$seed_output" >&2
  exit 1
fi
echo "Seeded talk_id=$talk_id talk_slug=$talk_slug session_id=$session_id"

start_rodney

# assert_floating_emoji EMOJI LABEL
#
# Checks that a .floating-emoji element with the given text exists on the
# currently-focused tab. Uses a "some" check (not count+text) because a
# backgrounded tab pauses the floatUp animation, so a stale element from an
# earlier tap may still be present alongside the new one.
assert_floating_emoji() {
  local emoji="$1"
  local label="$2"
  if rodney assert "Array.from(document.querySelectorAll('.floating-emoji')).some(el => el.textContent.trim() === '$emoji')" >/dev/null 2>&1; then
    echo "PASS: $label shows .floating-emoji $emoji"
  else
    echo "FAIL: $label did not show .floating-emoji $emoji" >&2
    exit 1
  fi
}

# assert_cooldown_active LABEL EMOJI
#
# Checks #emoji-buttons is in its cooling-down state for the given emoji
# button (cooling-down class, disabled button, "Cooling down… 3s" label).
assert_cooldown_active() {
  local label="$1"
  local emoji="$2"
  local class label_text
  class=$(rodney attr "#emoji-buttons" class)
  label_text=$(rodney text ".cooldown-label")
  if echo "$class" | grep -q "cooling-down" \
    && rodney attr "[phx-value-emoji=\"$emoji\"]" disabled >/dev/null 2>&1 \
    && [ "$label_text" = "Cooling down… 3s" ]; then
    echo "PASS: $label cooldown active (cooling-down class, buttons disabled, '$label_text')"
  else
    echo "FAIL: $label cooldown not active as expected (class='$class', label='$label_text')" >&2
    exit 1
  fi
}

# assert_cooldown_idle LABEL EMOJI
#
# Checks #emoji-buttons is idle for the given emoji button (no cooling-down
# class, button enabled, "Tap to react" label).
assert_cooldown_idle() {
  local label="$1"
  local emoji="$2"
  local class label_text
  class=$(rodney attr "#emoji-buttons" class)
  label_text=$(rodney text ".cooldown-label")
  if ! echo "$class" | grep -q "cooling-down" \
    && ! rodney attr "[phx-value-emoji=\"$emoji\"]" disabled >/dev/null 2>&1 \
    && [ "$label_text" = "Tap to react" ]; then
    echo "PASS: $label cooldown idle (no cooling-down class, buttons enabled, '$label_text')"
  else
    echo "FAIL: $label cooldown not idle as expected (class='$class', label='$label_text')" >&2
    exit 1
  fi
}

TALK_URL="$BASE_URL/t/$talk_slug"

# --- Open both devices on the talk page ---

rodney open "$TALK_URL" >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#emoji-buttons" >/dev/null; then
  echo "FAIL: #emoji-buttons did not render on Device A ($TALK_URL)" >&2
  exit 1
fi
echo "PASS: Device A opened $TALK_URL, #emoji-buttons present"

rodney newpage "$TALK_URL" >/dev/null
rodney page 1 >/dev/null
rodney waitload >/dev/null
if ! rodney exists "#emoji-buttons" >/dev/null; then
  echo "FAIL: #emoji-buttons did not render on Device B ($TALK_URL)" >&2
  exit 1
fi
echo "PASS: Device B opened $TALK_URL, #emoji-buttons present"

# --- First tap (Device A): heart ---

rodney page 0 >/dev/null
rodney click '[phx-value-emoji="❤️"]' >/dev/null
rodney sleep 0.2 >/dev/null
assert_floating_emoji "❤️" "Device A"
assert_cooldown_active "Device A" "❤️"

# --- Cross-device check #1: Device B sees the same broadcast ---

rodney page 1 >/dev/null
assert_floating_emoji "❤️" "Device B"
assert_cooldown_idle "Device B" "❤️"

# --- Wait for cooldown, then second tap (Device A): laughing ---

rodney page 0 >/dev/null
rodney sleep 4 >/dev/null
assert_cooldown_idle "Device A" "❤️"

rodney click '[phx-value-emoji="😂"]' >/dev/null
rodney sleep 0.2 >/dev/null
assert_floating_emoji "😂" "Device A"

# --- Cross-device check #2: Device B sees the second broadcast ---

rodney page 1 >/dev/null
assert_floating_emoji "😂" "Device B"

rodney closepage 1 >/dev/null
rodney page 0 >/dev/null

# --- Verify persistence ---

complete_magic_link_login "$BASE_URL" "$EMAIL"
echo "PASS: logged in via magic link, #talk-list present on /dashboard"

rodney open "$BASE_URL/sessions/$session_id" >/dev/null
rodney waitload >/dev/null
total_reactions=$(rodney text "#total-reactions")
slide0=$(rodney text "#slide-row-0")
if [ "$total_reactions" = "2" ] \
  && echo "$slide0" | grep -q "General" \
  && echo "$slide0" | grep -q "❤️" \
  && echo "$slide0" | grep -q "😂"; then
  echo "PASS: /sessions/$session_id shows #total-reactions=2, #slide-row-0 (General, ❤️, 😂)"
else
  echo "FAIL: expected #total-reactions=2 and #slide-row-0 with General/❤️/😂; got total_reactions=$total_reactions slide0='$slide0'" >&2
  exit 1
fi

# --- Cleanup: delete the seeded talk ---

rodney open "$BASE_URL/dashboard" >/dev/null
rodney waitload >/dev/null
rodney click "#talk-list li button" >/dev/null
rodney waitstable >/dev/null
confirm_and_click "#delete-talk-$talk_id"
rodney waitstable >/dev/null
if rodney exists "#delete-talk-$talk_id" >/dev/null; then
  echo "FAIL: #delete-talk-$talk_id still present after delete" >&2
  exit 1
fi
echo "PASS: talk $talk_id deleted (cleanup)"

# --- Sign out ---

rodney click 'a[href="/users/log-out"]' >/dev/null
rodney waitload >/dev/null
rodney open "$BASE_URL/dashboard" >/dev/null
rodney waitload >/dev/null
url=$(rodney url)
case "$url" in
  "$BASE_URL"/users/log-in*)
    echo "PASS: signed out, /dashboard redirects to /users/log-in"
    ;;
  *)
    echo "FAIL: expected /dashboard to redirect to /users/log-in after sign out, got $url" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/manual_tests/reaction_flow.sh
```

- [ ] **Step 3: Check the file's syntax**

```bash
bash -n scripts/manual_tests/reaction_flow.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`.

- [ ] **Step 5: Run it against the dev server**

```bash
scripts/manual_tests/reaction_flow.sh
```

Expected output (timestamps/ids differ each run):

```
Seeding active session for manual-test-<timestamp>@example.com
Seeded talk_id=<N> talk_slug=manualtest<timestamp> session_id=<M>
PASS: Device A opened http://localhost:4000/t/manualtest<timestamp>, #emoji-buttons present
PASS: Device B opened http://localhost:4000/t/manualtest<timestamp>, #emoji-buttons present
PASS: Device A shows .floating-emoji ❤️
PASS: Device A cooldown active (cooling-down class, buttons disabled, 'Cooling down… 3s')
PASS: Device B shows .floating-emoji ❤️
PASS: Device B cooldown idle (no cooling-down class, buttons enabled, 'Tap to react')
PASS: Device A cooldown idle (no cooling-down class, buttons enabled, 'Tap to react')
PASS: Device A shows .floating-emoji 😂
PASS: Device B shows .floating-emoji 😂
PASS: logged in via magic link, #talk-list present on /dashboard
PASS: /sessions/<M> shows #total-reactions=2, #slide-row-0 (General, ❤️, 😂)
PASS: talk <N> deleted (cleanup)
PASS: signed out, /dashboard redirects to /users/log-in
```

Exit code 0.

- [ ] **Step 6: If Step 5 fails**

The browser stays open (the `trap` only fires on script exit), so inspect live state:

```bash
rodney pages
rodney url
rodney html "#emoji-buttons"
rodney html "#emoji-stream"
```

Compare against the selectors and timing notes verified in this plan's header. If `rodney click` itself errors with `Execution context was destroyed` (a transient CDP issue occasionally seen on long-lived/heavily-used browser sessions during planning, but not on a freshly-started one), run `rodney stop` and re-run Step 5 from scratch. Otherwise fix the script, then `rodney stop` and re-run Step 5.

- [ ] **Step 7: Commit**

```bash
git add scripts/manual_tests/reaction_flow.sh
git commit -m "feat: add manual integration test script for attendee reaction flow"
```

---

### Task 3: Update `docs/manual_tests.md`

**Files:**
- Modify: `docs/manual_tests.md`

- [ ] **Step 1: Update the "Quick start" section**

Find this paragraph:

```markdown
(default `http://localhost:4000`). This runs `auth_throttle.sh email`,
`dashboard.sh`, and `session_analytics.sh` back-to-back, printing each
script's output as it goes, then a PASS/FAIL summary line per script. Exits
non-zero if any failed.
```

Replace it with:

```markdown
(default `http://localhost:4000`). This runs `auth_throttle.sh email`,
`dashboard.sh`, `session_analytics.sh`, and `reaction_flow.sh` back-to-back,
printing each script's output as it goes, then a PASS/FAIL summary line per
script. Exits non-zero if any failed.
```

Then find this sentence later in the same section:

```markdown
**Dev-only** — refuses a non-local `--base-url`, since two of the three
scripts depend on `/dev/mailbox` and `mix run` for seeding. The `ip`-cooldown
```

Replace `two of the three` with `three of the four`:

```markdown
**Dev-only** — refuses a non-local `--base-url`, since three of the four
scripts depend on `/dev/mailbox` and `mix run` for seeding. The `ip`-cooldown
```

- [ ] **Step 2: Add the "Attendee reaction flow" section**

Add this new `##` section at the end of the file, after the "## Session analytics" section:

```markdown

## Attendee reaction flow

Tests the anonymous attendee-facing reaction page
(`SpeechwaveWeb.TalkLive`, `/t/:slug`): real-time emoji broadcast across
devices, the rate-limit cooldown UI, and reaction persistence to an active
session.

Scripts:
- `scripts/manual_tests/seed_active_session.exs` — seeds a talk with one
  active (unstopped) session and no reactions. Run directly with
  `mix run scripts/manual_tests/seed_active_session.exs <email>`, or via
  `reaction_flow.sh` below. Prints `email=`, `talk_id=`, `talk_slug=`,
  `session_id=` on stdout (interleaved with `[debug]` SQL logs on stderr).
- `scripts/manual_tests/reaction_flow.sh [--base-url URL]` (default
  `http://localhost:4000`)

**Dev-only** — same constraint as `dashboard.sh`/`session_analytics.sh`
(depends on `complete_magic_link_login` and on `mix run` for seeding). See
"SSH/eval magic-link-token helper for production runs" in `docs/roadmap.md`.

`reaction_flow.sh` opens **two** rodney tabs on the same `/t/:slug` page —
"Device A" (taps reactions) and "Device B" (observes only) — simulating two
attendees viewing the same talk:

1. Seeds an active session via `seed_active_session.exs` for a fresh
   `manual-test-<timestamp>@example.com`.
2. Opens Device A and Device B on `/t/<talk_slug>`. Checks `#emoji-buttons`
   renders on both.
3. Device A taps ❤️. Checks a `.floating-emoji` "❤️" appears (the
   broadcast + `EmojiStream` hook round-trip back to the tapping tab) and
   that `#emoji-buttons` enters its cooldown state (`cooling-down` class,
   disabled buttons, `.cooldown-label` shows "Cooling down… 3s").
4. **Cross-device check** — switches to Device B and checks a
   `.floating-emoji` "❤️" appears there too (the PubSub broadcast reached a
   second client in real time), while Device B's cooldown stays idle
   ("Tap to react", buttons enabled) — confirming the rate limiter is
   per-attendee, not global.
5. Waits ~4s (cooldown is 3s) and checks Device A's `#emoji-buttons` returns
   to idle.
6. Device A taps 😂. Checks a `.floating-emoji` "😂" appears.
7. **Cross-device check** — switches to Device B and checks a
   `.floating-emoji` "😂" appears there too.
8. Closes Device B's tab.
9. Logs in as the seeded user via magic link, opens
   `/sessions/<session_id>`. Checks `#total-reactions` is `2` and
   `#slide-row-0` ("General" — `current_slide` stays `0` for this whole
   flow) shows both ❤️ and 😂.
10. Deletes the talk (cleanup).
11. Signs out.
```

- [ ] **Step 3: Commit**

```bash
git add docs/manual_tests.md
git commit -m "docs: add manual test section for attendee reaction flow"
```

---

### Task 4: Update `scripts/manual_tests/run_all_dev.sh`

**Files:**
- Modify: `scripts/manual_tests/run_all_dev.sh`

- [ ] **Step 1: Update the non-local error message**

Find:

```bash
if ! is_local; then
  echo "ERROR: run_all_dev.sh only runs scripts that require a local dev server" >&2
  echo "(auth_throttle.sh email mode, dashboard.sh, session_analytics.sh)." >&2
  echo "Re-run with --base-url http://localhost:4000 (or omit --base-url)." >&2
  exit 1
fi
```

Replace with:

```bash
if ! is_local; then
  echo "ERROR: run_all_dev.sh only runs scripts that require a local dev server" >&2
  echo "(auth_throttle.sh email mode, dashboard.sh, session_analytics.sh," >&2
  echo "reaction_flow.sh)." >&2
  echo "Re-run with --base-url http://localhost:4000 (or omit --base-url)." >&2
  exit 1
fi
```

- [ ] **Step 2: Add `reaction_flow.sh` to the chain**

Find:

```bash
run_script "auth_throttle.sh email" "$SCRIPT_DIR/auth_throttle.sh" --base-url "$BASE_URL" email
run_script "dashboard.sh"           "$SCRIPT_DIR/dashboard.sh" --base-url "$BASE_URL"
run_script "session_analytics.sh"   "$SCRIPT_DIR/session_analytics.sh" --base-url "$BASE_URL"
```

Replace with:

```bash
run_script "auth_throttle.sh email" "$SCRIPT_DIR/auth_throttle.sh" --base-url "$BASE_URL" email
run_script "dashboard.sh"           "$SCRIPT_DIR/dashboard.sh" --base-url "$BASE_URL"
run_script "session_analytics.sh"   "$SCRIPT_DIR/session_analytics.sh" --base-url "$BASE_URL"
run_script "reaction_flow.sh"       "$SCRIPT_DIR/reaction_flow.sh" --base-url "$BASE_URL"
```

- [ ] **Step 3: Check the file's syntax**

```bash
bash -n scripts/manual_tests/run_all_dev.sh
```

Expected: no output, exit code 0.

- [ ] **Step 4: Confirm the dev server is running**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: `200`.

- [ ] **Step 5: Run it against the dev server**

```bash
scripts/manual_tests/run_all_dev.sh
```

Expected: each of the four scripts prints its own `PASS`/`FAIL` lines (per
their own plans/docs), followed by:

```

==== Summary ====
PASS  auth_throttle.sh email
PASS  dashboard.sh
PASS  session_analytics.sh
PASS  reaction_flow.sh
```

Exit code 0.

- [ ] **Step 6: If Step 5 fails**

Check the `Summary` block to see which script(s) failed, then re-run that
script directly (e.g. `scripts/manual_tests/reaction_flow.sh`) to debug —
its own "If it fails" recovery steps apply.

- [ ] **Step 7: Commit**

```bash
git add scripts/manual_tests/run_all_dev.sh
git commit -m "feat: add reaction_flow.sh to run_all_dev.sh chain"
```

---

### Task 5: Update `docs/roadmap.md`

**Files:**
- Modify: `docs/roadmap.md`

- [ ] **Step 1: Remove the "Manual test: attendee reaction flow" item**

Find and remove this entire section (including its trailing blank line),
from the "## Manual/Live-Environment Testing" section:

```markdown
### Manual test: attendee reaction flow (`/t/:slug`)

The attendee-facing reaction page (`TalkLive`, `/t/:slug`) has no manual-test
coverage yet. It's independent of login — anonymous attendees scan a QR code
and tap emoji reactions — so it can be designed and scripted without
depending on `complete_magic_link_login`.

Note `TalkLive.handle_event("react", ...)` only persists a `Reaction` if
`Talks.get_active_session/1` is non-nil, so this test needs an active
session — e.g. via `scripts/manual_tests/seed_sessions.exs` without calling
`stop_session`, or the channel-driven `start_session` flow.

```

The "### Manual test: account settings ..." and "### Manual test: OAuth
connect/disconnect" items that follow are unaffected.

- [ ] **Step 2: Commit**

```bash
git add docs/roadmap.md
git commit -m "docs: remove planned attendee reaction flow item from roadmap"
```

---

### Task 6: Final precommit check

**Files:** none (verification only)

- [ ] **Step 1: Run `mix precommit`**

```bash
mix precommit
```

Expected: all checks pass (compile, deps.unlock, format, test, lint,
static). None of this plan's files are Elixir source under `lib/`/`test/`,
so this is a regression check that nothing else broke.

- [ ] **Step 2: If `mix precommit` fails**

Fix the reported issue, re-run Step 1, then commit the fix with a message
describing what was fixed.

---

## Files touched

- `scripts/manual_tests/seed_active_session.exs` — new
- `scripts/manual_tests/reaction_flow.sh` — new
- `scripts/manual_tests/run_all_dev.sh` — add `reaction_flow.sh` to the
  chain, update error message
- `docs/manual_tests.md` — new "Attendee reaction flow" section, update
  Quick start description
- `docs/roadmap.md` — remove "Manual test: attendee reaction flow" item
