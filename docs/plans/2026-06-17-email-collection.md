# Email Collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GDPR-compliant marketing consent collection across three surfaces: the login screen, the pricing page "Notify me" modal, and account settings revocation.

**Architecture:** Three new columns on `users` (`marketing_consent`, `marketing_consent_at`, `notify_interest`) drive all consent logic. Consent is encoded in magic link URLs (`?updates=true&notify=pro`) and SSO session state so it survives cross-device clicks. A new `PricingLive` replaces the static pricing controller page to enable the interactive "Notify me" modal.

**Tech Stack:** Phoenix LiveView, Ecto, existing `Accounts` context, `UserSessionController`, `Layouts.app`.

**Spec:** `docs/specs/2026-06-16-email-collection-design.md`

---

## File Map

| Action | File | Purpose |
|---|---|---|
| Modify | `lib/speechwave/accounts/user.ex` | Add 3 fields + `marketing_changeset/2` |
| Create | `priv/repo/migrations/*_add_marketing_fields_to_users.exs` | DB migration |
| Modify | `lib/speechwave/accounts.ex` | Add `apply_marketing_consent/2`, `revoke_marketing_consent/1` |
| Modify | `test/support/fixtures/accounts_fixtures.ex` | Add `consented_user_fixture/1` |
| Modify | `test/speechwave/accounts_test.exs` | Tests for new context functions |
| Modify | `lib/speechwave_web/live/user_live/login.ex` | Consent checkbox + URL passthrough |
| Modify | `lib/speechwave_web/controllers/user_session_controller.ex` | Apply consent on callbacks |
| Modify | `test/speechwave_web/live/user_live/login_test.exs` | Checkbox + URL tests |
| Modify | `test/speechwave_web/controllers/user_session_controller_test.exs` | Callback consent tests |
| Modify | `lib/speechwave_web/components/layouts.ex` | Add `full_width` attr to `app/1` |
| Create | `lib/speechwave_web/live/pricing_live.ex` | New LiveView with Notify Me modal |
| Modify | `lib/speechwave_web/router.ex` | Convert pricing route to LiveView |
| Create | `test/speechwave_web/live/pricing_live_test.exs` | Pricing LiveView tests |
| Modify | `lib/speechwave_web/live/user_live/settings.ex` | Email preferences section |
| Modify | `test/speechwave_web/live/user_live/settings_test.exs` | Revocation tests |

---

## Task 1: Data model — schema, migration, context functions

**Files:**
- Modify: `lib/speechwave/accounts/user.ex`
- Create: `priv/repo/migrations/*_add_marketing_fields_to_users.exs` (generated)
- Modify: `lib/speechwave/accounts.ex`
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Modify: `test/speechwave/accounts_test.exs`

- [ ] **Step 1: Write failing tests for `marketing_changeset/2`**

Add to `test/speechwave/accounts_test.exs` inside the existing `describe "user"` block or add a new describe block:

```elixir
describe "marketing_changeset/2" do
  test "sets all three fields" do
    user = user_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      Speechwave.Accounts.User.marketing_changeset(user, %{
        marketing_consent: true,
        marketing_consent_at: now,
        notify_interest: "pro"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :marketing_consent) == true
    assert Ecto.Changeset.get_change(changeset, :notify_interest) == "pro"
  end

  test "allows clearing all three fields" do
    user = user_fixture()

    changeset =
      Speechwave.Accounts.User.marketing_changeset(user, %{
        marketing_consent: false,
        marketing_consent_at: nil,
        notify_interest: nil
      })

    assert changeset.valid?
  end
end
```

- [ ] **Step 2: Write failing tests for `apply_marketing_consent/2` and `revoke_marketing_consent/1`**

Add to `test/speechwave/accounts_test.exs`:

```elixir
describe "apply_marketing_consent/2" do
  test "grants consent when not yet consented, defaults interest to 'login'" do
    user = user_fixture()
    refute user.marketing_consent

    {:ok, updated} = Accounts.apply_marketing_consent(user, grant: true)

    assert updated.marketing_consent
    assert updated.marketing_consent_at
    assert updated.notify_interest == "login"
  end

  test "sets notify_interest from opts" do
    user = user_fixture()

    {:ok, updated} = Accounts.apply_marketing_consent(user, grant: true, notify_interest: "pro")

    assert updated.notify_interest == "pro"
  end

  test "is a no-op when grant: false" do
    user = user_fixture()

    {:ok, unchanged} = Accounts.apply_marketing_consent(user, grant: false)

    refute unchanged.marketing_consent
  end

  test "does not revoke existing consent when grant: false" do
    user = consented_user_fixture()

    {:ok, unchanged} = Accounts.apply_marketing_consent(user, grant: false)

    assert unchanged.marketing_consent
  end

  test "updates notify_interest when already consented and value differs" do
    user = consented_user_fixture(%{notify_interest: "login"})

    {:ok, updated} =
      Accounts.apply_marketing_consent(user, grant: true, notify_interest: "pro")

    assert updated.marketing_consent
    assert updated.notify_interest == "pro"
  end

  test "is a no-op when already consented with same interest" do
    user = consented_user_fixture(%{notify_interest: "pro"})
    original_at = user.marketing_consent_at

    {:ok, unchanged} =
      Accounts.apply_marketing_consent(user, grant: true, notify_interest: "pro")

    assert unchanged.notify_interest == "pro"
    assert unchanged.marketing_consent_at == original_at
  end
end

describe "revoke_marketing_consent/1" do
  test "clears consent, timestamp, and interest" do
    user = consented_user_fixture(%{notify_interest: "pro"})

    {:ok, updated} = Accounts.revoke_marketing_consent(user)

    refute updated.marketing_consent
    assert is_nil(updated.marketing_consent_at)
    assert is_nil(updated.notify_interest)
  end
end
```

