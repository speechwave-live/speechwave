# In-App Help Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Help" link in the public nav bar that opens `https://docs.speechwave.live` in a new tab, closing out the last unchecked follow-up in `docs/roadmap.md` under "Onboarding docs and help pages."

**Architecture:** HEEx changes to `lib/speechwave_web/components/layouts.ex`. Every page renders through `Layouts.app/1`, which branches into one of two mutually-exclusive headers based on `@current_scope`: the authenticated header (Dashboard/Settings/logout, for logged-in users on any page) or `public_nav/1` (for logged-out visitors). The Help link must appear in **both** branches so it shows on every page — Dashboard, Settings, session analytics, home, pricing, login, terms, privacy. `public_footer/1` remains out of scope (footer, not header). No context, schema, or router changes.

**Revision note (2026-07-04):** Task 1 originally added Help to `public_nav/1` only, per an initial scoping decision to limit it to logged-out marketing pages. User feedback after reviewing the branch: Help must appear for logged-in users too (Dashboard, Settings, etc.) — those are exactly the pages where help is most needed. Task 3 below adds it to the authenticated header to close that gap.

**Tech Stack:** Phoenix 1.8 LiveView, HEEx, Tailwind v4, `Phoenix.ConnTest`.

## Global Constraints

- Conventional commit format for all commits (e.g. `feat: ...`).
- HEEx rules from CLAUDE.md apply: `{...}` interpolation in attributes, class lists use `[...]` syntax.
- External links in this codebase use `target="_blank" rel="noopener noreferrer"` (see `lib/speechwave_web/live/dashboard_live.html.heex:181-189`).
- The Help link must be unconditional inside `public_nav/1` (shown regardless of `@current_scope`), not added to `Layouts.app/1`'s authenticated header or to `public_footer/1`.
- Run `mix format` before committing.

---

### Task 1: Add Help link to public nav

**Files:**
- Modify: `lib/speechwave_web/components/layouts.ex:96-99` (inside `public_nav/1`, the `<nav>` block)
- Test: `test/speechwave_web/controllers/page_controller_test.exs`

**Interfaces:**
- Consumes: nothing new — `public_nav/1` already receives `@current_scope` as an existing attr; the Help link does not depend on it.
- Produces: a DOM element `id="help-nav-link"` other tests/specs can target later.

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave_web/controllers/page_controller_test.exs`, after the existing `"GET / returns 200"` test:

```elixir
test "GET / includes a Help link to the docs site", %{conn: conn} do
  html = get(conn, ~p"/") |> html_response(200)

  assert html =~ ~s(id="help-nav-link")
  assert html =~ ~s(href="https://docs.speechwave.live")
  assert html =~ ~s(target="_blank")
  assert html =~ ~s(rel="noopener noreferrer")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/speechwave_web/controllers/page_controller_test.exs`
Expected: FAIL — `id="help-nav-link"` (and the other assertions) not found in the response body.

- [ ] **Step 3: Add the Help link to `public_nav/1`**

In `lib/speechwave_web/components/layouts.ex`, the `<nav>` block currently reads (lines 96-99):

```heex
        <nav class="flex items-center gap-1">
          <a href={~p"/pricing"} class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors">
            Pricing
          </a>
```

Change it to add the Help link immediately after the Pricing link, before the `<%= if @current_scope do %>` block:

```heex
        <nav class="flex items-center gap-1">
          <a href={~p"/pricing"} class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors">
            Pricing
          </a>
          <a
            id="help-nav-link"
            href="https://docs.speechwave.live"
            target="_blank"
            rel="noopener noreferrer"
            class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
          >
            Help
          </a>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/speechwave_web/controllers/page_controller_test.exs`
Expected: PASS (all 4 tests in the file, including the new one).

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/speechwave_web/components/layouts.ex test/speechwave_web/controllers/page_controller_test.exs
git commit -m "feat: add in-app Help link to public nav"
```

---

### Task 2: Update roadmap

**Files:**
- Modify: `docs/roadmap.md:33`

**Interfaces:**
- None — documentation-only change.

- [ ] **Step 1: Check off the roadmap item**

In `docs/roadmap.md`, change line 33 from:

```markdown
- [ ] Add in-app "Help" links from speechwave.live to docs.speechwave.live
```

to:

```markdown
- [x] Add in-app "Help" links from speechwave.live to docs.speechwave.live
      (done 2026-07-04; public nav only — see
      `docs/plans/2026-07-04-in-app-help-link.md`)
```

