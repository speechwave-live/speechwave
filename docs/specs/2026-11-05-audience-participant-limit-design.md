# Audience participant limit

## Why

Pricing, terms and the dashboard all promise "up to 15 participants per talk"
on the free plan, and the whole pricing structure is built on audience size.
Today nothing limits the audience. The only check is in `ReactionChannel.join/3`:
it counts Presence entries on `reactions:<slug>`, and the only things tracked
there are the presenter's own extension connections. So the free plan really
means "15 extension connections per talk", and any number of people can open
the audience page and react.

## Goals

- A free-plan talk admits at most `Plans.limit(:max_participants, plan)` (15)
  audience members at once. Paid plans (`:unlimited`) are never limited.
- "Participant" means a distinct browser, identified by the anonymous audience
  ID that `assets/js/audience_id.js` already keeps in localStorage. Reloads and
  extra tabs from the same browser are one participant.
- A person whose connection drops keeps their place for 30 seconds, so a
  network blip on a phone does not cost them a slot. A place is released only
  when *all* of that participant's connections have ended and the 30 seconds
  have passed with no reconnect.
- The first time a limit is hit during a session is recorded, and the session
  analytics page shows it ("Participant limit reached at 20:38").
- Pricing, terms and dashboard wording says exactly what is enforced.

## Non-goals

- Limits on presenters per organization (revisit with an Enterprise tier).
- Telling the presenter during the talk. See anti-goals.
- Counting or reporting who was turned away beyond the first-hit time.
- Making the limit apply per session rather than per talk (a talk has at most
  one active session, so they coincide).

## Anti-goals

- **The presenter must never see "the talk is full" while presenting.** It is
  not actionable mid-talk, they are busy, and it could embarrass them. Nothing
  about the limit is sent over the extension channel. They learn about it
  afterwards, on the analytics page.
- A full talk must not leave someone on a dead page. The person turned away
  sees what happened and has a way to try again.
- A turned-away visitor must not receive the reaction stream. A slot is what
  entitles a viewer to receive reactions, which is also what the free cap is
  protecting (work grows with viewers times reactions per second).
- The audience ID is not extra personal data. It is not stored for this
  feature. Slots live in memory, keyed by talk and a value derived from the ID,
  and are gone on restart.

## Approaches considered

1. **Phoenix Presence keyed by audience ID.** Little code. Presence removes an
   entry as soon as its last process leaves, so it cannot hold a slot for 30
   seconds without extra bookkeeping, and the check-then-track race at the 15th
   slot has to be repaired after the fact.
2. **A small supervised GenServer that owns the slots (chosen).** One process
   serializes claims, so the 15th slot cannot be double-booked. It monitors
   each LiveView process, keeps a set of connections per participant, and
   starts a 30 second timer when the last one goes away. Single node only,
   which matches the app (SQLite).
3. **Count distinct reactors from the database.** Matches the analytics
   "people reacted" number and needs no process, but silent watchers are free
   and still cost the server fan-out work, so it does not protect the thing
   the limit exists for.

Chosen: 2. It gives the grace period and exact admission in one place.

## How it works

### Audience slots

New module `Speechwave.AudienceSlots`, a GenServer started in
`application.ex`.

- `claim(talk_id, plan_limit, participant_key, pid)` returns `:ok` or
  `{:error, :full}`. `plan_limit` is an integer or `:unlimited`.
  - If `participant_key` already holds a place (live or in its grace period),
    the connection is added to it and any release timer is cancelled: `:ok`.
  - Otherwise, if the number of held places for the talk is below the limit,
    a new place is created: `:ok`. If not: `{:error, :full}`.
- The server monitors `pid`. On `:DOWN`, the connection is removed from the
  participant. If it was the last one, a release timer for 30 seconds starts
  (module attribute, overridable by app env for tests). When the timer fires
  and the participant still has no connections, the place is freed and the
  waiting page is told so nothing else needs to happen.
- `participant_key` is the audience ID the LiveView received, lowercased. If
  the browser never sends one, the LiveView uses its own `socket.id`, so the
  person still holds exactly one place.
- Paid plans skip the server entirely (nothing to count, nothing to track).

### Audience page (`TalkLive`)

- The claim happens when the `audience_id` event arrives, since that is when
  the participant key is known. Before then the page shows the reaction UI as
  it does today but the stream and buttons are not yet "live".