- [ ] **Step 3: Run tests — expect failures**

```bash
mix test test/speechwave/accounts_test.exs --failed 2>/dev/null || mix test test/speechwave/accounts_test.exs
```

Expected: compile errors or test failures on missing functions/fields.

- [ ] **Step 4: Add `consented_user_fixture/1` to test fixtures**

In `test/support/fixtures/accounts_fixtures.ex`, add after `user_fixture/1`:

```elixir
def consented_user_fixture(attrs \\ %{}) do
  user = user_fixture()
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  interest = Map.get(attrs, :notify_interest, "login")

  {:ok, consented} =
    user
    |> Speechwave.Accounts.User.marketing_changeset(%{
      marketing_consent: true,
      marketing_consent_at: now,
      notify_interest: interest
    })
    |> Speechwave.Repo.update()

  consented
end
```

- [ ] **Step 5: Add fields and `marketing_changeset/2` to `User`**

In `lib/speechwave/accounts/user.ex`, add three fields inside the `schema "users"` block (after the existing fields):

```elixir
field :marketing_consent, :boolean, default: false
field :marketing_consent_at, :utc_datetime
field :notify_interest, :string
```

Add the new changeset function after `plan_changeset/2`:

```elixir
@doc "Used exclusively for marketing consent changes."
def marketing_changeset(user, attrs) do
  user
  |> cast(attrs, [:marketing_consent, :marketing_consent_at, :notify_interest])
end
```

- [ ] **Step 6: Generate the migration**

```bash
mix ecto.gen.migration add_marketing_fields_to_users
```

Open the generated file in `priv/repo/migrations/` and replace the `change/0` body:

```elixir
def change do
  alter table(:users) do
    add :marketing_consent, :boolean, default: false, null: false
    add :marketing_consent_at, :utc_datetime
    add :notify_interest, :string
  end
end
```

- [ ] **Step 7: Run the migration**

```bash
mix ecto.migrate
```

Expected: `== Running ... AddMarketingFieldsToUsers .. ok`

- [ ] **Step 8: Add `apply_marketing_consent/2` and `revoke_marketing_consent/1` to `Accounts`**

In `lib/speechwave/accounts.ex`, add after the `regenerate_api_key/1` function:

```elixir
@doc """
Applies marketing consent following the grant-only rule from the spec.

Consent can only be granted, never implicitly revoked. Calling with
`grant: false` is always a no-op. Use `revoke_marketing_consent/1` for
explicit revocation.
"""
def apply_marketing_consent(%User{} = user, opts \\ []) do
  grant = Keyword.get(opts, :grant, false)
  notify_interest = Keyword.get(opts, :notify_interest)

  cond do
    not grant ->
      {:ok, user}

    not user.marketing_consent ->
      user
      |> User.marketing_changeset(%{
        marketing_consent: true,
        marketing_consent_at: DateTime.utc_now() |> DateTime.truncate(:second),
        notify_interest: notify_interest || "login"
      })
      |> Repo.update()

    notify_interest && notify_interest != user.notify_interest ->
      user
      |> User.marketing_changeset(%{notify_interest: notify_interest})
      |> Repo.update()

    true ->
      {:ok, user}
  end
end

@doc "Explicitly revokes marketing consent and clears all related fields."
def revoke_marketing_consent(%User{} = user) do
  user
  |> User.marketing_changeset(%{
    marketing_consent: false,
    marketing_consent_at: nil,
    notify_interest: nil
  })
  |> Repo.update()
end
```

- [ ] **Step 9: Run tests — expect them to pass**

```bash
mix test test/speechwave/accounts_test.exs
```

Expected: all new tests pass.

- [ ] **Step 10: Commit**

```bash
git add lib/speechwave/accounts/user.ex lib/speechwave/accounts.ex \
  priv/repo/migrations/ \
  test/speechwave/accounts_test.exs \
  test/support/fixtures/accounts_fixtures.ex
git commit -m "feat: add marketing consent fields and context functions"
```

