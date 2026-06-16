# Hero Demo Animation — Design Spec

**Date:** 2026-06-15
**Status:** Approved

## Problem

The current home page hero contains a single small browser-window mockup showing only the audience mobile view (emoji reaction buttons). It is an inaccurate and incomplete representation of the product — it shows one of three surfaces and gives no sense of the real-time, animated nature of the experience.

## Goal

Replace the existing hero mockup with a three-panel animated demo section that communicates the full product experience — presenter view, audience mobile view, and post-talk analytics — at a glance to a first-time visitor.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Placement | Separate section below hero | Hero stays compact (text + CTA). Demo gets its own breathing room with a section heading. |
| Presentation frame | Simple browser chrome (3 dots + label) | Matches existing mockup style; cleaner than full Google Slides UI |
| Mobile frame | Phone bezel | Immediately communicates "audience uses their phone" without words |
| Animation implementation | CSS keyframes + small JS timer | Clean choreography between panels; easy to tune; ~30 lines, no framework |
| Animation trigger | Continuous loop | Catches the eye as visitors scroll past; feels alive |

## Layout

### Desktop

```
┌─────────────────────────────────────┐  ┌──────────────────┐
│  ● ● ●  Google Slides presentation  │  │  [phone bezel]   │
│                                     │  │                  │
│  Slide title / content              │  │  Talk title      │
│                                     │  │                  │
│                          [emoji     │  │  ❤️  😂  👏      │
│                           overlay]  │  │  🤯  🎉  😮      │
└─────────────────────────────────────┘  └──────────────────┘

┌────────────────────────────────────────────────────────────┐
│  ● ● ●  Session analytics                                  │
│                                                            │
│  247          Slide 1   Slide 3   Slide 5   Slide 7        │
│  reactions    ❤️ ████   🤯 ████   👏 ████   🎉 ████        │
│               😂 ███    😮 ███    ❤️ ███    😮 ███         │
│  34                                                        │
│  audience                                                  │
└────────────────────────────────────────────────────────────┘
```

The presentation panel is wider (~1.6x) than the phone panel. Both panels share the same simple chrome style (macOS-style dots + text label). The analytics panel spans full width below.

### Mobile (≤640px)

- Top row stacks vertically: presentation panel first, phone bezel centered below
- Analytics slide cards wrap to multiple rows instead of scrolling horizontally
- Section padding reduces from 48px to 32px

## Presentation Panel

- Browser chrome: macOS dots + label "Google Slides presentation"
- Slide content occupies the full panel body (no divider or separate zone)
- Emoji float overlay is positioned absolutely in the **lower-right corner only**, approximately 35% wide × 45% tall of the slide area — matching how the real Chrome extension overlays the presenter's screen
- Floats animate upward with slight horizontal drift and fade out near the top of the overlay

## Phone Panel

- Dark phone bezel (CSS, no images) with rounded corners, speaker notch, home bar
- Inner screen shows: status bar, talk title, subtitle, 3×2 emoji grid, "Tap to react" label
- Tap animation: button background flashes mint-green and scales up briefly

## Analytics Panel

- Browser chrome: same dots + label "Session analytics"
- Summary stats on the left: total reactions count, audience count
- Per-slide breakdown on the right: each slide is a card with emoji + horizontal bar + count, bars filled with mint (`#00d4a4`)
- Static data (representative, not live): 4 slides shown (Slides 1, 3, 5, 7) with varied emoji distributions

## Animation Loop

Implemented as a plain JS initializer (~30 lines) in `app.js`. The home page is controller-rendered (not LiveView), so `phx-hook` and colocated hook scripts are not available. The initializer runs on `DOMContentLoaded`, selects the section by a stable DOM id, and starts the loop.

**Cycle (repeats every ~1.8s per emoji, 6 emojis total = ~11s full loop):**

1. Highlight phone emoji button (mint background + scale up, 480ms)
2. After 360ms delay: spawn floating emoji in the slide overlay
3. Float rises upward over ~2.0s, fades out near top
4. Advance to next emoji, repeat

Multiple floats can be in flight simultaneously as the cycle continues. Horizontal position within the overlay is randomized on each spawn to avoid a static column.

## File Changes

- `lib/speechwave_web/controllers/page_html/home.html.heex` — remove existing hero mockup div; add new "See it in action" section between hero and "How it works"
- `assets/js/app.js` — add plain JS initializer (runs on `DOMContentLoaded`) for the animation loop
- `assets/css/app.css` — add `@keyframes floatUp` and supporting classes (`.float-emoji`, `.emoji-btn.tapping`, phone bezel styles)

## Out of Scope

- Actual screenshots of the product
- Video or GIF
- LiveView socket connection (purely presentational)
- Scroll-into-view trigger (continuous loop only)
