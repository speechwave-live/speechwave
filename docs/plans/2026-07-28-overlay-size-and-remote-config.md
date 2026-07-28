# Overlay Size Setting and Remote Extension Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users set the Chrome extension's emoji-overlay size as a percentage of slide coverage (100% = full slide) from their account Settings page, and move the extension's internal animation-tuning constants to a backend-delivered config so they can be adjusted via a backend deploy instead of a new Chrome Web Store submission.

**Architecture:** `SpeechwaveWeb.ReactionChannel.join/3` (in the `speechwave` repo) starts returning a `{settings, tuning}` payload instead of today's empty reply. `settings` comes from two new columns on `users`; `tuning` comes from a new plain `Speechwave.ExtensionTuning` module (not a DB table — see spec's rejected-alternatives section). In the `chrome-extension` repo, `background.js` captures this payload at join and relays it to content scripts via a new `SET_REMOTE_CONFIG` broadcast, plus answers a new `GET_REMOTE_CONFIG` pull request (mirroring the existing `GET_STATUS` pattern) for content scripts that load without a fresh join. `content.js`'s sizing math changes from a fixed-box-scaled-by-slide-width model to computing box width/height directly as `slideDimension * (percent / 100)`, replacing the old `SLIDE_REFERENCE_WIDTH`/`overlayScale` system entirely.

**Tech Stack:** Phoenix Channels, Ecto (SQLite via `ecto_sqlite3`), Phoenix LiveView 1.8, Chrome Extension Manifest V3, Jest.

Full design rationale: `docs/specs/2026-07-27-overlay-size-and-remote-config-design.md`.

## Global Constraints

- **Two separate git repositories.** Backend tasks (1–4) are in `/Users/tracy/projects/speechwave-live/speechwave`. Extension tasks (5–8) are in `/Users/tracy/projects/speechwave-live/chrome-extension`. Commit each repo's changes separately — do not mix commits across repos.
- **SQLite, not Postgres** (`ecto_sqlite3`). No jsonb column type. `overlay_size_percent`/`fireworks_enabled` are plain typed columns on `users`.
- **No DB-backed tuning config, no admin UI for it.** `Speechwave.ExtensionTuning` is a plain Elixir module returning a hardcoded map — this was explicitly decided against a DB table + admin page (see spec).
- **No migration of existing local `fireworksEnabled` toggle values.** Every user gets the new default (`fireworks_enabled: true`) regardless of what they'd previously set in the extension popup.
- **`debugEnabled` is untouched** — stays a local extension dev tool, does not move to the backend.
- **Canonical config shape**, used identically in every task below (backend response, extension `DEFAULT_CONFIG`, and every test fixture) — do not invent alternate key names or shapes:
  ```json
  {
    "settings": { "overlay_size_percent": 20, "fireworks_enabled": true },
    "tuning": {
      "default_overlay_size_percent": 20,
      "min_overlay_size_percent": 10,
      "overlay_margin_px": 8,
      "emoji_font_size_ratio": 0.14,
      "firework_font_size_ratio": 0.12,
      "firework_center_x_ratio": 0.5,
      "firework_center_y_ratio": 0.5,
      "firework_spread_min_ratio": 0.375,
      "firework_spread_range_ratio": 0.25,
      "emoji_rise_ratio": 0.3
    }
  }
  ```
  All keys are snake_case on both sides (matches this codebase's existing precedent of `session_id` flowing unchanged from Elixir to the extension's JS — no camelCase transformation layer).
- **Message protocol**: `SET_REMOTE_CONFIG` (background → content, broadcast) and `GET_REMOTE_CONFIG` (content → background, request/response) are new. `SET_FIREWORKS` is removed entirely (both the popup→background send and the background→content broadcast) — fireworks on/off now arrives only via `SET_REMOTE_CONFIG`/`GET_REMOTE_CONFIG`.
- Follow `CLAUDE.md`: `<Layouts.app flash={@flash} current_scope={@current_scope}>` wraps LiveView templates; use `@current_scope.user`, never `@current_user`; use `<.input>` for form fields; run `mix precommit` once all backend tasks are done (end of Task 4).
- Extension tests use the existing `eval()`-the-source-file pattern (`tests/setup/chrome-mock.js` provides `global.chrome`); follow the exact conventions already in `tests/content.test.js`, `tests/background.test.js`, `tests/popup.test.js`.

---

### Task 1: `Speechwave.ExtensionTuning` module

**Files:**
- Create: `lib/speechwave/extension_tuning.ex`
- Test: `test/speechwave/extension_tuning_test.exs`

**Interfaces:**
- Produces: `Speechwave.ExtensionTuning.current/0` — returns the `tuning` map from the canonical shape in Global Constraints. Consumed by Task 3 (channel join) and Task 4 (Settings LiveView).

- [ ] **Step 1: Write the failing test**

Create `test/speechwave/extension_tuning_test.exs`:

```elixir
defmodule Speechwave.ExtensionTuningTest do
  use ExUnit.Case, async: true

  alias Speechwave.ExtensionTuning

  test "current/0 returns all expected keys with correct types" do
    tuning = ExtensionTuning.current()

    assert is_integer(tuning.default_overlay_size_percent)
    assert is_integer(tuning.min_overlay_size_percent)
    assert is_integer(tuning.overlay_margin_px)
    assert is_float(tuning.emoji_font_size_ratio)
    assert is_float(tuning.firework_font_size_ratio)
    assert is_float(tuning.firework_center_x_ratio)
    assert is_float(tuning.firework_center_y_ratio)
    assert is_float(tuning.firework_spread_min_ratio)
    assert is_float(tuning.firework_spread_range_ratio)
    assert is_float(tuning.emoji_rise_ratio)
  end

  test "min_overlay_size_percent is below default_overlay_size_percent" do
    tuning = ExtensionTuning.current()
    assert tuning.min_overlay_size_percent < tuning.default_overlay_size_percent
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/speechwave/extension_tuning_test.exs`
Expected: FAIL — `Speechwave.ExtensionTuning` module not defined.

- [ ] **Step 3: Write the implementation**

Create `lib/speechwave/extension_tuning.ex`:

```elixir
defmodule Speechwave.ExtensionTuning do
  @moduledoc """
  Tuning constants for the Chrome extension's emoji-overlay rendering,
  delivered to the extension via the reactions channel join reply instead
  of being hardcoded in the extension itself. Change these values and
  redeploy (or, locally, let the code reloader pick up the change) to
  adjust overlay/animation behavior without a new extension version.

  Deliberately a plain module, not a database-backed config with an admin
  UI — see docs/specs/2026-07-27-overlay-size-and-remote-config-design.md
  for why that was considered and rejected.
  """

  def current do
    %{
      default_overlay_size_percent: 20,
      min_overlay_size_percent: 10,
      overlay_margin_px: 8,
      emoji_font_size_ratio: 0.14,
      firework_font_size_ratio: 0.12,
      firework_center_x_ratio: 0.5,
      firework_center_y_ratio: 0.5,
      firework_spread_min_ratio: 0.375,
      firework_spread_range_ratio: 0.25,
      emoji_rise_ratio: 0.3
    }
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/speechwave/extension_tuning_test.exs`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
git add lib/speechwave/extension_tuning.ex test/speechwave/extension_tuning_test.exs
git commit -m "feat: add ExtensionTuning module for backend-delivered overlay tuning constants"
```

---

### Task 2: User extension settings (schema, migration, changeset, context)

**Files:**
- Modify: `lib/speechwave/accounts/user.ex`
- Modify: `lib/speechwave/accounts.ex`
- Create: migration (via `mix ecto.gen.migration`)
- Modify: `test/speechwave/accounts_test.exs`

**Interfaces:**
- Consumes: `Speechwave.ExtensionTuning.current/0` (Task 1) for the changeset's minimum-bound validation.
- Produces: `User.extension_settings_changeset/2`; `Accounts.change_extension_settings/2`; `Accounts.update_extension_settings/2`; new fields `overlay_size_percent` (nullable integer) and `fireworks_enabled` (boolean, default `true`) on `%User{}`. Consumed by Task 3 (channel reads the fields directly) and Task 4 (Settings LiveView calls the two `Accounts` functions).

- [ ] **Step 1: Generate the migration**

Run: `mix ecto.gen.migration add_extension_settings_to_users`

This creates a timestamped file at `priv/repo/migrations/<timestamp>_add_extension_settings_to_users.exs`. Replace its contents with:

```elixir
defmodule Speechwave.Repo.Migrations.AddExtensionSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :overlay_size_percent, :integer
      add :fireworks_enabled, :boolean, default: true, null: false
    end
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `mix ecto.migrate`
Expected: migration runs successfully, no errors.

- [ ] **Step 3: Write the failing tests**

Append to `test/speechwave/accounts_test.exs` (add `alias Speechwave.Accounts` and `alias Speechwave.ExtensionTuning` near the top if not already present):

```elixir
  describe "update_extension_settings/2" do
    test "updates overlay_size_percent and fireworks_enabled" do
      user = user_fixture()

      assert {:ok, updated} =
               Accounts.update_extension_settings(user, %{
                 "overlay_size_percent" => 40,
                 "fireworks_enabled" => false
               })

      assert updated.overlay_size_percent == 40
      assert updated.fireworks_enabled == false
    end

    test "allows overlay_size_percent to be nil" do
      user = user_fixture()

      assert {:ok, updated} =
               Accounts.update_extension_settings(user, %{"overlay_size_percent" => nil})

      assert updated.overlay_size_percent == nil
    end

    test "rejects overlay_size_percent below the tuning minimum" do
      user = user_fixture()
      min = ExtensionTuning.current().min_overlay_size_percent

      assert {:error, changeset} =
               Accounts.update_extension_settings(user, %{"overlay_size_percent" => min - 1})

      assert "must be greater than or equal to #{min}" in errors_on(changeset).overlay_size_percent
    end

    test "rejects overlay_size_percent above 100" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_extension_settings(user, %{"overlay_size_percent" => 101})

      assert "must be less than or equal to 100" in errors_on(changeset).overlay_size_percent
    end

    test "new users default to fireworks_enabled: true and overlay_size_percent: nil" do
      user = user_fixture()
      assert user.fireworks_enabled == true
      assert user.overlay_size_percent == nil
    end
  end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `mix test test/speechwave/accounts_test.exs`
Expected: FAIL — `Accounts.update_extension_settings/2` is undefined.

- [ ] **Step 5: Add the schema fields and changeset**

Modify `lib/speechwave/accounts/user.ex` — add the two fields to the `schema` block and a new changeset function:

```elixir
  schema "users" do
    field :email, :string
    field :authenticated_at, :utc_datetime, virtual: true
    field :api_key, :string
    field :plan, Ecto.Enum, values: [:free, :pro, :org], default: :free
    field :is_admin, :boolean, default: false
    field :confirmed_at, :utc_datetime
    field :overlay_size_percent, :integer
    field :fireworks_enabled, :boolean, default: true

    has_many :identities, Speechwave.Accounts.UserIdentity

    timestamps(type: :utc_datetime)
  end
```

Add this changeset function (anywhere after `plan_changeset/2`):

```elixir
  @doc """
  Updates a user's Chrome-extension overlay settings. `overlay_size_percent`
  may be nil (meaning "use the tuning module's default"); when present it
  must be between the tuning module's minimum and 100.
  """
  def extension_settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:overlay_size_percent, :fireworks_enabled])
    |> validate_number(:overlay_size_percent,
      greater_than_or_equal_to: Speechwave.ExtensionTuning.current().min_overlay_size_percent,
      less_than_or_equal_to: 100
    )
  end
```

- [ ] **Step 6: Add the context functions**

Modify `lib/speechwave/accounts.ex` — add these two functions near `set_user_plan/2`:

```elixir
  @doc "Returns a changeset for a user's extension settings, for form rendering."
  def change_extension_settings(%User{} = user, attrs \\ %{}) do
    User.extension_settings_changeset(user, attrs)
  end

  @doc "Updates a user's extension settings (overlay size percent, fireworks toggle)."
  def update_extension_settings(%User{} = user, attrs) do
    user
    |> User.extension_settings_changeset(attrs)
    |> Repo.update()
  end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/speechwave/accounts_test.exs`
Expected: PASS (all tests, including the 5 new ones)

- [ ] **Step 8: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
git add priv/repo/migrations lib/speechwave/accounts/user.ex lib/speechwave/accounts.ex test/speechwave/accounts_test.exs
git commit -m "feat: add overlay_size_percent and fireworks_enabled settings to users"
```

---

### Task 3: Channel join delivers settings + tuning

**Files:**
- Modify: `lib/speechwave_web/channels/reaction_channel.ex`
- Modify: `test/speechwave_web/channels/reaction_channel_test.exs`