- On `{:error, :full}`: assign `full: true`, unsubscribe from `reactions:<slug>`
  and `slides:<slug>`, and render a "This talk is full" panel in place of the
  emoji stream and buttons, with a "Try again" button that reloads the page
  (`window.location.reload()`, via `JS` or a plain link to the same URL). The
  `react` handler ignores events while `full` is true.
- The limit comes from the talk owner's plan, so `TalkLive` loads the owner
  (`Talks.get_talk_by_slug/1` already returns the talk; preload the user or
  ask `Accounts` for the plan).
- The first `{:error, :full}` for a talk with an active session records
  `limit_hit_at` (below). Repeats do nothing.

### Recording that the limit was hit

- New nullable column `talk_sessions.participant_limit_hit_at`
  (`:utc_datetime`). Set once, only if null, using the active session when the
  turn-away happens. A turn-away while no session is active records nothing.
- `Talks.record_participant_limit_hit(session)` does the guarded update
  (`where is_nil(...)`) so concurrent hits cannot overwrite the first time.
- The session analytics page shows "Participant limit reached at 20:38" near
  the top stats, with the time as elapsed time since `started_at`, formatted
  m:ss the same way the timeline's aria label does (hours roll into minutes
  as the existing helper does). Hidden when null. A session with no hit shows
  nothing at all.
- The session timeline does not draw it (out of scope).

### Presenter side

- The capacity check in `ReactionChannel.join/3` is removed, and with it the
  misleading comment about plan-based capacity.
- **Builder's call, mine rather than yours to confirm silently:** to limit
  account sharing, add a different, simple check: a user may have at most 3
  extension connections at once across all their talks. A fourth join fails
  with the existing reason `"capacity_reached"`. It is not plan based. 3 allows
  a laptop, a second device and a reconnect overlap. Presence on
  `reactions:<slug>` already tracks these connections, but it is per talk, so
  this check needs a per-user key as well (track in `after_join` under a
  `"presenters:<user_id>"` topic). The extension needs to handle the reason it
  already knows. This is a guardrail, not a pricing feature, and the number is
  a constant that is easy to change.

### Copy

- Pricing line becomes "Up to 15 people connected at once per talk".
- Terms: same wording in the free-plan sentence.
- Dashboard: "Max participants per talk" row keeps its label and adds
  "connected at once" to the explanation.
- Changelog entry under Fixed or Changed (it changes behavior): the free plan
  now actually limits audience size.

## Constraints

- Phoenix 1.8 / LiveView; no new dependencies.
- Follow CLAUDE.md. No LiveComponents; tests use element ids; no
  `Process.sleep` (use `Process.monitor`, `:sys.get_state`, and an injectable
  grace period so tests can set it to 0 or a few milliseconds).
- The slot server keeps only talk ids, participant keys, pids and timers. No
  audience IDs are written to disk and none are logged.
- Existing free-plan talks must keep working: a talk with 15 or fewer people
  is unaffected, and nothing changes for paid plans.

## Left to the builder

- Exact element ids and wording of the "full" panel, within the copy rules in
  the `writing-tracy` skill (no dash separators, no listed cliches).
- Whether `AudienceSlots` keeps state in the process or in ETS, as long as
  claims stay serialized.
- Whether to also push a `slots_freed` message so a full page retries itself
  (not wanted for the first version: the Try again button is enough).
- Test layout, as long as the cases below are covered.

## Cases the tests must cover

- 15 distinct participants are admitted; the 16th gets `{:error, :full}`.
- The same participant key from two connections counts once.
- When one of two connections ends, the place is kept; when the last ends, it
  is kept through the grace period and freed after it.
- A reconnect inside the grace period keeps the place, and the timer does not
  later free it.
- A freed place can be claimed by a new participant.
- `:unlimited` never returns `{:error, :full}` and does not create state.
- `TalkLive`: a full visitor sees the full panel and a retry control and no
  emoji buttons; a full visitor's `react` event does nothing; an admitted
  visitor is unaffected.
- The first turn-away sets `participant_limit_hit_at`; a second does not move
  it; no active session sets nothing.
- The analytics page shows the hit time when set and nothing when not.
- Presenter: the old capacity check no longer rejects a join when many
  Presence entries exist; a 4th concurrent connection by one user is rejected
  with `"capacity_reached"`.
- Join fails for the wrong owner or key exactly as before.
