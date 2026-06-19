# Chrome Extension: Service Worker Architecture

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Phoenix WebSocket connection from the content script into a background service worker so the extension connects to a talk from any tab, with the Google Slides content script becoming a display-only overlay.

**Architecture:** A new `background/background.js` service worker owns the Phoenix Socket and channel; it relays emojis to Slides tabs and slide changes to the channel. `content/content.js` is stripped to overlay + slide detection only. `popup/popup.js` sends all messages to the service worker via `chrome.runtime.sendMessage`.

**Tech Stack:** Chrome Extension Manifest V3, JavaScript service worker, Phoenix JS (UMD, loaded via `importScripts`), chrome.runtime / chrome.tabs messaging APIs.

**Spec:** `docs/specs/2026-06-18-extension-service-worker-design.md`

**All paths are relative to the `chrome-extension/` repo root** (`../chrome-extension/` from the `speechwave/` app). Work on branch `feature/production-submission`.

---

### Task 1: Create background/background.js

**Files:**
- Create: `background/background.js`

- [ ] **Create the `background/` directory and write `background/background.js`** with the full contents below:

```js
importScripts('../lib/phoenix.js');
const { Socket } = Phoenix;

const DEV_MODE = false; // set to true locally for testing
const HOST = DEV_MODE ? "ws://localhost:4000" : "wss://speechwave.live";

let socket = null;
let channel = null;
let currentSlide = 0;
let intentionalDisconnect = false;

function connect(slug, apiKey) {
  if (socket) {
    intentionalDisconnect = true;
    socket.disconnect();
    socket = null;
    channel = null;
    currentSlide = 0;
  }

  socket = new Socket(`${HOST}/socket`, {
    logger: (kind, msg, data) => console.debug(`[Speechwave] ${kind}: ${msg}`, data)
  });
  socket.onError(() => console.error("[Speechwave] Socket error — check HOST and server"));
  socket.connect();

  channel = socket.channel(`reactions:${slug}`, { api_key: apiKey });

  channel.on("new_reaction", ({ emoji }) => {
    chrome.tabs.query({ url: "https://docs.google.com/presentation/*" }, (tabs) => {
      tabs.forEach(tab => {
        chrome.tabs.sendMessage(tab.id, { type: "RENDER_EMOJI", emoji }, () => {
          void chrome.runtime.lastError;
        });
      });
    });
  });

  channel
    .join()
    .receive("ok", () => {
      console.log(`[Speechwave] Joined reactions:${slug}`);
    })
    .receive("error", ({ reason }) => {
      console.error(`[Speechwave] Channel join failed: ${reason}`);
      socket.disconnect();
      socket = null;
      channel = null;
      notifyPopup({ type: "CONNECT_ERROR", reason });
    });

  channel.onClose(() => {
    if (intentionalDisconnect) {
      intentionalDisconnect = false;
      return;
    }
    socket = null;
    channel = null;
    notifyPopup({ type: "CONNECT_ERROR", reason: "key_updated" });
  });
}

function isConnected() {
  return socket !== null && socket.isConnected();
}

function notifyPopup(msg) {
  chrome.runtime.sendMessage(msg, () => void chrome.runtime.lastError);
}

function broadcastToSlidesTabs(msg) {
  chrome.tabs.query({ url: "https://docs.google.com/presentation/*" }, (tabs) => {
    tabs.forEach(tab => {
      chrome.tabs.sendMessage(tab.id, msg, () => void chrome.runtime.lastError);
    });
  });
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === "SET_SLUG") {
    chrome.storage.local.set({ slug: msg.slug });
    connect(msg.slug, msg.apiKey);
    sendResponse({ connected: true });
  } else if (msg.type === "GET_STATUS") {
    sendResponse({ connected: isConnected(), slide: currentSlide });
  } else if (msg.type === "START_SESSION") {
    if (!channel) {
      sendResponse({ error: "not_connected" });
      return;
    }
    channel
      .push("start_session", {})
      .receive("ok", ({ session_id, label }) => sendResponse({ session_id, label }))
      .receive("error", ({ reason }) => sendResponse({ error: reason }));
    return true; // keep message channel open for async reply
  } else if (msg.type === "STOP_SESSION") {
    if (!channel) {
      sendResponse({ error: "not_connected" });
      return;
    }
    channel
      .push("stop_session", { session_id: msg.sessionId })
      .receive("ok", () => sendResponse({ stopped: true }))
      .receive("error", ({ reason }) => sendResponse({ error: reason }));
    return true; // keep message channel open for async reply
  } else if (msg.type === "SLIDE_CHANGED") {
    currentSlide = msg.slide;
    if (channel) channel.push("slide_changed", { slide: currentSlide });
    notifyPopup({ type: "SLIDE_CHANGED", slide: currentSlide });
  } else if (msg.type === "SET_FIREWORKS") {
    broadcastToSlidesTabs({ type: "SET_FIREWORKS", enabled: msg.enabled });
  } else if (msg.type === "TEST_FIREWORKS") {
    broadcastToSlidesTabs({ type: "TEST_FIREWORKS" });
  }
});

// Auto-reconnect on service worker startup (also fires after SW is terminated and restarted)
chrome.storage.local.get("slug", ({ slug }) => {
  if (slug) {
    chrome.storage.sync.get("apiKey", ({ apiKey }) => {
      if (apiKey) connect(slug, apiKey);
    });
  }
});
```

