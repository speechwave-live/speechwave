# Email Collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GDPR-compliant marketing consent collection across three surfaces: the login screen, the pricing page "Notify me" modal, and account settings revocation.

**Architecture:** A new `user_consents` table stores one record per `(user_id, consent_type)` — extensible to future consent types without migrations. Each record carries `granted_at` (original consent timestamp) and `revoked_at` (revocation timestamp), so the full audit trail is preserved. Consent intent is encoded in magic link URLs (`?updates=true&notify=pro`) and SSO session state so it survives cross-device clicks. A new `PricingLive` replaces the static pricing controller page to enable the interactive "Notify me" modal.

**Tech Stack:** Phoenix LiveView, Ecto, existing `Accounts` context, `UserSessionController`, `Layouts.app`.

**Spec:** `docs/specs/2026-06-16-email-collection-design.md`

---

## File Map

| Action | File | Purpose |
|---|---|---|
| Create | `lib/speechwave/accounts/user_consent.ex` | `UserConsent` schema with changeset validation |
| Create | `priv/repo/migrations/*_create_user_consents.exs` | DB migration (generated) |
| Modify | `lib/speechwave/accounts.ex` | Add `grant_consent/3`, `revoke_consent/2`, `consented?/2`, `get_consent/2` |
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

## Task 1: Data model — `user_consents` table, schema, context functions

**Files:**
- Create: `lib/speechwave/accounts/user_consent.ex`
- Create: `priv/repo/migrations/*_create_user_consents.exs` (generated)
- Modify: `lib/speechwave/accounts.ex`
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Modify: `test/speechwave/accounts_test.exs`

### Schema design

One row per `(user_id, consent_type)`. Fields:
- `consent_type` — string identifying the type, e.g. `"marketing_email"`. Adding a new consent type later is just a new value — no migration needed.
- `granted` — boolean, current state.
- `granted_at` — when consent was granted; preserved on revocation for the audit trail.
- `source` — where consent was collected: `"login"`, `"pricing_pro"`, `"pricing_enterprise"`.
- `revoked_at` — when consent was revoked; nil when currently consented.

The changeset validates that `granted_at` is present whenever `granted: true` (addresses Finding 1 from the review: prevents a corrupted record where someone consented but has no timestamp).

### Context API

- `Accounts.grant_consent(user, type, opts)` — upserts; idempotent; updates `source` when it changes.
- `Accounts.revoke_consent(user, type)` — sets `granted: false`, records `revoked_at`, preserves `granted_at`.
- `Accounts.consented?(user, type)` — boolean; returns `true` only when a record exists and `granted: true`.
- `Accounts.get_consent(user, type)` — returns `%UserConsent{}` or `nil`.

---

- [ ] **Step 1: Write failing tests for `UserConsent.changeset/2`**

Add to `test/speechwave/accounts_test.exs`. Place the two new describe blocks before the closing `end` of the module. You'll need to add `alias Speechwave.Accounts.UserConsent` to the existing alias list at the top of the file:

```elixir
alias Speechwave.Accounts.{User, UserConsent, UserToken}
```

Then add the describe blocks:

```elixir
describe "UserConsent.changeset/2" do
  test "is valid when granted with granted_at present" do
    changeset =
      UserConsent.changeset(%UserConsent{}, %{
        consent_type: "marketing_email",
        granted: true,
        granted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        source: "login"
      })

    assert changeset.valid?
  end

  test "is invalid when granted: true without granted_at" do
    changeset =
      UserConsent.changeset(%UserConsent{}, %{
        consent_type: "marketing_email",
        granted: true,
        source: "login"
      })

    refute changeset.valid?
    assert errors_on(changeset)[:granted_at]
  end

  test "is valid when granted: false without granted_at" do
    changeset =
      UserConsent.changeset(%UserConsent{}, %{
        consent_type: "marketing_email",
        granted: false
      })

    assert changeset.valid?
  end
end
```

- [ ] **Step 2: Write failing tests for the four context functions**

Add to `test/speechwave/accounts_test.exs` (same file, new describe blocks):

