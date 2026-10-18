# First-login welcome banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show new users a dismissible welcome banner under the header that links to the docs site's Getting Started page, and never show it again once dismissed.

**Architecture:** A nullable `users.welcomed_at` column drives the banner. `Layouts.app/1` renders the banner while it is `nil`. The close button runs `JS.hide |> JS.push("dismiss_welcome")`, and one `handle_event` hook attached in `UserAuth.mount_current_scope/2` records the dismissal for every LiveView, so there is no controller and no reload.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto (SQLite), Tailwind v4, ExUnit with `Phoenix.LiveViewTest`.

**Spec:** `docs/specs/2026-10-17-first-login-welcome-banner-design.md`

## Global Constraints

- Work on a feature branch (`feat/welcome-banner`), never a git worktree.
- Conventional commit messages.
- Banner text: `Welcome to Speechwave.live! Read the **Getting Started** guide for a quick tour, or click **Help** at the top of any page.` "Getting Started" is the link; "Help" is bold text, not a link.
- Link target: docs base from `Application.get_env(:speechwave, :docs_url)` joined with `getting-started.html` using exactly one `/`. Opens with `target="_blank" rel="noopener noreferrer"`, like the Help link.
- DOM ids: `welcome-banner`, `welcome-banner-dismiss`, `welcome-banner-link`.
- `welcomed_at` is `:utc_datetime`, never in a `cast` list. Only `Accounts.mark_welcomed/1` writes it.
- Migration generated with `mix ecto.gen.migration add_welcomed_at_to_users`, and it backfills every existing user with `CURRENT_TIMESTAMP`.
- No inline `<script>` tags. Use Tailwind classes and the existing tokens (`bg-surface`, `border-hairline`, `text-ink`, `text-steel`).
- User-facing prose has no AI cliches and no dash-separated phrases.
- Run `mix precommit` at the end and fix what it reports.

## Review Focus

- A user created before this ships must not see the banner (backfill). Pinned in Task 1 by running the migration against a database with an existing row.
- Admin live session mounts `mount_current_scope/2` twice on one socket, and a duplicate `attach_hook` id raises. Pinned in Task 3.
- Dismissing must not drop the scope's virtual `authenticated_at`, or `Accounts.sudo_mode?/2` stops working on the same socket. Pinned in Task 3.
- Docs base URL with and without a trailing slash must give one slash. Pinned in Task 2.
- Signed-out visitors on public LiveViews (pricing, login) get no banner and no hook. Pinned in Task 3.
- The banner must not appear on the controller-rendered dev login page. Pinned in Task 2.

---

### Task 1: `welcomed_at` column and `Accounts.mark_welcomed/1`

**Files:**
- Create: `priv/repo/migrations/<timestamp>_add_welcomed_at_to_users.exs` (via `mix ecto.gen.migration add_welcomed_at_to_users`)
- Modify: `lib/speechwave/accounts/user.ex` (add `field :welcomed_at, :utc_datetime` to the schema)
- Modify: `lib/speechwave/accounts.ex` (add `mark_welcomed/1` near the session functions)
- Test: `test/speechwave/accounts_test.exs`

**Interfaces:**
- Produces: `Speechwave.Accounts.mark_welcomed(user :: %User{}) :: {:ok, %User{}}`. Sets `welcomed_at` to `DateTime.utc_now(:second)` only if it is currently `nil`. If already set, returns `{:ok, user}` with the stored timestamp unchanged. The returned struct is reloaded from the database.
- Produces: `%User{welcomed_at: DateTime.t() | nil}`, `nil` for new users.

- [ ] **Step 1: Write the failing tests** in a new `describe "mark_welcomed/1"` block in `accounts_test.exs`:
  - `"sets welcomed_at on a new user"`: `user_fixture().welcomed_at == nil`; after `{:ok, updated} = Accounts.mark_welcomed(user)`, `updated.welcomed_at` is a `%DateTime{}` and `Repo.get!(User, user.id).welcomed_at == updated.welcomed_at`.
  - `"does not change an existing timestamp"`: mark once, `Process.sleep` is not allowed, so instead set `welcomed_at` directly with `Repo.update_all` to `~U[2026-01-01 00:00:00Z]`, call `mark_welcomed` on the reloaded user, and assert the timestamp is still `~U[2026-01-01 00:00:00Z]`.
- [ ] **Step 2: Run to verify failure:** `mix test test/speechwave/accounts_test.exs`. Expected: FAIL (`mark_welcomed/1` undefined, unknown field).
- [ ] **Step 3: Generate the migration and implement.** The migration adds `:welcomed_at, :utc_datetime` to `users`, then runs `execute("UPDATE users SET welcomed_at = CURRENT_TIMESTAMP")` for the backfill, with a `down` that removes the column. Add the schema field. Implement `mark_welcomed/1` as one `Repo.update_all` guarded by `is_nil(u.welcomed_at)` and then `Repo.get!`, so two concurrent callers keep the first timestamp.
- [ ] **Step 4: Prove the backfill.** Before running the new migration on the dev database, confirm it has at least one user row (`mix ecto.migrate` after rolling back is enough: `mix ecto.rollback`, then `mix ecto.migrate`). Then check with Tidewave `project_eval` or `sqlite3` that `SELECT count(*) FROM users WHERE welcomed_at IS NULL` is `0`. Expected: `0`.
- [ ] **Step 5: Run tests:** `mix test test/speechwave/accounts_test.exs`. Expected: PASS.
- [ ] **Step 6: Commit** `feat: add welcomed_at to users and Accounts.mark_welcomed/1`