- [ ] **Commit:**

```bash
git add background/background.js
git commit -m "feat: add service worker to manage Phoenix socket connection"
```

---

### Task 2: Update manifest.json

**Files:**
- Modify: `manifest.json`

- [ ] **Add the `background` key and remove `lib/phoenix.js` from the content script's JS array.** Replace the full contents of `manifest.json` with:

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
  "background": {
    "service_worker": "background/background.js"
  },
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
      "js": ["lib/fireworks.js", "adapters/google_slides.js", "adapters/index.js", "content/content.js"],
      "run_at": "document_idle"
    }
  ]
}
```

Note: `lib/phoenix.js` is removed from `content_scripts[0].js` because `content.js` no longer uses Phoenix. The service worker loads it via `importScripts`.

- [ ] **Verify the JSON is valid:**

```bash
node -e "JSON.parse(require('fs').readFileSync('manifest.json', 'utf8')); console.log('valid')"
```

Expected output: `valid`

- [ ] **Commit:**

```bash
git add manifest.json
git commit -m "fix: add service worker to manifest, remove phoenix from content script"
```

---

### Task 3: Simplify content/content.js

**Files:**
- Modify: `content/content.js`

The content script no longer manages the WebSocket. Remove the Phoenix import, all socket/channel variables, `connect()`, `isConnected()`, and the handlers for `SET_SLUG`, `GET_STATUS`, `START_SESSION`, `STOP_SESSION`. Keep overlay, fireworks, and slide detection. The slide observer now always starts on page load (no longer gated on a channel join). Slide changes go to the service worker via `chrome.runtime.sendMessage`.

- [ ] **Replace the full contents of `content/content.js`** with:

```js
const FIREWORKS_MIN_COUNT = 5;
const FIREWORKS_MIN_PERCENT = 0.4;
const FIREWORKS_COOLDOWN_MS = 8000;
const FIREWORKS_BURST_COUNT = 16;

const inFlight = {};
let fireworksEnabled = false;
let fireworksActive = false;
let lastFireworksTime = 0;
let slideInterval = null;
let currentSlide = 0;

const style = document.createElement("style");
style.textContent = `
  @keyframes speechwaveFloat {
    0%   { transform: translateY(0);    opacity: 1; }
    100% { transform: translateY(-60px); opacity: 0; }
  }
`;
document.head.appendChild(style);

function getOrCreateOverlay() {
  let overlay = document.getElementById("speechwave-overlay");
  if (!overlay) {
    overlay = document.createElement("div");
    overlay.id = "speechwave-overlay";
    overlay.style.cssText = [
      "position: fixed",
      "bottom: 40px",
      "right: 20px",
      "width: 160px",
      "height: 200px",
      "pointer-events: none",
      "z-index: 999999",
      "overflow: hidden",
    ].join(";");
    document.body.appendChild(overlay);
  }
  return overlay;
}

