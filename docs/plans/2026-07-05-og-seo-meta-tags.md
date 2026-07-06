# OG / SEO Meta Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `<meta name="description">` plus Open Graph and Twitter card tags to the four public pages (`/`, `/pricing`, `/terms`, `/privacy`), backed by a single shared 1200×630 social-share image.

**Architecture:** A fixed block of meta tags in `root.html.heex` reads `page_title`/`page_description` assigns (with fallbacks), plus a shared `og:image` built from a new `priv/static/images/og-hero.png` asset. `page_title`/`page_description` are set per-page via controller `render/3` assigns (`/`, `/terms`, `/privacy`) or `LiveView.mount/3` assigns (`/pricing`). The image itself is captured from the already-committed `docs/og_hero.html` mockup using `rodney` + ImageMagick.

**Tech Stack:** Phoenix 1.8 / HEEx, `Phoenix.VerifiedRoutes` (`~p` sigil), `rodney` (Chrome CDP automation CLI), ImageMagick (`magick`).

**Spec:** `docs/specs/2026-07-05-og-seo-meta-tags-design.md`

## Global Constraints

- Scope is exactly four pages: `/`, `/pricing`, `/terms`, `/privacy`. Do not touch authenticated app pages (dashboard, talk, session analytics, settings).
- One shared OG image (`priv/static/images/og-hero.png`) is used across all four pages — no per-page images.
- `og:title`/`twitter:title` reuse the existing `page_title` assign that feeds `<.live_title default="Speechwave">` in `root.html.heex:7-9`; `/` keeps the default ("Speechwave") rather than setting an explicit `page_title`.
- Canonical/`og:url`/`og:image` are absolute URLs built from `SpeechwaveWeb.Endpoint.url()`, confirmed empirically to be `http://localhost:4000` in the test environment (from `config/config.exs`'s `url: [host: "localhost"]`) — this is independent of whatever fake host the test `conn` presents, so tests assert against the literal `http://localhost:4000`.
- `@conn` is confirmed available in `root.html.heex` for both controller-rendered pages and the LiveView-rendered `/pricing` page: `Phoenix.Controller.render/3` puts `conn: conn` into template assigns, and `Phoenix.LiveView.Controller.live_render/2` calls that same `Phoenix.Controller.render/3` for its initial disconnected render.
- **Inside a HEEx `~H` template (including embedded layout templates like `root.html.heex`), `@name` always means `assigns[:name]` — never an Elixir module attribute.** A module attribute like `@default_description` defined in `layouts.ex` will NOT be visible as `@default_description` inside `root.html.heex`; it raises `KeyError` (assign not found) instead. Use a private function (e.g. `default_description/0`) instead, and call it as `default_description()` from the template.
- **Self-closing void elements (`<meta>`, `<link>`) serialize differently depending on render path** (verified empirically, not a guess): on the LiveView-rendered `/pricing` page, they keep a trailing `/>` with no space before it (e.g. `content="x"/>`); on plain controller-rendered pages (`/`, `/terms`, `/privacy`), the slash is dropped entirely (just `content="x">`). Match whichever your test's page actually uses.
- **`<.live_title>`'s rendered `<title>` tag always carries a `data-default="..."` attribute and preserves internal newline/indentation around its text**, e.g. `<title data-default="Speechwave">\n      Pricing · Speechwave\n    </title>`, regardless of render path. Match it with a tolerant regex (`~r/<title[^>]*>\s*TEXT\s*<\/title>/`), not an exact literal.
- HTML-escapes apostrophes as `&#39;` (e.g. `"Speechwave's"` renders as `"Speechwave&#39;s"`) — any copy with an apostrophe needs the escaped form in test assertions.
- Conventional commit format for all commits.
- Run `mix precommit` after the final task and fix any issues it reports before considering the work done.

---

### Task 1: Generate and commit the OG share image

**Files:**
- Create: `priv/static/images/og-hero.png`
- Read (no changes): `docs/og_hero.html` (already committed in `550ac05`)

**Interfaces:**
- Produces: `priv/static/images/og-hero.png`, a 1200×630 PNG. Task 2's `root.html.heex` references it by path `~p"/images/og-hero.png"`.

- [ ] **Step 1: Start rodney and load the mockup**

```bash
rodney start
rodney open "file:///Users/tracy/projects/speechwave-live/speechwave/docs/og_hero.html"
rodney waitload
```

Expected: last command prints `Page loaded`.

- [ ] **Step 2: Screenshot the `#hero` element**

```bash
rodney screenshot-el "#hero" /tmp/og-hero-raw.png
magick identify /tmp/og-hero-raw.png
```

Expected: `identify` prints `/tmp/og-hero-raw.png PNG 1200x630 ...` — exactly 1200×630, since `.hero` in `docs/og_hero.html` is a fixed-size element and `screenshot-el` captures its exact bounding box (no cropping needed).

- [ ] **Step 3: Stop rodney**

```bash
rodney stop
```

Expected: prints `Chrome stopped`.

- [ ] **Step 4: Optimize and write the final asset**

```bash
magick /tmp/og-hero-raw.png -strip -define png:compression-level=9 priv/static/images/og-hero.png
magick identify priv/static/images/og-hero.png
```

Expected: `identify` prints `priv/static/images/og-hero.png PNG 1200x630 ...`.

- [ ] **Step 5: Commit**

```bash
git add priv/static/images/og-hero.png
git commit -m "feat: add OG share image asset"
```

---

### Task 2: Root layout meta tags (completes `/`)

**Files:**
- Modify: `lib/speechwave_web/components/layouts/root.html.heex`
- Modify: `lib/speechwave_web/components/layouts.ex` (add a `default_description/0` private function after `embed_templates "layouts/*"`)
- Test: `test/speechwave_web/controllers/page_controller_test.exs`

**Interfaces:**
- Consumes: `priv/static/images/og-hero.png` from Task 1 (referenced via `~p"/images/og-hero.png"`).
- Produces: the `page_title` / `page_description` assign contract that Task 3 (LiveView mount) and Task 4 (controller `render/3`) rely on — any HEEx template rendered through this root layout may set `page_title` (a full string like `"Pricing · Speechwave"`) and `page_description` (a plain sentence, no site-name suffix) as assigns; both are optional and fall back to `"Speechwave"` / `default_description()` respectively.

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave_web/controllers/page_controller_test.exs`, inside the existing `SpeechwaveWeb.PageControllerTest` module (after the existing `"GET / returns 200"` test):

```elixir
  test "GET / includes SEO and Open Graph meta tags", %{conn: conn} do
    html = get(conn, ~p"/") |> html_response(200)

    assert html =~
             ~s(<meta name="description" content="Speechwave lets your audience react with emoji in real time during your talk, then gives you per-slide analytics to see what landed.">)

    assert html =~ ~s(<link rel="canonical" href="http://localhost:4000/">)
    assert html =~ ~s(<meta property="og:site_name" content="Speechwave">)
    assert html =~ ~s(<meta property="og:type" content="website">)
    assert html =~ ~s(<meta property="og:title" content="Speechwave">)
    assert html =~ ~s(<meta property="og:url" content="http://localhost:4000/">)
    assert html =~ ~s(<meta property="og:image" content="http://localhost:4000/images/og-hero.png">)
    assert html =~ ~s(<meta property="og:image:width" content="1200">)
    assert html =~ ~s(<meta property="og:image:height" content="630">)
    assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)
    assert html =~ ~s(<meta name="twitter:image" content="http://localhost:4000/images/og-hero.png">)
  end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs
```

Expected: the new test FAILs (the meta tags don't exist yet); the three pre-existing tests in the file still PASS.

- [ ] **Step 3: Add the default description helper**

In `lib/speechwave_web/components/layouts.ex`, add this private function directly after the `embed_templates "layouts/*"` line (currently line 12) — **not** a module attribute, since `@name` inside the `~H` templates that `embed_templates` compiles always means `assigns[:name]`:

```elixir
  embed_templates "layouts/*"

  defp default_description do
    "Speechwave lets your audience react with emoji in real time during your talk, then gives you per-slide analytics to see what landed."
  end
```

- [ ] **Step 4: Add the meta tag block to the root layout**

In `lib/speechwave_web/components/layouts/root.html.heex`, replace:

```heex
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title default="Speechwave">
      {assigns[:page_title]}
    </.live_title>
```

with:

```heex
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title default="Speechwave">
      {assigns[:page_title]}
    </.live_title>
    <meta name="description" content={assigns[:page_description] || default_description()} />
    <link rel="canonical" href={SpeechwaveWeb.Endpoint.url() <> @conn.request_path} />
    <meta property="og:site_name" content="Speechwave" />
    <meta property="og:type" content="website" />
    <meta property="og:title" content={assigns[:page_title] || "Speechwave"} />
    <meta
      property="og:description"
      content={assigns[:page_description] || default_description()}
    />
    <meta property="og:url" content={SpeechwaveWeb.Endpoint.url() <> @conn.request_path} />
    <meta property="og:image" content={SpeechwaveWeb.Endpoint.url() <> ~p"/images/og-hero.png"} />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={assigns[:page_title] || "Speechwave"} />
    <meta
      name="twitter:description"
      content={assigns[:page_description] || default_description()}
    />
    <meta
      name="twitter:image"
      content={SpeechwaveWeb.Endpoint.url() <> ~p"/images/og-hero.png"}
    />