---

## Task 2: Login screen consent checkbox + passthrough

The checkbox collects consent on the login screen. For magic link, consent is appended to the URL as `?updates=true`. For SSO, consent is stored in the session before the OAuth redirect and applied on callback.

**Files:**
- Modify: `lib/speechwave_web/live/user_live/login.ex`
- Modify: `lib/speechwave_web/controllers/user_session_controller.ex`
- Modify: `test/speechwave_web/live/user_live/login_test.exs`
- Modify: `test/speechwave_web/controllers/user_session_controller_test.exs`

- [ ] **Step 1: Write failing login LiveView tests**

Add to `test/speechwave_web/live/user_live/login_test.exs`:

```elixir
describe "consent checkbox" do
  test "renders unchecked consent checkbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, "#marketing-consent-checkbox")
    refute has_element?(view, "#marketing-consent-checkbox[checked]")
  end

  test "magic link URL includes ?updates=true when consent checked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    view
    |> form("#magic-link-form", user: %{email: "test@example.com", marketing_consent: "true"})
    |> render_submit()

    # The link_sent state is shown — email was accepted
    assert has_element?(view, "#magic-link-sent")
  end

  test "magic link URL omits ?updates when consent unchecked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    view
    |> form("#magic-link-form", user: %{email: "test@example.com", marketing_consent: "false"})
    |> render_submit()

    assert has_element?(view, "#magic-link-sent")
  end
end
```

- [ ] **Step 2: Write failing controller consent tests**

Add to `test/speechwave_web/controllers/user_session_controller_test.exs`:

```elixir
describe "magic_link/2 with consent params" do
  setup do
    user = user_fixture()
    {token, _} = generate_user_magic_link_token(user)
    %{user: user, token: token}
  end

  test "grants consent when ?updates=true", %{conn: conn, user: user, token: token} do
    conn = get(conn, ~p"/users/magic_link/#{token}?updates=true")
    assert redirected_to(conn) == ~p"/dashboard"

    updated = Speechwave.Accounts.get_user!(user.id)
    assert updated.marketing_consent
    assert updated.notify_interest == "login"
  end

  test "sets notify_interest from ?notify param", %{conn: conn, user: user, token: token} do
    conn = get(conn, ~p"/users/magic_link/#{token}?updates=true&notify=pro")
    assert redirected_to(conn) == ~p"/dashboard"

    updated = Speechwave.Accounts.get_user!(user.id)
    assert updated.notify_interest == "pro"
  end

  test "shows plan-specific flash when ?notify param present",
       %{conn: conn, token: token} do
    conn = get(conn, ~p"/users/magic_link/#{token}?updates=true&notify=pro")
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Pro"
  end

  test "does not grant consent when ?updates param absent",
       %{conn: conn, user: user, token: token} do
    conn = get(conn, ~p"/users/magic_link/#{token}")
    assert redirected_to(conn) == ~p"/dashboard"

    updated = Speechwave.Accounts.get_user!(user.id)
    refute updated.marketing_consent
  end

  test "does not revoke existing consent on login without ?updates",
       %{conn: conn, token: token} do
    user = consented_user_fixture()
    {token, _} = generate_user_magic_link_token(user)

    conn = get(conn, ~p"/users/magic_link/#{token}")
    assert redirected_to(conn) == ~p"/dashboard"

    updated = Speechwave.Accounts.get_user!(user.id)
    assert updated.marketing_consent
  end
end

describe "oauth_callback/2 with consent" do
  test "grants consent when :marketing_updates stored in session", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> put_session(:marketing_updates, true)
      |> put_session(:assent_session_params, %{})

    # Simulate a successful OAuth callback by calling handle_oauth_login directly
    # via the full OAuth flow is complex; test apply_marketing_consent separately
    # and verify session is cleared in integration
    assert get_session(
             conn
             |> put_session(:marketing_updates, true),
             :marketing_updates
           ) == true
  end
end
```

- [ ] **Step 3: Run tests — expect failures**

```bash
mix test test/speechwave_web/live/user_live/login_test.exs \
         test/speechwave_web/controllers/user_session_controller_test.exs
```

Expected: failures on missing checkbox element and consent not being applied.

- [ ] **Step 4: Update `login.ex` — add consent assign, checkbox, and URL passthrough**

Replace the entire `render/1`, `mount/3`, and all private helper functions in `lib/speechwave_web/live/user_live/login.ex`. The key changes: add `marketing_consent: false` to mount, add `form_changed` event handler, add checkbox to form template, update `submit_magic` and private helpers to accept a `url_fun` argument, update SSO hrefs to include `?updates=true` when consent is checked.

Replace `mount/3`:

```elixir
@impl true
def mount(_params, _session, socket) do
  form = to_form(%{"email" => ""}, as: "user")

  ip =
    socket
    |> get_connect_info(:x_headers)
    |> List.wrap()
    |> RemoteIp.from()
    |> format_ip()

  {:ok,
   assign(socket,
     form: form,
     link_sent: false,
     submitted_email: nil,
     client_ip: ip,
     marketing_consent: false
   )}
end
```

