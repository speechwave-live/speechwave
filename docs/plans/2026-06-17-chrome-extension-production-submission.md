# Chrome Extension: Production Readiness & Web Store Submission

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the Chrome extension to connect to `speechwave.live`, add required icons, verify the full authenticated flow end-to-end, then submit to the Chrome Web Store.

**Architecture:** Three small code changes update the hard-coded dev URLs to production; icons are generated from a source SVG; manual testing verifies the full flow against the live server; submission follows a checklist of store assets and form fields.

**Tech Stack:** Chrome Extension Manifest V3, JavaScript (no build step), ImageMagick or rsvg-convert for icon generation, Chrome Web Store developer console.

**Spec:** `docs/specs/2026-06-17-chrome-extension-production-submission-design.md`

**All paths are relative to the `chrome-extension/` repo root** (`../chrome-extension/` from the `speechwave/` app).

---

### Task 1: Update HOST in content.js

**Files:**
- Modify: `content/content.js` (lines 1–7)

- [ ] **Open `content/content.js`** and replace the two HOST lines with a flag-driven constant:

  Remove these lines:
  ```js
  // const HOST = "wss://speechwave.fly.dev";
  const HOST = "ws://localhost:4000";
  ```

  Replace with:
  ```js
  const HOST = DEV_MODE ? "ws://localhost:4000" : "wss://speechwave.live";
  ```

  The top of the file should now read:
  ```js
  const DEV_MODE = false; // set to true locally for testing
  const HOST = DEV_MODE ? "ws://localhost:4000" : "wss://speechwave.live";
  ```