```

- [ ] **Step 5: Format the file**

```bash
mix format lib/speechwave_web/components/layouts/root.html.heex
```

Expected: exits 0. `mix format` may reflow the two `og:description`/`twitter:description` tags (they're the longest lines) — that's fine, the code above is a starting point, not a byte-exact requirement. What matters is the *rendered* output, checked by the test.

- [ ] **Step 6: Run the test to verify it passes**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs
```

Expected: all tests in the file PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/speechwave_web/components/layouts.ex lib/speechwave_web/components/layouts/root.html.heex test/speechwave_web/controllers/page_controller_test.exs
git commit -m "feat: add SEO and Open Graph meta tags to root layout"
```

---

### Task 3: Pricing page title and description

**Files:**
- Modify: `lib/speechwave_web/live/pricing_live.ex:223-231` (the `mount/3` function)
- Test: `test/speechwave_web/live/pricing_live_test.exs`

**Interfaces:**
- Consumes: the `page_title` / `page_description` assign contract from Task 2.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave_web/live/pricing_live_test.exs`, inside the existing `"pricing page"` describe block. Note this page renders through LiveView, so self-closing tags keep their `/>` (no space before it) and the `<title>` needs the tolerant regex — see Global Constraints:

```elixir
    test "sets page title and SEO/OG meta tags", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pricing")

      assert html =~ ~r/<title[^>]*>\s*Pricing · Speechwave\s*<\/title>/

      assert html =~
               ~s(<meta name="description" content="Compare Speechwave&#39;s free and paid plans. Start free, no credit card required, and upgrade when you need more participants or sessions."/>)

      assert html =~ ~s(<meta property="og:title" content="Pricing · Speechwave"/>)
      assert html =~ ~s(<meta property="og:url" content="http://localhost:4000/pricing"/>)
    end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/speechwave_web/live/pricing_live_test.exs
```

Expected: the new test FAILs (title/description still default); pre-existing tests in the file still PASS.

- [ ] **Step 3: Set the assigns in `mount/3`**

In `lib/speechwave_web/live/pricing_live.ex`, replace:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       free_participant_limit: Plans.limit(:max_participants, :free),
       free_session_limit: Plans.limit(:full_sessions_per_month, :free),
       show_modal: nil,
       notify_sent: false,
       notify_email: ""
     )}
  end
