# Reaction push batching and insert failure handling

Date: 2026-11-19. Status: draft, awaiting approval.

Follows from the load test (`docs/load_test_results.md`) and the performance
post. That work found that the reaction path saturates one core because every
tap is pushed to every audience page, and that a saturated core makes the tap's
database insert time out and crash the tapper's LiveView.

## Intent

Raise the audience size and tap rate Speechwave can carry on one Fly CPU,
and stop a database timeout from taking an audience page down.

The limit today is roughly `35,000 / people` total taps per second. Cutting
the number of pushes per second from `people x taps/s` to `people x 4` moves
that limit out by an order of magnitude for rooms of a few hundred or more.

## Goals

1. Audience pages receive reactions in one batched push per 250 ms tick instead
   of one push per reaction.
2. A failed or timed-out reaction insert no longer crashes the LiveView. The
   reaction still floats up on screens, the failure is logged and counted.
3. The speaker's extension keeps working with no update.
4. Measured improvement, using the existing `scripts/load_test/` harness.

## Non-goals

- **Batching the database writes.** Deferred. SQLite managed 7,500 inserts/s
  and the observed insert failure was a symptom of CPU starvation, not of write
  volume. Decide after goal 4 is measured (see Follow-ups).
- **Batching or throttling the extension's stream.** The extension still gets
  one `new_reaction` per tap. Revisit if a presenter-side measurement shows a
  problem.
- **Memory per connection** (0.23 MB per person, the OOM at 3,200). Separate.
- **Changing the 3 s per-person cooldown** or any plan limits.

## Anti-goals

- Hiding lost data. If an insert is dropped, analytics undercount, and that must
  be visible in logs and telemetry, not swallowed.
- A design that still delivers every tap as its own message to every audience
  LiveView. That saves nothing, because the cost is the per-process delivery.

## Constraints

- Single Fly machine, one CPU, 512 MB. The design must still be correct if
  there are several nodes: each node batches its own taps and PubSub delivers
  every node's batch to every audience page.
- The extension joins the channel topic `reactions:<slug>`. Phoenix forwards
  whatever is broadcast on that topic to the extension, so that topic and the
  `new_reaction` event must stay exactly as they are.
- Elixir rules from `CLAUDE.md` apply: tests start processes with
  `start_supervised!/1`, no `Process.sleep/1`.

## Approaches considered

**A. Split the server-side topic, batch for audience pages only (chosen).**
Audience LiveViews stop subscribing to `reactions:<slug>` and subscribe to a new
`audience:<slug>` topic instead. A batcher process broadcasts one
`reactions_batch` per tick there. The tap handler still broadcasts the
per-reaction `new_reaction` on `reactions:<slug>`, so the extension is
untouched.

**B. One topic, batch only.** Replace `new_reaction` with `reactions_batch` for
everyone. Smallest server change, but it breaks every installed extension until
it updates, and forces the presenter and the audience to share one cadence.

**C. One topic, send both events.** Audience pages would still receive every
`new_reaction` as a process message even if they ignore it, so nothing is
saved. Rejected.

A also leaves room to batch the extension's stream later, as a server-side
change plus a handler in the extension, with the old path kept for old versions.

## Design

### Topics

| Topic | Subscribers | Events |
|---|---|---|
| `reactions:<slug>` | extension channel (via Phoenix), nobody else | `new_reaction` (unchanged) |
| `audience:<slug>` | audience `TalkLive` pages | `reactions_batch` |
| `slides:<slug>` | audience `TalkLive` pages (unchanged) | `slide_changed` |

### Batcher

New module `Speechwave.ReactionBatcher`, a single GenServer added to the
supervision tree in `application.ex` after `Speechwave.PubSub`.

- State: a map of `slug => [emoji]`, newest first.
- `ReactionBatcher.add(slug, emoji)` is a `GenServer.cast`. The tap handler
  calls it after the rate limiter accepts the tap.
- Every `tick_ms` (250, configurable via application env so tests can set it
  very large and trigger flushes by message) it takes the map, resets state to
  empty, and for each slug broadcasts
  `%{emojis: [...]}` as event `reactions_batch` on `audience:<slug>` using
  `Endpoint.broadcast/3`. A tick with nothing pending sends nothing.
- If a slug has more than `max_batch` emoji (50, my call), keep a random sample
  of `max_batch`. The animation can't show more than that legibly, and it bounds
  both message size and client work.
- A single process is enough: even 500 taps/s is 500 trivial casts. If the
  batcher crashes, the supervisor restarts it and at most one tick of
  animations is lost. Nothing in it is durable.

### Audience LiveView (`talk_live.ex`)

- `subscribe/1` subscribes to `audience:<slug>` and `slides:<slug>` and no
  longer to `reactions:<slug>`.
