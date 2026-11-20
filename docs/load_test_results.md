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

## After batching (2026-11-19)

Reaction pushes to audience pages are now batched (one message per page every
250 ms, see `docs/specs/2026-11-19-reaction-push-batching-design.md`), and a
database timeout no longer crashes the audience page. Same setup as above, run
the same day on the same machine against the commit before the change and the
commit after it. The seeded user is on the pro plan now, because the free
plan's 15-person cap (added after the first runs) turns the simulated audience
away. "Delivered" is the extension-style listener, which still gets one
message per tap.

| People | Taps/s | Build | CPU | Delivered | Latency p50 / p95 | Log errors |
|---|---|---|---|---|---|---|
| 400 | 100 | before | 99% | 100% | 38 / 205 ms | 0 |
| 400 | 100 | after | 27% | 100% | 3 / 25 ms | 0 |
| 400 | 125 | before | 86% | 77% | 29 / 135 ms | 96 |
| 400 | 125 | after | 32% | 100% | 3 / 23 ms | 0 |
| 800 | 45 | before | 87% | 100% | 37 / 173 ms | 0 |
| 800 | 45 | after | 28% | 100% | 5 / 40 ms | 0 |
| 800 | 60 | before | 92% | 81% | 709 / 1312 ms | 171 |
| 800 | 60 | after | 30% | 100% | 3 / 19 ms | 0 |
| 1200 (one tap per 30 s, 40 taps/s) | 40 | before | 100% | 83% | 921 ms (2 probes) | 213 |
| 1200 (one tap per 30 s, 40 taps/s) | 40 | after | 30% | 100% | 4 / 40 ms | 0 |

The latency column is the extension-style listener's, which still gets one
message per tap. It says nothing about audience pages, which now wait up to
250 ms longer for each emoji by design (the batch interval). That delay was
not measured.

Audience pages received about 3.9 batches per second each, whatever the tap
rate, and every emoji reached every page (the audience-side count matched the
taps in all five runs). The database stored every tap in the "after" runs.

How to read it: CPU at the same load fell to about a third, and the failure
mode (insert timeouts, lost reactions, reconnecting phones) did not appear at
any step that used to produce it. These were single 60 s runs, and the probe
counts are small (11), so treat the latencies as rough. The limit has moved,
but these steps did not find where. Finding the new edge needs higher steps
(for example 800 people at 120 taps/s, or 1,600 people), which were not run.
Memory is unchanged and is now the nearer ceiling: the 1,200-person run used
about 417 MB of 512 MB.

## What limits it

(Written before batching. Items 1 and 2 describe the build before 2026-11-19;
see the section above for what changed.)

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