**Interfaces:**
- Consumes: `Speechwave.ExtensionTuning.current/0` (Task 1); `user.overlay_size_percent`/`user.fireworks_enabled` (Task 2).
- Produces: join reply payload matching the canonical shape in Global Constraints. Consumed by Task 5 (`background.js`).

- [ ] **Step 1: Write the failing test**

Add to `test/speechwave_web/channels/reaction_channel_test.exs` (a new top-level test, alongside the existing `"joins when api_key is valid..."` test):

```elixir
  test "join reply includes settings and tuning", %{socket: socket, talk: talk, user: user} do
    assert {:ok, payload, _joined} = channel_join(socket, talk.slug, user.api_key)

    tuning = Speechwave.ExtensionTuning.current()

    assert payload.settings == %{
             overlay_size_percent: tuning.default_overlay_size_percent,
             fireworks_enabled: true
           }

    assert payload.tuning == tuning
  end

  test "join reply uses the user's explicit overlay_size_percent when set", %{
    socket: socket,
    talk: talk,
    user: user
  } do
    {:ok, user} = Speechwave.Accounts.update_extension_settings(user, %{"overlay_size_percent" => 55})

    assert {:ok, payload, _joined} = channel_join(socket, talk.slug, user.api_key)
    assert payload.settings.overlay_size_percent == 55
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/speechwave_web/channels/reaction_channel_test.exs`
Expected: FAIL — join reply payload is currently empty (`assert {:ok, _, _}` in the pre-existing test still passes, since `_` matches anything, but the two new tests fail matching against `payload.settings`).

- [ ] **Step 3: Update `join/3`**

Modify `lib/speechwave_web/channels/reaction_channel.ex`. Change the success branch:

```elixir
  def join("reactions:" <> slug, %{"api_key" => api_key}, socket) do
    with {:talk, %Talks.Talk{} = talk} <- {:talk, Talks.get_talk_by_slug(slug)},
         {:user, %Accounts.User{} = user} <- {:user, Accounts.get_user_by_api_key(api_key)},
         {:owner, true} <- {:owner, talk.user_id == user.id},
         {:capacity, :ok} <-
           {:capacity,
            Plans.check(
              :max_participants,
              user.plan,
              Presence.list("reactions:#{slug}") |> map_size()
            )} do
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "user:#{user.id}:disconnect")
      send(self(), :after_join)
      {:ok, join_payload(user), assign(socket, talk: talk, user: user)}
    else
      {:talk, nil} -> {:error, %{reason: "not_found"}}
      {:user, nil} -> {:error, %{reason: "unauthorized"}}
      {:owner, false} -> {:error, %{reason: "unauthorized"}}
      {:capacity, {:error, :limit_reached}} -> {:error, %{reason: "capacity_reached"}}
    end
  end
```

Add a private helper right after `join/3`:

```elixir
  defp join_payload(user) do
    tuning = Speechwave.ExtensionTuning.current()

    %{
      settings: %{
        overlay_size_percent: user.overlay_size_percent || tuning.default_overlay_size_percent,
        fireworks_enabled: user.fireworks_enabled
      },
      tuning: tuning
    }
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/speechwave_web/channels/reaction_channel_test.exs`
Expected: PASS (all tests, including the 2 new ones)

- [ ] **Step 5: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
git add lib/speechwave_web/channels/reaction_channel.ex test/speechwave_web/channels/reaction_channel_test.exs
git commit -m "feat: deliver user settings and tuning config in reactions channel join reply"
```

---

### Task 4: Settings page UI

**Files:**
- Modify: `lib/speechwave_web/live/user_live/settings.ex`
- Modify: `test/speechwave_web/live/user_live/settings_test.exs`

**Interfaces:**
- Consumes: `Accounts.change_extension_settings/2`, `Accounts.update_extension_settings/2` (Task 2); `Speechwave.ExtensionTuning.current/0` (Task 1).
- Produces: form `id="extension_settings_form"` on `/users/settings`. No downstream consumer within this plan — this is the user-facing entry point.

- [ ] **Step 1: Write the failing tests**

Append to `test/speechwave_web/live/user_live/settings_test.exs`:

```elixir
  describe "extension settings form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders the tuning module's default percent when unset", %{conn: conn} do
      default = Speechwave.ExtensionTuning.current().default_overlay_size_percent
      {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Overlay size (#{default}%)"
    end

    test "updates overlay size and fireworks toggle", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      lv
      |> form("#extension_settings_form", %{
        "user" => %{"overlay_size_percent" => "45", "fireworks_enabled" => "false"}
      })
      |> render_submit()

      updated = Speechwave.Repo.get!(Speechwave.Accounts.User, user.id)
      assert updated.overlay_size_percent == 45
      assert updated.fireworks_enabled == false
    end

    test "rejects an overlay size below the tuning minimum", %{conn: conn} do
      min = Speechwave.ExtensionTuning.current().min_overlay_size_percent
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#extension_settings_form", %{
          "user" => %{"overlay_size_percent" => to_string(min - 1), "fireworks_enabled" => "true"}
        })
        |> render_change()

      assert result =~ "must be greater than or equal to #{min}"
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/speechwave_web/live/user_live/settings_test.exs`
Expected: FAIL — no `#extension_settings_form` exists yet.

- [ ] **Step 3: Add the UI section**

Modify `lib/speechwave_web/live/user_live/settings.ex`. In `render/1`, insert this new section right after the API Key section's closing `</div>` and before the `<div class="divider" />` that precedes "Email preferences":

```heex
      <div class="divider" />

      <%!-- Extension overlay settings --%>
      <div class="space-y-2">
        <h3 class="font-semibold text-base-content">Presentation overlay</h3>
        <p class="text-sm text-base-content/70">
          Controls the emoji-reaction overlay in the Speechwave browser extension.
          Applies the next time you connect during a talk.
        </p>
        <.form
          for={@extension_settings_form}
          id="extension_settings_form"
          phx-submit="update_extension_settings"
          phx-change="validate_extension_settings"
        >
          <.input
            field={@extension_settings_form[:overlay_size_percent]}
            type="range"
            min={@tuning.min_overlay_size_percent}
            max="100"
            label={"Overlay size (#{@extension_settings_form[:overlay_size_percent].value}%)"}
          />
          <.input
            field={@extension_settings_form[:fireworks_enabled]}
            type="checkbox"
            label="Fireworks animations"
          />
          <.button variant="primary" phx-disable-with="Saving...">Save</.button>
        </.form>
      </div>
```

