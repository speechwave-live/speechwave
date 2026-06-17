# Chrome Extension: Production Readiness & Web Store Submission

**Date:** 2026-06-17
**Status:** Approved

## Overview

The Speechwave Chrome extension already implements API key authentication, the
setup screen, and all required error handling (as of commit `605946b`). The
remaining work falls into three areas:

1. **Code changes** — update hardcoded URLs to point at `speechwave.live`, add icons
2. **Testing** — end-to-end verification of the full authenticated flow against the live server
3. **Chrome Web Store submission** — account setup, store listing assets, and submission

---

## Code Changes

### Host URL (`content/content.js`)

Replace the hardcoded localhost constant with a flag-driven value:

```js
const DEV_MODE = false; // set to true locally for testing
const HOST = DEV_MODE ? "ws://localhost:4000" : "wss://speechwave.live";
```

The `DEV_MODE` flag already controls the test fireworks button; tying HOST to
it keeps the dev/prod distinction in one place. Developers set `DEV_MODE =
true` for local testing and revert before packaging for submission.

### Manifest (`manifest.json`)

- Replace `https://speechwave.fly.dev/*` with `https://speechwave.live/*` in
  `host_permissions`
- Keep `http://localhost/*` for local development
- Add `icons` block and update `action.default_icon` (see Icons section below)

### Popup settings link (`popup/popup.html`)

Update the Account Settings link from `https://speechwave.fly.dev/users/settings`
to `https://speechwave.live/users/settings`.

### Icons

The extension currently has no icons. Required files in an `icons/` directory:

| File | Size | Used in |
|------|------|---------|
| `icons/icon16.png` | 16×16 | Browser toolbar |
| `icons/icon48.png` | 48×48 | Extension management page |
| `icons/icon128.png` | 128×128 | Chrome Web Store listing |

Reference them in the manifest:

```json
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
}
```

Design at 128×128 (use the Speechwave microphone visual or a mic/wave mark)
and downsample to 48 and 16. Export all three as PNG.

---

## Testing Plan

All scenarios require a real account on `speechwave.live` and the extension
sideloaded unpacked in Chrome developer mode (`chrome://extensions` →
"Load unpacked"). Ensure `DEV_MODE = false` before testing against production.

### Scenarios

**1. First-run setup**
- Open popup with no API key stored → setup screen appears
- Enter a valid API key → main screen appears
- Close and reopen popup → main screen persists (key stored in sync storage)

**2. Connect and react**
- Enter a valid talk slug → click Connect → status shows Connected
- Open the attendee page for that talk in another tab, send reactions →
  emoji float up in the overlay on the Google Slides tab
- Advance slides in Google Slides → slide indicator in popup updates

**3. Session lifecycle**
- Click Start Session → session appears in the Speechwave dashboard
- Click Stop Session → session ends, dashboard reflects it

**4. Error paths**
- Wrong API key → popup shows "Invalid API key or you don't own this talk"
- Nonexistent talk slug → "Talk not found"
- Regenerate API key in Settings while connected → popup shows "Your API key
  was regenerated. Please update it in the extension." and disconnects
- At-capacity talk (requires a talk at the 50-participant limit) → "Talk is at capacity"

**5. Persistence**
- Enter a slug, connect, close Chrome, reopen → slug is restored in the input
- Navigate away from and back to a Google Slides presentation → auto-reconnect fires

**6. DEV_MODE sanity**
- Set `DEV_MODE = true` → HOST resolves to `ws://localhost:4000`, test
  fireworks button appears in popup
- Set `DEV_MODE = false` → HOST resolves to `wss://speechwave.live`, test
  fireworks button is hidden

---

## Chrome Web Store Account Setup

1. Go to `chrome.google.com/webstore/devconsole` and sign in with the Google
   account that will serve as the long-term publisher
2. Pay the one-time **$5 registration fee**
3. Complete identity verification if prompted

Use an account you control permanently — it becomes the publisher identity
visible to users and cannot easily be transferred.

---

## Store Listing Content

### Name
`Speechwave`

### Short description (129 chars)
```
Live emoji reactions from your audience while you present. See real-time feedback and per-slide analytics in your Speechwave dashboard.
```

### Long description
```
Speechwave brings your audience into the room — even when they're remote.

While you present in Google Slides, your attendees send live emoji reactions from any device using just a QR code or link. The reactions float up as a subtle overlay so you get real-time feedback without breaking your flow.

HOW IT WORKS

1. Create a free account at speechwave.live
2. Create a talk in your dashboard and get your unique link or QR code
3. Share it with your audience at the start of your presentation
4. Connect the extension to your talk — one-time API key setup
5. Start a session when you're ready, and watch reactions come in live

FEATURES

• Live emoji reactions — see audience sentiment in real time as you present
• Per-slide analytics — review which slides generated the most engagement after each talk
• Fireworks animations — when reactions surge, a burst effect fires automatically (optional)
• Session tracking — start and stop sessions manually so each talk is tracked separately
• Works across devices — your audience joins from phone, tablet, or laptop; nothing to install

REQUIREMENTS

A free Speechwave account (speechwave.live). Your API key is displayed in Account Settings after you log in.

FREE TO USE

The Speechwave free plan includes up to 50 participants per talk and 10 full sessions per month. No credit card required.

PRIVACY

Speechwave stores only your API key and last-used talk slug in Chrome sync storage. No browsing data is collected or transmitted.
```

### Category
Productivity

### Permissions justification (displayed to users and reviewed by Google)

- **storage** — saves your API key and last-used talk slug so you don't have to re-enter them each session
- **tabs** — sends messages between the popup and the active Google Slides tab to connect and control your session

### Privacy policy URL
`https://speechwave.live/privacy`

---

## Screenshots

At least one required; 2–3 recommended. Dimensions: 1280×800 or 640×400 PNG or JPEG.

Suggested shots:
1. Popup in Connected state with slide indicator visible
2. Emoji reaction overlay floating over a Google Slides presentation in fullscreen
3. The setup/API key entry screen

Optional: a 440×280 promotional tile PNG for search result display in the Web Store.

---

## Zip Packaging

Include only runtime files. Exclude development and documentation artifacts.

**Include:**
```
manifest.json
popup/
content/
lib/
adapters/
icons/
```

**Exclude:** `node_modules/`, `.git/`, `docs/`, `tests/`, `jest.config.js`,
`package.json`, `package-lock.json`, `AGENTS.md`, `README.md`, `.gitignore`

---

## Submission Steps

1. In the developer console, click **New Item** and upload the `.zip`
2. Fill in the store listing fields using the content above
3. Upload the 128×128 icon and screenshots
4. Under **Privacy**, enter `https://speechwave.live/privacy`
5. Under **Distribution**, select **Public**
6. Submit for review

---

## Timeline

Google's review time for new extensions is typically **3–7 business days**,
but first submissions can take **2–3 weeks**. Submit as early as possible
once the extension is tested. The web app is fully functional independently —
if review is delayed, the soft launch option is to make the app publicly
accessible while noting "Chrome extension coming soon" on the landing page.
