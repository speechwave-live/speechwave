# OG / SEO meta tags — design

Deferred item from `docs/roadmap.md` ("OG / SEO meta tags"): add
`<meta name="description">` and Open Graph / Twitter card tags to public pages
so links share well and search engines have context.

## Scope

Four public pages, all reachable without authentication:

- `/` (`PageController.home`)
- `/pricing` (`PricingLive`)
- `/terms` (`PageController.terms`)
- `/privacy` (`PageController.privacy`)

Authenticated app pages (dashboard, talk, session analytics, settings, etc.)
are out of scope — they aren't meant to be shared or indexed.

## Image asset

A single shared Open Graph image is used across all four pages (per-page
custom images are more design effort than this item calls for).

- Source mockup: `docs/og_hero.html`, a self-contained HTML/CSS file (same
  pattern as the pre-existing `docs/hero.html`) rendering a `#hero` element
  at a fixed 1200×630, matching the real brand:
  - Background: the same `hero-sky` gradient tokens used on the homepage
    hero (`--color-hero-sky-from` → `--color-hero-sky-to`)
  - Mark: the real logo (`priv/static/images/logo.svg`'s mic-in-rounded-square)
    at larger size, next to an "Speechwave" wordmark in `--color-ink`, with a
    mint (`--color-mint` → `--color-mint-deep`) wave-line accent underneath
  - Tagline: "Real-time audience reactions for speakers"
  - Emoji cluster (❤️🔥👏😂🤯 at varying size/opacity) confined to the
    bottom-right corner, matching the in-product reaction overlay convention
    (`.demo-emoji-overlay` in `assets/css/app.css`) rather than symmetric
    side columns
- Capture: `rodney` screenshot of the `#hero` element (`screenshot-el`),
  which is already exactly 1200×630 — no cropping needed.
- Post-process: `magick -strip -define png:compression-level=9` to drop
  metadata and optimize file size.
- Output committed to `priv/static/images/og-hero.png`.
- `docs/og_hero.html` is kept as the editable source for future re-renders,
  same as `docs/hero.html`.

## Meta tag architecture

`root.html.heex` renders a fixed block of tags driven by per-page assigns,
with fallbacks so no page ships a blank tag:

```heex
<meta name="description" content={assigns[:page_description] || @default_description} />
<link rel="canonical" href={...} />
<meta property="og:site_name" content="Speechwave" />
<meta property="og:type" content="website" />
<meta property="og:title" content={...} />
<meta property="og:description" content={...} />
<meta property="og:image" content={...} />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:url" content={...} />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content={...} />
<meta name="twitter:description" content={...} />
<meta name="twitter:image" content={...} />
```

- `og:title` / `twitter:title` reuse the same `page_title` assign that
  already feeds `<.live_title default="Speechwave">`. No page currently sets
  `page_title`, so this design also starts setting page-specific `<title>`s
  (e.g. `"Pricing · Speechwave"`) — a distinct OG title needs one anyway, and
  per-page `<title>`s are good SEO practice in their own right. `/` keeps the
  existing default ("Speechwave") rather than setting an explicit title.
- Canonical/`og:url`/`og:image` are absolute URLs built from
  `SpeechwaveWeb.Endpoint.url()` plus the request path. The root layout
  already uses `@conn`-dependent helpers (`get_csrf_token/0`), so `@conn`
  (and therefore `@conn.request_path`) is expected to be available for both
  controller-rendered and LiveView-rendered pages; this gets a concrete
  verification pass during implementation.
- `og:image` points at the single shared `og-hero.png` for all four pages.

## Per-page content

| Page | `page_title` | `page_description` |
|---|---|---|
| `/` | *(unset — falls back to default "Speechwave")* | "Speechwave lets your audience react with emoji in real time during your talk, then gives you per-slide analytics to see what landed." |
| `/pricing` | `"Pricing · Speechwave"` | "Compare Speechwave's free and paid plans. Start free, no credit card required, and upgrade when you need more participants or sessions." |
| `/terms` | `"Terms of Service · Speechwave"` | "Speechwave's terms of service." |
| `/privacy` | `"Privacy Policy · Speechwave"` | "How Speechwave collects, uses, and protects your data." |

`@default_description` (used only as a fallback if some other page ever
renders through this root layout without setting `page_description`) is the
`/` description above.

## Testing

- Controller tests (`PageControllerTest` or similar) for `/`, `/terms`,
  `/privacy`: assert the response body contains the expected
  `<meta name="description">` and `og:*` tag values.
- LiveView test for `/pricing`: assert the same against the initial
  disconnected-render HTML returned by `live/2` (which renders the full
  document, including the root layout, before the socket upgrades).

## Out of scope

- Authenticated app pages.
- Per-page/unique OG images.
- `twitter:site` / `twitter:creator` (no Twitter/X handle to reference).
- Structured data / JSON-LD.