document.addEventListener("fullscreenchange", () => {
  const overlay = document.getElementById("speechwave-overlay");
  if (!overlay) return;
  if (document.fullscreenElement) {
    document.fullscreenElement.appendChild(overlay);
  } else {
    document.body.appendChild(overlay);
  }
});

function spawnEmoji(emoji) {
  inFlight[emoji] = (inFlight[emoji] || 0) + 1;

  const overlay = getOrCreateOverlay();
  const el = document.createElement("span");
  el.textContent = emoji;
  el.style.cssText = [
    "position: absolute",
    "bottom: 0",
    `left: ${Math.floor(Math.random() * 70)}%`,
    "font-size: 28px",
    "animation: speechwaveFloat 2.5s ease-out forwards",
    "pointer-events: none",
  ].join(";");
  overlay.appendChild(el);
  el.addEventListener("animationend", () => {
    el.remove();
    inFlight[emoji] = Math.max(0, (inFlight[emoji] || 0) - 1);
    if (inFlight[emoji] === 0) delete inFlight[emoji];
  });

  maybeSpawnFireworks(emoji);
}

function maybeSpawnFireworks(emoji) {
  if (!fireworksEnabled) return;
  if (fireworksActive) return;
  if (Date.now() - lastFireworksTime < FIREWORKS_COOLDOWN_MS) return;
  if (window.SpeechwaveFireworks.checkFireworksTrigger(inFlight, emoji, {
    minCount: FIREWORKS_MIN_COUNT,
    minPercent: FIREWORKS_MIN_PERCENT,
  })) {
    spawnFireworks(emoji);
  }
}

function spawnFireworks(emoji) {
  fireworksActive = true;
  lastFireworksTime = Date.now();

  if (FIREWORKS_BURST_COUNT === 0) {
    fireworksActive = false;
    return;
  }

  const overlay = getOrCreateOverlay();
  const cx = 80;
  const cy = 100;
  let remaining = FIREWORKS_BURST_COUNT;
  const safetyTimer = setTimeout(() => { fireworksActive = false; }, 2000);

  for (let i = 0; i < FIREWORKS_BURST_COUNT; i++) {
    const angle = (i / FIREWORKS_BURST_COUNT) * 2 * Math.PI;
    const dist = 60 + Math.random() * 40;
    const tx = Math.round(Math.cos(angle) * dist);
    const ty = Math.round(Math.sin(angle) * dist);
    const delay = Math.random() * 300;

    const el = document.createElement("span");
    el.textContent = emoji;
    el.style.cssText = [
      "position: absolute",
      `left: ${cx}px`,
      `top: ${cy}px`,
      "font-size: 24px",
      "pointer-events: none",
    ].join(";");
    overlay.appendChild(el);

    const anim = el.animate(
      [
        { transform: "translate(0, 0) scale(1)", opacity: 1 },
        { transform: `translate(${tx}px, ${ty}px) scale(0.3)`, opacity: 0 },
      ],
      { duration: 1200, delay, easing: "ease-out", fill: "forwards" }
    );
    anim.addEventListener("finish", () => {
      el.remove();
      remaining--;
      if (remaining === 0) {
        clearTimeout(safetyTimer);
        fireworksActive = false;
      }
    });
  }
}

function startSlideObserver() {
  const registry = window.SpeechwaveAdapterRegistry;
  if (!registry) return;

  const adapter = registry.getAdapter(window.location.href);
  if (!adapter) return;

  function checkSlide() {
    const slide = adapter.getSlide();
    if (slide !== currentSlide) {
      currentSlide = slide;
      chrome.runtime.sendMessage({ type: "SLIDE_CHANGED", slide: currentSlide }, () => {
        void chrome.runtime.lastError;
      });
    }
  }

  checkSlide();
  slideInterval = setInterval(checkSlide, 500);
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === "RENDER_EMOJI") {
    spawnEmoji(msg.emoji);
  } else if (msg.type === "SET_FIREWORKS") {
    fireworksEnabled = msg.enabled;
  } else if (msg.type === "TEST_FIREWORKS") {
    if (!fireworksActive) {
      const testEmojis = ["❤️", "😂", "👏", "🤯", "🙋🏻", "🎉", "💩", "😮", "🎯"];
      spawnFireworks(testEmojis[Math.floor(Math.random() * testEmojis.length)]);
    }
  }
});