- [ ] **Verify the test suite still passes** (the change doesn't touch any tested code, but confirm nothing is broken):

  ```bash
  npm test
  ```

  Expected: all tests pass, no failures.

- [ ] **Commit:**

  ```bash
  git add content/content.js
  git commit -m "fix: derive HOST from DEV_MODE flag, point prod at speechwave.live"
  ```

---

### Task 2: Update manifest.json

**Files:**
- Modify: `manifest.json`

- [ ] **Replace the full contents of `manifest.json`** with the following (updates `host_permissions` and adds the `icons` block; icon files will be created in Task 4):

  ```json
  {
    "manifest_version": 3,
    "name": "Speechwave",
    "version": "1.0.0",
    "description": "Live emoji reactions overlay for conference talks",
    "permissions": ["storage", "tabs"],
    "host_permissions": [
      "http://localhost/*",
      "https://speechwave.live/*"
    ],
    "icons": {
      "16": "icons/icon16.png",
      "48": "icons/icon48.png",
      "128": "icons/icon128.png"
    },
    "action": {
      "default_popup": "popup/popup.html",
      "default_title": "Speechwave",
      "default_icon": {
        "16": "icons/icon16.png",
        "48": "icons/icon48.png"
      }
    },
    "content_scripts": [
      {
        "matches": ["https://docs.google.com/presentation/*"],
        "js": ["lib/phoenix.js", "lib/fireworks.js", "adapters/google_slides.js", "adapters/index.js", "content/content.js"],
        "run_at": "document_idle"
      }
    ]
  }
  ```

- [ ] **Verify the JSON is valid:**

  ```bash
  node -e "JSON.parse(require('fs').readFileSync('manifest.json', 'utf8')); console.log('valid')"
  ```

  Expected output: `valid`

- [ ] **Commit:**

  ```bash
  git add manifest.json
  git commit -m "fix: update host_permissions to speechwave.live, add icons to manifest"
  ```

---

### Task 3: Update settings link in popup.html

**Files:**
- Modify: `popup/popup.html` (line 33)

- [ ] **Find and update the Account Settings link** in `popup/popup.html`:

  Find:
  ```html
  Find it in <a href="https://speechwave.fly.dev/users/settings" target="_blank">Account Settings</a>.
  ```

  Replace with:
  ```html
  Find it in <a href="https://speechwave.live/users/settings" target="_blank">Account Settings</a>.
  ```

- [ ] **Commit:**

  ```bash
  git add popup/popup.html
  git commit -m "fix: update settings link to speechwave.live"
  ```

---

### Task 4: Create extension icons

**Files:**
- Create: `icons/icon16.png`
- Create: `icons/icon48.png`
- Create: `icons/icon128.png`
- Create: `icons/icon.svg` (source, not referenced by manifest — keep for future edits)

The icon uses the Speechwave brand colors: dark background (`#0a0a0a`), mint
microphone (`#00d4a4`). Design at 128×128 and downsample.

- [ ] **Create the `icons/` directory:**

  ```bash
  mkdir icons
  ```

- [ ] **Create `icons/icon.svg`** with the following content (a rounded-rect background with a mint microphone silhouette):

  ```svg
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
    <rect width="128" height="128" rx="22" fill="#0a0a0a"/>
    <!-- Mic capsule -->
    <rect x="46" y="18" width="36" height="54" rx="18" fill="#00d4a4"/>
    <!-- Mic stand arc -->
    <path d="M30 70 C30 98 98 98 98 70" stroke="#00d4a4" stroke-width="7"
          fill="none" stroke-linecap="round"/>
    <!-- Stem -->
    <line x1="64" y1="97" x2="64" y2="112"
          stroke="#00d4a4" stroke-width="7" stroke-linecap="round"/>
    <!-- Base -->
    <line x1="48" y1="112" x2="80" y2="112"
          stroke="#00d4a4" stroke-width="7" stroke-linecap="round"/>
  </svg>
  ```

- [ ] **Export PNGs from the SVG.** Choose one method:

  **Option A — rsvg-convert (recommended on macOS):**
  ```bash
  brew install librsvg   # skip if already installed
  rsvg-convert -w 128 -h 128 icons/icon.svg -o icons/icon128.png
  rsvg-convert -w 48  -h 48  icons/icon.svg -o icons/icon48.png
  rsvg-convert -w 16  -h 16  icons/icon.svg -o icons/icon16.png
  ```

  **Option B — ImageMagick:**
  ```bash
  brew install imagemagick   # skip if already installed
  magick icons/icon.svg -resize 128x128 icons/icon128.png
  magick icons/icon.svg -resize 48x48   icons/icon48.png
  magick icons/icon.svg -resize 16x16   icons/icon16.png
  ```

  **Option C — Figma/Sketch:** design or paste the SVG, export at 128, 48, and 16px to `icons/`.

- [ ] **Verify the files exist and are non-empty:**

  ```bash
  ls -lh icons/
  ```

  Expected: `icon.svg`, `icon16.png`, `icon48.png`, `icon128.png` all present with non-zero sizes.

- [ ] **Load the extension unpacked in Chrome to confirm the icon appears** in the toolbar and extension management page (`chrome://extensions`):

  1. Open `chrome://extensions`
  2. Enable **Developer mode** (top-right toggle)
  3. Click **Load unpacked** and select the `chrome-extension/` directory
  4. Confirm the Speechwave icon appears in the Chrome toolbar

- [ ] **Commit:**

  ```bash
  git add icons/
  git commit -m "feat: add extension icons (16, 48, 128px)"
  ```

---

### Task 5: End-to-end manual testing

**Prerequisites:** extension loaded unpacked in Chrome (from Task 4), a real account on `speechwave.live`, `DEV_MODE = false`.

Work through each scenario. Stop and fix any failure before proceeding.

- [ ] **Scenario 1 — First-run setup**
  1. Open the Speechwave popup with no API key stored
     - Expected: setup screen with API key input and Account Settings link
  2. Click the Account Settings link → confirm it opens `speechwave.live/users/settings`
  3. Copy your API key from the Settings page, paste it in the popup, click Save Key
     - Expected: main screen appears
  4. Close and reopen the popup
     - Expected: main screen still shown (key persisted)

- [ ] **Scenario 2 — Connect and react**
  1. In your Speechwave dashboard, create a test talk and note its slug
  2. Open a Google Slides presentation in a tab
  3. In the popup, enter the slug and click Connect
     - Expected: status indicator turns green, shows "Connected"
  4. Open the attendee URL for the talk in another tab and send reactions
     - Expected: emoji float up in the overlay on the Slides tab
  5. Advance slides in Google Slides
     - Expected: slide indicator in the popup increments

- [ ] **Scenario 3 — Session lifecycle**
  1. Click Start Session in the popup
     - Expected: session appears in the Speechwave dashboard
  2. Click Stop Session
     - Expected: session ends; dashboard reflects the stopped state

- [ ] **Scenario 4 — Error paths**
  1. Click the Speechwave toolbar icon while on a non-Slides page, or disconnect first
  2. Enter a **wrong API key**: clear storage (`chrome.storage.sync.clear()` in the extension's service worker console or reload the extension and enter a bad key), reconnect
     - Expected: "Invalid API key or you don't own this talk"
  3. Enter a **nonexistent slug** with your real API key and connect
     - Expected: "Talk not found"
  4. Regenerate your API key in Settings while connected to a talk
     - Expected: popup shows "Your API key was regenerated. Please update it in the extension." and disconnects

- [ ] **Scenario 5 — Persistence**
  1. Enter a slug and connect
  2. Close Chrome entirely and reopen it, navigate back to a Google Slides URL
     - Expected: slug is pre-populated in the popup; extension auto-reconnects

- [ ] **Scenario 6 — DEV_MODE sanity**
  1. Temporarily set `DEV_MODE = true` in `content/content.js`, reload the extension
     - Expected: test fireworks button appears in popup
  2. Restore `DEV_MODE = false` and reload
     - Expected: test fireworks button is hidden

- [ ] **Commit a note if any bugs were found and fixed during testing:**

  ```bash
  git add -A
  git commit -m "fix: <describe what was fixed>"
  ```

---

### Task 6: Package the extension for submission

**Files:** produces `speechwave-extension.zip` (not committed to the repo)

- [ ] **Create the zip**, including only runtime files:

  ```bash
  cd ..   # run from the parent of chrome-extension/
  zip -r speechwave-extension.zip chrome-extension/ \
    --exclude "chrome-extension/.git/*" \
    --exclude "chrome-extension/node_modules/*" \
    --exclude "chrome-extension/docs/*" \
    --exclude "chrome-extension/tests/*" \
    --exclude "chrome-extension/jest.config.js" \
    --exclude "chrome-extension/package.json" \
    --exclude "chrome-extension/package-lock.json" \
    --exclude "chrome-extension/AGENTS.md" \
    --exclude "chrome-extension/README.md" \
    --exclude "chrome-extension/.gitignore" \
    --exclude "chrome-extension/.DS_Store" \
    --exclude "chrome-extension/.claude/*"
  ```

- [ ] **Verify the zip contents** contain only the expected files:

  ```bash
  unzip -l speechwave-extension.zip | grep -v "/$"
  ```

  Expected files (no dev artifacts):
  ```
  chrome-extension/manifest.json
  chrome-extension/popup/popup.html
  chrome-extension/popup/popup.js
  chrome-extension/content/content.js
  chrome-extension/lib/phoenix.js
  chrome-extension/lib/fireworks.js
  chrome-extension/adapters/google_slides.js
  chrome-extension/adapters/index.js
  chrome-extension/icons/icon16.png
  chrome-extension/icons/icon48.png
  chrome-extension/icons/icon128.png
  chrome-extension/icons/icon.svg
  chrome-extension/LICENSE
  ```

---

### Task 7: Prepare store listing assets

**Produces:** screenshots and optional promotional tile (files, not committed)

- [ ] **Take screenshot 1** — popup in Connected state with slide indicator visible
  - Resize/crop to **1280×800** or **640×400**
  - Save as `screenshot-connected.png`

- [ ] **Take screenshot 2** — emoji reaction overlay floating over a Google Slides presentation in fullscreen
  - Same dimensions
  - Save as `screenshot-overlay.png`

- [ ] **Take screenshot 3** — the API key setup screen
  - Same dimensions
  - Save as `screenshot-setup.png`

- [ ] **(Optional) Create a 440×280 promotional tile** — shown in Web Store search results. A simple branded image with the Speechwave name and icon is sufficient.

---

### Task 8: Create Chrome Web Store developer account

- [ ] Go to `https://chrome.google.com/webstore/devconsole`
- [ ] Sign in with the Google account that will be the permanent publisher identity
- [ ] Pay the **one-time $5 registration fee**
- [ ] Complete identity verification if prompted
- [ ] Confirm you can see the developer dashboard

---

### Task 9: Submit to the Chrome Web Store

Use the store listing content from the spec: `docs/specs/2026-06-17-chrome-extension-production-submission-design.md`.

- [ ] In the developer console, click **New Item**
- [ ] Upload `speechwave-extension.zip`
- [ ] Fill in **Store listing:**
  - **Name:** `Speechwave`
  - **Short description:** `Live emoji reactions from your audience while you present. See real-time feedback and per-slide analytics in your Speechwave dashboard.`
  - **Long description:** copy from spec (the full multi-section text under "Long description")
  - **Category:** Productivity
  - **Language:** English
- [ ] Upload **icons and screenshots:**
  - 128×128 store icon: `icons/icon128.png`
  - Screenshots: `screenshot-connected.png`, `screenshot-overlay.png`, `screenshot-setup.png`
  - Promotional tile (if created)
- [ ] Under **Privacy:**
  - **Privacy policy URL:** `https://speechwave.live/privacy`
  - **Permissions justification:**
    - `storage` — saves your API key and last-used talk slug so you don't re-enter them each session
    - `tabs` — sends messages between the popup and the active Google Slides tab to connect and control your session
- [ ] Under **Distribution:** select **Public**
- [ ] Click **Submit for review**
- [ ] Note the submission date — review typically takes 3–7 business days, up to 2–3 weeks for a first submission

---

## Post-submission

While awaiting review, update the roadmap to mark the "Chrome extension: API key auth" item as submitted and note the expected review window. If the review is delayed beyond 2 weeks, consider the soft launch option described in the spec: publish the web app with a "Chrome extension coming soon" note and use the email consent flow to capture early signees.