- `handle_info` for `reactions_batch` calls
  `push_event(socket, "reactions_batch", %{emojis: emojis})`. The old
  `new_reaction` `handle_info` clause is removed.
- The tap handler: rate limit, record the reaction (below), call
  `ReactionBatcher.add/2`, and still broadcast `new_reaction` on
  `reactions:<slug>` for the extension.

### Client hook (`assets/js/hooks/emoji_stream.js`)

Replace the `new_reaction` handler with `reactions_batch`. For each emoji in the
batch, spawn the same floating element as today but with a random
`animation-delay` between 0 and 250 ms, so a batch looks like a stream and not
one clump. The cleanup on `animationend` is unchanged.

A tapper now sees their own emoji up to 250 ms after tapping, not on the next
message. That is acceptable. Whether to also show it locally at once on tap is
left to the builder, but if done it must not then show it a second time when
the batch arrives.

### Rescuing the insert failure

New `Speechwave.Reactions.record_reaction/4`, wrapping the active-session lookup
and `create_reaction/4`:

- Rescues `DBConnection.ConnectionError` only (pool checkout timeout, connection
  lost). Anything else, including changeset errors and genuine bugs, still
  surfaces as before. The builder should confirm in a test or in `iex` that a
  checkout timeout under the `Repo` pool raises this exact exception, and adjust
  the rescued exceptions if it does not.
- On rescue: `Logger.warning` with the exception message (no emoji, no audience
  or client ID, because LiveView crash logs already leak `client_id`, see
  `docs/techdebt.md`), emit a `[:speechwave, :reaction, :insert_failed]`
  telemetry event, and return `{:error, :db_busy}`.
- The tap handler ignores that result and carries on to batch and broadcast, so
  the audience still sees the reaction. The reaction is missing from analytics
  and that is the accepted tradeoff, logged and countable.
- **Finding from the release image (2026-11-19):** a checkout timeout does
  raise `DBConnection.ConnectionError`, but SQLite's single-writer lock is a
  second way to fail: with a connection free and another holding the write
  lock, the insert raised `Exqlite.Error` "Database busy" after about 2 s.
  The rescue therefore covers both, chosen by `Reactions.busy_error?/1`, and
  re-raises any other exception. `scripts/load_test/db_busy_check.exs`
  reproduces both cases.
- The `get_active_session` call is inside the rescue too, because it hits the
  same pool and times out the same way.

Both new modules get a moduledoc and comments explaining the OTP pieces. The
author is new to Elixir and wants the code to teach.

## Testing

- `ReactionBatcher`: `start_supervised!` with a huge tick, add several emoji for
  two slugs, send the flush message, and assert on the broadcasts received by a
  test process subscribed to `audience:<slug>`. Cover the empty tick, the
  per-slug separation, and the `max_batch` cap.
- `TalkLive`: use `assert_push_event` for `reactions_batch` after a flush. A tap
  broadcasts `new_reaction` on `reactions:<slug>` for the extension. A page
  does not receive `new_reaction`.
- `record_reaction/4`: the failure path returns `{:error, :db_busy}`, logs, and
  emits telemetry. How to force a `DBConnection.ConnectionError` in a test is
  left to the builder.
- Existing Playwright e2e tests that watch for floating emoji should still
  pass. They go through the real hook, so they cover the JS change.
- Run `mix precommit`.

## Measuring

Rerun the harness, not new tooling: `scripts/load_test/run_rate_steps.sh` at
400 and 800 people, and the 1,200-people-at-30 s case. Success means the
800-people 45 and 60 taps/s steps (100% CPU, 82% delivered, p95 1.5 s before)
run with delivered at or near 100% and clearly lower CPU, and pushes/s to
audience pages falls from about `people x taps/s` to about `people x 4`.

The load test's listener counts `new_reaction` on pages. The audience-side
listener in `audience_load.mjs` needs to count emoji inside `reactions_batch`
instead. Update `docs/load_test_results.md` with before and after.

## Delivery

Feature branch, conventional commits. Suggested split, so the safe part can
ship alone if the batching needs more time:

1. `fix: keep a reaction insert timeout from crashing the audience page`
   (`record_reaction/4`, rescue, log, telemetry, tests).
2. `perf: batch reaction pushes to audience pages` (batcher, topic split,
   hook, tests, load test updates).

## Follow-ups, after measurement

- If the 800-person runs still show insert checkout timeouts, batch inserts:
  the batcher can already hold the data, so each tick would also
  `Repo.insert_all` the pending reactions. Note `inserted_at` would then be the
  flush time (up to 250 ms late), which the analytics timeline buckets (seconds)
  tolerate.
- Update the "How we can make it even better" section of the blog post once the
  numbers exist.
- Throttling or summarizing the extension's stream for very large talks.

## Left to the builder

Exact module names and file layout, how the tick is configured in tests, the
telemetry event shape, whether the tapper's own emoji is shown immediately, and
the visual stagger details.
