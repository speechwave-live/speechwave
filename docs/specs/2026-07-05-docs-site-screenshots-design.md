# Docs Site Screenshots — Design

**Date:** 2026-07-05
**Source:** Roadmap "screenshots for docs site" item (Pre-launch Tasks / Should
haves), deferred from `docs/specs/2026-07-04-docs-site-design.md` phase 2
("Screenshots (later pass)").
**Scope:** Adding screenshots to the five existing pages of the
`speechwave-live/docs` Jekyll site (`docs.speechwave.live`). No changes to
page prose beyond inserting images at existing headings.

## Goals

Give the docs site's getting-started, dashboard, and extension pages visual
anchors so a new speaker can recognize the UI they're reading about, without
re-deriving anything already decided in the docs-site-design spec (hosting,
theme, page structure).

## Image sourcing

Two of the four candidate source images already exist as real captures made
for the Chrome Web Store listing (`speechwave/tmp/store_0*.png`), with
hand-added animated emoji reactions composited on top — reactions float and
animate in the live product, so a fresh automated screenshot can't reproduce
that effect. Rather than re-stage animated reactions, this pass reuses or
crops those where the underlying capture is still accurate, and takes fresh
plain screenshots everywhere else.

| # | Image | Source | Treatment |
|---|---|---|---|
| A | Dashboard talk list + create-talk form | Fresh capture, local dev | New |
| B | Dashboard talk panel (audience URL, QR, slug, sessions list) | Fresh capture, local dev | New |
| C | Account Settings — API key field | Fresh capture, local dev | New |
| D | Extension popup — unconfigured "Save Key" setup screen | Manual capture by Tracy | New |
| E | Slides with floating emoji overlay + "Powered by Speechwave" badge | `tmp/store_01_slides.png` | Use as-is — badge and emoji cluster are both genuine parts of the slide/overlay, not composite artifacts |
| F | Extension popup — connected + active session state | `tmp/store_02_popup.png` | Crop to isolate just the popup panel from the surrounding slide backdrop |
| G | Audience mobile view with floating emoji, header, and reaction grid | `tmp/store_03_audience.png` | Crop to drop the dark frame/padding added for the store listing; keep only real page content |
| H | Session analytics breakdown (single session) | `tmp/store_04_analytics.png` | Use as-is — genuine capture, not composited |

## Placement map

- **index.md** — G, under "Audience mobile view"
- **getting-started.md** — A (step 2, "Create a talk"), B (step 3, "Share
  with your audience"), D (step 4, "Connect the Chrome extension"), E (step
  6, "What happens during the talk")
- **dashboard.md** — A (under "Your talks"), B (under "Finding your talk
  slug"), C (under "Finding your API key"), H (under "Session analytics")
- **extension.md** — D (under "Connect your account"), F (under "Sessions
  from the extension"), E (under "Present")
- **troubleshooting.md** — none in this pass; error states (invalid key,
  duplicate emojis, etc.) are hard to stage reliably and are deferred until a
  specific state is easy to reproduce on demand.

Some images are reused across two pages (A, B, D, E each appear twice) — same
file, embedded in both locations.

## Execution mechanics

**Fresh captures (A, B, C):**
1. Start `mix phx.server` locally.
2. Run `mix run scripts/manual_tests/seed_screenshots.exs <throwaway-email>`
   to get the `emojilove` talk seeded with seven finished-session reactions
   across four slides.
3. Complete magic-link login via `/dev/mailbox` (dev-only mailbox UI).
4. Drive and capture with `rodney` at a 1280px-wide viewport: dashboard talk
   list, the `emojilove` talk panel expanded, and the Account Settings page.

**Manual capture (D — extension popup, unconfigured state):**
Automating this turned out not to be viable on this machine: launching
Chrome with `--load-extension=<repo>/chrome-extension
--remote-debugging-port=<port>` and driving it via `rodney connect` hit a
persistent Chrome content-verifier rejection
(`Content verify job failed for extension: <id> at path: popup/popup.html
and for reason:1`) specific to the command-line `--load-extension` path —
confirmed to be unrelated to the Ghostty macOS Automation permission (same
failure recurred after that permission was granted and Ghostty/Claude Code
were fully restarted). Loading the same unpacked extension interactively via
`chrome://extensions` → **Load unpacked** is the standard, fully-supported
path and doesn't hit this check.

So D is a manual step: Tracy loads the unpacked extension that way in her
regular Chrome, opens the toolbar popup before saving any API key (the
fresh/unconfigured state), and screenshots it herself, dropping the file for
placement into `docs/assets/images/`.

**Crops (F, G):**
Use `magick`/`convert` (ImageMagick) for precise pixel-region crops:
- F: isolate the popup panel bounds from `store_02_popup.png`, dropping the
  slide backdrop and emoji cluster around it.
- G: trim `store_03_audience.png` down to the real page content (header
  through footer), dropping the dark padding added for the store listing.

**Storage:** new files land in `docs/assets/images/` (the `speechwave-live/docs`
repo), named `screenshot-<page>-<topic>.png`, e.g.
`screenshot-dashboard-talk-panel.png`. Reused images get one file, referenced
from both embed locations.

**Embedding:** plain Markdown image syntax under the relevant heading on each
page, with a kramdown IAL width constraint so images don't blow out the
just-the-docs content column, e.g.:

```markdown
![Dashboard talk panel showing the audience URL, QR code, and slug](/assets/images/screenshot-dashboard-talk-panel.png){: width="700" }
```

## Out of scope

- Troubleshooting-page error-state screenshots (see placement map above).
- Recapturing E or H (both already accurate, unmodified-by-us captures).
- Any change to page prose beyond inserting images — text is already
  accurate per the docs-site-design spec's phase 2 acceptance criteria.
- Dark-mode variants, retina/@2x assets, or a custom screenshot CSS treatment
  (border/shadow) beyond the width constraint above.

## Verification

- Each image renders correctly in a local `bundle exec jekyll serve` of the
  docs site, at both wide and narrow (mobile) viewport widths.
- Each image is genuinely legible at its constrained width — not so busy or
  small-text-heavy that it stops helping at docs-column width.
- `git status` in both the `speechwave` and `docs` repos shows only the
  intended new/changed files (no stray files from the capture process, e.g.
  from an aborted Chrome/rodney session).