- [ ] **Step 4: Assign the new socket state in `mount/3`**

Modify the no-token `mount/3` clause in the same file:

```elixir
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    marketing_consent = Accounts.get_consent(user, "marketing_email")
    tuning = Speechwave.ExtensionTuning.current()
    resolved_percent = user.overlay_size_percent || tuning.default_overlay_size_percent

    extension_settings_changeset =
      Accounts.change_extension_settings(user, %{overlay_size_percent: resolved_percent})

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:api_key, user.api_key)
      |> assign(:identities, Accounts.list_user_identities(user))
      |> assign(:marketing_consent, marketing_consent)
      |> assign(:tuning, tuning)
      |> assign(:extension_settings_form, to_form(extension_settings_changeset))

    {:ok, socket}
  end
```

- [ ] **Step 5: Add the event handlers**

Add these two `handle_event` clauses (anywhere alongside the other `handle_event` clauses):

```elixir
  def handle_event("validate_extension_settings", %{"user" => params}, socket) do
    form =
      socket.assigns.current_scope.user
      |> Accounts.change_extension_settings(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :extension_settings_form, form)}
  end

  def handle_event("update_extension_settings", %{"user" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_extension_settings(user, params) do
      {:ok, _updated} ->
        {:noreply, put_flash(socket, :info, "Overlay settings saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :extension_settings_form, to_form(changeset))}
    end
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/speechwave_web/live/user_live/settings_test.exs`
Expected: PASS (all tests, including the 3 new ones)

- [ ] **Step 7: Run the full backend test suite and precommit**

Run: `mix precommit`
Expected: PASS — this runs the full test suite plus formatting/credo checks per the project's standard alias. Fix any issues it surfaces before continuing.

- [ ] **Step 8: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/speechwave
git add lib/speechwave_web/live/user_live/settings.ex test/speechwave_web/live/user_live/settings_test.exs
git commit -m "feat: add overlay size and fireworks settings to the account Settings page"
```

---

### Task 5: `background.js` — capture, cache, and relay remote config

**Files:**
- Modify: `background/background.js`
- Modify: `tests/background.test.js`

**Interfaces:**
- Consumes: channel join payload shape from Task 3 (works against the mocked `MockChannel` in tests; the real shape only exists once the `speechwave` repo change from Task 3 is deployed — see Global Constraints' rollout-ordering note in the spec, this extension code degrades safely either way).
- Produces: `SET_REMOTE_CONFIG` broadcast (`{ type: 'SET_REMOTE_CONFIG', settings, tuning }`) to all matching Slides tabs after every successful join; `GET_REMOTE_CONFIG` request/response (background replies with last-known or default `{settings, tuning}`). Consumed by Task 6 (`content.js`).

- [ ] **Step 1: Write the failing tests**

Replace the existing `describe("SET_FIREWORKS", ...)` block (lines 278–324 of `tests/background.test.js`) — delete it entirely, it tests a message type this task removes — and add these two new `describe` blocks in its place:

```javascript
// ---------------------------------------------------------------------------
// Remote config: capture on join, broadcast, and GET_REMOTE_CONFIG
// ---------------------------------------------------------------------------

describe("remote config from channel join", () => {
  test("broadcasts SET_REMOTE_CONFIG to Slides tabs when join succeeds with settings/tuning", () => {
    const { messageHandler } = loadBackground();

    chrome.tabs.query.mockImplementation((_query, callback) => {
      callback([{ id: 5 }]);
    });

    messageHandler({ type: "SET_SLUG", slug: "talk", apiKey: "key" }, {}, jest.fn());

    const payload = {
      settings: { overlay_size_percent: 35, fireworks_enabled: false },
      tuning: { min_overlay_size_percent: 10 },
    };
    mockChannel.joinReceiveHandlers["ok"](payload);

    expect(chrome.tabs.sendMessage).toHaveBeenCalledWith(
      5,
      { type: "SET_REMOTE_CONFIG", settings: payload.settings, tuning: payload.tuning },
      expect.any(Function)
    );
  });

  test("does not broadcast SET_REMOTE_CONFIG when the join payload has no settings/tuning", () => {
    const { messageHandler } = loadBackground();

    chrome.tabs.query.mockImplementation((_query, callback) => {
      callback([{ id: 5 }]);
    });

    messageHandler({ type: "SET_SLUG", slug: "talk", apiKey: "key" }, {}, jest.fn());
    mockChannel.joinReceiveHandlers["ok"]({});

    expect(chrome.tabs.sendMessage).not.toHaveBeenCalled();
  });

  test("still resolves onResult with connected: true when join payload has no settings/tuning", () => {
    const { messageHandler } = loadBackground();
    const sendResponse = jest.fn();

    messageHandler({ type: "SET_SLUG", slug: "talk", apiKey: "key" }, {}, sendResponse);
    mockChannel.joinReceiveHandlers["ok"]({});

    expect(sendResponse).toHaveBeenCalledWith({ connected: true });
  });
});