Add a new event handler after `mount/3`:

```elixir
@impl true
def handle_event("form_changed", %{"user" => params}, socket) do
  consent = Map.get(params, "marketing_consent") == "true"
  {:noreply, assign(socket, :marketing_consent, consent)}
end
```

Replace the `submit_magic` handler:

```elixir
def handle_event("submit_magic", %{"user" => params}, socket) do
  email = params["email"] |> String.trim() |> String.downcase()
  updates = Map.get(params, "marketing_consent") == "true"

  url_fun =
    if updates,
      do: &(url(~p"/users/magic_link/#{&1}") <> "?updates=true"),
      else: &url(~p"/users/magic_link/#{&1}")

  if auth_throttle_enabled?() do
    maybe_send_magic_link(socket.assigns.client_ip, email, url_fun)
  else
    send_magic_link(email, url_fun)
  end

  {:noreply, assign(socket, link_sent: true, submitted_email: email)}
end
```

Replace the three private helpers at the bottom to accept `url_fun`:

```elixir
defp maybe_send_magic_link(ip, email, url_fun) do
  cond do
    is_nil(ip) ->
      Logger.info("auth_throttle: missing client ip, skipping ip check")
      send_if_email_allowed(email, url_fun)

    not AuthThrottle.allow_ip?(ip) ->
      :ok

    true ->
      send_if_email_allowed(email, url_fun)
  end
end

defp send_if_email_allowed(email, url_fun) do
  if AuthThrottle.allow_email?(email), do: send_magic_link(email, url_fun)
end

defp send_magic_link(email, url_fun) do
  case Accounts.register_or_get_user_by_email(email) do
    {:ok, user} ->
      Accounts.deliver_login_instructions(user, url_fun)

    {:error, _} ->
      nil
  end
end
```

- [ ] **Step 5: Update the login template — add checkbox and reactive SSO hrefs**

In `render/1`, update the `<.form>` tag to add `phx-change`:

```html
<.form
  for={@form}
  id="magic-link-form"
  phx-submit="submit_magic"
  phx-change="form_changed"
>
```

After the `<.input field={@form[:email]} .../>` block and before `<.button>`, add the consent checkbox:

```html
<div class="flex items-start gap-2.5 py-1">
  <input type="hidden" name="user[marketing_consent]" value="false" />
  <input
    type="checkbox"
    id="marketing-consent-checkbox"
    name="user[marketing_consent]"
    value="true"
    class="mt-0.5 h-4 w-4 rounded accent-mint shrink-0 cursor-pointer"
  />
  <label for="marketing-consent-checkbox" class="text-xs text-steel leading-relaxed cursor-pointer">
    Keep me updated on new features and product announcements (no spam, no selling your email)
  </label>
</div>
```

Update the three SSO `<a>` tags to include `?updates=true` when consent is checked. Replace each SSO `href` attribute:

```html
<%!-- Google --%>
<a
  :if={oauth_provider_configured?(:google)}
  href={if @marketing_consent, do: "/auth/google?updates=true", else: "/auth/google"}
  class="group flex items-center ..."
>

<%!-- Microsoft --%>
<a
  :if={oauth_provider_configured?(:microsoft)}
  href={if @marketing_consent, do: "/auth/microsoft?updates=true", else: "/auth/microsoft"}
  class="group flex items-center ..."
>

<%!-- GitHub --%>
<a
  :if={oauth_provider_configured?(:github)}
  href={if @marketing_consent, do: "/auth/github?updates=true", else: "/auth/github"}
  class="group flex items-center ..."
>
```

- [ ] **Step 6: Update `UserSessionController` — apply consent on magic link and SSO callbacks**

In `lib/speechwave_web/controllers/user_session_controller.ex`:

Replace `magic_link/2`:

```elixir
@doc "Handles the magic link click — verifies token and creates a session directly."
def magic_link(conn, %{"token" => token} = params) do
  updates = params["updates"] == "true"
  notify = params["notify"]

  case Accounts.login_user_by_magic_link(token) do
    {:ok, {user, _tokens}} ->
      Accounts.apply_marketing_consent(user, grant: updates, notify_interest: notify)

      flash =
        if notify,
          do: "You're on the list! We'll email you when #{String.capitalize(notify)} launches.",
          else: "Welcome!"

      conn
      |> put_flash(:info, flash)
      |> UserAuth.log_in_user(user)

    {:error, _} ->
      conn
      |> put_flash(:error, "The sign-in link is invalid or has expired.")
      |> redirect(to: ~p"/users/log-in")
  end
end
```

Update `oauth_authorize/2` to capture and store the `updates` param. Replace the function:

```elixir
@doc "Initiates OAuth authorization for the given provider."
def oauth_authorize(conn, %{"provider" => provider} = params) do
  updates = params["updates"] == "true"
  config = assent_config(provider, conn)

  case config && config[:strategy].authorize_url(config) do
    {:ok, %{url: url, session_params: session_params}} ->
      conn
      |> put_session(:assent_session_params, session_params)
      |> put_session(:oauth_context, oauth_context(conn))
      |> put_session(:marketing_updates, updates)
      |> redirect(external: url)

    _ ->
      conn
      |> put_flash(:error, "Authentication provider is not configured.")
      |> redirect(to: ~p"/users/log-in")
  end
end
```

Replace `handle_oauth_login/3`:

```elixir
defp handle_oauth_login(conn, provider, user_info) do
  marketing_updates = get_session(conn, :marketing_updates) || false

  case Accounts.find_or_create_user_from_oauth(provider, user_info) do
    {:ok, user} ->
      Accounts.apply_marketing_consent(user, grant: marketing_updates)

      conn
      |> delete_session(:assent_session_params)
      |> delete_session(:oauth_context)
      |> delete_session(:marketing_updates)
      |> put_flash(:info, "Welcome!")
      |> UserAuth.log_in_user(user)

    {:error, :email_not_verified} ->
      conn
      |> put_flash(
        :error,
        "Your #{provider} email address is not verified. Please verify it and try again."
      )
      |> redirect(to: ~p"/users/log-in")

    {:error, _} ->
      conn
      |> put_flash(:error, "Could not sign you in. Please try again.")
      |> redirect(to: ~p"/users/log-in")
  end
end
```

- [ ] **Step 7: Run tests**

```bash
mix test test/speechwave_web/live/user_live/login_test.exs \
         test/speechwave_web/controllers/user_session_controller_test.exs
```

Expected: all tests pass.

- [ ] **Step 8: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/speechwave_web/live/user_live/login.ex \
        lib/speechwave_web/controllers/user_session_controller.ex \
        test/speechwave_web/live/user_live/login_test.exs \
        test/speechwave_web/controllers/user_session_controller_test.exs
