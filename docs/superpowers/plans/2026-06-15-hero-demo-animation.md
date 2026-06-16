# Hero Demo Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing single-panel hero mockup on the home page with an animated three-panel demo section (presentation view, phone audience view, analytics) that communicates the full product experience at a glance.

**Architecture:** A new `<section>` is inserted between the hero and "How it works" sections in `home.html.heex`. The phone bezel and float animation are implemented as custom CSS classes in `app.css`. A plain JS `DOMContentLoaded` initializer in `app.js` drives the animation loop — it is a no-op on non-home pages thanks to an early `null` guard.

**Tech Stack:** Tailwind CSS v4 (layout/colors/spacing), raw CSS (phone bezel, keyframe animation), vanilla JS (animation loop), Phoenix HEEx templates.

---

## Files

| Action | File | Purpose |
|---|---|---|
| Modify | `assets/css/app.css` | Phone bezel, tap state, float overlay, `@keyframes demoEmojiFloat` |
| Modify | `lib/speechwave_web/controllers/page_html/home.html.heex` | Remove old mockup, add demo section |
| Modify | `assets/js/app.js` | `DOMContentLoaded` animation loop initializer |

---

## Task 1: Add CSS for the demo section

**Files:**
- Modify: `assets/css/app.css` (append after line 143, end of file)

The existing `@keyframes floatUp` and `.floating-emoji` classes in `app.css` are used by the real talk page and must not be changed. The demo uses distinct class names (`demo-float-emoji`, `demoEmojiFloat`).

- [ ] **Step 1: Append demo CSS to `assets/css/app.css`**

Add the following block at the very end of the file:

```css
/* ── Demo section (home page) ── */

.demo-phone-bezel {
  background: #1a1a1a;
  border-radius: 36px;
  padding: 14px 10px;
  width: 150px;
  box-shadow: 0 12px 32px rgba(0,0,0,0.3), inset 0 0 0 1px rgba(255,255,255,0.05);
}
.demo-phone-notch {
  background: #2a2a2a;
  width: 40px;
  height: 5px;
  border-radius: 3px;
  margin: 0 auto 8px;
}
.demo-phone-screen {
  background: white;
  border-radius: 22px;
  overflow: hidden;
}
.demo-phone-home-bar {
  background: #333;
  width: 40px;
  height: 4px;
  border-radius: 2px;
  margin: 10px auto 0;
}

.demo-emoji-btn {
  font-size: 26px;
  border-radius: 12px;
  padding: 6px;
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: transform 0.12s ease, background 0.12s ease;
}
.demo-emoji-btn.tapping {
  background: rgba(0, 212, 164, 0.18);
  transform: scale(1.28);
}

.demo-emoji-overlay {
  position: absolute;
  bottom: 0;
  right: 0;
  width: 35%;
  height: 45%;
  pointer-events: none;
  overflow: hidden;
}
.demo-float-emoji {
  position: absolute;
  bottom: -30px;
  font-size: 22px;
  animation: demoEmojiFloat 2.0s ease-out forwards;
  pointer-events: none;
}

@keyframes demoEmojiFloat {
  0%   { bottom: 4px;  opacity: 1; transform: translateX(0) scale(1); }
  40%  {               opacity: 1; }
  100% { bottom: 88px; opacity: 0; transform: translateX(var(--demo-drift, 6px)) scale(0.85); }
}
```

- [ ] **Step 2: Verify CSS compiles without errors**

```bash
mix assets.build
```

Expected: no errors, `app.css` bundle rebuilt.

- [ ] **Step 3: Commit**

```bash
git add assets/css/app.css
git commit -m "style: add demo section CSS — phone bezel, tap state, float animation"
```

---

## Task 2: Replace hero mockup and add demo section in home.html.heex

**Files:**
- Modify: `lib/speechwave_web/controllers/page_html/home.html.heex`

The existing product mockup lives inside the hero `<section>` at lines 31–59 (the `<%!-- Product mockup --%>` block). Remove it. Then add the new demo `<section>` between the closing `</section>` of the hero and the opening `<section>` of "How it works".

- [ ] **Step 1: Remove the existing product mockup from the hero**

In `home.html.heex`, delete lines 31–59:

```heex
    <%!-- Product mockup --%>
    <div class="mt-16 max-w-xs mx-auto bg-canvas rounded-2xl border border-hairline-soft shadow-[rgba(0,0,0,0.12)_0px_24px_48px_-8px] overflow-hidden text-left">
      ...the entire div including all its contents...
    </div>
```

The hero `<section>` should end right after the two CTA buttons `</div>` (closing the flex container) then `</div>` (closing `max-w-4xl`) then `</section>`.

- [ ] **Step 2: Add the demo section after the closing `</section>` of the hero**

Insert this block between the hero `</section>` and the `<%!-- How it works --%>` comment:

```heex
<%!-- Demo section --%>
<section class="py-20 px-6 bg-canvas" id="demo-section">
  <div class="max-w-5xl mx-auto">
    <div class="text-center mb-12">
      <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">
        See it in action
      </p>
      <h2 class="text-3xl sm:text-[36px] font-semibold text-ink tracking-tight">
        The full experience, at a glance
      </h2>
    </div>

    <%!-- Top row: presentation panel + phone (stacks on mobile) --%>
    <div class="flex flex-col sm:flex-row gap-5 mb-5 items-start">

      <%!-- Presentation panel --%>
      <div class="sm:flex-[1.6] w-full bg-canvas rounded-2xl border border-hairline shadow-[rgba(0,0,0,0.07)_0px_4px_20px] overflow-hidden">
        <div class="px-4 py-3 border-b border-hairline-soft bg-surface-soft flex items-center gap-3">
          <div class="flex gap-1.5 shrink-0">
            <span class="size-2.5 rounded-full bg-[#ff5f57] inline-block"></span>
            <span class="size-2.5 rounded-full bg-[#ffbd2e] inline-block"></span>
            <span class="size-2.5 rounded-full bg-[#28c940] inline-block"></span>
          </div>
          <span class="text-[11px] text-muted flex-1 text-center">Google Slides presentation</span>
        </div>
        <div class="px-8 pt-8 pb-6 relative min-h-[220px]">
          <div class="text-center mb-4">
            <h3 class="text-lg font-semibold text-ink tracking-tight mb-2">Introducing Speechwave</h3>
            <p class="text-sm text-steel">Real-time audience reactions for your presentations</p>
            <div class="flex gap-2 justify-center mt-4">
              <span class="text-xs font-medium text-mint-deep bg-[#f0f9f6] border border-[#c5f0e4] rounded-full px-3 py-1">Live reactions</span>
              <span class="text-xs font-medium text-mint-deep bg-[#f0f9f6] border border-[#c5f0e4] rounded-full px-3 py-1">Instant feedback</span>
            </div>
          </div>
          <%!-- Float overlay: lower-right corner, ~35% wide × 45% tall of slide body --%>
          <div class="demo-emoji-overlay" id="demo-emoji-overlay"></div>
        </div>
      </div>

      <%!-- Phone panel --%>
      <div class="sm:flex-1 w-full flex justify-center">
        <div class="demo-phone-bezel">
          <div class="demo-phone-notch"></div>
          <div class="demo-phone-screen">
            <div class="flex justify-between items-center px-3 py-1.5 bg-surface-soft border-b border-hairline-soft">
              <span class="text-[8px] font-semibold text-ink">9:41</span>
              <span class="text-[8px] text-ink">●●●</span>
            </div>
            <div class="px-3.5 py-3">
              <p class="text-[9px] font-semibold text-ink mb-0.5">Introducing Speechwave</p>
              <p class="text-[8px] text-muted mb-3.5">React live while you listen</p>
              <div class="grid grid-cols-3 gap-2.5 place-items-center mb-3" id="demo-emoji-grid">
                <div class="demo-emoji-btn" id="demo-btn-0">❤️</div>
                <div class="demo-emoji-btn" id="demo-btn-1">😂</div>
                <div class="demo-emoji-btn" id="demo-btn-2">👏</div>
                <div class="demo-emoji-btn" id="demo-btn-3">🤯</div>
                <div class="demo-emoji-btn" id="demo-btn-4">🎉</div>
                <div class="demo-emoji-btn" id="demo-btn-5">😮</div>
              </div>
              <p class="text-[8px] text-muted text-center">Tap to react</p>
            </div>
          </div>
          <div class="demo-phone-home-bar"></div>
        </div>
      </div>

    </div>

    <%!-- Analytics panel --%>
    <div class="bg-canvas rounded-2xl border border-hairline shadow-[rgba(0,0,0,0.07)_0px_4px_20px] overflow-hidden">
      <div class="px-4 py-3 border-b border-hairline-soft bg-surface-soft flex items-center gap-3">
        <div class="flex gap-1.5 shrink-0">
          <span class="size-2.5 rounded-full bg-[#ff5f57] inline-block"></span>
          <span class="size-2.5 rounded-full bg-[#ffbd2e] inline-block"></span>
          <span class="size-2.5 rounded-full bg-[#28c940] inline-block"></span>
        </div>
        <span class="text-[11px] text-muted flex-1 text-center">Session analytics</span>
      </div>
      <div class="flex flex-col sm:flex-row gap-6 sm:gap-8 p-6">
        <%!-- Summary stats --%>
        <div class="flex sm:flex-col gap-6 sm:gap-4 shrink-0">
          <div>
            <div class="text-3xl font-semibold text-ink leading-none mb-1">247</div>
            <div class="text-[10px] text-muted">Total reactions</div>
          </div>
          <div>
            <div class="text-3xl font-semibold text-ink leading-none mb-1">34</div>
            <div class="text-[10px] text-muted">Audience</div>
          </div>
        </div>
        <%!-- Per-slide breakdown — wraps on mobile --%>
        <div class="flex flex-wrap gap-4 flex-1">
          <%= for {slide_label, bars} <- [
            {"Slide 1", [{"❤️", 85, 42}, {"😂", 55, 27}, {"👏", 40, 20}, {"🎉", 30, 15}]},
            {"Slide 3", [{"🤯", 90, 36}, {"😮", 70, 28}, {"👏", 50, 20}, {"❤️", 25, 10}]},
            {"Slide 5", [{"👏", 100, 51}, {"❤️", 65, 33}, {"🎉", 45, 23}, {"😂", 20, 10}]},
            {"Slide 7", [{"🎉", 80, 32}, {"😮", 60, 24}, {"❤️", 35, 14}, {"🤯", 18, 7}]}
          ] do %>
            <div class="min-w-[130px] flex-1">
              <p class="text-[10px] font-semibold text-steel uppercase tracking-[0.3px] mb-2">{slide_label}</p>
              <%= for {emoji, pct, count} <- bars do %>
                <div class="flex items-center gap-1.5 mb-1.5">
                  <span class="text-xs w-4 text-center">{emoji}</span>
                  <div class="flex-1 h-1.5 bg-surface rounded-full overflow-hidden">
                    <div class="h-full bg-mint rounded-full" style={"width: #{pct}%"}></div>
                  </div>
                  <span class="text-[9px] text-muted w-4 text-right">{count}</span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>

  </div>
</section>
```

