# Docs Site Screenshots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add eight screenshots to the five pages of the `speechwave-live/docs` Jekyll site — four freshly captured against local dev with `rodney`, three cropped/reused from existing Chrome Web Store assets, and one captured manually by Tracy.

**Architecture:** All new image files land in `docs/assets/images/` in the `speechwave-live/docs` repo. Fresh captures come from driving `speechwave`'s local dev server with `rodney` (headless Chrome automation) through the same magic-link login and seed-script flow already proven in `scripts/manual_tests/*.sh`. Cropped images come from `speechwave/tmp/store_0*.png` via ImageMagick. Pages get plain Markdown `![]()` image embeds with a kramdown width attribute, inserted at fixed locations under existing headings — no prose changes.

**Tech Stack:** `rodney` (Chrome CDP automation CLI), ImageMagick (`magick`/`convert`), Jekyll 4.4 / just-the-docs (verification only).

**Spec:** `/Users/tracy/projects/speechwave-live/speechwave/docs/specs/2026-07-05-docs-site-screenshots-design.md`

## Global Constraints

- **New files land in `/Users/tracy/projects/speechwave-live/docs`** (the docs repo). The app repo at `/Users/tracy/projects/speechwave-live/speechwave` is read-only source material — no code changes there, only running existing scripts (`seed_screenshots.exs`) and reading existing files (`tmp/store_0*.png`).
- Conventional commit format for all commits (both repos, though only the docs repo should need commits here).
- Image files: `docs/assets/images/screenshot-<topic>.png`.
- Every fresh `rodney` capture uses a 1280px-wide viewport per the approved spec.
- `--load-extension` + `rodney connect` for the Chrome extension is a **known dead end on this machine** (persistent Chrome content-verifier rejection, confirmed unrelated to any terminal/OS permission) — do not attempt it. Screenshot D is a manual capture handoff (Task 3).
- Clean up after yourself: stop `rodney` (`rodney stop`) and the dev server at the end of any task that starts them. Don't leave background processes running between tasks.
- Verification command after Task 4 (and again in Task 5): `bundle exec jekyll build` from the docs repo root must exit 0.

---

### Task 1: Fresh dashboard and account settings captures (A, B, C)

**Files:**
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-dashboard-talk-list.png`
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-dashboard-talk-panel.png`
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-account-settings-api-key.png`

**Interfaces:**
- Consumes: `speechwave`'s local dev server (`mix phx.server`), `scripts/manual_tests/seed_screenshots.exs` (creates the `emojilove` talk), `/dev/mailbox` (dev-only magic-link mailbox), and the DOM ids already used by `scripts/manual_tests/dashboard.sh` / `account_settings.sh` (`#talk-list`, `#selected-talk-qr`, `#api-key-display`).
- Produces: three PNG files other tasks don't depend on directly, but Task 4 embeds them by this exact path/filename.

