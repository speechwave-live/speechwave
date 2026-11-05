# Audience Participant Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce the free plan's 15-participant limit on the audience (people connected at once per talk), record when a talk first hit it, show that on the session analytics page, and replace the presenter-side capacity check with an account-sharing guardrail.

**Architecture:** A supervised GenServer, `Speechwave.AudienceSlots`, owns the places per talk. Each place is keyed by the browser's anonymous audience ID, holds a set of monitored LiveView pids, and survives a 30 second grace period after its last connection ends. `TalkLive` claims a place when the audience ID arrives and turns the visitor away (no stream, no reactions, a "Try again" link) if the talk is full. The first turn-away during a session is stored on `talk_sessions.participant_limit_hit_at` and shown on the analytics page as relative plus local clock time.

**Tech Stack:** Elixir/Phoenix LiveView 1.8, Ecto + SQLite, Phoenix Presence (presenter guardrail only), ExUnit.

**Spec:** `docs/specs/2026-11-05-audience-participant-limit-design.md` (read it first; it is short).

## Global Constraints

- Limit comes from `Plans.limit(:max_participants, owner_plan)` (free `15`, pro and org `:unlimited`). Never hard-code 15 in code or tests.
- A participant is a distinct audience ID. Two connections with the same ID hold one place. A place is freed only after the last connection ends and `30_000` ms pass with no reconnect (module default, overridable for tests).
- Nothing about the limit is ever sent over the extension channel. The presenter must not learn of it during a talk.
- A turned-away visitor must not receive `reactions:<slug>` or `slides:<slug>` broadcasts and their `react` events do nothing.
- Audience IDs are never written to disk or logged by this feature. Slots live in memory only.
- Presenter guardrail: at most `3` concurrent extension connections per user across all talks; the fourth join fails with `{:error, %{reason: "capacity_reached"}}` (a reason the extension already knows). The old per-talk capacity check is removed.
- New copy follows the `writing-tracy` rules (sentence case, no dash separators, none of its listed phrases). Lint any changed prose file with `node ~/.claude/skills/writing-tracy/scripts/lint.js <file>`; changelog hits in old entries are expected.
- CLAUDE.md applies: colocated hooks only, unique DOM ids, no `Process.sleep` in tests, tests use `element/2` / `has_element?/2`, migrations via `mix ecto.gen.migration`, no git worktrees.
- Conventional commits. Run `mix precommit` before the last commit.
- Branch: `feat/audience-participant-limit` (already created; the design doc is committed on it).

## Review Focus

Inputs the spec implies that no obvious test covers, most likely first. Each has a test in the task that owns the code.

- A stale grace timer from an earlier disconnect must not free a place that was claimed again after it. (Task 2)
- A visitor on a limited plan who never sends `audience_id` gets no stream and cannot react. (Task 3)
- A turn-away while the talk has no active session does not crash and records nothing. (Task 3)
- A talk owned by a Pro user never creates slot state, whatever the audience size. (Task 3)
- One user holding connections on different talks counts all of them toward the 3; closing one frees it. (Task 5)

---

### Task 1: Store when the limit was first hit

**Files:**
- Create: migration via `mix ecto.gen.migration add_participant_limit_hit_at_to_talk_sessions`
- Modify: `lib/speechwave/talks/talk_session.ex`, `lib/speechwave/talks.ex`
- Test: `test/speechwave/talks_test.exs`

**Interfaces:**
- Produces: `talk_sessions.participant_limit_hit_at :: utc_datetime | nil`, schema field `:participant_limit_hit_at` (not in `cast`), and `Talks.record_participant_limit_hit(%TalkSession{}) :: :ok` which sets the column to `DateTime.utc_now()` truncated to seconds only if it is null (single guarded `update_all`), and never overwrites.

- [ ] **Step 1: Write failing tests** in `test/speechwave/talks_test.exs` (new `describe "record_participant_limit_hit/1"`):
  - first call sets `participant_limit_hit_at` (reload the session; not nil);
  - a second call leaves the first value unchanged (backdate the column to a known time with `Repo.update_all`, call again, assert unchanged);
  - returns `:ok` both times.