```elixir
describe "grant_consent/3" do
  test "creates a consent record for a new user" do
    user = user_fixture()
    before = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, consent} = Accounts.grant_consent(user, "marketing_email", source: "login")

    assert consent.granted
    assert consent.consent_type == "marketing_email"
    assert consent.source == "login"
    assert DateTime.compare(consent.granted_at, before) in [:gt, :eq]
    assert is_nil(consent.revoked_at)
  end

  test "defaults source to 'login'" do
    user = user_fixture()

    {:ok, consent} = Accounts.grant_consent(user, "marketing_email")

    assert consent.source == "login"
  end

  test "is a no-op when already consented with the same source" do
    user = user_fixture()
    {:ok, original} = Accounts.grant_consent(user, "marketing_email", source: "login")

    {:ok, same} = Accounts.grant_consent(user, "marketing_email", source: "login")

    assert same.id == original.id
    assert same.granted_at == original.granted_at
  end

  test "updates source when already consented with a different source" do
    user = user_fixture()
    {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")

    {:ok, updated} = Accounts.grant_consent(user, "marketing_email", source: "pricing_pro")

    assert updated.source == "pricing_pro"
    assert updated.granted
  end

  test "re-grants after revocation with granted set and revoked_at cleared" do
    user = user_fixture()
    {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")
    {:ok, _} = Accounts.revoke_consent(user, "marketing_email")

    {:ok, reconsented} = Accounts.grant_consent(user, "marketing_email", source: "login")

    assert reconsented.granted
    assert not is_nil(reconsented.granted_at)
    assert is_nil(reconsented.revoked_at)
  end
end

describe "revoke_consent/2" do
  test "sets granted: false, records revoked_at, preserves granted_at" do
    user = user_fixture()
    {:ok, consented} = Accounts.grant_consent(user, "marketing_email", source: "login")
    original_granted_at = consented.granted_at
    before_revoke = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, revoked} = Accounts.revoke_consent(user, "marketing_email")

    refute revoked.granted
    assert DateTime.compare(revoked.revoked_at, before_revoke) in [:gt, :eq]
    assert revoked.granted_at == original_granted_at
  end

  test "is a no-op (returns {:ok, nil}) for a user who never consented" do
    user = user_fixture()

    assert {:ok, nil} = Accounts.revoke_consent(user, "marketing_email")
  end
end

describe "consented?/2" do
  test "returns false for a new user" do
    user = user_fixture()

    refute Accounts.consented?(user, "marketing_email")
  end

  test "returns true after consent is granted" do
    user = user_fixture()
    {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")

    assert Accounts.consented?(user, "marketing_email")
  end

  test "returns false after consent is revoked" do
    user = user_fixture()
    {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")
    {:ok, _} = Accounts.revoke_consent(user, "marketing_email")

    refute Accounts.consented?(user, "marketing_email")
  end
end

describe "get_consent/2" do
  test "returns nil when no record exists" do
    user = user_fixture()

    assert is_nil(Accounts.get_consent(user, "marketing_email"))
  end

  test "returns the consent record after granting" do
    user = user_fixture()
    {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")

    consent = Accounts.get_consent(user, "marketing_email")

    assert %Speechwave.Accounts.UserConsent{} = consent
    assert consent.consent_type == "marketing_email"
    assert consent.granted
  end
end
```

- [ ] **Step 3: Run tests — expect failures**

```bash
mix test test/speechwave/accounts_test.exs 2>&1 | tail -20
```

Expected: compile errors because `UserConsent` does not exist yet.

- [ ] **Step 4: Create `lib/speechwave/accounts/user_consent.ex`**

```elixir
defmodule Speechwave.Accounts.UserConsent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Speechwave.Accounts.User

  schema "user_consents" do
    belongs_to :user, User
    field :consent_type, :string
    field :granted, :boolean, default: false
    field :granted_at, :utc_datetime
    field :source, :string
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [:consent_type, :granted, :granted_at, :source, :revoked_at])
    |> validate_required([:consent_type, :granted])
    |> validate_granted_at_when_granted()
    |> unique_constraint([:user_id, :consent_type])
  end

  defp validate_granted_at_when_granted(changeset) do
    case get_field(changeset, :granted) do
      true ->
        if get_field(changeset, :granted_at) do
          changeset
        else
          add_error(changeset, :granted_at, "is required when consent is granted")
        end

      _ ->
        changeset
    end
  end
end
```