---

### Task 2: Banner component, docs link, `show_welcome` attr

**Files:**
- Modify: `lib/speechwave_web/components/layouts.ex` (banner, wrapper, `docs_url/1`, `show_welcome` attr)
- Modify: `lib/speechwave_web/controllers/dev_login_html/index.html.heex` (pass `show_welcome={false}`)
- Test: `test/speechwave_web/components/layouts_test.exs` (new)

**Interfaces:**
- Consumes: `User.welcomed_at` from Task 1.
- Produces: `attr :show_welcome, :boolean, default: true` on `Layouts.app/1`.
- Produces: private `docs_url(path :: String.t()) :: String.t()` in `Layouts`, joining the configured base and `path` with one `/`.
- Produces: `welcome_banner/1` function component in `Layouts`, rendering `#welcome-banner` with `#welcome-banner-link` and a close button `#welcome-banner-dismiss`. The close button's `phx-click` is `JS.hide(to: "#welcome-banner", transition: "fade-out") |> JS.push("dismiss_welcome")`.

- [ ] **Step 1: Write the failing tests** in `layouts_test.exs` (`use SpeechwaveWeb.ConnCase, async: false` because two tests change app env; restore with `on_exit`). Render with `Phoenix.LiveViewTest.render_component(&SpeechwaveWeb.Layouts.app/1, assigns)` where assigns are `flash: %{}`, `current_scope: Scope.for_user(user)`, `inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "" end}]`, and parse with `LazyHTML`:
  - `"shows the banner when welcomed_at is nil"`: `#welcome-banner` exists.
  - `"hides the banner when welcomed_at is set"`: user with `welcomed_at` set, no `#welcome-banner`.
  - `"hides the banner when show_welcome is false"`: nil `welcomed_at` but `show_welcome: false`, no `#welcome-banner`.
  - `"hides the banner when signed out"`: `current_scope: nil`, no `#welcome-banner`.
  - `"links to getting-started.html on the docs base"`: with `:docs_url` set to `"https://docs.example.com"`, `#welcome-banner-link` has `href="https://docs.example.com/getting-started.html"`; repeat with `"https://docs.example.com/"` and expect the same href.
- [ ] **Step 2: Run to verify failure:** `mix test test/speechwave_web/components/layouts_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `Layouts.app/1`'s signed-in branch, wrap the banner and `<main>` in one `<div class="pt-14">` and remove `pt-14` from `<main>` (keep the padding classes for the non-`full_width` case). Render `<.welcome_banner :if={...} docs_href={docs_url("getting-started.html")} />` above `<main>`, guarded by `@show_welcome and is_nil(@current_scope.user.welcomed_at)`. Style as a full-width bar with `bg-surface border-b border-hairline`, content constrained like the header (`max-w-6xl mx-auto px-6`), text wrapping on small screens, a fade-in, and an `hero-x-mark` icon via `<.icon>` in the close button with an `aria-label`. Add `show_welcome={false}` to the dev login template's `<Layouts.app>`. Define `fade-out` as a short opacity transition via `JS.hide`'s `transition: {"transition-opacity duration-200", "opacity-100", "opacity-0"}`.
- [ ] **Step 4: Run tests:** `mix test test/speechwave_web/components/layouts_test.exs`. Expected: PASS.
- [ ] **Step 5: Look at it.** Start the dev server, log in as a user with `welcomed_at` nil, and check `/users/settings` at desktop and phone width: banner sits under the header, nothing overlaps, text wraps, close button reachable. (Reload note from the project memory: do not run `mix compile` against the running dev server; use `mix test` or touch files.)
- [ ] **Step 6: Commit** `feat: add welcome banner component linking to Getting Started`

---

### Task 3: Dismiss hook in `UserAuth`

**Files:**
- Modify: `lib/speechwave_web/user_auth.ex` (`mount_current_scope/2` and a private event handler)
- Test: `test/speechwave_web/live/welcome_banner_test.exs` (new)

**Interfaces:**
- Consumes: `Accounts.mark_welcomed/1` (Task 1), the `dismiss_welcome` push and `#welcome-banner-dismiss` (Task 2).
- Produces: `mount_current_scope/2` attaches `Phoenix.LiveView.attach_hook(socket, :welcome_banner, :handle_event, &handle_welcome_event/3)` once per socket, and only when the scope has a user.
- Produces: private `handle_welcome_event(event :: String.t(), params :: map(), socket) :: {:halt, socket} | {:cont, socket}`. For `"dismiss_welcome"` it calls `mark_welcomed`, then assigns `:current_scope` as `%Scope{user | welcomed_at: ...}` by updating only `welcomed_at` on the existing `current_scope.user` struct, so the virtual `authenticated_at` survives. Every other event returns `{:cont, socket}`.