- [ ] **Step 1: Start the dev server**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
mix phx.server > /tmp/speechwave-dev-server.log 2>&1 &
disown
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/users/log-in || true)
  [ "$code" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4000/users/log-in
```

Expected: prints `200`. If it never reaches 200, check `/tmp/speechwave-dev-server.log` for a boot error before continuing.

- [ ] **Step 2: Seed the emojilove talk**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
mix run scripts/manual_tests/seed_screenshots.exs screenshot-demo@example.com
```

Expected: output includes `talk_slug=emojilove` and `session2_id=... (active — connect extension to this)`.

- [ ] **Step 3: Start rodney and log in via magic link**

```bash
rodney start
rodney open "http://localhost:4000/dev/mailbox"
rodney waitload
if [ "$(rodney count 'a[href^="/dev/mailbox/"]')" -gt 0 ]; then
  rodney click 'form[action="/dev/mailbox/clear"] button'
  rodney waitload
fi

rodney open "http://localhost:4000/users/log-in"
rodney waitload
rodney input "#user_email" "screenshot-demo@example.com"
rodney click "#magic-link-form button"
rodney waitstable
rodney exists "#magic-link-sent"
```

Expected: last command exits 0 (element found). This mirrors `complete_magic_link_login` in `scripts/manual_tests/lib.sh`.

- [ ] **Step 4: Follow the magic link and confirm login**

```bash
rodney open "http://localhost:4000/dev/mailbox"
rodney waitload
magic_url=$(rodney text "#text-body-content" | grep -o 'https\?://[^[:space:]]*/users/magic_link/[^[:space:]]*')
echo "magic_url=$magic_url"
rodney open "$magic_url"
rodney waitload
rodney open "http://localhost:4000/dashboard"
rodney waitload
rodney exists "#talk-list"
```

Expected: `magic_url` is non-empty and the final `rodney exists` exits 0.

- [ ] **Step 5: Capture A — dashboard talk list + create-talk form**

```bash
rodney screenshot -w 1280 -h 1000 /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-dashboard-talk-list.png
```

- [ ] **Step 6: Select the talk and capture B — talk panel**

```bash
rodney click "#talk-list button"
rodney waitstable
rodney exists "#selected-talk-qr"
```

Expected: exits 0.

```bash
rodney screenshot -w 1280 -h 1000 /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-dashboard-talk-panel.png
```

- [ ] **Step 7: Navigate to Account Settings and capture C**

```bash
rodney open "http://localhost:4000/users/settings"
rodney waitload
rodney exists "#api-key-display"
```

Expected: exits 0.

```bash
rodney screenshot -w 1280 -h 900 /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-account-settings-api-key.png
```

- [ ] **Step 8: Tear down**

```bash
rodney stop
pkill -f "mix phx.server" || true
```

- [ ] **Step 9: Visually verify all three captures**

Read each of the three PNG files. Confirm:
- `screenshot-dashboard-talk-list.png` shows the "Create a Talk" form and "Your Talks" list with "Emoji Love" listed, no talk selected.
- `screenshot-dashboard-talk-panel.png` shows the "Emoji Love" panel selected, with audience URL, QR code, "Slug for browser extension" (`emojilove`), and a Sessions list.
- `screenshot-account-settings-api-key.png` shows the Account Settings page with the API key field visible.

If any capture is cut off (content taller than the `-h` value) or shows mostly blank space, redo that single `rodney screenshot` call with an adjusted `-h` — no need to redo the whole login/seed flow, rodney's session is still live until Step 8.

- [ ] **Step 10: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/docs
git add assets/images/screenshot-dashboard-talk-list.png assets/images/screenshot-dashboard-talk-panel.png assets/images/screenshot-account-settings-api-key.png
git commit -m "docs: add dashboard and account settings screenshots"
```

---

### Task 2: Recrop and reuse existing store screenshots (E, F, G, H)

**Files:**
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-slides-overlay.png`
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-session-analytics.png`
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-extension-popup-connected.png`
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-audience-view.png`

**Interfaces:**
- Consumes: `speechwave/tmp/store_01_slides.png`, `store_02_popup.png`, `store_03_audience.png`, `store_04_analytics.png` (all 1280x800, pre-existing, read-only).
- Produces: four PNGs Task 4 embeds by these exact paths.

- [ ] **Step 1: Copy E and H as-is (no cropping — both are genuine, unmodified-by-us captures)**

```bash
cp /Users/tracy/projects/speechwave-live/speechwave/tmp/store_01_slides.png \
   /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-slides-overlay.png
cp /Users/tracy/projects/speechwave-live/speechwave/tmp/store_04_analytics.png \
   /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-session-analytics.png
```

- [ ] **Step 2: Crop F — isolate the extension popup panel**

```bash
magick /Users/tracy/projects/speechwave-live/speechwave/tmp/store_02_popup.png \
  -crop 250x326+100+101 +repage \
  /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-extension-popup-connected.png
```

This crop box was already verified during the design pass: it keeps the popup panel (Speechwave header, Connected status, Talk Slug, Disconnect, Slide/Session indicator, Stop Session, Fireworks checkbox, Change API key link) and drops the surrounding slide backdrop and floating emoji cluster.

- [ ] **Step 3: Crop G — drop the store-listing padding frame**

```bash
magick /Users/tracy/projects/speechwave-live/speechwave/tmp/store_03_audience.png \
  -crop 438x800+420+0 +repage \
  /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-audience-view.png
```

This crop box was also verified during the design pass: it keeps the real page content (header through footer) and drops the dark padding added around it for the Chrome Web Store listing.

- [ ] **Step 4: Visually verify all four**

Read each of the four PNG files. Confirm:
- `screenshot-slides-overlay.png` — unchanged from the source, full slide with "Emoji Love!" title, heart-eyes emoji, "Powered by Speechwave" badge, and the floating emoji cluster bottom-right.
- `screenshot-session-analytics.png` — unchanged from the source, the Session 1 analytics breakdown.
- `screenshot-extension-popup-connected.png` — just the popup panel (Connected, Talk Slug "emojilove", Slide 2 / Session 4, Stop Session), no green backdrop margin wider than a few px, no slide content visible.
- `screenshot-audience-view.png` — the light header bar through the dark footer, no dark padding strip on the left/right edges.

If a crop is off by more than a few px of stray background, adjust the `-crop WxH+X+Y` box and rerun — the four numbers are `width x height + left-offset + top-offset` in the original 1280x800 image.

- [ ] **Step 5: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/docs
git add assets/images/screenshot-slides-overlay.png assets/images/screenshot-session-analytics.png \
        assets/images/screenshot-extension-popup-connected.png assets/images/screenshot-audience-view.png
git commit -m "docs: add cropped and reused extension/audience screenshots"
```

---

### Task 3: Manual capture handoff (D)

**Files:**
- Create: `/Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-extension-popup-setup.png`

**Interfaces:**
- Consumes: `/Users/tracy/projects/speechwave-live/speechwave/tmp/extension_popup_api_key.png`, provided by Tracy (already captured — she loaded the unpacked extension via `chrome://extensions` → Load unpacked and screenshotted the popup before saving an API key).
- Produces: one PNG Task 4 embeds by this exact path.

This task depended on a human action that couldn't be scripted (per the design spec, `--load-extension` automation is a confirmed dead end on this machine) — that action is already done as of 2026-07-05.

- [ ] **Step 1: Place the file**

```bash
cp /Users/tracy/projects/speechwave-live/speechwave/tmp/extension_popup_api_key.png \
   /Users/tracy/projects/speechwave-live/docs/assets/images/screenshot-extension-popup-setup.png
```

- [ ] **Step 2: Visually verify**

Read `screenshot-extension-popup-setup.png`. Confirm it shows the "Paste your Speechwave API key to get started" setup screen (an input field, a link to Account Settings, and a "Save Key" button) — not the connected/main state. (Already confirmed once during planning: the source file shows exactly this.)

- [ ] **Step 3: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/docs
git add assets/images/screenshot-extension-popup-setup.png
git commit -m "docs: add extension popup setup screenshot"
```

---

### Task 4: Embed all eight images into the four docs pages

**Files:**
- Modify: `/Users/tracy/projects/speechwave-live/docs/index.md`
- Modify: `/Users/tracy/projects/speechwave-live/docs/getting-started.md`
- Modify: `/Users/tracy/projects/speechwave-live/docs/dashboard.md`
- Modify: `/Users/tracy/projects/speechwave-live/docs/extension.md`

**Interfaces:**
- Consumes: the eight PNG files created in Tasks 1–3, referenced by absolute site path (e.g. `/assets/images/screenshot-dashboard-talk-list.png`).
- Produces: no interface for later tasks — Task 5 just verifies the result renders.

`troubleshooting.md` is intentionally not touched (out of scope for this pass per the spec).

- [ ] **Step 1: index.md — insert G after the audience mobile view paragraph**

Find:
```markdown
**Audience mobile view**
Your audience opens your talk's link (`https://speechwave.live/t/<your-talk-slug>`) on their phone, or scans a QR code you display on screen. There's nothing to install and no account to create. They just open the page and start tapping emoji.

**Speaker dashboard & analytics**
```

Replace with:
```markdown
**Audience mobile view**
Your audience opens your talk's link (`https://speechwave.live/t/<your-talk-slug>`) on their phone, or scans a QR code you display on screen. There's nothing to install and no account to create. They just open the page and start tapping emoji.

![Speechwave audience view on a phone, showing a floating reaction and a grid of emoji to tap](/assets/images/screenshot-audience-view.png){: width="320" }

**Speaker dashboard & analytics**
```

- [ ] **Step 2: getting-started.md — insert A after step 2**

Find:
```markdown
From your dashboard, use the "Create a Talk" form and enter a title. Speechwave generates a URL slug for you automatically, and you can edit it if you'd like something more memorable. Your talk gets its own audience link: `https://speechwave.live/t/<slug>`.

## 3. Share with your audience
```

Replace with:
```markdown
From your dashboard, use the "Create a Talk" form and enter a title. Speechwave generates a URL slug for you automatically, and you can edit it if you'd like something more memorable. Your talk gets its own audience link: `https://speechwave.live/t/<slug>`.

![Speechwave dashboard showing the Create a Talk form and a list of talks](/assets/images/screenshot-dashboard-talk-list.png){: width="700" }

## 3. Share with your audience
```

- [ ] **Step 3: getting-started.md — insert B after step 3**

Find:
```markdown
Select your talk in the dashboard to see the URL for your audience and a QR code. Project the QR code on a slide, download it as a PNG for your own materials, or just read the link aloud. Your audience needs no account and no app. They open the link on their phone and they're ready to react.

## 4. Connect the Chrome extension
```

Replace with:
```markdown
Select your talk in the dashboard to see the URL for your audience and a QR code. Project the QR code on a slide, download it as a PNG for your own materials, or just read the link aloud. Your audience needs no account and no app. They open the link on their phone and they're ready to react.

![Speechwave dashboard talk panel showing the audience URL, QR code, and slug for the browser extension](/assets/images/screenshot-dashboard-talk-panel.png){: width="700" }

## 4. Connect the Chrome extension
```

- [ ] **Step 4: getting-started.md — insert D after step 4**

Find:
```markdown
The [Chrome extension](extension.html) is what overlays incoming reactions onto your slides while you present. Install it, then enter your API key (found in your account settings) and your talk's slug (shown on the dashboard as "Slug for browser extension") to connect it to this talk.

## 5. Start a session
```

Replace with:
```markdown
The [Chrome extension](extension.html) is what overlays incoming reactions onto your slides while you present. Install it, then enter your API key (found in your account settings) and your talk's slug (shown on the dashboard as "Slug for browser extension") to connect it to this talk.

![Speechwave Chrome extension popup prompting for an API key before it's connected](/assets/images/screenshot-extension-popup-setup.png){: width="280" }

## 5. Start a session
```

- [ ] **Step 5: getting-started.md — insert E after step 6**

Find:
```markdown
Your audience taps emoji on their phones as you speak. Each reaction floats up over your slides in real time, so you can see how the room is responding without breaking your flow. Behind the scenes, every reaction is tallied against whichever slide was showing when it was sent, building the slide-by-slide breakdown you'll see in your session analytics afterward.

---
```

Replace with:
```markdown
Your audience taps emoji on their phones as you speak. Each reaction floats up over your slides in real time, so you can see how the room is responding without breaking your flow. Behind the scenes, every reaction is tallied against whichever slide was showing when it was sent, building the slide-by-slide breakdown you'll see in your session analytics afterward.

![A Google Slides presentation with a floating cluster of emoji reactions in the bottom-right corner](/assets/images/screenshot-slides-overlay.png){: width="700" }

---
```

- [ ] **Step 6: dashboard.md — insert A after "Your talks"**

Find:
```markdown
To delete a talk, select it and use the trash icon next to its name. Deleting a talk removes all of its sessions and reactions too, so double-check before confirming.

## Finding your talk slug
```

Replace with:
```markdown
To delete a talk, select it and use the trash icon next to its name. Deleting a talk removes all of its sessions and reactions too, so double-check before confirming.

![Speechwave dashboard showing the Create a Talk form and a list of talks](/assets/images/screenshot-dashboard-talk-list.png){: width="700" }

## Finding your talk slug
```

- [ ] **Step 7: dashboard.md — insert B after "Finding your talk slug"**

Find:
```markdown
The slug is the last part of your audience URL (`speechwave.live/t/<slug>`), and it's the one piece of information the browser extension needs to connect to the right talk. Select the talk in your dashboard and look for **"Slug for browser extension"** in its panel. Click the copy icon next to it and paste it straight into the extension.

## Finding your API key
```

Replace with:
```markdown
The slug is the last part of your audience URL (`speechwave.live/t/<slug>`), and it's the one piece of information the browser extension needs to connect to the right talk. Select the talk in your dashboard and look for **"Slug for browser extension"** in its panel. Click the copy icon next to it and paste it straight into the extension.

![Speechwave dashboard talk panel showing the audience URL, QR code, and slug for the browser extension](/assets/images/screenshot-dashboard-talk-panel.png){: width="700" }

## Finding your API key
```

- [ ] **Step 8: dashboard.md — insert C after "Finding your API key"**

Find:
```markdown
Regenerating your key immediately invalidates the old one and disconnects any extension using it. Paste the new key into the extension before it can reconnect. See [troubleshooting](troubleshooting.html) if reactions stop showing up after a regeneration.

## Sessions
```

Replace with:
```markdown
Regenerating your key immediately invalidates the old one and disconnects any extension using it. Paste the new key into the extension before it can reconnect. See [troubleshooting](troubleshooting.html) if reactions stop showing up after a regeneration.

![Speechwave Account Settings page showing the Browser Extension API Key field](/assets/images/screenshot-account-settings-api-key.png){: width="700" }

## Sessions
```

- [ ] **Step 9: dashboard.md — insert H after "Session analytics"**

Find:
```markdown
If your talk has more than one session, you can also compare two sessions of the same talk side by side, with each session's slide-by-slide breakdown shown next to the other. That's a quick way to see how a reworked section of your talk performed against an earlier run.

## Plan usage
```

Replace with:
```markdown
If your talk has more than one session, you can also compare two sessions of the same talk side by side, with each session's slide-by-slide breakdown shown next to the other. That's a quick way to see how a reworked section of your talk performed against an earlier run.

![Speechwave session analytics page showing a slide-by-slide breakdown of reactions](/assets/images/screenshot-session-analytics.png){: width="700" }

## Plan usage
```

- [ ] **Step 10: extension.md — insert D after "Connect your account"**

Find:
```markdown
If you ever need to swap in a different key (say, after regenerating one), click **Change API key** near the bottom of the popup.

## Connect to a talk
```

Replace with:
```markdown
If you ever need to swap in a different key (say, after regenerating one), click **Change API key** near the bottom of the popup.

![Speechwave Chrome extension popup prompting for an API key before it's connected](/assets/images/screenshot-extension-popup-setup.png){: width="280" }

## Connect to a talk
```

- [ ] **Step 11: extension.md — insert E after "Present"**

Find:
```markdown
**Important:** after installing or updating the extension, refresh any Google Slides tabs you already had open before you connect. Chrome doesn't load the update into tabs that were already open, so the overlay won't appear until you reload them.

## Sessions from the extension
```

Replace with:
```markdown
**Important:** after installing or updating the extension, refresh any Google Slides tabs you already had open before you connect. Chrome doesn't load the update into tabs that were already open, so the overlay won't appear until you reload them.

![A Google Slides presentation with a floating cluster of emoji reactions in the bottom-right corner](/assets/images/screenshot-slides-overlay.png){: width="700" }

## Sessions from the extension
```

- [ ] **Step 12: extension.md — insert F after "Sessions from the extension"**

Find:
```markdown
Once you're connected, the popup shows a session area below the connect button. Click **Start Session** to begin recording reactions for this run of your talk. The button changes to **Stop Session** while one is running, along with a slide indicator ("Slide 3", or "Slide —" if none is detected yet). Click **Stop Session** when you're done presenting. Your [dashboard](dashboard.html) is where you rename sessions and review their analytics afterward.

## Common errors
```

Replace with:
```markdown
Once you're connected, the popup shows a session area below the connect button. Click **Start Session** to begin recording reactions for this run of your talk. The button changes to **Stop Session** while one is running, along with a slide indicator ("Slide 3", or "Slide —" if none is detected yet). Click **Stop Session** when you're done presenting. Your [dashboard](dashboard.html) is where you rename sessions and review their analytics afterward.

![Speechwave Chrome extension popup connected to a talk with an active session running](/assets/images/screenshot-extension-popup-connected.png){: width="280" }

## Common errors
```

- [ ] **Step 13: Build and verify**

```bash
cd /Users/tracy/projects/speechwave-live/docs
bundle exec jekyll build
```

Expected: exit 0, no errors. If a `just-the-docs` link-check or Liquid error appears, it's most likely a stray unescaped character in one of the alt-text strings above — check the exact text you inserted against what's shown here.

- [ ] **Step 14: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/docs
git add index.md getting-started.md dashboard.md extension.md
git commit -m "docs: embed screenshots into the five docs pages"
```

---

### Task 5: Final verification

**Files:** none (read-only verification pass).

**Interfaces:**
- Consumes: the committed state of the docs repo from Tasks 1–4.
- Produces: nothing — this is the plan's acceptance check.

- [ ] **Step 1: Full site build**

```bash
cd /Users/tracy/projects/speechwave-live/docs
bundle exec jekyll build
```

Expected: exit 0.

- [ ] **Step 2: Serve locally and screenshot each changed page at wide and narrow widths**

```bash
cd /Users/tracy/projects/speechwave-live/docs
bundle exec jekyll serve --detach --port 4001 > /tmp/jekyll-serve.log 2>&1
sleep 3
rodney start
for page in index getting-started dashboard extension; do
  rodney open "http://localhost:4001/${page}.html"
  rodney waitload
  rodney screenshot -w 1280 "/tmp/verify-${page}-wide.png"
  rodney screenshot -w 400 "/tmp/verify-${page}-narrow.png"
done
rodney stop
pkill -f "jekyll serve" || true
```

- [ ] **Step 3: Visually confirm each of the 8 screenshots**

Read each of the 8 `/tmp/verify-*.png` files. Confirm at both widths:
- Every embedded image renders (no broken-image icon).
- No image overflows its column or gets cut off oddly at the narrow (400px) width — just-the-docs should scale each `<img>` down to fit; the `width` IAL values are a display cap, not a hard requirement, so slight downscaling on narrow viewports is expected and fine.
- Image content is legible at the width it renders at (not so small the text/UI in the screenshot is illegible).

If any image is genuinely illegible or broken, that's a real finding — go back and adjust the relevant task (recrop, recapture, or change the `width` IAL) rather than shipping it broken.

- [ ] **Step 4: Confirm clean git state in both repos**

```bash
cd /Users/tracy/projects/speechwave-live/docs && git status
cd /Users/tracy/projects/speechwave-live/speechwave && git status
```

Expected: docs repo shows a clean working tree (everything from Tasks 1–4 already committed). The speechwave repo shows no changes at all — this plan never modifies app code, only reads `tmp/store_0*.png` and runs `seed_screenshots.exs` against the local dev database.

- [ ] **Step 5: Clean up temp files**

```bash
rm -f /tmp/verify-*.png /tmp/jekyll-serve.log /tmp/speechwave-dev-server.log
```