- [ ] **Step 5: Generate the migration**

```bash
mix ecto.gen.migration create_user_consents
```

Open the generated file in `priv/repo/migrations/` and replace the `change/0` body:

```elixir
def change do
  create table(:user_consents) do
    add :user_id, references(:users, on_delete: :delete_all), null: false
    add :consent_type, :string, null: false
    add :granted, :boolean, null: false, default: false
    add :granted_at, :utc_datetime
    add :source, :string
    add :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  create unique_index(:user_consents, [:user_id, :consent_type])
end
```

- [ ] **Step 6: Run the migration**

```bash
mix ecto.migrate
```

Expected: `== Running ... CreateUserConsents .. ok`

- [ ] **Step 7: Add context functions to `lib/speechwave/accounts.ex`**

First, add `UserConsent` to the existing alias at the top of the file (around line 9):

```elixir
alias Speechwave.Accounts.{User, UserConsent, UserIdentity, UserNotifier, UserToken}
```

Then add these four functions after the `regenerate_api_key/1` function:

```elixir
@doc "Returns the consent record for the given user and type, or nil."
def get_consent(%User{} = user, consent_type) do
  Repo.get_by(UserConsent, user_id: user.id, consent_type: consent_type)
end

@doc "Returns true if the user currently has active consent of the given type."
def consented?(%User{} = user, consent_type) do
  case get_consent(user, consent_type) do
    %UserConsent{granted: true} -> true
    _ -> false
  end
end

@doc """
Grants consent of the given type for the user.

Idempotent: calling again with the same source is a no-op. Calling with a
different source updates the source (e.g. upgrading from "login" to
"pricing_pro" when the user clicks Notify Me). Re-grants after revocation
record a fresh `granted_at` timestamp.

Options:
  - `:source` — where consent was collected; defaults to `"login"`.
"""
def grant_consent(%User{} = user, consent_type, opts \\ []) do
  source = Keyword.get(opts, :source, "login")
  existing = get_consent(user, consent_type)

  cond do
    is_nil(existing) ->
      %UserConsent{user_id: user.id}
      |> UserConsent.changeset(%{
        consent_type: consent_type,
        granted: true,
        granted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        source: source
      })
      |> Repo.insert()

    not existing.granted ->
      existing
      |> UserConsent.changeset(%{
        granted: true,
        granted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        source: source,
        revoked_at: nil
      })
      |> Repo.update()

    existing.source == source ->
      {:ok, existing}

    true ->
      existing
      |> UserConsent.changeset(%{source: source})
      |> Repo.update()
  end
end

@doc """
Revokes consent of the given type for the user.

Records `revoked_at` for the audit trail but preserves `granted_at` so the
original consent timestamp remains. Is a no-op (returns `{:ok, nil}`) if no
consent record exists.
"""
def revoke_consent(%User{} = user, consent_type) do
  case get_consent(user, consent_type) do
    nil ->
      {:ok, nil}

    consent ->
      consent
      |> UserConsent.changeset(%{
        granted: false,
        revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()
  end
end
```

- [ ] **Step 8: Add `consented_user_fixture/1` to `test/support/fixtures/accounts_fixtures.ex`**

Add after `user_fixture/1`:

```elixir
def consented_user_fixture(attrs \\ %{}) do
  user = user_fixture()
  source = Map.get(attrs, :source, "login")
  {:ok, _} = Speechwave.Accounts.grant_consent(user, "marketing_email", source: source)
  user
end
```

Note: the fixture returns the plain `User` struct (not the consent record). Callers check consent state via `Accounts.consented?(user, "marketing_email")` or `Accounts.get_consent(user, "marketing_email")`.

- [ ] **Step 9: Run the accounts tests — expect them all to pass**

```bash
mix test test/speechwave/accounts_test.exs
```

Expected: all tests pass (both old and new).

- [ ] **Step 10: Commit**

```bash
git add lib/speechwave/accounts/user_consent.ex \
        lib/speechwave/accounts.ex \
        priv/repo/migrations/ \
        test/speechwave/accounts_test.exs \
        test/support/fixtures/accounts_fixtures.ex
git commit -m "feat: add user_consents table and consent context functions"
```

---

## Task 2: Login screen consent checkbox + passthrough