- [ ] **Step 2: Commit**

```bash
git add docs/roadmap.md
git commit -m "docs: check off in-app Help link follow-up"
```

---

### Task 3: Add Help link to authenticated header

**Files:**
- Modify: `lib/speechwave_web/components/layouts.ex:49-53` (inside `app/1`'s authenticated branch, the `<div class="flex items-center gap-4 text-sm ml-auto">` block)
- Test: `test/speechwave_web/live/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `@current_scope` (already available in `app/1`'s authenticated branch — no new assign needed).
- Produces: reuses the DOM id `id="help-nav-link"` from Task 1. The two branches of `app/1` are mutually exclusive (only one renders per request), so the id is never duplicated in a single page's DOM.

- [ ] **Step 1: Write the failing test**

The file has a top-level `setup` block (lines 10-13) that already logs a user in and provides an authenticated `conn`:

```elixir
setup %{conn: conn} do
  user = user_fixture()
  %{conn: log_in_user(conn, user), user: user}
end
```

Add this test as a new top-level test (not inside a nested `describe`), right after the existing `"renders new talk form"` test (line 21-24):

```elixir
test "shows a Help link to the docs site", %{conn: conn} do
  {:ok, _view, html} = live(conn, "/dashboard")

  assert html =~ ~s(id="help-nav-link")
  assert html =~ ~s(href="https://docs.speechwave.live")
  assert html =~ ~s(target="_blank")
  assert html =~ ~s(rel="noopener noreferrer")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/speechwave_web/live/dashboard_live_test.exs`
Expected: FAIL — `id="help-nav-link"` not found (the authenticated header doesn't have a Help link yet).

- [ ] **Step 3: Add the Help link to the authenticated header**

In `lib/speechwave_web/components/layouts.ex`, the authenticated header's link row currently reads (lines 49-53):

```heex
          <div class="flex items-center gap-4 text-sm ml-auto">
            <a href={~p"/dashboard"} class="text-steel hover:text-ink transition-colors">Dashboard</a>
            <a href={~p"/users/settings"} class="text-steel hover:text-ink transition-colors">
              Settings
            </a>
```

Change it to add the Help link after Settings, before the email span:

```heex
          <div class="flex items-center gap-4 text-sm ml-auto">
            <a href={~p"/dashboard"} class="text-steel hover:text-ink transition-colors">Dashboard</a>
            <a href={~p"/users/settings"} class="text-steel hover:text-ink transition-colors">
              Settings
            </a>
            <a
              id="help-nav-link"
              href="https://docs.speechwave.live"
              target="_blank"
              rel="noopener noreferrer"
              class="text-steel hover:text-ink transition-colors"
            >
              Help
            </a>
```

Note the class here matches the surrounding Dashboard/Settings links (`text-steel hover:text-ink transition-colors`, no `px-3 py-2`) — this header's links are unpadded, unlike `public_nav/1`'s padded links. Do not copy `public_nav/1`'s class string here.

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/speechwave_web/live/dashboard_live_test.exs`
Expected: PASS.

Also re-run the Task 1 test to confirm the shared id doesn't collide across branches:

Run: `mix test test/speechwave_web/controllers/page_controller_test.exs`
Expected: PASS (unchanged from Task 1).

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/speechwave_web/components/layouts.ex test/speechwave_web/live/dashboard_live_test.exs
git commit -m "feat: add Help link to authenticated header"
```

---

### Task 4: Correct roadmap wording

**Files:**
- Modify: `docs/roadmap.md` (the line added in Task 2)

**Interfaces:**
- None — documentation-only change.

**Context:** Task 2 committed roadmap wording that said "public nav only," which described Task 1's scope at the time. Task 3 closes that gap, so the note is now inaccurate and must be corrected to avoid misleading future readers.

- [ ] **Step 1: Update the roadmap note**

Change the line added in Task 2 from:

```markdown
- [x] Add in-app "Help" links from speechwave.live to docs.speechwave.live
      (done 2026-07-04; public nav only — see
      `docs/plans/2026-07-04-in-app-help-link.md`)
```

to:

```markdown
- [x] Add in-app "Help" links from speechwave.live to docs.speechwave.live
      (done 2026-07-04; appears in the header on every page, logged in or
      out — see `docs/plans/2026-07-04-in-app-help-link.md`)
```

- [ ] **Step 2: Commit**

```bash
git add docs/roadmap.md
git commit -m "docs: correct Help link roadmap note to reflect full header coverage"
```
