# Reaction load test results (2026-11-05)

How many audience members can react before reactions are dropped or delayed.
Method and scripts: `scripts/load_test/`.

## Setup

Production image run locally in Docker with fly.toml's limits: 1 CPU pinned to
one core (so the BEAM has one scheduler, as on Fly), 512 MB, DB pool of 2,
throwaway SQLite. Simulated audience LiveView connections plus an
extension-style channel listener. Tap-to-listener latency is measured with
probe reactions. Server side only: the extension's rendering was not tested.

## Results

Everyone tapping every 3.2 s (the fastest the 3 s cooldown allows):

| People | Taps/s | Pushes/s to audience pages | CPU | Delivered | Latency p95 |
|---|---|---|---|---|---|
| 200 | 62 | 12k | 39% | 100% | 16 ms |
| 400 | 125 | 50k | 86% | 84% | 430 ms |
| 800 | 250 | 200k | n/a | 27% | n/a |
| 1600 | 500 | 800k | n/a | under 1% | n/a |

Everyone tapping every 30 s (closer to real audiences):

| People | Taps/s | Pushes/s | CPU | Delivered | Latency p50 / p95 |
|---|---|---|---|---|---|
| 800 | 27 | 21k | 55% | 100% | 1 / 40 ms |
| 1200 | 40 | 48k | 100% | 91% | 422 / 895 ms |

## Total reaction rate at a fixed audience size

Audience held constant, total taps per second stepped up (one 60 s run each):

| People | Taps/s | CPU | Delivered | Latency p50 / p95 |
|---|---|---|---|---|
| 400 | 40 | 52% | 100% | 4 / 9 ms |
| 400 | 60 | 68% | 100% | 4 / 18 ms |
| 400 | 80 | 75% | 100% | 9 / 32 ms |
| 400 | 100 | 99% | 100% | 60 / 116 ms |
| 400 | 125 (earlier run) | 86% | 84% | 24 / 430 ms |
| 800 | 25 | 63% | 100% | 3 / 88 ms |
| 800 | 35 | 80% | 95% (40 errors) | 2 / 91 ms |
| 800 | 45 | 100% | 100% | 76 / 251 ms |
| 800 | 60 | 100% | 82% | 43 / 1495 ms |

Slowdown starts when the core saturates: about 100 taps/s at 400 people and
about 45 taps/s at 800. Drops start just past that (400: between 100 and 125;
800: 60, with one unexplained 5% loss at 35). Single runs, so the exact edge is
fuzzy. Both points sit at about 36 to 40k pushes/s.

## What limits it

1. **CPU, because of fan-out.** Every accepted reaction is pushed to every
   audience page (they show the floating emoji too), so work per second is
   about people x taps per second, which grows with the square of the audience.
   One core handles roughly 35 to 40k pushes/s (see the rate steps below). Rule
   of thumb: total reactions per second should stay under about 35,000 divided
   by the number of people connected.
2. **Failure mode.** Past that, the DB insert inside the audience member's
   LiveView times out waiting for a pool connection, the LiveView crashes, the
   reaction is lost and the browser reconnects.
3. **Memory.** About 0.23 MB per connected audience member over a ~160 MB
   baseline. A 3,200-person run was OOM-killed at 512 MB.

SQLite itself is not the limit: 7,500 inserts/s measured in the same container.

## Caveats

Fly's shared CPU can be throttled harder than a pinned Docker core, so real
limits may be lower. The test machine is an Apple Silicon Mac. The probe
latency only counts reactions that arrived.