The checkbox collects consent on the login screen. For magic link, consent intent is appended to the URL as `?updates=true`. For SSO, consent intent is stored in the session before the OAuth redirect and applied on callback.

**Files:**
- Modify: `lib/speechwave_web/live/user_live/login.ex`
- Modify: `lib/speechwave_web/controllers/user_session_controller.ex`
- Modify: `test/speechwave_web/live/user_live/login_test.exs`
- Modify: `test/speechwave_web/controllers/user_session_controller_test.exs`

- [ ] **Step 1: Write failing login LiveView tests**

Add to `test/speechwave_web/live/user_live/login_test.exs` (new describe block, inside the module):

```elixir
describe "consent checkbox" do
  test "renders unchecked consent checkbox", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, "#marketing-consent-checkbox")
    refute has_element?(view, "#marketing-consent-checkbox[checked]")
  end

  test "submitting with consent checked shows magic link sent confirmation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    view
    |> form("#magic-link-form", %{"user" => %{"email" => "test@example.com", "marketing_consent" => "true"}})
    |> render_submit()

    assert has_element?(view, "#magic-link-sent")
  end

  test "submitting without consent checked also shows confirmation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    view
    |> form("#magic-link-form", %{"user" => %{"email" => "test@example.com", "marketing_consent" => "false"}})
    |> render_submit()

    assert has_element?(view, "#magic-link-sent")
  end
end
```

- [ ] **Step 2: Write failing controller consent tests**

Add to `test/speechwave_web/controllers/user_session_controller_test.exs`. First add an alias at the top of the module (alongside the existing `import Speechwave.AccountsFixtures`):

```elixir
alias Speechwave.Accounts
```

Then add new describe blocks:

```elixir
describe "magic_link/2 with consent params" do
  setup do
    user = user_fixture()
    {token, _} = generate_user_magic_link_token(user)
    %{user: user, token: token}
  end

  test "grants consent with source 'login' when ?updates=true", %{conn: conn, user: user, token: token} do
    before = DateTime.utc_now() |> DateTime.truncate(:second)
    get(conn, ~p"/users/magic_link/#{token}?updates=true")

    consent = Accounts.get_consent(user, "marketing_email")
    assert consent
    assert consent.granted
    assert consent.source == "login"
    assert DateTime.compare(consent.granted_at, before) in [:gt, :eq]
  end

  test "sets source to 'pricing_pro' when ?updates=true&notify=pro", %{conn: conn, user: user, token: token} do
    get(conn, ~p"/users/magic_link/#{token}?updates=true&notify=pro")

    consent = Accounts.get_consent(user, "marketing_email")
    assert consent.source == "pricing_pro"
  end

  test "shows plan-specific flash when ?notify present", %{conn: conn, token: token} do
    conn = get(conn, ~p"/users/magic_link/#{token}?updates=true&notify=pro")

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Pro"
  end

  test "does not grant consent when ?updates absent", %{conn: conn, user: user, token: token} do
    get(conn, ~p"/users/magic_link/#{token}")

    refute Accounts.consented?(user, "marketing_email")
  end

  test "preserves existing consent on login without ?updates", %{conn: conn} do
    user = consented_user_fixture()
    {token, _} = generate_user_magic_link_token(user)

    get(conn, ~p"/users/magic_link/#{token}")

    assert Accounts.consented?(user, "marketing_email")
  end
end
```

- [ ] **Step 3: Run tests — expect failures**

```bash
mix test test/speechwave_web/live/user_live/login_test.exs \
         test/speechwave_web/controllers/user_session_controller_test.exs
```

Expected: failures on missing `#marketing-consent-checkbox` and consent not being applied.

- [ ] **Step 4: Update `mount/3` in `lib/speechwave_web/live/user_live/login.ex`**

Replace the existing `mount/3` function:

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

- [ ] **Step 5: Add a `form_changed` event handler in `lib/speechwave_web/live/user_live/login.ex`**

Add this new handler after `mount/3`:

```elixir
@impl true
def handle_event("form_changed", %{"user" => params}, socket) do
  consent = Map.get(params, "marketing_consent") == "true"
  {:noreply, assign(socket, :marketing_consent, consent)}
end
```

- [ ] **Step 6: Replace `submit_magic` and private helpers in `lib/speechwave_web/live/user_live/login.ex`**

