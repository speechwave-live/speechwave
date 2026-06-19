# Chrome Extension: Service Worker Architecture

**Date:** 2026-06-18
**Status:** Approved

## Overview

The extension currently manages the Phoenix WebSocket channel inside `content/content.js`,
which is injected only on `https://docs.google.com/presentation/*` pages. This means
connecting to a talk requires the active tab to be a Google Slides presentation.

The correct design: the connection lives in a **background service worker** that runs
independently of any tab. The content script becomes a display-only overlay consumer
scoped to Google Slides. Connecting, session management, and status reporting all work
from any tab.

---

## Architecture

```
┌──────────┐  chrome.runtime.sendMessage  ┌─────────────────────────┐
│  Popup   │ ────────────────────────────▶ │  Service Worker         │
│ popup.js │ ◀──────────────────────────── │  background/background.js│
└──────────┘  SLIDE_CHANGED, CONNECT_ERROR └──────────┬──────────────┘
                                                       │
                                          chrome.tabs.sendMessage
                                          (Google Slides tabs only)
                                                       │
                                           ┌───────────▼──────────┐
                                           │  Content Script       │
                                           │  content/content.js   │
                                           │  (Slides pages only)  │
                                           └───────────────────────┘
```

### Service Worker responsibilities
- Owns the Phoenix Socket and channel
- Auto-reconnects on startup using slug/apiKey from storage
- Routes all messages: popup ↔ channel ↔ content scripts
- Pushes `slide_changed` events to the channel when content script reports them

### Content Script responsibilities
- Creates and manages the emoji overlay div
- Runs slide change detection and reports to service worker
- Renders emojis and fireworks on receiving `RENDER_EMOJI` from service worker
- No WebSocket, no channel — purely display and detection

### Popup responsibilities
- Sends all messages to the service worker via `chrome.runtime.sendMessage`
- Receives `SLIDE_CHANGED` and `CONNECT_ERROR` messages from service worker
- No `chrome.tabs.sendMessage` calls for core operations

---

## Message Protocol

### Popup → Service Worker

| Type | Payload | Response |
|------|---------|----------|
| `SET_SLUG` | `{ slug, apiKey }` | `{ connected: true }` (optimistic; errors arrive async via CONNECT_ERROR) |
| `GET_STATUS` | — | `{ connected: bool, slide: number }` |
| `START_SESSION` | — | `{ session_id, label }` or `{ error }` |
| `STOP_SESSION` | `{ sessionId }` | `{ stopped: true }` or `{ error }` |
| `SET_FIREWORKS` | `{ enabled }` | none (fire-and-forget) |
| `TEST_FIREWORKS` | — | none (fire-and-forget, DEV_MODE only) |

### Service Worker → Content Scripts (Slides tabs only, via chrome.tabs.query + sendMessage)

| Type | Payload |
|------|---------|
| `RENDER_EMOJI` | `{ emoji }` |
| `SET_FIREWORKS` | `{ enabled }` |
| `TEST_FIREWORKS` | — |

### Content Script → Service Worker

| Type | Payload |
|------|---------|
| `SLIDE_CHANGED` | `{ slide }` |

### Service Worker → Popup (async, popup may be closed — errors suppressed)

| Type | Payload |
|------|---------|
| `SLIDE_CHANGED` | `{ slide }` |
| `CONNECT_ERROR` | `{ reason }` |

---

## File Changes

### New
- `background/background.js` — service worker: Phoenix Socket, channel, message routing,
  auto-reconnect, relay of emojis to Slides tabs

### Modified
- `content/content.js` — remove all WebSocket/channel code; keep overlay, fireworks,
  slide detection; report slide changes to service worker via `chrome.runtime.sendMessage`;
  start slide observer immediately on load
- `popup/popup.js` — replace all `chrome.tabs.query` + `chrome.tabs.sendMessage` blocks
  with `chrome.runtime.sendMessage`; remove manual `chrome.storage.local.set({ slug })`
  (service worker handles it)
- `manifest.json` — add `"background": { "service_worker": "background/background.js" }`;
  remove `lib/phoenix.js` from `content_scripts[0].js` (content.js no longer uses Phoenix)

---

## Phoenix in Service Worker

`lib/phoenix.js` is an IIFE bundle (`var Phoenix = (() => { ... })()`). When loaded
via `importScripts('../lib/phoenix.js')` in the service worker, `Phoenix` is declared
in the service worker global scope and is directly accessible.

The bundle guards all page-lifecycle listeners behind `if (phxWindow && ...)` where
`phxWindow = typeof window !== "undefined" ? window : null`. In a service worker
`window` is undefined, so `phxWindow` is `null` and no `document.*` APIs are accessed.
WebSocket and timers are available in service workers. No compatibility issues.

---

## Auto-Reconnect

The service worker may be terminated by Chrome after inactivity and restarted when a
message arrives or a Chrome event fires. On every startup, the service worker reads
`slug` from `chrome.storage.local` and `apiKey` from `chrome.storage.sync` and calls
`connect()` if both are present. This is equivalent to the auto-connect behavior that
previously lived in the content script.