- [ ] **Step 2: Run** `mix test test/speechwave/talks_test.exs` and see them fail.
- [ ] **Step 3: Generate the migration**, add a nullable `:utc_datetime` column `participant_limit_hit_at` to `talk_sessions`, add the schema field, implement `record_participant_limit_hit/1` with `from(s in TalkSession, where: s.id == ^session.id and is_nil(s.participant_limit_hit_at))` and `Repo.update_all(set: [...])`.
- [ ] **Step 4: Run** the file again; all pass. Run `mix ecto.migrate` is not needed in test (it migrates on start); confirm with `mix test`.
- [ ] **Step 5: Commit** `feat: record when a session first hit the participant limit`.

---

### Task 2: AudienceSlots server

**Files:**
- Create: `lib/speechwave/audience_slots.ex`, `test/speechwave/audience_slots_test.exs`
- Modify: `lib/speechwave/application.ex` (add `Speechwave.AudienceSlots` to the children after `Speechwave.RateLimiter`)

**Interfaces:**
- Produces:
  - `AudienceSlots.start_link(opts)` with opts `:name` (default `__MODULE__`), `:grace_ms` (default `Application.get_env(:speechwave, :audience_slot_grace_ms, 30_000)`), `:notify` (a pid or `nil`; when set, it receives `{:slot_released, talk_id, key}` each time a place is freed).
  - `claim(talk_id, limit, key, pid, server \\ __MODULE__) :: :ok | {:error, :full}` where `limit :: non_neg_integer | :unlimited`, `key :: String.t()`, `pid :: pid()`. `:unlimited` returns `:ok` without monitoring or storing anything.
  - `count(talk_id, server \\ __MODULE__) :: non_neg_integer` places currently held (live or in grace) for the talk.
- Consumes: nothing from earlier tasks.

Behavior: one process serializes claims. A claim for a key that already holds a place adds the connection (monitoring `pid`) and cancels a pending release. A claim for a new key succeeds only while `count < limit`. On `:DOWN` the connection is removed; if it was the last, schedule the release after `grace_ms` with `Process.send_after` carrying a unique reference stored on the place; when the timer message arrives, free the place only if the stored reference still matches (this is what stops a stale timer freeing a re-claimed place). Remove empty talk entries.

- [ ] **Step 1: Write failing tests.** Start isolated instances with `start_supervised!({AudienceSlots, name: :slots_test, grace_ms: 60_000, notify: self()})` and pass the server name as the last argument. Use throwaway pids from `spawn(fn -> receive do :stop -> :ok end end)`; end one by monitoring it and sending `:stop`, then `assert_receive {:DOWN, ...}` and `:sys.get_state(:slots_test)` to synchronize. Cases (one test each):
  - `limit` participants are admitted, the next new key returns `{:error, :full}`;
  - same key from two pids counts once (`count == 1`);
  - ending one of two connections keeps the place and no release is sent;
  - ending the last connection keeps the place during the grace period (`count` still 1, no `:slot_released` message) ;
  - with `grace_ms: 10`, ending the last connection eventually sends `{:slot_released, talk_id, key}` (use `assert_receive`) and `count` drops to 0;
  - after a release a new key can claim;
  - a reconnect (new pid, same key) inside the grace period keeps the place; with a short grace, the old timer must not free it: claim again, then assert `refute_receive {:slot_released, _, _}, 100` (this is the stale timer case);
  - `:unlimited` returns `:ok` for any number of keys and `count` stays 0.
- [ ] **Step 2: Run** `mix test test/speechwave/audience_slots_test.exs`; fail.
- [ ] **Step 3: Implement** `Speechwave.AudienceSlots` as above, with a `@moduledoc` explaining the grace period and why a GenServer was chosen over Presence.
- [ ] **Step 4: Add it to the supervision tree**, run the file and `mix test`; pass.
- [ ] **Step 5: Commit** `feat: add AudienceSlots to hold audience places with a grace period`.

---

### Task 3: Claim and turn away in TalkLive

**Files:**
- Modify: `lib/speechwave_web/live/talk_live.ex`, `lib/speechwave_web/live/talk_live.html.heex`
- Test: `test/speechwave_web/live/talk_live_test.exs`

