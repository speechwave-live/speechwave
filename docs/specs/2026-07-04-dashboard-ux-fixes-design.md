# Dashboard & Analytics UX Fixes — Design

**Date:** 2026-07-04
**Source:** "Should haves" section of `docs/roadmap.md` (pre-launch UX fixes).
**Scope:** The three dashboard/analytics UX fixes only. The onboarding docs
site is deferred to its own brainstorm/spec.

## Goals

Fix three launch-blocking UX problems:

1. Speakers can't find the talk slug they need to connect the Chrome extension.
2. Session names in the dashboard are unreadable (near-white text on a
   near-white chip), and the "Active" badge crowds the name.
3. The session analytics page shows the logged-out header nav to logged-in
   users.

## Fix 1: Talk slug in the selected-talk panel

**File:** `lib/speechwave_web/live/dashboard_live.html.heex` (selected-talk
panel, `#selected-talk-qr`).

Restructure the panel to match the roadmap mockup:

```text
.------------------------------.
| Talk title                   |
|                              |
| URL for your audience:       |
| [user view url] [copy]       |
| [QR code]                    |
| ---------------------------- |
| Slug for browser extension:  |
| [talk slug] [copy]           |
| ---------------------------- |
| Sessions                     |
| ...                          |
`------------------------------'
```

- Add the label "URL for your audience:" above the existing URL + copy row.
- Keep the QR code and download link unchanged.
- Add a new section, divided by a top border like the Sessions panel, labeled
  "Slug for browser extension:" showing `@selected_talk.slug` in a monospace
  chip with a copy button.
  - Reuse the existing `CopyToClipboard` hook pattern (see `#copy-talk-link`).
  - New DOM id: `copy-talk-slug`. Flash message: "Slug copied to clipboard".
- No LiveView module changes — the slug is already on `@selected_talk`.

## Fix 2: Session row readability

**File:** `lib/speechwave_web/live/dashboard_live.html.heex` (sessions panel).

**Root cause:** the session label has no explicit text color class, so it
inherits the theme's base content color (near-white in dark mode) on a
hardcoded `bg-gray-50` chip — white-on-white. The single-row flex layout also
crowds the name, badge, count, and action icons together.

Restructure each session row to two lines:

- **Line 1:** session name (explicit `text-gray-900 font-medium`, truncating),
  start date (`Calendar.strftime(session.started_at, "%b %d, %Y")`, muted),
  and the "Active" badge when `ended_at` is nil. The badge sits inline after
  the name; the name truncates independently so nothing overlaps.
- **Line 2:** reaction count (muted) + action links: analytics, rename,
  delete.
- Make the analytics link prominent: colored icon (`text-indigo-600`) plus a
  small "Analytics" text label. It is a key feature and currently easy to
  miss. *Flagged for follow-up review once rendered — treatment may change.*
- Rename/delete keep their current muted icon-button treatment.
- The rename form (edit mode) keeps its current behavior.

## Fix 3: Session analytics header

**File:** `lib/speechwave_web/live/session_analytics_live.html.heex:1`.

One-line fix: pass the missing assign —

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
```

The route already lives in the `live_session :require_authenticated_user`
block, so `@current_scope` is always assigned; the template just never passed
it to the layout, which made `Layouts.app` fall back to the logged-out nav
(Pricing / Log in / Get started free). With the assign passed, the logged-in
nav (Dashboard / email / Log out) renders automatically.

## Testing

- Dashboard LiveView tests: assert the new `#copy-talk-slug` element exists
  and the slug text renders when a talk is selected; assert session rows
  render the label and analytics link elements by ID.
- Session analytics test: assert the logged-in nav renders (e.g. a Dashboard
  link is present) for an authenticated user.
- `mix precommit` must pass.

## Implementation approach

Each fix is dispatched to a subagent on a lower-power model (fixes 1 and 3
are mechanical template edits; fix 2 restructures layout and touches tests),
with results reviewed in the main session. Fixes are independent and touch
mostly disjoint template regions (1 and 2 share a file but different
sections, so they run sequentially; 3 is independent).

## Out of scope

- Onboarding docs/help pages (separate repo/CI; own spec later).
- Any broader dark-mode/theming cleanup of the dashboard's hardcoded light
  palette beyond making the session rows readable.
