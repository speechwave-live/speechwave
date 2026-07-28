defmodule SpeechwaveWeb.UserLive.Settings do
  use SpeechwaveWeb, :live_view

  alias Speechwave.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your email and connected accounts</:subtitle>
        </.header>
      </div>

      <%!-- Email section --%>
      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button id="change-email-btn" variant="primary" phx-disable-with="Changing...">
          Change Email
        </.button>
      </.form>

      <div class="divider" />

      <%!-- Connected OAuth accounts --%>
      <div id="connected-accounts" class="space-y-4">
        <h3 class="font-semibold text-base-content">Connected accounts</h3>
        <p class="text-sm text-base-content/70">
          Sign in faster using a linked account. Magic link is always available as a fallback.
        </p>

        <div class="space-y-2">
          <%= for provider <- ["google", "microsoft", "github"] do %>
            <% identity = Enum.find(@identities, &(&1.provider == provider)) %>
            <div
              id={"identity-#{provider}"}
              class="flex items-center justify-between p-3 rounded-lg border border-base-300"
            >
              <span class="font-medium capitalize">{provider}</span>
              <%= if identity do %>
                <button
                  id={"disconnect-#{provider}"}
                  phx-click="disconnect_identity"
                  phx-value-id={identity.id}
                  data-confirm={"Disconnect your #{provider} account?"}
                  class="text-sm text-error hover:underline"
                >
                  Disconnect
                </button>
              <% else %>
                <.link
                  id={"connect-#{provider}"}
                  href={~p"/auth/#{provider}"}
                  class="text-sm text-primary hover:underline"
                >
                  Connect
                </.link>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <div class="divider" />

      <%!-- API Key section --%>
      <div class="space-y-2">
        <h3 class="font-semibold text-base-content">Browser Extension API Key</h3>
        <p class="text-sm text-base-content/70">
          Paste this key into the Speechwave browser extension to authenticate.
          Keep it secret.
        </p>
        <div class="flex gap-2 items-center">
          <input
            id="api-key-display"
            type="text"
            readonly
            value={@api_key}
            class="flex-1 font-mono text-sm px-3 py-2 rounded-lg border border-base-300 bg-base-200 text-base-content"
            phx-hook=".SelectOnClick"
          />
          <button
            id="copy-api-key-btn"
            type="button"
            phx-hook="CopyToClipboard"
            data-clipboard-text={@api_key}
            data-flash-message="API key copied to clipboard"
            title="Copy API key"
            class="shrink-0 p-2 text-base-content/40 hover:text-base-content rounded-lg border border-base-300 hover:bg-base-200 transition-colors"
          >
            <.icon name="hero-clipboard-document" class="copy-icon-idle w-4 h-4" />
            <.icon
              name="hero-clipboard-document-check"
              class="copy-icon-copied hidden w-4 h-4 text-green-600"
            />
          </button>
          <button
            id="regenerate-api-key-btn"
            phx-click="regenerate_api_key"
            data-confirm="Regenerate your API key? Any active extension connections will be disconnected immediately."
            class="px-4 py-2 text-sm font-medium rounded-lg border border-base-300 hover:bg-base-200 transition-colors"
          >
            Regenerate
          </button>
        </div>
      </div>

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
            field={@extension_settings_form[:customize_overlay_size]}
            type="checkbox"
            label="Customize overlay size"
          />
          <.input
            field={@extension_settings_form[:overlay_size_percent]}
            type="range"
            min={@tuning.min_overlay_size_percent}
            max="100"
            label={"Overlay size (#{@extension_settings_form[:overlay_size_percent].value}%)"}
            class="range range-primary w-full"
            error_class="range-error"
            phx-debounce="100"
            disabled={
              !Phoenix.HTML.Form.normalize_value(
                "checkbox",
                @extension_settings_form[:customize_overlay_size].value
              )
            }
          />
          <.input
            field={@extension_settings_form[:fireworks_enabled]}
            type="checkbox"
            label="Fireworks animations"
          />
          <.button id="save-extension-settings-btn" variant="primary" phx-disable-with="Saving...">
            Save
          </.button>
        </.form>
      </div>

      <div class="divider" />

      <%!-- Email preferences section --%>
      <div
        id="email-prefs-section"
        data-consented={to_string(@marketing_consent != nil and @marketing_consent.granted)}
      >
        <h3 class="font-semibold text-base-content">Email preferences</h3>
        <div class="space-y-2 mt-2">
          <p class="text-sm font-medium text-base-content">Product updates &amp; announcements</p>
          <%= if @marketing_consent != nil and @marketing_consent.granted do %>
            <p class="text-sm text-base-content/70">
              You're subscribed. We'll let you know about new features and product updates.
            </p>
            <button
              id="revoke-consent-btn"
              phx-click="revoke_consent"
              class="text-sm text-base-content/70 underline hover:text-base-content transition-colors"
            >
              Unsubscribe
            </button>
          <% else %>
            <p class="text-sm text-base-content/70">
              You're not subscribed to product updates.
              Sign in again and check the "Keep me updated" box to subscribe.
            </p>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SelectOnClick">
      export default {
        mounted() { this.el.addEventListener("click", () => this.el.select()) }
      }
    </script>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, socket |> assign(:marketing_consent, nil) |> push_navigate(to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    marketing_consent = Accounts.get_consent(user, "marketing_email")
    tuning = Speechwave.ExtensionTuning.current()
    resolved_percent = user.overlay_size_percent || tuning.default_overlay_size_percent
    customizing? = user.overlay_size_percent != nil

    extension_settings_changeset =
      Accounts.change_extension_settings(user, %{
        overlay_size_percent: resolved_percent,
        customize_overlay_size: customizing?
      })

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

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("disconnect_identity", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    identity = Enum.find(socket.assigns.identities, &(to_string(&1.id) == id))

    if identity && identity.user_id == user.id do
      {:ok, _} = Accounts.delete_user_identity(identity)
      {:noreply, assign(socket, :identities, Accounts.list_user_identities(user))}
    else
      {:noreply, put_flash(socket, :error, "Could not disconnect that account.")}
    end
  end

  def handle_event("revoke_consent", _params, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.revoke_consent(user, "marketing_email") do
      {:ok, _} ->
        marketing_consent = Accounts.get_consent(user, "marketing_email")
        {:noreply, assign(socket, :marketing_consent, marketing_consent)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not unsubscribe. Please try again.")}
    end
  end

  def handle_event("clipboard_copy", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_event("regenerate_api_key", _params, socket) do
    user = socket.assigns.current_scope.user
    {:ok, updated_user} = Accounts.regenerate_api_key(user)

    SpeechwaveWeb.Endpoint.broadcast!("user:#{user.id}:disconnect", "disconnect", %{})

    {:noreply, assign(socket, :api_key, updated_user.api_key)}
  end

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
end
