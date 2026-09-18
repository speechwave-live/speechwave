# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
