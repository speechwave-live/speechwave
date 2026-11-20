# Reaction push batching and insert failure handling: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Batch reaction pushes to audience pages (one per 250 ms tick) and stop a database timeout from crashing the audience LiveView.

**Architecture:** A single `Speechwave.ReactionBatcher` GenServer collects accepted taps per talk slug and broadcasts one `reactions_batch` per tick on a new `audience:<slug>` PubSub topic. Audience `TalkLive` pages subscribe there instead of `reactions:<slug>`. The tap handler still broadcasts `new_reaction` on `reactions:<slug>` so the extension is untouched. `Reactions.record_reaction/4` wraps the session lookup and insert and rescues `DBConnection.ConnectionError`.

**Tech Stack:** Elixir, Phoenix 1.8 PubSub and LiveView, Ecto with SQLite, a colocated JS hook (`assets/js/hooks/emoji_stream.js`), Node load test scripts in `scripts/load_test/`.

**Spec:** `docs/specs/2026-11-19-reaction-push-batching-design.md`

## Global Constraints

- Tick is 250 ms. Batch cap `max_batch` is 50, a random sample when exceeded.
- The extension-facing topic `reactions:<slug>` and event `new_reaction` (payload `%{emoji: emoji}`) stay exactly as they are.
- Audience topic is `audience:<slug>`, event `reactions_batch`, payload `%{emojis: [emoji]}`.
- Rescue `DBConnection.ConnectionError` only. Log without emoji, audience ID or client ID. Telemetry event `[:speechwave, :reaction, :insert_failed]`.
- Tests: `start_supervised!/1`, no `Process.sleep/1`, LiveView tests use `has_element?`/`assert_push_event`, not raw HTML.
- Both new modules get a `@moduledoc` and comments explaining the OTP pieces (the author is new to Elixir and reads the code to learn).
- Work on a feature branch (no git worktrees). Conventional commits. Run `mix precommit` at the end.

## Review Focus