describe("GET_REMOTE_CONFIG", () => {
  test("returns hardcoded defaults when never connected", () => {
    const { messageHandler } = loadBackground();
    const sendResponse = jest.fn();

    messageHandler({ type: "GET_REMOTE_CONFIG" }, {}, sendResponse);

    expect(sendResponse).toHaveBeenCalledWith({
      settings: { overlay_size_percent: 20, fireworks_enabled: true },
      tuning: expect.objectContaining({ min_overlay_size_percent: 10 }),
    });
  });

  test("returns last-known config after a successful join", () => {
    const { messageHandler } = loadBackground();

    messageHandler({ type: "SET_SLUG", slug: "talk", apiKey: "key" }, {}, jest.fn());

    const payload = {
      settings: { overlay_size_percent: 60, fireworks_enabled: false },
      tuning: { min_overlay_size_percent: 10 },
    };
    mockChannel.joinReceiveHandlers["ok"](payload);

    const sendResponse = jest.fn();
    messageHandler({ type: "GET_REMOTE_CONFIG" }, {}, sendResponse);

    expect(sendResponse).toHaveBeenCalledWith(payload);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/background.test.js`
Expected: FAIL — `SET_REMOTE_CONFIG`/`GET_REMOTE_CONFIG` don't exist yet; the two deleted `SET_FIREWORKS` tests are gone so they won't show as failures.

- [ ] **Step 3: Add state and the default config**

Modify `background/background.js`. Add after the existing `let debugEnabled = false;` (in the `--- State ---` block):

```javascript
let lastKnownSettings = null;
let lastKnownTuning = null;

const DEFAULT_REMOTE_CONFIG = {
  settings: { overlay_size_percent: 20, fireworks_enabled: true },
  tuning: {
    default_overlay_size_percent: 20,
    min_overlay_size_percent: 10,
    overlay_margin_px: 8,
    emoji_font_size_ratio: 0.14,
    firework_font_size_ratio: 0.12,
    firework_center_x_ratio: 0.5,
    firework_center_y_ratio: 0.5,
    firework_spread_min_ratio: 0.375,
    firework_spread_range_ratio: 0.25,
    emoji_rise_ratio: 0.3,
  },
};
```

- [ ] **Step 4: Capture and broadcast on join**

Modify the `c.join()` call inside `connect()`:

```javascript
  c.join()
    .receive('ok', (payload) => {
      console.info(`[Speechwave SW] Joined reactions:${slug}`);
      if (payload && payload.settings && payload.tuning) {
        lastKnownSettings = payload.settings;
        lastKnownTuning = payload.tuning;
        broadcastToSlidesTabs({
          type: 'SET_REMOTE_CONFIG',
          settings: lastKnownSettings,
          tuning: lastKnownTuning,
        });
      }
      if (onResult) onResult({ connected: true });
    })
```

- [ ] **Step 5: Add the `GET_REMOTE_CONFIG` handler and remove `SET_FIREWORKS`**

In the `chrome.runtime.onMessage.addListener` block, remove this existing branch entirely:

```javascript
  } else if (msg.type === 'SET_FIREWORKS') {
    broadcastToSlidesTabs({ type: 'SET_FIREWORKS', enabled: msg.enabled });
    // no sendResponse needed
```

Add this branch in its place:

```javascript
  } else if (msg.type === 'GET_REMOTE_CONFIG') {
    sendResponse({
      settings: lastKnownSettings || DEFAULT_REMOTE_CONFIG.settings,
      tuning: lastKnownTuning || DEFAULT_REMOTE_CONFIG.tuning,
    });
    // synchronous — no `return true` needed
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `npx jest tests/background.test.js`
Expected: PASS (all tests)

- [ ] **Step 7: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/chrome-extension
git add background/background.js tests/background.test.js
git commit -m "feat: capture and relay remote config from channel join, add GET_REMOTE_CONFIG"
```

---

### Task 6: `content.js` — consume remote config (fireworks toggle)

**Files:**
- Modify: `content/content.js`
- Modify: `tests/content.test.js`

**Interfaces:**
- Consumes: `SET_REMOTE_CONFIG`/`GET_REMOTE_CONFIG` from Task 5.
- Produces: module-level `remoteConfig` variable (shape `{settings, tuning}`, canonical shape from Global Constraints), kept in sync via `SET_REMOTE_CONFIG` and an initial `GET_REMOTE_CONFIG` pull. Consumed by Task 7 (sizing math — not touched in this task).

This task only changes where `fireworksEnabled` gets its value from. Box sizing (`syncOverlayPosition`, `spawnEmoji`, `spawnFireworks`) is untouched here — Task 7 handles that separately.

- [ ] **Step 1: Write the failing tests**

Add this new `describe` block to `tests/content.test.js` (anywhere after the `beforeEach`, e.g. right before `describe("overlay", ...)`):

```javascript
describe("remote config", () => {
  test("requests GET_REMOTE_CONFIG on load", () => {
    loadContent();

    const call = chrome.runtime.sendMessage.mock.calls.find(
      ([msg]) => msg.type === "GET_REMOTE_CONFIG"
    );
    expect(call).toBeDefined();
  });

  test("SET_REMOTE_CONFIG with fireworks_enabled: false suppresses firework triggering", () => {
    const { messageHandler } = loadContent();

    messageHandler(
      {
        type: "SET_REMOTE_CONFIG",
        settings: { overlay_size_percent: 20, fireworks_enabled: false },
        tuning: { min_overlay_size_percent: 10 },
      },
      {},
      jest.fn()
    );

    for (let i = 0; i < 6; i++) {
      messageHandler({ type: "RENDER_EMOJI", emoji: "🎉" }, {}, jest.fn());
    }

    expect(Element.prototype.animate).not.toHaveBeenCalled();
  });

  test("SET_REMOTE_CONFIG with fireworks_enabled: true allows firework triggering", () => {
    const { messageHandler } = loadContent();

    messageHandler(
      {
        type: "SET_REMOTE_CONFIG",
        settings: { overlay_size_percent: 20, fireworks_enabled: true },
        tuning: { min_overlay_size_percent: 10 },
      },
      {},
      jest.fn()
    );

    for (let i = 0; i < 6; i++) {
      messageHandler({ type: "RENDER_EMOJI", emoji: "🎉" }, {}, jest.fn());
    }

    expect(Element.prototype.animate).toHaveBeenCalled();
  });

  test("defaults to fireworks enabled before any config arrives", () => {
    const { messageHandler } = loadContent();

    for (let i = 0; i < 6; i++) {
      messageHandler({ type: "RENDER_EMOJI", emoji: "🎉" }, {}, jest.fn());
    }

    expect(Element.prototype.animate).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/content.test.js`
Expected: FAIL — `content.js` doesn't send `GET_REMOTE_CONFIG` or handle `SET_REMOTE_CONFIG` yet; fireworks currently default to `false` (via the old `chrome.storage.sync` mock returning `{fireworksEnabled: false}`), so the "defaults to fireworks enabled" test also fails against current code.

- [ ] **Step 3: Add `DEFAULT_CONFIG` and the `remoteConfig` variable**

Modify `content/content.js`. Add near the top, after the existing tuning-related constants block (`OVERLAY_MAX_Z_INDEX` etc. — leave those untouched, Task 7 removes them):

```javascript
const DEFAULT_CONFIG = {
  settings: { overlay_size_percent: 20, fireworks_enabled: true },
  tuning: {
    default_overlay_size_percent: 20,
    min_overlay_size_percent: 10,
    overlay_margin_px: 8,
    emoji_font_size_ratio: 0.14,
    firework_font_size_ratio: 0.12,
    firework_center_x_ratio: 0.5,
    firework_center_y_ratio: 0.5,
    firework_spread_min_ratio: 0.375,
    firework_spread_range_ratio: 0.25,
    emoji_rise_ratio: 0.3,
  },
};

let remoteConfig = DEFAULT_CONFIG;
```

Change `let fireworksEnabled = false;` to:

```javascript
let fireworksEnabled = DEFAULT_CONFIG.settings.fireworks_enabled;
```

- [ ] **Step 4: Handle `SET_REMOTE_CONFIG`, remove `SET_FIREWORKS`**

In the `chrome.runtime.onMessage.addListener` block, remove:

```javascript
  } else if (msg.type === "SET_FIREWORKS") {
    fireworksEnabled = msg.enabled;
```

Replace it with:

```javascript
  } else if (msg.type === "SET_REMOTE_CONFIG") {
    remoteConfig = { settings: msg.settings, tuning: msg.tuning };
    fireworksEnabled = remoteConfig.settings.fireworks_enabled;
```

- [ ] **Step 5: Replace the `chrome.storage.sync` fireworks read with `GET_REMOTE_CONFIG`**

At the bottom of `content/content.js`, remove:

```javascript
chrome.storage.sync.get({ fireworksEnabled: true }, ({ fireworksEnabled: val }) => {
  fireworksEnabled = val;
});
```

Replace it with:

```javascript
chrome.runtime.sendMessage({ type: "GET_REMOTE_CONFIG" }, (response) => {
  if (chrome.runtime.lastError) return;
  if (response && response.settings && response.tuning) {
    remoteConfig = response;
    fireworksEnabled = remoteConfig.settings.fireworks_enabled;
  }
});
```

- [ ] **Step 6: Remove the now-unused `chrome.storage.sync.get` mock from the test helper**

In `tests/content.test.js`'s `loadContent()` function, remove this line (it configured a mock for the storage call `content.js` no longer makes):

```javascript
  chrome.storage.sync.get.mockImplementation((_keys, callback) => {
    callback({ fireworksEnabled: false });
  });
```

Leave the rest of `loadContent()` unchanged. The default `chrome.runtime.sendMessage` mock already in `loadContent()` calls back with no payload for any message, which the new `GET_REMOTE_CONFIG` handler in Step 5 correctly ignores (`if (response && ...)` guards against `undefined`), so `remoteConfig` stays at `DEFAULT_CONFIG` in tests that don't explicitly send `SET_REMOTE_CONFIG` — no other test changes needed for this.

- [ ] **Step 7: Run tests to verify they pass**

Run: `npx jest tests/content.test.js`
Expected: PASS (all tests — including all pre-existing ones, since `DEFAULT_CONFIG.settings.fireworks_enabled` is `true` and no existing test relied on the old `false` default)

- [ ] **Step 8: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/chrome-extension
git add content/content.js tests/content.test.js
git commit -m "feat: consume fireworks setting from remote config instead of local storage"
```

---

### Task 7: `content.js` — percent-of-slide-dimension sizing math

**Files:**
- Modify: `content/content.js`
- Modify: `tests/content.test.js`

**Interfaces:**
- Consumes: `remoteConfig.settings.overlay_size_percent`, `remoteConfig.tuning.*` (Task 6).
- Produces: final overlay sizing/positioning and emoji/firework proportions. No downstream consumer within this plan.

- [ ] **Step 1: Write the failing tests**

In `tests/content.test.js`, delete the entire `describe("overlay position relative to the presentation iframe", ...)` block and the entire `describe("overlay and emoji scale with the slide's rendered size", ...)` block (both test the now-removed `overlayScale`/reference-width mechanism). Replace them with:

```javascript
const FULL_TUNING = {
  default_overlay_size_percent: 20,
  min_overlay_size_percent: 10,
  overlay_margin_px: 8,
  emoji_font_size_ratio: 0.14,
  firework_font_size_ratio: 0.12,
  firework_center_x_ratio: 0.5,
  firework_center_y_ratio: 0.5,
  firework_spread_min_ratio: 0.375,
  firework_spread_range_ratio: 0.25,
  emoji_rise_ratio: 0.3,
};

describe("overlay sizing: percent of the slide's actual dimensions", () => {
  function addPresentIframe(rect) {
    const iframe = document.createElement("iframe");
    iframe.className = "punch-present-iframe";
    iframe.getBoundingClientRect = jest.fn().mockReturnValue(rect);
    document.body.appendChild(iframe);
    return iframe;
  }

  function setRemoteConfig(messageHandler, { percent, fireworksEnabled = true, tuning = FULL_TUNING }) {
    messageHandler(
      {
        type: "SET_REMOTE_CONFIG",
        settings: { overlay_size_percent: percent, fireworks_enabled: fireworksEnabled },
        tuning,
      },
      {},
      jest.fn()
    );
  }

  test("falls back to a fixed viewport corner (tuning margin) when no presentation iframe is present", () => {
    loadContent();
    const overlay = document.getElementById("speechwave-overlay");
    expect(overlay.style.right).toBe("8px"); // DEFAULT_CONFIG.tuning.overlay_margin_px
    expect(overlay.style.bottom).toBe("8px");
    expect(overlay.style.left).toBe("");
    expect(overlay.style.top).toBe("");
  });

  test("sizes the overlay to overlay_size_percent of the slide's actual dimensions", () => {
    addPresentIframe({ left: 0, top: 0, right: 1000, bottom: 500, width: 1000, height: 500 });
    loadContent();

    const overlay = document.getElementById("speechwave-overlay");
    // DEFAULT_CONFIG.settings.overlay_size_percent = 20
    expect(overlay.style.width).toBe("200px"); // 1000 * 0.2
    expect(overlay.style.height).toBe("100px"); // 500 * 0.2
    // left: 1000 - 200 - 8 (margin) = 792; top: 500 - 100 - 8 = 392
    expect(overlay.style.left).toBe("792px");
    expect(overlay.style.top).toBe("392px");
  });

  test("covers the entire slide edge-to-edge at 100%, without margin overflow", () => {
    addPresentIframe({ left: 0, top: 0, right: 800, bottom: 600, width: 800, height: 600 });
    const { messageHandler } = loadContent();

    setRemoteConfig(messageHandler, { percent: 100 });
    messageHandler({ type: "RENDER_EMOJI", emoji: "🎉" }, {}, jest.fn());

    const overlay = document.getElementById("speechwave-overlay");
    expect(overlay.style.width).toBe("800px");
    expect(overlay.style.height).toBe("600px");
    expect(overlay.style.left).toBe("0px");
    expect(overlay.style.top).toBe("0px");
  });

  test("clamps overlay_size_percent up to the tuning minimum if a low value ever arrives", () => {
    addPresentIframe({ left: 0, top: 0, right: 1000, bottom: 500, width: 1000, height: 500 });
    const { messageHandler } = loadContent();

    setRemoteConfig(messageHandler, { percent: 2 }); // below FULL_TUNING.min_overlay_size_percent (10)
    messageHandler({ type: "RENDER_EMOJI", emoji: "🎉" }, {}, jest.fn());

    const overlay = document.getElementById("speechwave-overlay");
    expect(overlay.style.width).toBe("100px"); // clamped to 10% of 1000, not 2%
  });

  test("scales emoji font size and rise distance with the box's actual height", () => {
    addPresentIframe({ left: 0, top: 0, right: 1000, bottom: 500, width: 1000, height: 500 });
    const { messageHandler } = loadContent();

    setRemoteConfig(messageHandler, { percent: 20 });
    messageHandler({ type: "RENDER_EMOJI", emoji: "🎉" }, {}, jest.fn());

    const span = document.getElementById("speechwave-overlay").querySelector("span");
    // box height: 500 * 0.2 = 100; font-size: 100 * 0.14 = 14
    expect(span.style.fontSize).toBe("14px");
    // rise: 100 * 0.3 = 30
    expect(span.style.getPropertyValue("--rise")).toBe("30px");
  });

  test("scales firework center and font size with the box's actual dimensions", () => {
    addPresentIframe({ left: 0, top: 0, right: 1000, bottom: 500, width: 1000, height: 500 });
    const { messageHandler } = loadContent();

    setRemoteConfig(messageHandler, { percent: 20 });
    messageHandler({ type: "TEST_FIREWORKS" }, {}, jest.fn());

    const span = document.getElementById("speechwave-overlay").querySelector("span");
    // box: width 200, height 100; center: (200*0.5, 100*0.5) = (100, 50)
    expect(span.style.left).toBe("100px");
    expect(span.style.top).toBe("50px");
    // font-size: 100 (height) * 0.12 = 12
    expect(span.style.fontSize).toBe("12px");
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx jest tests/content.test.js`
Expected: FAIL — the sizing math hasn't changed yet, so computed pixel values don't match the new percent-based expectations.

- [ ] **Step 3: Remove the old sizing constants and `overlayScale`**

In `content/content.js`, delete these constants entirely (all now superseded by `remoteConfig`):

```javascript
const SLIDE_REFERENCE_WIDTH = 960;
const MIN_OVERLAY_SCALE = 0.4;
const MAX_OVERLAY_SCALE = 2;

const OVERLAY_WIDTH = 160;
const OVERLAY_HEIGHT = 200;
const OVERLAY_RIGHT_MARGIN = 20;
const OVERLAY_BOTTOM_MARGIN = 20;
const EMOJI_FONT_SIZE = 28;
const FIREWORK_FONT_SIZE = 24;
const FIREWORK_CENTER_X = 80;
const FIREWORK_CENTER_Y = 100;
const FIREWORK_MIN_DISTANCE = 60;
const FIREWORK_DISTANCE_RANGE = 40;
```

Keep `OVERLAY_MAX_Z_INDEX` — it's still used. Delete `let overlayScale = 1;`.

- [ ] **Step 4: Update the CSS keyframe to use a configurable rise distance**

Modify the `style.textContent` block near the top of the file:

```javascript
const style = document.createElement("style");
style.textContent = `
  @keyframes speechwaveFloat {
    0%   { transform: translateY(0);    opacity: 1; }
    100% { transform: translateY(calc(-1 * var(--rise, 60px))); opacity: 0; }
  }
`;
document.head.appendChild(style);
```

- [ ] **Step 5: Rewrite `syncOverlayPosition`**

Replace the whole function:

```javascript
function syncOverlayPosition(overlay) {
  const iframe = getPresentIframe();
  const rect = iframe && (getSlideRect(iframe) || iframe.getBoundingClientRect());
  const tuning = remoteConfig.tuning;

  if (rect) {
    const percent = Math.max(
      remoteConfig.settings.overlay_size_percent,
      tuning.min_overlay_size_percent
    );
    const slideWidth = rect.right - rect.left;
    const slideHeight = rect.bottom - rect.top;
    const width = slideWidth * (percent / 100);
    const height = slideHeight * (percent / 100);
    // Clamp margin so the box never overflows the slide's opposite edges —
    // at percent close to 100 there isn't room for the full configured margin.
    const marginX = Math.min(tuning.overlay_margin_px, slideWidth - width);
    const marginY = Math.min(tuning.overlay_margin_px, slideHeight - height);

    overlay.style.width = `${width}px`;
    overlay.style.height = `${height}px`;
    overlay.style.left = `${rect.right - width - marginX}px`;
    overlay.style.top = `${rect.bottom - height - marginY}px`;
    overlay.style.right = "";
    overlay.style.bottom = "";
    overlay.style.zIndex = OVERLAY_MAX_Z_INDEX;
  } else {
    overlay.style.width = "";
    overlay.style.height = "";
    overlay.style.left = "";
    overlay.style.top = "";
    overlay.style.right = `${tuning.overlay_margin_px}px`;
    overlay.style.bottom = `${tuning.overlay_margin_px}px`;
    overlay.style.zIndex = 999999;
  }
}
```

- [ ] **Step 6: Rewrite `spawnEmoji`'s sizing**

Modify `spawnEmoji` — replace the `el.style.cssText` assignment and add the `--rise` custom property:

```javascript
function spawnEmoji(emoji) {
  inFlight[emoji] = (inFlight[emoji] || 0) + 1;

  const overlay = getOrCreateOverlay();
  const boxHeight = parseFloat(overlay.style.height) || 0;
  const tuning = remoteConfig.tuning;

  const el = document.createElement("span");
  el.textContent = emoji;
  el.style.cssText = [
    "position: absolute",
    "bottom: 0",
    `left: ${Math.floor(Math.random() * 70)}%`,
    `font-size: ${boxHeight * tuning.emoji_font_size_ratio}px`,
    "animation: speechwaveFloat 2.5s ease-out forwards",
    "pointer-events: none",
  ].join(";");
  el.style.setProperty("--rise", `${boxHeight * tuning.emoji_rise_ratio}px`);
  overlay.appendChild(el);
  el.addEventListener("animationend", () => {
    el.remove();
    inFlight[emoji] = Math.max(0, (inFlight[emoji] || 0) - 1);
    if (inFlight[emoji] === 0) delete inFlight[emoji];
  });

  maybeSpawnFireworks(emoji);
}
```

- [ ] **Step 7: Rewrite `spawnFireworks`'s sizing**

Modify `spawnFireworks` — replace the `cx`/`cy` computation and the `dist`/font-size lines inside the loop:

```javascript
function spawnFireworks(emoji) {
  fireworksActive = true;
  lastFireworksTime = Date.now();

  if (FIREWORKS_BURST_COUNT === 0) {
    fireworksActive = false;
    return;
  }

  const overlay = getOrCreateOverlay();
  const boxWidth = parseFloat(overlay.style.width) || 0;
  const boxHeight = parseFloat(overlay.style.height) || 0;
  const tuning = remoteConfig.tuning;
  const cx = boxWidth * tuning.firework_center_x_ratio;
  const cy = boxHeight * tuning.firework_center_y_ratio;
  const spreadBase = Math.min(boxWidth, boxHeight);
  let remaining = FIREWORKS_BURST_COUNT;
  const safetyTimer = setTimeout(() => { fireworksActive = false; }, 2000);

  for (let i = 0; i < FIREWORKS_BURST_COUNT; i++) {
    const angle = (i / FIREWORKS_BURST_COUNT) * 2 * Math.PI;
    const dist =
      spreadBase * (tuning.firework_spread_min_ratio + Math.random() * tuning.firework_spread_range_ratio);
    const tx = Math.round(Math.cos(angle) * dist);
    const ty = Math.round(Math.sin(angle) * dist);
    const delay = Math.random() * 300;

    const el = document.createElement("span");
    el.textContent = emoji;
    el.style.cssText = [
      "position: absolute",
      `left: ${cx}px`,
      `top: ${cy}px`,
      `font-size: ${boxHeight * tuning.firework_font_size_ratio}px`,
      "pointer-events: none",
    ].join(";");
    overlay.appendChild(el);

    const anim = el.animate(
      [
        { transform: "translate(0, 0) scale(1)", opacity: 1 },
        { transform: `translate(${tx}px, ${ty}px) scale(0.3)`, opacity: 0 },
      ],
      { duration: 1200, delay, easing: "ease-out", fill: "forwards" }
    );
    anim.addEventListener("finish", () => {
      el.remove();
      remaining--;
      if (remaining === 0) {
        clearTimeout(safetyTimer);
        fireworksActive = false;
      }
    });
  }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `npx jest tests/content.test.js`
Expected: PASS (all tests)

- [ ] **Step 9: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/chrome-extension
git add content/content.js tests/content.test.js
git commit -m "feat: size overlay as a percentage of the slide's actual dimensions"
```

---

### Task 8: Remove the popup fireworks toggle

**Files:**
- Modify: `popup/popup.html`
- Modify: `popup/popup.js`
- Modify: `tests/popup.test.js`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — pure removal, now redundant with the Settings-page toggle from Task 4.

- [ ] **Step 1: Remove the toggle from `popup.html`**

In `popup/popup.html`, remove this block entirely (inside the settings/toggle `<div>`, right before `test-fireworks-btn`):

```html
      <label style="display: flex; align-items: flex-start; gap: 6px; cursor: pointer;">
        <input type="checkbox" id="fireworks-toggle" style="margin-top: 1px;">
        <span style="font-size: 11px; color: #5f6368;">Fireworks animations</span>
      </label>
```

`test-fireworks-btn` and the `debug-toggle-label`/`debug-toggle` block stay untouched.

- [ ] **Step 2: Remove the toggle's wiring from `popup.js`**

In `popup/popup.js`, remove this line from the `--- DOM references ---` block:

```javascript
const fireworksToggle = document.getElementById("fireworks-toggle");
```

Remove this entire block (the `--- Fireworks ---` section):

```javascript
// --- Fireworks ---
chrome.storage.sync.get({ fireworksEnabled: true }, ({ fireworksEnabled }) => {
  fireworksToggle.checked = fireworksEnabled;
});

fireworksToggle.addEventListener("change", () => {
  const enabled = fireworksToggle.checked;
  chrome.storage.sync.set({ fireworksEnabled: enabled });
  chrome.runtime.sendMessage({ type: "SET_FIREWORKS", enabled }, () => {
    void chrome.runtime.lastError;
  });
});
```

- [ ] **Step 3: Remove the toggle from the test fixture**

In `tests/popup.test.js`, in the `POPUP_HTML` template string, remove:

```html
    <input type="checkbox" id="fireworks-toggle" />
```

- [ ] **Step 4: Run the popup test suite to verify nothing broke**

Run: `npx jest tests/popup.test.js`
Expected: PASS (all existing tests — none reference `fireworks-toggle`, so this is a pure regression check, not a new-test cycle)

- [ ] **Step 5: Run the full extension test suite**

Run: `npx jest`
Expected: PASS (all test suites — `content.test.js`, `background.test.js`, `popup.test.js`, `adapter_registry.test.js`, `google_slides_adapter.test.js`, `fireworks.test.js`)

- [ ] **Step 6: Commit**

```bash
cd /Users/tracy/projects/speechwave-live/chrome-extension
git add popup/popup.html popup/popup.js tests/popup.test.js
git commit -m "chore: remove popup fireworks toggle, now on the account Settings page"
```

---

## After all 8 tasks: manual live verification

None of the automated tests above can verify actual rendering — jsdom doesn't paint pixels. Per the spec, this is unavoidable and was true throughout the original overlay-anchoring work this plan builds on. Before considering this done:

1. Run the local backend (`mix phx.server`), set an `overlay_size_percent` on the Settings page (e.g. 15%, 50%, 100%), and reload the extension with `bin/dev_mode_on` pointed at `localhost:4000`.
2. Open a real Google Slides deck in windowed present mode. Confirm the overlay box visually matches the chosen percentage of the slide, anchored to the bottom-right corner, and that 100% genuinely covers the slide edge-to-edge without overflowing past it.
3. Toggle the fireworks setting on the Settings page, Disconnect/Connect in the popup (not reload the extension), and confirm the change takes effect — this is the "avoid a new extension version" loop the whole `ExtensionTuning` design exists for.
4. Edit a value in `Speechwave.ExtensionTuning.current/0` (e.g. `overlay_margin_px`), let the dev code reloader pick it up, Disconnect/Connect again, and confirm the visual change — this exercises the actual fast-iteration loop this feature was built to enable.
5. Spot-check OS-fullscreen present mode too, to confirm nothing here regressed the `fullscreenchange` reparenting path from the earlier session's work.