Replace the existing `handle_event("submit_magic", ...)` handler:

```elixir
@impl true
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

Replace the three private helpers at the bottom of the file to accept `url_fun`:

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

- [ ] **Step 7: Update the `<.form>` tag in `render/1` in `lib/speechwave_web/live/user_live/login.ex`**

Find the `<.form>` tag (around line 43) and add `phx-change`:

```html
<.form
  for={@form}
  id="magic-link-form"
  phx-submit="submit_magic"
  phx-change="form_changed"
>
```

- [ ] **Step 8: Add the consent checkbox to the form in `lib/speechwave_web/live/user_live/login.ex`**

In `render/1`, after the `<.input field={@form[:email]} .../>` block and before `<.button>`, add:

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

The hidden input ensures `marketing_consent` is submitted as `"false"` when unchecked. The visible checkbox overrides it to `"true"` when checked.

- [ ] **Step 9: Update SSO `<a>` hrefs in `render/1` in `lib/speechwave_web/live/user_live/login.ex`**

Replace each SSO button's `href` to conditionally include `?updates=true`:

For Google (find `href={~p"/auth/google"}`):
```html
href={if @marketing_consent, do: "/auth/google?updates=true", else: "/auth/google"}
```

For Microsoft (find `href={~p"/auth/microsoft"}`):
```html
href={if @marketing_consent, do: "/auth/microsoft?updates=true", else: "/auth/microsoft"}
```

For GitHub (find `href={~p"/auth/github"}`):
```html
href={if @marketing_consent, do: "/auth/github?updates=true", else: "/auth/github"}
```

- [ ] **Step 10: Update `magic_link/2` in `lib/speechwave_web/controllers/user_session_controller.ex`**

Replace the existing `magic_link/2` function:

```elixir
@doc "Handles the magic link click — verifies token and creates a session directly."
def magic_link(conn, %{"token" => token} = params) do
  updates = params["updates"] == "true"
  notify = params["notify"]

  case Accounts.login_user_by_magic_link(token) do
    {:ok, {user, _tokens}} ->
      if updates do
        source = if notify, do: "pricing_#{notify}", else: "login"
        Accounts.grant_consent(user, "marketing_email", source: source)
      end

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

- [ ] **Step 11: Update `oauth_authorize/2` in `lib/speechwave_web/controllers/user_session_controller.ex`**

Replace the existing `oauth_authorize/2` function to capture and store the `updates` param:

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

- [ ] **Step 12: Update `handle_oauth_login/3` in `lib/speechwave_web/controllers/user_session_controller.ex`**

Replace the existing `handle_oauth_login/3` private function:

```elixir
defp handle_oauth_login(conn, provider, user_info) do
  marketing_updates = get_session(conn, :marketing_updates) || false

  case Accounts.find_or_create_user_from_oauth(provider, user_info) do
    {:ok, user} ->
      if marketing_updates do
        Accounts.grant_consent(user, "marketing_email", source: "login")
      end

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

- [ ] **Step 13: Run the tests**

```bash
mix test test/speechwave_web/live/user_live/login_test.exs \
         test/speechwave_web/controllers/user_session_controller_test.exs
```

Expected: all tests pass.

- [ ] **Step 14: Run full test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 15: Commit**

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
- Modify: `test/speechwave_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Write failing pricing LiveView tests**

Create `test/speechwave_web/live/pricing_live_test.exs`:

```elixir
defmodule SpeechwaveWeb.PricingLiveTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts

  describe "pricing page" do
    test "renders all three pricing tiers", %{conn: conn} do
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
      view |> form("#notify-form", %{"email" => "interested@example.com"}) |> render_submit()

      assert has_element?(view, "#notify-sent-message")
    end
  end

  describe "Notify me — logged-in user without consent" do
    test "applies consent directly with source 'pricing_pro' and shows flash", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
      assert render(view) =~ "You&#39;re on the list"

      consent = Accounts.get_consent(user, "marketing_email")
      assert consent
      assert consent.granted
      assert consent.source == "pricing_pro"
    end
  end

  describe "Notify me — logged-in user already consented" do
    test "shows already-on-list flash without modal", %{conn: conn} do
      user = consented_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
      assert render(view) =~ "already on the list"
    end
  end
end
```