- Tap while no session is active: no insert, but the tap must still reach the audience and the extension as it does today.
- Turned-away (`:full`) visitors and visitors still `:pending` must not receive `reactions_batch` (they aren't subscribed to `audience:<slug>`).
- A flush with nothing pending, and batches for two different talks, must not leak between slugs.
- More than 50 taps in one tick: batch is capped at 50 and does not crash.
- Batcher restart after a crash: LiveViews keep working, `add/2` to a restarting batcher must not crash the caller (it is a cast).
- An insert timeout must not log the emoji or client ID, and a non-connection error (changeset error) must still behave as before.

---

### Task 1: Rescue reaction insert failures

**Files:**
- Modify: `lib/speechwave/reactions.ex` (add `record_reaction/4` near `create_reaction/4`)
- Modify: `lib/speechwave_web/live/talk_live.ex:66-88` (the `"react"` handler)
- Test: `test/speechwave/reactions_test.exs`, `test/speechwave_web/live/talk_live_test.exs`

**Interfaces:**
- Consumes: `Speechwave.Talks.get_active_session/1` (takes a talk id, returns a `TalkSession` or `nil`), `Reactions.create_reaction/4`.
- Produces: `Speechwave.Reactions.record_reaction(talk_id :: integer, emoji :: String.t(), slide_number :: integer, audience_id :: String.t() | nil) :: :ok | {:error, :db_busy}`. Returns `:ok` both when a reaction is stored and when there is no active session. `audience_id` is the already-derived value (the handler computes it with its existing private `audience_id(session, client_id)`, which needs the session, so see Step 4).

- [ ] **Step 1: Confirm the exception class.** In `iex -S mix` (or Tidewave `project_eval`), cause a pool checkout timeout (for example `Repo.checkout(fn -> Task.async(fn -> Repo.query!("select 1", [], timeout: 1, queue_target: 1) end) |> Task.await() end)` with pool size low, or hold the pool's connections) and check the raised exception's struct. If it is not `DBConnection.ConnectionError`, use the real struct everywhere this plan says `DBConnection.ConnectionError`.

- [ ] **Step 2: Write the failing tests.**
  - In `reactions_test.exs`, describe `record_reaction/4`: `"stores the reaction and returns :ok"` (assert `count_reactions(session.id) == 1`), `"returns :ok and stores nothing when the talk has no active session"`, and `"returns {:error, :db_busy}, logs a warning and emits [:speechwave, :reaction, :insert_failed] when the insert raises DBConnection.ConnectionError"`. Use `:telemetry_test.attach_event_handlers(self(), [[:speechwave, :reaction, :insert_failed]])` and `ExUnit.CaptureLog`. Assert the captured log does not contain the emoji or the audience ID passed in. How to force the exception is yours to pick: a test-only way that does not alter production signatures, such as a sandbox connection owned by a process that has exited, or `Repo.checkout` held in another process with a tiny `queue_target`. If no honest way exists, document why in the test and test the rescue through the smallest private seam you can justify.
  - In `talk_live_test.exs`, `"a reaction whose insert fails is still broadcast to the extension topic and the view survives"`: same forced failure, subscribe the test process to `reactions:<slug>`, click `react`, `assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}`, and assert `Process.monitor` on `view.pid` sees no `:DOWN` (use `refute_receive {:DOWN, ...}`).

- [ ] **Step 3: Run them and see them fail.** `mix test test/speechwave/reactions_test.exs test/speechwave_web/live/talk_live_test.exs` — expect `record_reaction/4 undefined` and the view crash.

- [ ] **Step 4: Implement.** In `reactions.ex`, `record_reaction/4` as signed above: look up the active session, `create_reaction/4`, rescue only `DBConnection.ConnectionError` (wrapping both the lookup and the insert), `Logger.warning` the exception message only, `:telemetry.execute([:speechwave, :reaction, :insert_failed], %{count: 1}, %{})`, return `{:error, :db_busy}`. Because the handler currently derives `audience_id` from the session, change the signature to take `client_id` instead of `audience_id` and call the existing derivation inside (move `audience_id/2` out of `talk_live.ex` into `Reactions` if it is private there; keep its behavior byte for byte). Update the signature above and the Interfaces block of Task 3 to match what you land on. In `talk_live.ex`, the `"react"` handler replaces its `case Talks.get_active_session ...` block with one `Reactions.record_reaction/4` call whose result it ignores. The `new_reaction` broadcast stays where it is.

- [ ] **Step 5: Run the tests.** `mix test test/speechwave/reactions_test.exs test/speechwave_web/live/talk_live_test.exs` — expect all pass, including the existing persistence tests.

- [ ] **Step 6: Commit.**

```bash
git switch -c perf/reaction-push-batching
git add lib/speechwave/reactions.ex lib/speechwave_web/live/talk_live.ex test/
git commit -m "fix: keep a reaction insert timeout from crashing the audience page"
```

---

### Task 2: ReactionBatcher

**Files:**
- Create: `lib/speechwave/reaction_batcher.ex`
- Modify: `lib/speechwave/application.ex` (add `Speechwave.ReactionBatcher` to `children`, after `Speechwave.RateLimiter`)
- Modify: `config/test.exs` (set `config :speechwave, Speechwave.ReactionBatcher, tick_ms: :infinity`)
- Test: `test/speechwave/reaction_batcher_test.exs`

**Interfaces:**
- Produces:
  - `ReactionBatcher.start_link(opts)` with opts `:name` (default `Speechwave.ReactionBatcher`), `:tick_ms` (default from app env, else 250; `:infinity` means no timer), `:max_batch` (default 50).
  - `ReactionBatcher.add(server \\ __MODULE__, slug :: String.t(), emoji :: String.t()) :: :ok` (a cast).
  - `ReactionBatcher.flush(server \\ __MODULE__) :: :ok` (a synchronous call that runs one tick now; for tests and nothing else).
  - Each tick, per slug with pending emoji: `Endpoint.broadcast("audience:#{slug}", "reactions_batch", %{emojis: emojis})`, `emojis` in arrival order, capped at `max_batch` by random sample. A tick with nothing pending broadcasts nothing.

- [ ] **Step 1: Write the failing tests** in `reaction_batcher_test.exs`, each starting `start_supervised!({ReactionBatcher, name: :batcher_test, tick_ms: :infinity, max_batch: 3})` and subscribing the test process to `audience:a` (and `audience:b` where relevant):
  - `"flush broadcasts one reactions_batch per slug with emojis in arrival order"` (add 🔥 ❤️ to `a`, one to `b`; `assert_receive %Phoenix.Socket.Broadcast{topic: "audience:a", event: "reactions_batch", payload: %{emojis: ["🔥", "❤️"]}}` and the `b` batch separately).
  - `"flush with nothing pending broadcasts nothing"` (`refute_receive %Phoenix.Socket.Broadcast{}`).
  - `"a second flush does not repeat already sent emojis"`.
  - `"more than max_batch emojis are capped to a sample of max_batch drawn from those added"` (add 10 distinct, assert length 3 and subset).
  - `"ticks on its own when tick_ms is a number"`: start with `tick_ms: 10`, add one, `assert_receive` the batch (use the receive timeout, not a sleep).

- [ ] **Step 2: Run and see them fail.** `mix test test/speechwave/reaction_batcher_test.exs` — expect module not found.

- [ ] **Step 3: Implement `Speechwave.ReactionBatcher`** as a GenServer. State is a map `slug => [emoji]` (newest first, reversed on flush) plus config. Schedule the next tick with `Process.send_after(self(), :tick, tick_ms)` in `init` and at the end of each `:tick` (skip when `:infinity`). `flush/1` calls into the same private function the `:tick` message runs. Cap with `Enum.take_random/2`, preserving arrival order of the sample if cheap, otherwise any order (spec leaves order inside a capped sample open). Read defaults with `Application.get_env(:speechwave, __MODULE__, [])`.

- [ ] **Step 4: Wire into the supervision tree and test config**, then `mix test test/speechwave/reaction_batcher_test.exs` — expect pass.

- [ ] **Step 5: Commit.**

```bash
git add lib/speechwave/reaction_batcher.ex lib/speechwave/application.ex config/test.exs test/speechwave/reaction_batcher_test.exs
git commit -m "feat: add reaction batcher for audience pushes"
```

---

### Task 3: Switch audience pages to batched pushes

**Files:**
- Modify: `lib/speechwave_web/live/talk_live.ex` (`subscribe/1` at ~142, the `"react"` handler, the `new_reaction` `handle_info` at ~91)
- Modify: `assets/js/hooks/emoji_stream.js`
- Test: `test/speechwave_web/live/talk_live_test.exs` (update tests at ~168 and ~307, add new ones)

**Interfaces:**
- Consumes: `ReactionBatcher.add/2`, `ReactionBatcher.flush/0` from Task 2; `Reactions.record_reaction/4` from Task 1.
- Produces: audience LiveView pushes event `"reactions_batch"` with `%{emojis: [String.t()]}` to the client.

- [ ] **Step 1: Update and add failing tests** in `talk_live_test.exs`:
  - Rewrite `"receives Endpoint broadcast and page still renders correctly"`: broadcast `reactions_batch` `%{emojis: ["🔥", "❤️"]}` on `audience:<slug>`, `assert_push_event(view, "reactions_batch", %{emojis: ["🔥", "❤️"]})`, `has_element?(view, "#emoji-buttons")`.
  - Rewrite the turned-away test (~line 307) to broadcast `reactions_batch` on `audience:<slug>` and `refute_push_event(view, "reactions_batch", _, 100)`.
  - New: `"a tap reaches an audience page as a batch after a flush"`: two views, one clicks `react`, then `ReactionBatcher.flush()`, `assert_push_event(other_view, "reactions_batch", %{emojis: ["❤️"]})`.
  - New: `"a page does not receive new_reaction pushes"`: broadcast `new_reaction` on `reactions:<slug>`, `_ = :sys.get_state(view.pid)`, `refute_push_event(view, "new_reaction", _, 100)`.
  - New: `"a tap with no active session is still batched"` (extension and audience still see it, as today).
  - Existing tests that `assert_receive ... event: "new_reaction"` on `reactions:<slug>` stay unchanged and must still pass.

- [ ] **Step 2: Run and see failures.** `mix test test/speechwave_web/live/talk_live_test.exs`.

- [ ] **Step 3: Change `talk_live.ex`.** `subscribe/1` subscribes to `audience:#{slug}` and `slides:#{slug}`, no longer `reactions:#{slug}`. Replace the `new_reaction` `handle_info` clause with one for `%Phoenix.Socket.Broadcast{event: "reactions_batch", payload: %{emojis: emojis}}` that does `push_event(socket, "reactions_batch", %{emojis: emojis})`. In the `"react"` handler, after `record_reaction`, call `ReactionBatcher.add(socket.assigns.talk.slug, emoji)` and keep the existing `Endpoint.broadcast!` of `new_reaction`.

- [ ] **Step 4: Change `emoji_stream.js`.** Replace the `new_reaction` handler with `this.handleEvent("reactions_batch", ({ emojis }) => ...)`. For each emoji create the same `floating-emoji` span (same left offset and `animationend` cleanup) with `style.animationDelay` a random 0 to 250 ms. Extract the single-element creation into a small function inside the hook file.

- [ ] **Step 5: Run unit and e2e tests.** `mix test`, then the e2e suite (`mix test test/e2e`, per how the repo runs Playwright tests; check `docs/manual_tests.md` or the `mix.exs` aliases). `reaction_flow_test.exs` and `audience_reconnect_test.exs` assert `.floating-emoji` after a tap and must still pass with the 250 ms delay. Also run one manual look in the dev server: tap, see the emoji float within about half a second.

- [ ] **Step 6: Commit.**

```bash
git add lib/speechwave_web/live/talk_live.ex assets/js/hooks/emoji_stream.js test/
git commit -m "perf: batch reaction pushes to audience pages"
```

---

### Task 4: Measure and document

**Files:**
- Modify: `scripts/load_test/audience_load.mjs:75`
- Modify: `docs/load_test_results.md`, `docs/techdebt.md` only if a related item exists
- No new tests (these are measurement tools).

**Interfaces:**
- Consumes: the running batching build in the Docker image (`scripts/load_test/start_container.sh`).

- [ ] **Step 1: Update the audience-page listener** at line 75 so `pushesReceived` counts `"reactions_batch"` messages instead of `"new_reaction"`. Deviation from the spec: count messages, not emoji inside them, because parsing or counting emoji per message was the generator bottleneck noted in the comment above that line. Update the comment and the `pushes/s` label in the reporting scripts (`aggregate.mjs`, `README.md`) so the column reads "batches/s".

- [ ] **Step 2: Run the harness** per `scripts/load_test/README.md`: `run_rate_steps.sh` at 400 and 800 people (the same steps as the existing table), and the 1,200 people at 30 s case. Capture CPU, delivered %, latency p50/p95.

- [ ] **Step 3: Check against the spec's success bar.** The 800-person 45 and 60 taps/s steps (before: 100% CPU, 100% and 82% delivered, p95 251 ms and 1,495 ms) should run with delivered near 100% and clearly lower CPU. If not, record what was seen honestly and note the cause (insert checkout timeouts would be the trigger for the spec's batched-inserts follow-up).

- [ ] **Step 4: Update `docs/load_test_results.md`** with a dated "after batching" section next to the existing tables (keep the originals) and revise the "What limits it" section only where the new numbers change it.

- [ ] **Step 5: Run `mix precommit`**, fix anything it reports, then commit.

```bash
git add scripts/load_test docs/load_test_results.md
git commit -m "docs: record reaction load test results after push batching"
```

---

## Self-review notes

- **Spec coverage:** topics and batcher (Task 2, 3), cap and random sample (Task 2), hook stagger (Task 3), rescue, log hygiene and telemetry (Task 1), extension untouched (Task 3 keeps `new_reaction`), testing and measuring (Tasks 1-4), two-commit delivery split (Task 1 is the standalone fix; Tasks 2-4 the perf work). Follow-ups (insert batching, extension throttling, blog post update) are deliberately not tasks.
- **Deviations from the spec:** the load test counts `reactions_batch` messages not emoji (Task 4, reason given). Task 1 may move `audience_id/2` into `Reactions` and changes `record_reaction/4` to take `client_id`; the spec only fixed the name and arity.
- **Open for the executor:** forcing a `DBConnection.ConnectionError` in a test (Task 1, Step 2), and whether to show the tapper's own emoji instantly (spec leaves it open; this plan does not, to keep one code path).
