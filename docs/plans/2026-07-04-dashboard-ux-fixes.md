# Dashboard & Analytics UX Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three pre-launch UX problems: surface the talk slug (with copy) in the dashboard's selected-talk panel, make session rows readable with a two-line layout and a prominent analytics link, and restore the logged-in header on the session analytics page.

**Architecture:** All three fixes are HEEx template changes in existing LiveViews (`DashboardLive`, `SessionAnalyticsLive`) — no context, schema, or router changes. Tests extend the existing `Phoenix.LiveViewTest` suites and assert on element IDs.

**Tech Stack:** Phoenix 1.8 LiveView, HEEx, Tailwind v4, `Phoenix.LiveViewTest`.

**Spec:** `docs/specs/2026-07-04-dashboard-ux-fixes-design.md`

## Global Constraints

- Conventional commit format for all commits (e.g. `feat: ...`, `fix: ...`, `test: ...`).
- HEEx rules from CLAUDE.md apply: `{...}` interpolation in attributes, `<%= %>` for block constructs, class lists use `[...]` syntax, comments use `<%!-- --%>`.
- Never test raw HTML when an element ID works: use `has_element?(view, "#id", "text")`.
- Do not change any existing DOM ids (`#talk-link`, `#copy-talk-link`, `#download-qr-code`, `#session-label-*`, `#analytics-link-*`, `#rename-session-*`, `#delete-session-*`, `#sessions-panel`) — existing tests depend on them.
- Run tests with `mix test test/speechwave_web/live/<file>` from the repo root.
- Elixir formatting: run `mix format` before committing (it formats `.heex` too).

---

### Task 1: Talk slug row in the selected-talk panel

**Files:**
- Modify: `lib/speechwave_web/live/dashboard_live.html.heex` (selected-talk panel, `#selected-talk-qr`, roughly lines 172–225)
- Test: `test/speechwave_web/live/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `@selected_talk` (a `Speechwave.Talks.Talk` struct with `.slug`), already assigned by `DashboardLive`; the existing `CopyToClipboard` JS hook (used by `#copy-talk-link`).
- Produces: DOM ids `#talk-slug` and `#copy-talk-slug` (used by tests and future docs).

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave_web/live/dashboard_live_test.exs`, right after the existing test `"selected talk panel shows a copyable link and QR download link"` (ends near line 60):

```elixir
test "selected talk panel shows the slug with a copy button", %{conn: conn, user: user} do
  talk_fixture(user, %{title: "Prime Talk", slug: "prime"})
  {:ok, view, _html} = live(conn, "/dashboard")

  view |> element("#talk-list button", "Prime Talk") |> render_click()

  assert has_element?(view, "#talk-slug", "prime")
  assert has_element?(view, "#copy-talk-slug[data-clipboard-text='prime']")
  assert render(view) =~ "Slug for browser extension"
  assert render(view) =~ "URL for your audience"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/speechwave_web/live/dashboard_live_test.exs`
Expected: 1 failure — the new test fails on `has_element?(view, "#talk-slug", "prime")`. All other tests pass.

- [ ] **Step 3: Implement the template change**

In `lib/speechwave_web/live/dashboard_live.html.heex`, inside the `#selected-talk-qr` panel:

**(a)** Add a label line above the existing URL row. Find:

```heex
            <h2 class="text-lg font-semibold text-gray-800 mb-1">{@selected_talk.title}</h2>

            <div class="flex items-center gap-2 mb-4">
```

Replace with:

```heex
            <h2 class="text-lg font-semibold text-gray-800 mb-3">{@selected_talk.title}</h2>

            <p class="text-xs font-medium text-gray-500 mb-1">URL for your audience:</p>
            <div class="flex items-center gap-2 mb-4">
```

**(b)** Add the slug section between the QR block and the sessions panel. Find:

```heex
            <% end %>

            <%!-- Sessions Panel --%>
            <div id="sessions-panel" class="mt-4 border-t border-gray-100 pt-4">
```

(the `<% end %>` closing the `<%= if @selected_qr_data_uri do %>` block) and replace with:

```heex
            <% end %>

            <%!-- Talk Slug --%>
            <div id="slug-panel" class="mt-4 border-t border-gray-100 pt-4">
              <p class="text-xs font-medium text-gray-500 mb-1">Slug for browser extension:</p>
              <div class="flex items-center gap-2">
                <code
                  id="talk-slug"
                  class="flex-1 min-w-0 px-2 py-1 text-sm text-gray-800 bg-gray-50 rounded truncate"
                >
                  {@selected_talk.slug}
                </code>
                <button
                  id="copy-talk-slug"
                  type="button"
                  phx-hook="CopyToClipboard"
                  data-clipboard-text={@selected_talk.slug}
                  data-flash-message="Slug copied to clipboard"
                  title="Copy slug"
                  class="shrink-0 p-1.5 text-gray-400 hover:text-indigo-600 rounded transition-colors"
                >
                  <.icon name="hero-clipboard-document" class="copy-icon-idle w-4 h-4" />
                  <.icon
                    name="hero-clipboard-document-check"
                    class="copy-icon-copied hidden w-4 h-4 text-green-600"
                  />
                </button>
              </div>
            </div>

            <%!-- Sessions Panel --%>
            <div id="sessions-panel" class="mt-4 border-t border-gray-100 pt-4">
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix format && mix test test/speechwave_web/live/dashboard_live_test.exs`
Expected: all tests pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/live/dashboard_live.html.heex test/speechwave_web/live/dashboard_live_test.exs
git commit -m "feat: surface talk slug with copy button in dashboard talk panel"
```

---

### Task 2: Readable two-line session rows with prominent analytics link

**Files:**
- Modify: `lib/speechwave_web/live/dashboard_live.html.heex` (sessions panel — the `<%= else %>` display branch of each session `<li>`; after Task 1 the block starts near line 290)
- Test: `test/speechwave_web/live/dashboard_live_test.exs`

**Interfaces:**
- Consumes: `@sessions` entries `%{session: session, reaction_count: reaction_count}`; `session.label`, `session.started_at` (a `DateTime`), `session.ended_at` (nil while active).
- Produces: unchanged DOM ids `#session-{id}`, `#session-label-{id}`, `#analytics-link-{id}`, `#rename-session-{id}`, `#delete-session-{id}`, `.session-active-badge`; analytics link now contains visible text "Analytics"; row shows the formatted start date.

- [ ] **Step 1: Write the failing tests**

Add inside the `describe "sessions panel"` block of `test/speechwave_web/live/dashboard_live_test.exs`:

```elixir
test "session row shows start date and readable label", %{conn: conn, talk: talk} do
  {:ok, session} = Speechwave.Talks.start_session(talk)
  expected_date = Calendar.strftime(session.started_at, "%b %d, %Y")

  {:ok, view, _html} = live(conn, "/dashboard")
  view |> element("#talk-list button", "Prime Talk") |> render_click()

  assert has_element?(view, "#session-#{session.id}", expected_date)
  assert has_element?(view, "#session-label-#{session.id}.text-gray-900")
end

test "analytics link is labeled and prominent", %{conn: conn, talk: talk} do
  {:ok, session} = Speechwave.Talks.start_session(talk)
  {:ok, view, _html} = live(conn, "/dashboard")
  view |> element("#talk-list button", "Prime Talk") |> render_click()

  assert has_element?(view, "#analytics-link-#{session.id}", "Analytics")
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/speechwave_web/live/dashboard_live_test.exs`
Expected: 2 failures (the two new tests); all existing tests pass.

- [ ] **Step 3: Implement the two-line row layout**

In `lib/speechwave_web/live/dashboard_live.html.heex`, in the sessions panel, find the entire display branch (everything between `<% else %>` and the `<% end %>` that closes `<%= if @renaming_session_id == session.id do %>`):

```heex
                        <div class="flex items-center justify-between gap-2">
                          <div class="flex items-center gap-2 min-w-0">
                            <span id={"session-label-#{session.id}"} class="font-medium truncate">
                              {session.label}
                            </span>
                            <%= if is_nil(session.ended_at) do %>
                              <span class="session-active-badge px-1.5 py-0.5 bg-green-100 text-green-700 text-xs rounded-full shrink-0">
                                Active
                              </span>
                            <% end %>
                            <span class="text-gray-400 text-xs shrink-0">
                              {reaction_count} {if reaction_count == 1,
                                do: "reaction",
                                else: "reactions"}
                            </span>
                          </div>
                          <div class="flex gap-1 shrink-0">
                            <.link
                              id={"analytics-link-#{session.id}"}
                              navigate={~p"/sessions/#{session.id}"}
                              class="p-1 text-gray-400 hover:text-indigo-600 rounded transition-colors"
                              title="View analytics"
                            >
                              <.icon name="hero-chart-bar" class="w-4 h-4" />
                            </.link>
                            <button
                              id={"rename-session-#{session.id}"}
                              phx-click="rename_session"
                              phx-value-id={session.id}
                              class="p-1 text-gray-400 hover:text-gray-600 rounded transition-colors"
                              title="Rename"
                            >
                              <.icon name="hero-pencil" class="w-4 h-4" />
                            </button>
                            <button
                              id={"delete-session-#{session.id}"}
                              phx-click="delete_session"
                              phx-value-id={session.id}
                              data-confirm="Delete this session and its reactions?"
                              class="p-1 text-gray-400 hover:text-red-600 rounded transition-colors"
                              title="Delete"
                            >
                              <.icon name="hero-trash" class="w-4 h-4" />
                            </button>
                          </div>
                        </div>
```