- [ ] **Step 2: Run tests — expect failures (PricingLive doesn't exist)**

```bash
mix test test/speechwave_web/live/pricing_live_test.exs
```

Expected: compile error — `SpeechwaveWeb.PricingLive` module not found.

- [ ] **Step 3: Add `full_width` attr to `Layouts.app` in `lib/speechwave_web/components/layouts.ex`**

Add the new attr after the existing `current_scope` attr (around line 32):

```elixir
attr :full_width, :boolean,
  default: false,
  doc: "when true, skips the max-w-2xl wrapper — for marketing pages that handle their own width"
```

In `def app(assigns)`, replace both `<main>` blocks to conditionally skip the width wrapper.

Authenticated main (find `<main class="pt-14 px-4 py-8 sm:px-6 lg:px-8">` and its inner div):

```html
<main class={["pt-14", not @full_width && "px-4 py-8 sm:px-6 lg:px-8"]}>
  <div class={[@full_width || "mx-auto max-w-2xl space-y-4"]}>
    {render_slot(@inner_block)}
  </div>
</main>
```

Unauthenticated main (find `<main class="pt-16 px-4 py-8 sm:px-6 lg:px-8">` and its inner div):

```html
<main class={["pt-16", not @full_width && "px-4 py-8 sm:px-6 lg:px-8"]}>
  <div class={[@full_width || "mx-auto max-w-2xl space-y-4"]}>
    {render_slot(@inner_block)}
  </div>
</main>
```

How the class lists work:
- `not @full_width && "px-4 py-8 sm:px-6 lg:px-8"` → adds padding when NOT full_width; evaluates to `false` when full_width, which HEEx ignores.
- `@full_width || "mx-auto max-w-2xl space-y-4"` → when full_width is `true`, `true || ...` gives `true` (HEEx adds no class); when false, gives the string class.

- [ ] **Step 4: Create `lib/speechwave_web/live/pricing_live.ex`**

The template is ported from `lib/speechwave_web/controllers/page_html/pricing.html.heex` with these changes:
- Wrapped in `<Layouts.app>` with `full_width={true}`.
- The outer content div uses `pt-8` instead of `pt-24` — the `pt-24` in the original was compensating for the absence of a wrapping layout; with `Layouts.app`, the main tag already clears the fixed header.
- Pro and Enterprise buttons replaced with interactive `phx-click` buttons.
- Modal appended inside the layout wrapper.

```elixir
defmodule SpeechwaveWeb.PricingLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.{Accounts, Plans}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} full_width={true}>
      <div class="pt-8 pb-24 min-h-screen bg-surface">
        <div class="max-w-5xl mx-auto px-6">
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
      user && Accounts.consented?(user, "marketing_email") ->
        {:noreply, put_flash(socket, :info, "You're already on the list!")}

      user ->
        {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "pricing_#{plan}")
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

- [ ] **Step 5: Update `lib/speechwave_web/router.ex`**

Make two changes:

**Remove** `get "/pricing", PageController, :pricing` from the public scope block (around line 29).

**Add** `live "/pricing", PricingLive` inside the existing `live_session :current_user` block so it gets `@current_scope` mounted (required for the logged-in path in `open_notify_modal`):

```elixir
live_session :current_user,
  on_mount: [{SpeechwaveWeb.UserAuth, :mount_current_scope}] do
  live "/users/log-in", UserLive.Login, :new
  live "/pricing", PricingLive
end
```

- [ ] **Step 6: Run the pricing tests**

```bash
mix test test/speechwave_web/live/pricing_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 7: Remove the stale controller test for `GET /pricing`**

In `test/speechwave_web/controllers/page_controller_test.exs`, remove this test (the route now goes to PricingLive and will return a 404 for a plain HTTP request):

```elixir
test "GET /pricing returns 200", %{conn: conn} do
  conn = get(conn, ~p"/pricing")
  assert html_response(conn, 200) =~ "Free"
end
```

- [ ] **Step 8: Run the full test suite**

```bash
mix test
```

Expected: all tests pass.

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

Add an "Email preferences" section to the settings page that shows current consent state and lets users revoke consent.

**Files:**
- Modify: `lib/speechwave_web/live/user_live/settings.ex`
- Modify: `test/speechwave_web/live/user_live/settings_test.exs`

- [ ] **Step 1: Write failing tests**

Add to `test/speechwave_web/live/user_live/settings_test.exs` (new describe block, before the final `end`). The file already has `alias Speechwave.Accounts` and `import Speechwave.AccountsFixtures` at the top:

```elixir
describe "email preferences" do
  test "shows opted-in state when consented", %{conn: conn} do
    user = consented_user_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    assert has_element?(view, "#email-preferences")
    assert has_element?(view, "#consent-status[data-consented='true']")
  end

  test "shows not-subscribed state when not consented", %{conn: conn} do
    user = user_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    assert has_element?(view, "#email-preferences")
    assert has_element?(view, "#consent-status[data-consented='false']")
  end

  test "revoking consent updates the UI and persists to the database", %{conn: conn} do
    user = consented_user_fixture()

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    view |> element("#revoke-consent-btn") |> render_click()

    assert has_element?(view, "#consent-status[data-consented='false']")
    refute Accounts.consented?(user, "marketing_email")
  end
end
```

- [ ] **Step 2: Run tests — expect failures**

```bash
mix test test/speechwave_web/live/user_live/settings_test.exs
```

Expected: failures on missing `#email-preferences` element.

- [ ] **Step 3: Add `marketing_consent` to the settings mount in `lib/speechwave_web/live/user_live/settings.ex`**

Replace the `mount/2` that handles normal page load (the one that pattern-matches `_params`, not the one with `"token"`):

```elixir
def mount(_params, _session, socket) do
  user = socket.assigns.current_scope.user
  email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
  consent = Accounts.get_consent(user, "marketing_email")

  socket =
    socket
    |> assign(:current_email, user.email)
    |> assign(:email_form, to_form(email_changeset))
    |> assign(:api_key, user.api_key)
    |> assign(:identities, Accounts.list_user_identities(user))
    |> assign(:marketing_consent, consent != nil && consent.granted)

  {:ok, socket}
end
```

- [ ] **Step 4: Add the `revoke_consent` event handler to `lib/speechwave_web/live/user_live/settings.ex`**

Add after the existing `handle_event("regenerate_api_key", ...)` function:

```elixir
def handle_event("revoke_consent", _params, socket) do
  user = socket.assigns.current_scope.user
  {:ok, _} = Accounts.revoke_consent(user, "marketing_email")
  {:noreply, assign(socket, :marketing_consent, false)}
end
```

- [ ] **Step 5: Add the Email preferences section to the template in `lib/speechwave_web/live/user_live/settings.ex`**

In `render/1`, add the following after the closing `</div>` of the API Key section and before `</Layouts.app>`:

```html
<div class="divider" />

<%!-- Email preferences --%>
<div id="email-preferences" class="space-y-3">
  <h3 class="font-semibold text-base-content">Email preferences</h3>
  <p
    id="consent-status"
    data-consented={to_string(@marketing_consent)}
    class="text-sm text-base-content/70"
  >
    <%= if @marketing_consent do %>
      <span class="font-medium text-success">Opted in</span>
      — you'll receive product updates and feature announcements from us.
    <% else %>
      <span class="font-medium">Not subscribed</span>
      — you won't receive marketing emails from us.
    <% end %>
  </p>
  <%= if @marketing_consent do %>
    <button
      id="revoke-consent-btn"
      phx-click="revoke_consent"
      data-confirm="Unsubscribe from product updates?"
      class="text-sm text-error hover:underline"
    >
      Unsubscribe
    </button>
  <% end %>
</div>
```

The `data-consented={to_string(@marketing_consent)}` renders as `data-consented="true"` or `data-consented="false"` for the test selectors.

- [ ] **Step 6: Run tests**

```bash
mix test test/speechwave_web/live/user_live/settings_test.exs
```

Expected: all tests pass.

- [ ] **Step 7: Run full test suite and precommit checks**

```bash
mix test && mix precommit
```

Expected: all tests pass, no precommit issues.

- [ ] **Step 8: Commit**

```bash
git add lib/speechwave_web/live/user_live/settings.ex \
        test/speechwave_web/live/user_live/settings_test.exs
git commit -m "feat: add email preferences section to account settings"
```
