# In-App Help Link Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Help" link in the public nav bar that opens `https://docs.speechwave.live` in a new tab, closing out the last unchecked follow-up in `docs/roadmap.md` under "Onboarding docs and help pages."

**Architecture:** Single HEEx change to the `public_nav/1` function component in `lib/speechwave_web/components/layouts.ex`. `public_nav/1` is only rendered by `Layouts.app/1` when `@current_scope` is `nil` (i.e. for logged-out visitors on public pages: home, pricing, login, terms, privacy) — the authenticated header and footer are explicitly out of scope per this decision. No context, schema, or router changes.

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