getOrCreateOverlay();
startSlideObserver();

chrome.storage.sync.get({ fireworksEnabled: true }, ({ fireworksEnabled: val }) => {
  fireworksEnabled = val;
});
```

- [ ] **Confirm the tests still pass** (content.js is not directly tested, but verify nothing else broke):

```bash
npm test
```

Expected: 14 tests pass, 0 failures.

- [ ] **Commit:**

```bash
git add content/content.js
git commit -m "refactor: strip content script to overlay/slide-detection only"
```

---

### Task 4: Update popup/popup.js

**Files:**
- Modify: `popup/popup.js`

Replace all `chrome.tabs.query` + `chrome.tabs.sendMessage` calls with `chrome.runtime.sendMessage`. Remove the manual `chrome.storage.local.set({ slug })` from the connect handler (the service worker saves slug when it handles `SET_SLUG`).

- [ ] **Replace the full contents of `popup/popup.js`** with:

```js
const DEV_MODE = false; // set to true locally for testing

// --- DOM references ---
const setupSection = document.getElementById("setup-section");
const mainSection = document.getElementById("main-section");
const apiKeyInput = document.getElementById("api-key-input");
const saveApiKeyBtn = document.getElementById("save-api-key-btn");

const slugInput = document.getElementById("slug-input");
const connectBtn = document.getElementById("connect-btn");
const dot = document.getElementById("dot");
const statusText = document.getElementById("status-text");
const sessionSection = document.getElementById("session-section");
const sessionStatus = document.getElementById("session-status");
const sessionBtn = document.getElementById("session-btn");
const slideIndicator = document.getElementById("slide-indicator");
const fireworksToggle = document.getElementById("fireworks-toggle");
const testFireworksBtn = document.getElementById("test-fireworks-btn");
const errorMsg = document.getElementById("error-msg");

let currentSessionId = null;
let storedApiKey = null;

function setError(msg) {
  if (msg) {
    errorMsg.textContent = msg;
    errorMsg.style.display = "block";
  } else {
    errorMsg.textContent = "";
    errorMsg.style.display = "none";
  }
}

function showSetup() {
  setupSection.style.display = "block";
  mainSection.style.display = "none";
}

function showMain() {
  setupSection.style.display = "none";
  mainSection.style.display = "block";
}

function setStatus(connected) {
  dot.className = "dot" + (connected ? " connected" : "");
  statusText.textContent = connected ? "Connected" : "Disconnected";
  connectBtn.textContent = connected ? "Disconnect" : "Connect";
  sessionSection.style.display = connected ? "block" : "none";
}

function setSessionUI(active, label) {
  sessionStatus.textContent = active ? label : "No active session";
  sessionBtn.textContent = active ? "Stop Session" : "Start Session";
  sessionBtn.className = active ? "stop" : "";
}

function setSlideIndicator(slide) {
  slideIndicator.textContent = slide > 0 ? `Slide ${slide}` : "Slide —";
}

// --- API key setup ---
document.getElementById("change-api-key-link").addEventListener("click", (e) => {
  e.preventDefault();
  showSetup();
});

saveApiKeyBtn.addEventListener("click", () => {
  const key = apiKeyInput.value.trim();
  if (!key) return;
  chrome.storage.sync.set({ apiKey: key }, () => {
    storedApiKey = key;
    showMain();
    setError(null);
  });
});

// --- Fireworks ---
chrome.storage.sync.get({ fireworksEnabled: true }, ({ fireworksEnabled }) => {
  fireworksToggle.checked = fireworksEnabled;
});

fireworksToggle.addEventListener("change", () => {
  const enabled = fireworksToggle.checked;
  chrome.storage.sync.set({ fireworksEnabled: enabled });
  chrome.runtime.sendMessage({ type: "SET_FIREWORKS", enabled }, () => {
    void chrome.runtime.lastError;
  });
});

