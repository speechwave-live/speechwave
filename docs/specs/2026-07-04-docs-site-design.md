# Speechwave Docs Site (docs.speechwave.live) — Design

**Date:** 2026-07-04
**Source:** "Onboarding docs and help pages" in `docs/roadmap.md` (pre-launch
Should haves) plus the roadmap's "Chrome Extension Troubleshooting / FAQ"
section, which was written to become a user-facing help page.
**Scope:** A new, separate docs site repo with its own CI/CD. This spec lives
in the app repo because the roadmap does, but all implementation happens in
the new repo (except noted follow-ups).

## Goals

Frictionless speaker onboarding before the free-tier launch: a public docs
site covering the whole system (Chrome extension, speaker dashboard, audience
mobile view), served at `docs.speechwave.live`, deployable by pushing to
`main`, and independent of app deploys.

## Decisions made

- **Hosting:** static Jekyll site on Dreamhost at `docs.speechwave.live`
  (roadmap's proposal, confirmed). Not GitHub Pages; not served from the
  Phoenix app. This resolves the open question in the roadmap's
  "Documentation" subsection.
- **Repo:** new GitHub repo `speechwave-live/docs`, cloned locally at
  `/Users/tracy/projects/speechwave-live/docs` (sibling of `speechwave` and
  `chrome-extension`).
- **Generator/theme:** Jekyll 4.4 with `just-the-docs`, lightly branded.
  Mirrors the proven setup in `/Users/tracy/projects/jojo/docs` (Gemfile pins
  `jekyll ~> 4.4` and `just-the-docs`; no `github-pages` gem).
- **Deploy:** GitHub Actions on push to `main` (plus `workflow_dispatch`),
  adapted from the proven Hugo→Dreamhost workflow in
  `/Users/tracy/projects/tracyatteberry/.github/workflows/deploy.yml`:
  checkout → `ruby/setup-ruby` with bundler cache → `bundle exec jekyll
  build` → `wlixcc/SFTP-Deploy-Action` uploading `_site/*` to
  `/home/<dreamhost-user>/docs.speechwave.live/` with secrets
  `DREAMHOST_HOST`, `DREAMHOST_USERNAME`, `DREAMHOST_PASSWORD`, `port: 22`,
  `sftp_only: true`, `delete_remote_files: false`.
- **Content scope:** the full roadmap onboarding list, organized into five
  pages (below).
- **Phasing:** scaffolding first — repo, skeleton, and a proven end-to-end
  deploy — then content.

## Branding

- Speechwave logo copied from the app repo's `priv/static/images/logo.svg`;
  used as the just-the-docs site logo and favicon.
- Accent/link color aligned with the app's palette via a just-the-docs color
  scheme override.
- `aux_links` entry pointing back to `https://speechwave.live`.

## Site structure (five pages)

1. **Home / System overview** (`index.md`) — what Speechwave is and the three
   pieces: Chrome extension (speaker's laptop), speaker dashboard (web),
   audience mobile view (`/t/:slug`). Adapted from the app repo's
   `docs/explainer.md` big-picture section, with internals (protocol/module
   details) stripped.
2. **Getting started** (`getting-started.md`) — creating a speaker account,
   creating a talk, sharing the QR code / talk link with the audience,
   starting a session and why sessions matter.
3. **Speaker dashboard & analytics** (`dashboard.md`) — finding the talk slug
   (for the extension), finding the API key (Account Settings), managing
   sessions, reading session analytics.
4. **Chrome extension** (`extension.md`) — installing from the Web Store,
   entering the API key, connecting to a talk by slug, presentation-mode
   behavior.
5. **Troubleshooting & FAQ** (`troubleshooting.md`) — adapted from the
   roadmap's "Chrome Extension Troubleshooting / FAQ" section (no emojis
   appearing, invalid API key after regeneration, connected-but-no-emojis,
   not connecting, duplicate emojis).

Pages use just-the-docs front matter (`nav_order`, `title`) for sidebar
ordering. Text-first: no screenshots in v1 (the app repo's
`scripts/manual_tests/seed_screenshots.exs` exists for staging them later).

## Phases

**Phase 1 — scaffolding (priority):**
Repo initialized with Jekyll skeleton (Gemfile, `_config.yml`, branded theme
setup, five placeholder pages with correct nav), the deploy workflow, and a
verified end-to-end deploy: a push to `main` results in the placeholder site
visible at `https://docs.speechwave.live`.

Manual one-time steps done by Tracy (credentials never handled by tooling):
- ~~Create the `docs.speechwave.live` subdomain~~ — done 2026-07-03; hosting
  space exists at Dreamhost.
- Create the empty `docs` repo in the `speechwave-live` GitHub org.
- Add the three `DREAMHOST_*` secrets, scoped to the repo (or org). These are
  **different credentials** from the blog's Dreamhost secrets — the docs site
  uses its own Dreamhost user.

**Phase 2 — content:**
Write the five pages. Prose composition is dispatched to capably-powered
models (model chosen deliberately per task at dispatch time); source material
is the app repo's `docs/explainer.md`, the roadmap FAQ section, the app UI
itself, and `docs/manual_tests.md` for exact flows. Each page is reviewed for
accuracy against the current product (names of buttons, routes, limits)
before merge.

## Verification

- CI gate: the workflow fails if `jekyll build` fails.
- Phase 1 acceptance: placeholder site loads at `https://docs.speechwave.live`
  after a push to `main`.
- Phase 2 acceptance: each page's instructions verified against the running
  product (dev environment) before merge; internal links between the five
  pages resolve.

## Out of scope

- In-app "Help" links from speechwave.live to the docs site (small follow-up
  in the app repo once the site is live; add to roadmap).
- Screenshots (later pass).
- Docs versioning, analytics, or search beyond just-the-docs' built-in.
- Chrome Web Store listing text (separate concern).