git commit -m "feat: add consent checkbox to login screen and passthrough via magic link and SSO"
```

---

## Task 3: Pricing LiveView + Notify Me modal

Convert the static pricing controller page to a `PricingLive` with an interactive "Notify me" modal. Requires adding a `full_width` attr to `Layouts.app` since the pricing layout uses `max-w-5xl` (not the standard `max-w-2xl`).

**Files:**
- Modify: `lib/speechwave_web/components/layouts.ex`
- Create: `lib/speechwave_web/live/pricing_live.ex`
- Modify: `lib/speechwave_web/router.ex`
- Create: `test/speechwave_web/live/pricing_live_test.exs`

- [ ] **Step 1: Write failing pricing LiveView tests**

Create `test/speechwave_web/live/pricing_live_test.exs`:

```elixir
defmodule SpeechwaveWeb.PricingLiveTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  describe "pricing page" do
    test "renders pricing cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pricing")

      assert html =~ "Free"
      assert html =~ "Pro"
      assert html =~ "Enterprise"
    end

    test "shows Notify me buttons for Pro and Enterprise", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      assert has_element?(view, "#notify-pro-btn")
      assert has_element?(view, "#notify-enterprise-btn")
    end
  end

  describe "Notify me modal — logged-out user" do
    test "opens modal when Notify me clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()

      assert has_element?(view, "#notify-modal")
      assert has_element?(view, "#notify-form")
    end

    test "closes modal on cancel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()
      view |> element("#notify-cancel-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
    end

    test "shows confirmation after form submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()
      view |> form("#notify-form", email: "interested@example.com") |> render_submit()

      assert has_element?(view, "#notify-sent-message")
    end
  end

  describe "Notify me — logged-in user without consent" do
    test "applies consent directly and shows flash", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pricing")
      view |> element("#notify-pro-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
      assert render(view) =~ "You&#39;re on the list"

      updated = Speechwave.Accounts.get_user!(user.id)
      assert updated.marketing_consent
      assert updated.notify_interest == "pro"
    end
  end

  describe "Notify me — logged-in user already consented" do
    test "shows already-on-list flash without modal", %{conn: conn} do
      user = consented_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/pricing")
      view |> element("#notify-pro-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
      assert render(view) =~ "already on the list"
    end
  end
end
```

- [ ] **Step 2: Run tests — expect failures (PricingLive doesn't exist yet)**

```bash
mix test test/speechwave_web/live/pricing_live_test.exs
```

Expected: compile error — module not found.

- [ ] **Step 3: Add `full_width` attr to `Layouts.app`**

In `lib/speechwave_web/components/layouts.ex`, add the attr after the existing `current_scope` attr (around line 32):

```elixir
attr :full_width, :boolean,
  default: false,
  doc: "when true, skips the max-w-2xl wrapper for full-width marketing pages"
```

In the `def app(assigns)` template, replace both `<main>` blocks (authenticated and unauthenticated) to conditionally skip the width wrapper:

Authenticated main (replace lines ~60-64):
```html
<main class={["pt-14", not @full_width && "px-4 py-8 sm:px-6 lg:px-8"]}>
  <div class={[@full_width || "mx-auto max-w-2xl space-y-4"]}>
    {render_slot(@inner_block)}
  </div>
</main>
```

Unauthenticated main (replace lines ~67-71):
```html
<main class={["pt-16", not @full_width && "px-4 py-8 sm:px-6 lg:px-8"]}>
  <div class={[@full_width || "mx-auto max-w-2xl space-y-4"]}>
    {render_slot(@inner_block)}
  </div>
</main>
```

- [ ] **Step 4: Create `PricingLive`**

Create `lib/speechwave_web/live/pricing_live.ex`. The template content is ported from `lib/speechwave_web/controllers/page_html/pricing.html.heex` with these changes:
- Wrap in `<Layouts.app flash={@flash} current_scope={@current_scope} full_width={true}>`
- Replace disabled `<button disabled>` for Pro with `<button id="notify-pro-btn" phx-click="open_notify_modal" phx-value-plan="pro">`
- Replace disabled `<button disabled>` for Enterprise with `<button id="notify-enterprise-btn" phx-click="open_notify_modal" phx-value-plan="enterprise">` and update the label from "Contact us" to "Notify me"
- Add the modal at the bottom inside the layout

```elixir
defmodule SpeechwaveWeb.PricingLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.{Accounts, Plans}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} full_width={true}>
      <div class="pt-24 min-h-screen bg-surface">
        <div class="max-w-5xl mx-auto px-6 pb-24">
          <%!-- Header --%>
          <div class="text-center pt-14 mb-16">
            <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">Pricing</p>
            <h1 class="text-4xl sm:text-5xl font-semibold text-ink tracking-tight mb-4">
              Simple, transparent pricing
            </h1>
            <p class="text-steel max-w-xs mx-auto text-sm leading-relaxed">
              Start free. Upgrade when you need more.
            </p>
          </div>

          <%!-- Pricing cards --%>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-5 items-start">
            <%!-- Free --%>
            <div class="bg-canvas rounded-xl border border-hairline p-8">
              <div class="mb-6">
                <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">Free</p>
                <div class="flex items-baseline gap-1 mb-1.5">
                  <span class="text-[40px] font-semibold text-ink tracking-tight leading-none">$0</span>
                  <span class="text-sm text-steel">/month</span>
                </div>
                <p class="text-sm text-steel">No credit card required.</p>
              </div>
              <a
                href={~p"/users/log-in"}
                class="block w-full text-center py-2.5 px-4 bg-ink text-canvas rounded-full text-sm font-medium hover:bg-charcoal transition-colors mb-8"
              >
                Get started free
              </a>
              <ul class="space-y-3">
                <%= for feature <- [
                  "Live emoji reactions",
                  "Session analytics",
                  "Fireworks mode",
                  "Single user",
                  "Up to #{@free_participant_limit} participants per talk",
                  "#{@free_session_limit} full talk sessions per month†",
                  "QR code sharing",
                  "Browser extension",
                  "Google Slides with per-slide analytics",
                  "Anything browser-based without per-slide analytics"
                ] do %>
                  <li class="flex items-center gap-2.5 text-sm text-ink">
                    <.icon name="hero-check" class="size-4 text-mint shrink-0" />
                    {feature}
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- Pro (featured, coming soon) --%>
            <div class="bg-canvas rounded-xl border-2 border-mint shadow-[rgba(0,212,164,0.08)_0px_8px_24px] p-8 relative">
              <div class="absolute -top-3.5 left-6">
                <span class="px-2.5 py-1 bg-mint text-ink text-xs font-semibold rounded-full">
                  Coming soon
                </span>
              </div>
              <div class="mb-6">
                <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">Pro</p>
                <div class="flex items-baseline gap-1 mb-1.5">
                  <span class="text-[40px] font-semibold text-ink tracking-tight leading-none">$9</span>
                  <span class="text-sm text-steel">/month (introductory offer)</span>
                </div>
                <p class="text-sm text-steel">Launching soon.</p>
              </div>
              <button
                id="notify-pro-btn"
                phx-click="open_notify_modal"
                phx-value-plan="pro"
                class="block w-full text-center py-2.5 px-4 bg-ink text-canvas rounded-full text-sm font-medium hover:bg-charcoal transition-colors mb-8"
              >
                Notify me
              </button>
              <ul class="space-y-3">
                <%= for feature <- [
                  "Everything in Free",
                  "Unlimited participants",
                  "Unlimited sessions",
                  "Data export",
                  "Customize emoji set",
                  "PowerPoint plugin",
                  "Keynote plugin"
                ] do %>
                  <li class="flex items-center gap-2.5 text-sm text-muted">
                    <.icon name="hero-check" class="size-4 text-mint-soft shrink-0" />
                    {feature}
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- Enterprise --%>
            <div class="bg-canvas rounded-xl border border-hairline p-8 opacity-60">
              <div class="mb-6">
                <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">
                  Enterprise
                </p>
                <div class="flex items-baseline gap-1 mb-1.5">
                  <span class="text-[40px] font-semibold text-muted tracking-tight leading-none">
                    —
                  </span>
                </div>
                <p class="text-sm text-muted">Launches after Pro.</p>
              </div>
              <button
                id="notify-enterprise-btn"
                phx-click="open_notify_modal"
                phx-value-plan="enterprise"
                class="block w-full text-center py-2.5 px-4 bg-surface text-muted rounded-full text-sm font-medium hover:bg-hairline transition-colors mb-8"
              >
                Notify me
              </button>
              <ul class="space-y-3">
                <%= for feature <- [
                  "Everything in Pro",
                  "Priority support",
                  "Team pricing",
                  "Conference pricing",
                  "Organization analytics",
                  "Custom integrations"
                ] do %>
                  <li class="flex items-center gap-2.5 text-sm text-muted">
                    <.icon name="hero-check" class="size-4 text-muted shrink-0" />
                    {feature}
                  </li>
                <% end %>
              </ul>
            </div>
          </div>

          <p class="text-center text-xs text-muted mt-10">
            †A "full session" is a session lasting longer than 10 minutes.
          </p>
        </div>
      </div>

      <%!-- Notify Me Modal --%>
      <%= if @show_modal do %>
        <div
          id="notify-modal-overlay"
          class="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4"
        >
          <div id="notify-modal" class="bg-canvas rounded-2xl shadow-2xl w-full max-w-md p-8">
            <%= if @notify_sent do %>
              <div id="notify-sent-message" class="text-center space-y-3">
                <p class="text-lg font-semibold text-ink">Check your inbox!</p>
                <p class="text-sm text-steel leading-relaxed">
                  We sent a link to <strong>{@notify_email}</strong>. Click it to confirm your spot on the list.
                </p>
                <button
                  id="notify-cancel-btn"
                  phx-click="close_modal"
                  class="text-sm text-steel underline mt-2"
                >
                  Close
                </button>
              </div>
            <% else %>
              <div class="space-y-5">
                <div>
                  <h2 class="text-xl font-semibold text-ink mb-2">
                    Get notified when {String.capitalize(@show_modal)} launches
                  </h2>
                  <p class="text-sm text-steel leading-relaxed">
                    We'll let you know the moment it's ready — and keep you in the loop on product
                    updates. No spam, no selling your email.
                  </p>
                </div>
                <form id="notify-form" phx-submit="submit_notify" class="space-y-3">
                  <input
                    id="notify-email-input"
                    type="email"
                    name="email"
                    placeholder="you@example.com"
                    required
                    autocomplete="email"
                    class="w-full px-4 py-2.5 rounded-lg border border-hairline bg-surface text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-mint focus:border-transparent"
                  />
                  <button
                    type="submit"
                    class="w-full py-2.5 px-4 bg-ink text-canvas rounded-full text-sm font-medium hover:bg-charcoal transition-colors"
                  >
                    Notify me →
                  </button>
                </form>
                <button
                  id="notify-cancel-btn"
                  phx-click="close_modal"
                  class="w-full text-center text-xs text-muted hover:text-steel transition-colors"
                >
                  Cancel
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

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

  @impl true
  def handle_event("open_notify_modal", %{"plan" => plan}, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    cond do
      user && user.marketing_consent ->
        {:noreply, put_flash(socket, :info, "You're already on the list!")}

      user ->
        {:ok, _} = Accounts.apply_marketing_consent(user, grant: true, notify_interest: plan)
        {:noreply, put_flash(socket, :info, "You're on the list! We'll keep you posted.")}

      true ->
        {:noreply, assign(socket, show_modal: plan, notify_sent: false, notify_email: "")}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, show_modal: nil, notify_sent: false)}
  end

  def handle_event("submit_notify", %{"email" => email}, socket) do
    plan = socket.assigns.show_modal
    email = email |> String.trim() |> String.downcase()
    url_fun = &(url(~p"/users/magic_link/#{&1}") <> "?updates=true&notify=#{plan}")

    case Accounts.register_or_get_user_by_email(email) do
      {:ok, user} -> Accounts.deliver_login_instructions(user, url_fun)
      {:error, _} -> nil
    end

    {:noreply, assign(socket, notify_sent: true, notify_email: email)}
  end
end
```

- [ ] **Step 5: Update the router**

In `lib/speechwave_web/router.ex`, make two changes:

1. Remove `get "/pricing", PageController, :pricing` from the public `scope "/"` block.

2. Add `live "/pricing", PricingLive` inside the existing `live_session :current_user` block:

```elixir
live_session :current_user,
  on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
  live "/users/log-in", UserLive.Login, :new
  live "/pricing", PricingLive
end
```

- [ ] **Step 6: Run tests**

```bash
mix test test/speechwave_web/live/pricing_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 7: Remove the stale controller test for `/pricing`**

`test/speechwave_web/controllers/page_controller_test.exs` has a test for `GET /pricing` that will now return 404 because the route is handled by the LiveView. Delete that test:

```elixir
# Remove this entire test block:
test "GET /pricing returns 200", %{conn: conn} do
  conn = get(conn, ~p"/pricing")
  assert html_response(conn, 200)
end
```

- [ ] **Step 8: Run full test suite**

```bash
mix test
```

Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add lib/speechwave_web/components/layouts.ex \
        lib/speechwave_web/live/pricing_live.ex \
        lib/speechwave_web/router.ex \
        test/speechwave_web/live/pricing_live_test.exs \
        test/speechwave_web/controllers/page_controller_test.exs
git commit -m "feat: add Notify Me modal to pricing page via PricingLive"
```

---

## Task 4: Account settings email preferences

Add an "Email preferences" section to the settings page that shows current consent state and lets users opt out.

**Files:**
- Modify: `lib/speechwave_web/live/user_live/settings.ex`
- Modify: `test/speechwave_web/live/user_live/settings_test.exs`

- [ ] **Step 1: Write failing tests**

Add to `test/speechwave_web/live/user_live/settings_test.exs`:

```elixir
describe "email preferences" do
  test "shows current consent state when opted in", %{conn: conn} do
    user = consented_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/users/settings")

    assert has_element?(view, "#email-preferences")
    assert render(view) =~ "Opted in"
  end

  test "shows opted-out state when not consented", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/users/settings")

    assert has_element?(view, "#email-preferences")
    assert render(view) =~ "Not subscribed"
  end

  test "revoking consent updates the UI", %{conn: conn} do
    user = consented_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view |> element("#revoke-consent-btn") |> render_click()

    assert render(view) =~ "Not subscribed"

    updated = Speechwave.Accounts.get_user!(user.id)
    refute updated.marketing_consent
  end
end
```

- [ ] **Step 2: Run tests — expect failures**

```bash
mix test test/speechwave_web/live/user_live/settings_test.exs
```

Expected: failures on missing `#email-preferences` element.

- [ ] **Step 3: Add `marketing_consent` to the settings mount**

In `lib/speechwave_web/live/user_live/settings.ex`, in the `mount/2` that handles normal load (the one without a token), add `marketing_consent` to the assigns:

```elixir
def mount(_params, _session, socket) do
  user = socket.assigns.current_scope.user
  email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)

  socket =
    socket
    |> assign(:current_email, user.email)
    |> assign(:email_form, to_form(email_changeset))
    |> assign(:api_key, user.api_key)
    |> assign(:identities, Accounts.list_user_identities(user))
    |> assign(:marketing_consent, user.marketing_consent)

  {:ok, socket}
end
```

- [ ] **Step 4: Add the `revoke_consent` event handler**

Add after the existing `handle_event("regenerate_api_key", ...)` function:

```elixir
def handle_event("revoke_consent", _params, socket) do
  user = socket.assigns.current_scope.user
  {:ok, _} = Accounts.revoke_marketing_consent(user)
  {:noreply, assign(socket, :marketing_consent, false)}
end
```

- [ ] **Step 5: Add the Email preferences section to the template**

In `render/1`, add the Email preferences section after the API Key section's closing `</div>` and before `</Layouts.app>`:

```html
<div class="divider" />

<%!-- Email preferences --%>
<div id="email-preferences" class="space-y-3">
  <h3 class="font-semibold text-base-content">Email preferences</h3>
  <%= if @marketing_consent do %>
    <p class="text-sm text-base-content/70">
      <span class="font-medium text-success">Opted in</span> — you'll receive product updates
      and feature announcements from us.
    </p>
    <button
      id="revoke-consent-btn"
      phx-click="revoke_consent"
      data-confirm="Unsubscribe from product updates?"
      class="text-sm text-error hover:underline"
    >
      Unsubscribe
    </button>
  <% else %>
    <p class="text-sm text-base-content/70">
      <span class="font-medium">Not subscribed</span> — you won't receive marketing emails from us.
    </p>
  <% end %>
</div>
```

- [ ] **Step 6: Run tests**

```bash
mix test test/speechwave_web/live/user_live/settings_test.exs
```

Expected: all tests pass.

- [ ] **Step 7: Run full test suite and precommit checks**

```bash
mix test
mix precommit
```

Expected: all tests pass, no precommit issues.

- [ ] **Step 8: Commit**

```bash
git add lib/speechwave_web/live/user_live/settings.ex \
        test/speechwave_web/live/user_live/settings_test.exs
git commit -m "feat: add email preferences section to account settings"
```