**Interfaces:**
- Consumes: `AudienceSlots.claim/4`, `Talks.record_participant_limit_hit/1`, `Talks.get_talk_with_owner/1`, `Plans.limit/2`, existing `Talks.get_active_session/1`.
- Produces: assign `slot :: :pending | :held | :full`; DOM ids `#talk-full` (the turned-away panel, shown only when `:full`) and `#try-again` (an `<a href={~p"/t/#{@talk.slug}"}>`, a plain link so the browser does a full page load).

Behavior:
- `mount` uses `Talks.get_talk_with_owner(slug)` and computes `limit = Plans.limit(:max_participants, talk.user.plan)`.
- If `limit == :unlimited`: `slot: :held` and subscribe to both PubSub topics as today (no server involvement).
- Otherwise `slot: :pending` and do **not** subscribe yet.
- On the `"audience_id"` event: keep the existing UUID handling for `client_id`; the participant key is the lowercased id when it is a valid UUID, else `socket.id`. Claim once (`slot == :pending`): on `:ok` set `:held` and subscribe to both topics; on `{:error, :full}` set `:full` and call `Talks.record_participant_limit_hit/1` for the talk's active session if there is one.
- The `"audience_id"` handler must also run the claim for an invalid id (using `socket.id`), not return early.
- `"react"` does nothing unless `slot == :held`.
- Template: when `:full`, replace `#emoji-stream` and `#emoji-buttons` with `#talk-full` containing a short explanation (the talk has reached its limit of {limit} people connected at once; the page is not broken) and `#try-again` labelled "Try again". Keep the title.