- [ ] **Step 3: Run precommit checks**

```bash
mix precommit
```

Expected: no errors or warnings. Fix any formatter issues before continuing.

- [ ] **Step 4: Commit**

```bash
git add lib/speechwave_web/controllers/page_html/home.html.heex
git commit -m "feat: add hero demo section — presentation, phone, and analytics panels"
```

---

## Task 3: Add JS animation loop to app.js

**Files:**
- Modify: `assets/js/app.js` (insert before the `if (process.env.NODE_ENV === "development")` block, around line 57)

- [ ] **Step 1: Insert the animation initializer into `app.js`**

Add this block after `window.liveSocket = liveSocket` and before `if (process.env.NODE_ENV === "development")`:

```js
// Home page demo animation — no-op on pages without #demo-emoji-overlay
document.addEventListener("DOMContentLoaded", () => {
  const overlay = document.getElementById("demo-emoji-overlay")
  if (!overlay) return

  const emojis = ["❤️", "😂", "👏", "🤯", "🎉", "😮"]
  const drifts = ["-8px", "5px", "-4px", "9px", "-6px", "7px"]
  let step = 0

  function spawnFloat(emoji, drift) {
    const el = document.createElement("div")
    el.className = "demo-float-emoji"
    el.textContent = emoji
    el.style.setProperty("--demo-drift", drift)
    const w = overlay.offsetWidth
    el.style.left = (8 + Math.random() * Math.max(0, w - 36)) + "px"
    overlay.appendChild(el)
    setTimeout(() => el.remove(), 2100)
  }

  function tick() {
    const i = step % emojis.length
    const btn = document.getElementById("demo-btn-" + i)
    if (btn) {
      btn.classList.add("tapping")
      setTimeout(() => btn.classList.remove("tapping"), 480)
    }
    setTimeout(() => spawnFloat(emojis[i], drifts[i]), 360)
    step++
    setTimeout(tick, 1800)
  }

  setTimeout(tick, 700)
})
```

- [ ] **Step 2: Run precommit checks**

```bash
mix precommit
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add assets/js/app.js
git commit -m "feat: add demo section animation loop"
```

---

## Task 4: Manual verification

This is a visual feature — automated tests cannot verify the animation, layout, or responsive behaviour. Verify manually against the approved mockup.

- [ ] **Step 1: Start the dev server**

```bash
mix phx.server
```

Open `http://localhost:4000` in a browser.

- [ ] **Step 2: Verify desktop layout**

Checklist:
- [ ] Old single-phone mockup is gone from the hero section
- [ ] "See it in action" section appears between the hero and "How it works"
- [ ] Presentation panel (wider) and phone bezel sit side by side
- [ ] Analytics panel spans full width below
- [ ] Phone emoji button pulses mint-green every ~1.8s
- [ ] Corresponding emoji floats upward in the lower-right corner of the presentation panel
- [ ] Float disappears near the top of the overlay zone (not clipped abruptly)

- [ ] **Step 3: Verify mobile layout**

Resize the browser window below 640px (or use browser DevTools responsive mode).

Checklist:
- [ ] Presentation panel stacks above phone bezel (phone wraps below)
- [ ] Analytics slide cards wrap to multiple rows (no horizontal scroll)
- [ ] Summary stats and slide cards are still readable

- [ ] **Step 4: Run final precommit**

```bash
mix precommit
```

Expected: clean.
