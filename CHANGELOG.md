# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-10-19

Version 0.3.0 was tagged but never deployed, so its changes below go live with this release.

### Added

- New users see a short welcome banner on their first login, with a link to the Getting Started guide. The close button hides it right away and it does not come back.
- The session analytics page shows how many people reacted, the top slide and the top reaction.
- The reaction page now creates a random ID in the audience member's browser, so the analytics can count people instead of just reactions. The server stores only a one-way hash of it combined with the session, so nothing links a person across sessions. The privacy policy describes it.

### Changed

- Speechwave now always uses the light theme, including on the session analytics page.

### Fixed

- The Settings page no longer scrolls sideways on phone-sized screens.

## [0.3.0] - 2026-10-16

### Added

- You can now delete your own account from Settings (Danger zone). After you type your email to confirm, your account and everything in it (talks, sessions, reactions, consents and linked sign-ins) is removed immediately and you are signed out. Admin accounts can't be deleted from Settings.
- Admins can download a CSV of marketing email consents from the stats page, for the last month or any time range.

### Changed

- The privacy policy and terms now describe account deletion and say deleted data leaves our backups within 30 days. An anonymous account identifier is kept for up to 30 days so that a deleted account can't be restored from a backup.
- Flash messages now appear on the home, terms and privacy pages, so "Logged out successfully." shows after signing out.

## [0.2.0] - 2026-09-18

### Added

- Account Settings page: you can now set the Chrome extension's emoji overlay size as a percentage of slide coverage, and toggle the fireworks burst animation, instead of being stuck with whatever's hardcoded into the extension.

### Changed

- The Chrome extension's animation-tuning constants (overlay sizing, fireworks thresholds, and similar) are now delivered from the backend via the reactions channel's join reply, so they can be adjusted with a backend deploy instead of a new Chrome Web Store submission.
- Updated the privacy policy to disclose that the Chrome extension stores your API key locally in the browser and sends the current Google Slides slide number to the server while a session is active, so reactions can be attributed to the right slide.

## [0.1.2] - 2026-07-16

### Fixed

- Starting a session now always begins a fresh one, instead of sometimes silently resuming a session left open from a previous day. Previously, if the browser extension was never explicitly stopped (e.g. a laptop closed mid-presentation), clicking "Start Session" later would reattach to that stale session rather than create a new one, forcing an extra "Stop" then "Start" to get a clean session — as reported by a user who ran into this the day after forgetting to stop.
- Sessions left open for more than 4 hours are now closed automatically in the background. Previously, a session that was never explicitly stopped stayed "active" indefinitely, which also meant it never counted toward the monthly session limit since only completed sessions are counted — this closes that gap.

## [0.1.1] - 2026-07-14

### Fixed

- Reactions sent while the presenter had left Google Slides presentation mode (e.g. switching back to the editor mid-session) were misattributed to whichever slide was shown last, instead of falling into the general "no slide" pool.

## [0.1.0] - 2026-07-07

Initial public release.