```

with:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Pricing · Speechwave",
       page_description:
         "Compare Speechwave's free and paid plans. Start free, no credit card required, and upgrade when you need more participants or sessions.",
       free_participant_limit: Plans.limit(:max_participants, :free),
       free_session_limit: Plans.limit(:full_sessions_per_month, :free),
       show_modal: nil,
       notify_sent: false,
       notify_email: ""
     )}
  end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
mix test test/speechwave_web/live/pricing_live_test.exs
```

Expected: all tests in the file PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/speechwave_web/live/pricing_live.ex test/speechwave_web/live/pricing_live_test.exs
git commit -m "feat: add SEO and Open Graph meta tags to pricing page"
```

---

### Task 4: Terms and Privacy page titles and descriptions

**Files:**
- Modify: `lib/speechwave_web/controllers/page_controller.ex`
- Test: `test/speechwave_web/controllers/page_controller_test.exs`

**Interfaces:**
- Consumes: the `page_title` / `page_description` assign contract from Task 2.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing tests**

Add to `test/speechwave_web/controllers/page_controller_test.exs`, replacing the existing `"GET /terms returns 200"` and `"GET /privacy returns 200"` tests. Note these pages render through a plain controller, so self-closing tags drop the slash entirely (just `>`) — see Global Constraints:

```elixir
  test "GET /terms returns 200 with SEO meta tags", %{conn: conn} do
    html = get(conn, ~p"/terms") |> html_response(200)

    assert html =~ "Terms"
    assert html =~ ~r/<title[^>]*>\s*Terms of Service · Speechwave\s*<\/title>/
    assert html =~ ~s(<meta name="description" content="Speechwave&#39;s terms of service.">)
    assert html =~ ~s(<meta property="og:title" content="Terms of Service · Speechwave">)
  end

  test "GET /privacy returns 200 with SEO meta tags", %{conn: conn} do
    html = get(conn, ~p"/privacy") |> html_response(200)

    assert html =~ "Privacy"
    assert html =~ ~r/<title[^>]*>\s*Privacy Policy · Speechwave\s*<\/title>/

    assert html =~
             ~s(<meta name="description" content="How Speechwave collects, uses, and protects your data.">)

    assert html =~ ~s(<meta property="og:title" content="Privacy Policy · Speechwave">)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs
```

Expected: the two rewritten tests FAIL (title/description still default); the other tests in the file still PASS.

- [ ] **Step 3: Set the assigns in the controller actions**

In `lib/speechwave_web/controllers/page_controller.ex`, replace:

```elixir
  def terms(conn, _params), do: render(conn, :terms, free_limits())
  def privacy(conn, _params), do: render(conn, :privacy)
```

with:

```elixir
  def terms(conn, _params) do
    render(
      conn,
      :terms,
      Keyword.merge(free_limits(),
        page_title: "Terms of Service · Speechwave",
        page_description: "Speechwave's terms of service."
      )
    )
  end

  def privacy(conn, _params) do
    render(conn, :privacy,
      page_title: "Privacy Policy · Speechwave",
      page_description: "How Speechwave collects, uses, and protects your data."
    )
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
mix test test/speechwave_web/controllers/page_controller_test.exs
```

Expected: all tests in the file PASS.

- [ ] **Step 5: Run the full precommit suite**

```bash
mix precommit
```

Expected: exits 0 (compiles with no warnings, no unused deps, formatted, all tests pass, lint and static checks clean). This is the final task in this plan, so this is also the whole-project check over Tasks 1-4. Fix anything it reports before continuing.

- [ ] **Step 6: Commit**

```bash
git add lib/speechwave_web/controllers/page_controller.ex test/speechwave_web/controllers/page_controller_test.exs
git commit -m "feat: add SEO and Open Graph meta tags to terms and privacy pages"
```