- [ ] **Step 1: Write the failing tests** (`use SpeechwaveWeb.ConnCase, async: true`, `import Phoenix.LiveViewTest`):
  - `"dismissing records welcomed_at and removes the banner"`: log in a `user_fixture()`, `live(conn, ~p"/users/settings")`, assert `has_element?(view, "#welcome-banner")`, `render_click(element(view, "#welcome-banner-dismiss"))`, then `refute has_element?(view, "#welcome-banner")` and `Repo.get!(User, user.id).welcomed_at` is a `%DateTime{}`.
  - `"works from the admin live session (double mount)"`: same flow for `admin_user_fixture()` on `~p"/admin/stats"` with no crash.
  - `"dismissing twice keeps the first timestamp"`: dismiss, set the stored timestamp to `~U[2026-01-01 00:00:00Z]` via `Repo.update_all`, trigger the event again with `render_hook(view, "dismiss_welcome", %{})`, assert the stored timestamp is unchanged.
  - `"keeps sudo mode after dismissing"`: after dismissal, `view` still handles a normal event on a page that needs `authenticated_at` (settings), or assert directly that the socket's scope user still has `authenticated_at` by dismissing and then re-rendering settings without a redirect to login.
  - `"signed-out visitors get no banner"`: `live(conn, ~p"/pricing")` has no `#welcome-banner`, and `render_hook(view, "dismiss_welcome", %{})` does not crash or write anything.
  - `"a user with welcomed_at set sees no banner on dashboard"`.
- [ ] **Step 2: Run to verify failure:** `mix test test/speechwave_web/live/welcome_banner_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement** in `mount_current_scope/2`. Decide whether this is the first call by checking `Map.has_key?(socket.assigns, :current_scope)` before `assign_new`, attach the hook only on the first call and only when the resulting scope has a user. `Phoenix.LiveView.attach_hook/4` is allowed in `on_mount`.
- [ ] **Step 4: Run tests:** `mix test test/speechwave_web/live/welcome_banner_test.exs`, then the whole suite with `mix test`, because every existing test that logs in a fresh `user_fixture()` now renders the banner. Expected: PASS. Fix any test that matched text now duplicated by the banner by scoping its selector, not by deleting the banner.
- [ ] **Step 5: Commit** `feat: dismiss the welcome banner without a page reload`

---

### Task 4: Remove the plain "Welcome!" flash

**Files:**
- Modify: `lib/speechwave_web/controllers/user_session_controller.ex` (magic link flash around line 15 to 22, OAuth flash around line 104)
- Modify: `test/speechwave_web/controllers/user_session_controller_test.exs` (the test at line 101)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: magic link login sets the `You're on the list! ...` flash only when `notify` and `updates` are both present, and no flash otherwise. OAuth login sets no success flash.

- [ ] **Step 1: Update the test first.** Change the test named `"shows 'Welcome!' flash when ?notify present but ?updates absent"` to `"sets no flash when ?notify present but ?updates absent"`, asserting `Phoenix.Flash.get(conn.assigns.flash, :info) == nil`. Add `"sets no flash on a plain magic link login"` for a token with no params. Keep the existing `"shows plan-specific flash when ?notify present"` test (it passes `updates=true`).
- [ ] **Step 2: Run to verify failure:** `mix test test/speechwave_web/controllers/user_session_controller_test.exs`. Expected: the changed test FAILS.
- [ ] **Step 3: Implement.** Make the magic link flash conditional (`put_flash` only in the `notify && updates` case) and delete the `put_flash(:info, "Welcome!")` line in the OAuth success path. Check `rg -n '"Welcome!"' lib` returns nothing. The OAuth callback goes through Assent and has no practical controller test here, so that line is verified by the grep.
- [ ] **Step 4: Run tests:** `mix test test/speechwave_web/controllers/user_session_controller_test.exs`. Expected: PASS.
- [ ] **Step 5: Commit** `refactor: drop the plain Welcome! flash now that the banner welcomes new users`

---

### Task 5: Final checks

- [ ] **Step 1:** `mix precommit`. Fix anything it reports. Expected: clean exit.
- [ ] **Step 2:** `mix test`. Expected: all pass.
- [ ] **Step 3: Try it in the browser** with a brand-new account: log in by magic link, see the banner on `/users/settings`, click "Getting Started" (opens the docs page), dismiss, navigate to `/dashboard`, confirm it stays gone, then log in as an existing user and confirm no banner.
- [ ] **Step 4: Commit** any fixes from the checks, then spawn a fresh-eyes reviewer subagent on the branch diff against the spec.