if (DEV_MODE) {
  testFireworksBtn.style.display = "block";
  testFireworksBtn.addEventListener("click", () => {
    chrome.runtime.sendMessage({ type: "TEST_FIREWORKS" }, () => {
      void chrome.runtime.lastError;
    });
  });
}

// --- Connect ---
connectBtn.addEventListener("click", () => {
  const slug = slugInput.value.trim();
  if (!slug || !storedApiKey) return;
  setError(null);
  chrome.runtime.sendMessage({ type: "SET_SLUG", slug, apiKey: storedApiKey }, (response) => {
    setStatus(response?.connected ?? false);
  });
});

// --- Session ---
sessionBtn.addEventListener("click", () => {
  setError(null);
  if (currentSessionId) {
    chrome.runtime.sendMessage({ type: "STOP_SESSION", sessionId: currentSessionId }, (response) => {
      if (response?.stopped) {
        currentSessionId = null;
        chrome.storage.local.remove("sessionId");
        setSessionUI(false);
      }
    });
  } else {
    chrome.runtime.sendMessage({ type: "START_SESSION" }, (response) => {
      if (response?.session_id) {
        currentSessionId = response.session_id;
        chrome.storage.local.set({ sessionId: response.session_id });
        setSessionUI(true, response.label);
      } else if (response?.error) {
        const messages = {
          session_limit_reached: "Monthly session limit reached",
          not_connected: "Not connected to a talk",
        };
        setError(messages[response.error] || "Could not start session");
      }
    });
  }
});

// --- Init ---
chrome.storage.sync.get(["apiKey"], ({ apiKey }) => {
  if (apiKey) {
    storedApiKey = apiKey;
    showMain();

    chrome.storage.local.get(["slug", "sessionId"], ({ slug, sessionId }) => {
      if (slug) slugInput.value = slug;
      if (sessionId) {
        currentSessionId = sessionId;
        setSessionUI(true, "Session active");
      }
    });

    chrome.runtime.sendMessage({ type: "GET_STATUS" }, (response) => {
      setStatus(response?.connected ?? false);
      setSlideIndicator(response?.slide ?? 0);
    });
  } else {
    showSetup();
  }
});

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === "SLIDE_CHANGED") {
    setSlideIndicator(msg.slide);
  } else if (msg.type === "CONNECT_ERROR") {
    const messages = {
      capacity_reached: "Talk is at capacity",
      unauthorized: "Invalid API key or you don't own this talk",
      email_not_confirmed: "Please confirm your email before using the extension",
      not_found: "Talk not found",
      key_updated: "Your API key was regenerated. Please update it in the extension.",
    };
    setError(messages[msg.reason] || "Connection failed");
    setStatus(false);
  }
});
```

- [ ] **Run the tests one final time:**

```bash
npm test
```

Expected: 14 tests pass, 0 failures.

- [ ] **Commit:**

```bash
git add popup/popup.js
git commit -m "refactor: route all popup messages through service worker"
```

---

### Task 5: Smoke-test the extension unpacked

This is a quick sanity check before full manual testing (Task 5 in the production submission plan). Full scenario testing happens there.

- [ ] **Load the extension unpacked in Chrome:**
  1. Open `chrome://extensions`
  2. Enable Developer mode (top-right toggle)
  3. Click **Load unpacked** and select the `chrome-extension/` directory
  4. Confirm no errors appear in the extension's service worker console
     (click "Service Worker" link on the extension card → check for red errors)

- [ ] **Verify service worker loads Phoenix:**
  1. In the service worker DevTools console, type: `Phoenix`
  2. Expected: the Phoenix object is printed, not `undefined`

- [ ] **Verify basic message routing:**
  1. Open the popup on any non-Slides tab
  2. Enter a real slug and click Connect
  3. Expected: popup shows "Connected" (green dot); service worker console shows `[Speechwave] Joined reactions:<slug>`
  4. Navigate to `https://docs.google.com/presentation/` (any presentation)
  5. Expected: emoji overlay div exists in the page (inspect → `document.getElementById("speechwave-overlay")` is non-null)

- [ ] **Commit a note if any issues were found and fixed:**

```bash
git add -A
git commit -m "fix: <describe what was fixed>"
```