- [ ] **Step 1: Write failing tests** (new `describe "participant limit"`; tests that already react must first send `render_hook(view, "audience_id", %{"id" => uuid})`, update the existing ones accordingly):
  - the 16th distinct visitor (fill `Plans.limit(:max_participants, :free)` places with `AudienceSlots.claim/4` and spawned pids first) sees `#talk-full` and `#try-again`, no `#emoji-buttons`, and `render_click(view, "react", ...)` does not broadcast (`refute_receive`);
  - a turned-away visitor receives no `new_reaction` broadcast pushed to them (broadcast on the topic, `refute_push_event`);
  - an admitted visitor still sees `#emoji-buttons`, can react, receives broadcasts;
  - the same UUID in a second `live/2` connection is admitted when the talk is full of 15 others only if it already holds a place;
  - a visitor who never sends `audience_id` on a free-plan talk gets no stream broadcast and `react` does nothing;
  - first turn-away with an active session sets `participant_limit_hit_at`; with no active session nothing is recorded and nothing crashes;
  - a talk owned by a pro user (`user_fixture(%{plan: :pro})` or the project's equivalent) admits more than 15 and `AudienceSlots.count/1` stays 0.
- [ ] **Step 2: Run** `mix test test/speechwave_web/live/talk_live_test.exs`; fail.
- [ ] **Step 3: Implement** per the behavior above.
- [ ] **Step 4: Run** the file and `mix test.browser` (the audience page E2E must still pass); pass.
- [ ] **Step 5: Commit** `feat: limit free-plan talks to the plan's audience size`.

---

### Task 4: Show the limit-hit time on the analytics page

**Files:**
- Modify: `lib/speechwave_web/live/session_analytics_live.ex`, `lib/speechwave_web/live/session_analytics_live.html.heex`
- Test: `test/speechwave_web/live/session_analytics_live_test.exs`, plus a unit test for the formatter if it lives in its own module

**Interfaces:**
- Consumes: `participant_limit_hit_at` on `TalkSession` (Task 1).
- Produces: element `#limit-hit` containing the text `Participant limit reached {relative} after the session began (` + a `<time id="limit-hit-time" phx-hook=".LocalTime" phx-update="ignore" datetime={iso8601_utc}>` + `)`; the `<time>` text fallback is e.g. `8:38 PM UTC` from `Calendar.strftime(dt, "%-I:%M %p UTC")`. The element is absent when the column is nil.

Relative text (whole minutes from `started_at`): under one minute `less than a minute`, `1 minute`, `N minutes`, from sixty `1 hour`, `1 hour 5 minutes`, `2 hours` (pluralise; omit zero minutes). Compute on the server in a small private function or a tiny module; no hook involved.

Colocated hook `.LocalTime` in the same template: on `mounted()` and `updated()` set `this.el.textContent` to `new Date(this.el.getAttribute("datetime")).toLocaleTimeString([], {hour: "numeric", minute: "2-digit", timeZoneName: "short"})`, guarded by `isNaN` so a bad value leaves the fallback.

- [ ] **Step 1: Write failing tests:** with the column set (use `Repo.update_all` to set it relative to `started_at`) `#limit-hit` exists and contains the relative text for 0 minutes ("less than a minute"), 1, 23, 65 ("1 hour 5 minutes") and 120 minutes ("2 hours"), and `#limit-hit-time` has a `datetime` attribute equal to the ISO 8601 UTC time; with the column nil, `#limit-hit` is absent.
- [ ] **Step 2: Run** the file; fail.
- [ ] **Step 3: Implement** the assigns, template block (place it with the top stats, above the timeline), and the hook.
- [ ] **Step 4: Run** the file and `mix test.browser`; pass.
- [ ] **Step 5: Add a tech-debt bullet** to `docs/techdebt.md` (new section "Time zones"): the session start line on the analytics page prints UTC with no zone label; `.LocalTime` could be reused. Commit `feat: show when a session hit the participant limit`.

---

### Task 5: Presenter guardrail in ReactionChannel

**Files:**
- Modify: `lib/speechwave_web/channels/reaction_channel.ex`
- Test: `test/speechwave_web/channels/reaction_channel_test.exs`

**Interfaces:**
- Consumes: `SpeechwaveWeb.Presence`.
- Produces: join returns `{:error, %{reason: "capacity_reached"}}` when the user already has `3` extension connections across talks. Constant `@max_extension_connections 3`. Each connection tracks itself in `after_join` on topic `"presenters:#{user.id}"` with key `"conn:#{inspect(self())}"` in addition to the existing `reactions:<slug>` tracking (which stays; it is used elsewhere).

- [ ] **Step 1: Write failing tests:** remove or rewrite any existing test of the old per-talk capacity check; add (a) joining with more than 15 Presence entries on `reactions:<slug>` is no longer rejected, (b) one user can join 3 different talks, the fourth join is rejected with `"capacity_reached"`, (c) after one of the three channels is closed (`close/1` plus `Process.monitor` and `assert_receive {:DOWN, ...}`; Presence cleanup may need `:sys.get_state` on the Presence shards, or `Phoenix.Presence` test helpers; use whatever deterministic approach works), a new join succeeds, (d) a different user is unaffected, (e) the old reasons `not_found` and `unauthorized` are unchanged.
- [ ] **Step 2: Run** the file; fail.
- [ ] **Step 3: Implement:** drop the `Plans.check(:max_participants, ...)` clause and its `Presence.list` on the talk topic; add the per-user check using `Presence.list("presenters:#{user.id}") |> map_size()`; update the module comment (it no longer mentions plan-based capacity); keep the `{:capacity, ...}` else-branch mapping to `"capacity_reached"`.
- [ ] **Step 4: Run** the file and `mix test`; pass.
- [ ] **Step 5: Commit** `feat: limit extension connections per account instead of per talk`.

---

### Task 6: Copy, changelog, final checks

**Files:**
- Modify: `lib/speechwave_web/live/pricing_live.ex`, `lib/speechwave_web/controllers/page_html/terms.html.heex`, `lib/speechwave_web/live/dashboard_live.html.heex`, `CHANGELOG.md`, any tests asserting the old wording

- [ ] **Step 1: Update copy.** Pricing line 53: `"Up to #{@free_participant_limit} people connected at once per talk"`. Terms (line 39): same wording in the free-plan sentence. Dashboard: line 24 phrase becomes "up to {@participant_limit} people connected at once", and the label on line 81 becomes "Max people connected at once per talk". Find and fix any test asserting the old text (`mix test` shows them).
- [ ] **Step 2: Changelog** under `[Unreleased]`: `### Changed` entry "Free plan talks now limit the audience to 15 people connected at once, as the pricing page says. Before, only the speaker's own connections were limited. A person whose connection drops keeps their place for 30 seconds." and a `### Added` entry "The session analytics page tells you when a talk reached its participant limit." and a `### Changed` entry "The extension now allows up to 3 connections per account at once, across all talks." Lint with the writing-tracy linter.
- [ ] **Step 3: Verify:** `mix precommit`, `mix test`, `mix test.browser`, all green.
- [ ] **Step 4: Commit** `docs: describe the audience limit exactly as enforced`.