Replace it with the two-line layout:

```heex
                        <div class="flex items-center gap-2 min-w-0">
                          <span
                            id={"session-label-#{session.id}"}
                            class="font-medium text-gray-900 truncate"
                          >
                            {session.label}
                          </span>
                          <span class="text-gray-400 text-xs shrink-0">
                            {Calendar.strftime(session.started_at, "%b %d, %Y")}
                          </span>
                          <%= if is_nil(session.ended_at) do %>
                            <span class="session-active-badge px-1.5 py-0.5 bg-green-100 text-green-700 text-xs font-medium rounded-full shrink-0">
                              Active
                            </span>
                          <% end %>
                        </div>
                        <div class="flex items-center justify-between gap-2 mt-1.5">
                          <span class="text-gray-400 text-xs">
                            {reaction_count} {if reaction_count == 1,
                              do: "reaction",
                              else: "reactions"}
                          </span>
                          <div class="flex items-center gap-1 shrink-0">
                            <.link
                              id={"analytics-link-#{session.id}"}
                              navigate={~p"/sessions/#{session.id}"}
                              class="inline-flex items-center gap-1 px-1.5 py-1 text-xs font-medium text-indigo-600 hover:text-indigo-800 rounded transition-colors"
                              title="View analytics"
                            >
                              <.icon name="hero-chart-bar" class="w-4 h-4" /> Analytics
                            </.link>
                            <button
                              id={"rename-session-#{session.id}"}
                              phx-click="rename_session"
                              phx-value-id={session.id}
                              class="p-1 text-gray-400 hover:text-gray-600 rounded transition-colors"
                              title="Rename"
                            >
                              <.icon name="hero-pencil" class="w-4 h-4" />
                            </button>
                            <button
                              id={"delete-session-#{session.id}"}
                              phx-click="delete_session"
                              phx-value-id={session.id}
                              data-confirm="Delete this session and its reactions?"
                              class="p-1 text-gray-400 hover:text-red-600 rounded transition-colors"
                              title="Delete"
                            >
                              <.icon name="hero-trash" class="w-4 h-4" />
                            </button>
                          </div>
                        </div>
```

Do **not** touch the rename-form branch (`<%= if @renaming_session_id == session.id do %>` ... `<% else %>`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix format && mix test test/speechwave_web/live/dashboard_live_test.exs`
Expected: all tests pass, 0 failures (including the pre-existing sessions-panel tests, which assert the same IDs).

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/live/dashboard_live.html.heex test/speechwave_web/live/dashboard_live_test.exs
git commit -m "fix: readable two-line session rows with labeled analytics link"
```

---

### Task 3: Logged-in header on the session analytics page

**Files:**
- Modify: `lib/speechwave_web/live/session_analytics_live.html.heex:1`
- Test: `test/speechwave_web/live/session_analytics_live_test.exs`

**Interfaces:**
- Consumes: `@current_scope`, assigned by the `live_session :require_authenticated_user` on_mount hook — always present on this route.
- Produces: nothing new — the authenticated header from `Layouts.app` (Dashboard / Settings / email / Log out).

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave_web/live/session_analytics_live_test.exs` (note: the page body already contains a "Back to Dashboard" link pointing at `/dashboard`, so the test must target the `header` element and the Settings link, which only the authenticated nav has):

```elixir
test "shows the authenticated header nav, not the public nav", %{conn: conn, session: session} do
  {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

  assert has_element?(view, "header a[href='/users/settings']")
  refute render(view) =~ "Get started free"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/speechwave_web/live/session_analytics_live_test.exs`
Expected: 1 failure — no `header a[href='/users/settings']` (the layout currently renders the public nav with "Get started free").

- [ ] **Step 3: Pass current_scope to the layout**

In `lib/speechwave_web/live/session_analytics_live.html.heex`, change line 1 from:

```heex
<Layouts.app flash={@flash}>
```

to:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/speechwave_web/live/session_analytics_live_test.exs`
Expected: all tests pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/live/session_analytics_live.html.heex test/speechwave_web/live/session_analytics_live_test.exs
git commit -m "fix: show authenticated header on session analytics page"
```

---

### Task 4: Full-suite verification

**Files:**
- None modified (verification only; fix anything that fails).

**Interfaces:**
- Consumes: all changes from Tasks 1–3.
- Produces: green `mix precommit`.

- [ ] **Step 1: Run the precommit alias**

Run: `mix precommit`
Expected: compiles with no warnings, formatter clean, full test suite passes.

- [ ] **Step 2: Fix any failures and re-run**

If `mix precommit` reports issues, fix them, re-run until green, and commit any fixes:

```bash
git add -A && git commit -m "fix: address precommit findings for dashboard UX fixes"
```

(Skip the commit if nothing needed fixing.)
