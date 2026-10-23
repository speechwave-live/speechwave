defmodule SpeechwaveWeb.UserLive.Settings do
  use SpeechwaveWeb, :live_view

  alias Phoenix.LiveView.JS
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
            class="flex-1 min-w-0 font-mono text-sm px-3 py-2 rounded-lg border border-base-300 bg-base-200 text-base-content"
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
            class="shrink-0 px-4 py-2 text-sm font-medium rounded-lg border border-base-300 hover:bg-base-200 transition-colors"
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
          <%!--
            Deliberately not `disabled={...}`: a disabled range input is
            excluded from native form serialization, so the very phx-change
            event that flips "customize" on would submit no
            overlay_size_percent at all, leaving the field's value nil and
            the label showing "Overlay size (%)" with no number. Visually
            and interactively disable it instead (CSS + tabindex, plus
            aria-disabled so assistive tech gets the same signal a native
            disabled attribute would have given) so the browser always
            includes its current value; the changeset's
            maybe_clear_overlay_size_percent/1 is what actually decides
            whether that value gets persisted.
          --%>
          <% customizing? =
            Phoenix.HTML.Form.normalize_value(
              "checkbox",
              @extension_settings_form[:customize_overlay_size].value
            ) %>
          <.input
            field={@extension_settings_form[:overlay_size_percent]}
            type="range"
            min={@tuning.min_overlay_size_percent}
            max="100"
            label={"Overlay size (#{@extension_settings_form[:overlay_size_percent].value}%)"}
            class={["range range-primary w-full", !customizing? && "opacity-50 pointer-events-none"]}
            error_class="range-error"
            phx-debounce="100"
            tabindex={if !customizing?, do: "-1"}
            aria-disabled={to_string(!customizing?)}
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

      <div class="divider" />

      <%!-- Download a copy of the user's personal data (GDPR access and portability) --%>
      <div id="your-data-section">
        <h3 class="font-semibold text-base-content">Your data</h3>
        <p class="mt-1.5 text-sm text-base-content/70">
          Download a copy of the data we hold about you: your account, linked sign-ins,
          consents, talks and sessions, with reaction counts. You get a zip with the data,
          a schema describing it, and a README. It leaves out your API key and other
          people's data.
        </p>
        <a
          id="download-my-data"
          href={~p"/users/settings/export"}
          download
          class="mt-3 inline-flex items-center gap-2 rounded-lg border border-base-300 px-3.5 py-2 text-sm font-semibold text-base-content transition-colors hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" /> Download my data
        </a>
      </div>

      <div class="divider" />

      <%!-- Danger zone: permanent account deletion --%>
      <div
        id="danger-zone"
        class="rounded-xl border border-red-200 border-l-[5px] border-l-red-600 bg-red-50 p-4"
      >
        <h3 class="flex items-center gap-2 font-bold text-red-700">
          <.icon name="hero-exclamation-triangle" class="size-5" /> Danger zone
        </h3>
        <p class="mt-1.5 text-sm text-gray-700">
          Permanently delete your account and everything in it: your talks, sessions,
          reactions and settings. This cannot be undone.
        </p>
        <%= if not @can_delete? do %>
          <p id="danger-zone-admin-note" class="mt-3 text-sm font-medium text-gray-700">
            Admin accounts can't be deleted from here, so the site always keeps an administrator.
          </p>
        <% else %>
          <button
            id="open-delete-dialog"
            type="button"
            phx-click={JS.dispatch("open-dialog", to: "#delete-account-dialog")}
            class="mt-3 rounded-lg bg-red-600 px-3.5 py-2 text-sm font-semibold text-white transition-colors hover:bg-red-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
          >
            Delete my account…
          </button>
        <% end %>
      </div>

      <%= if @can_delete? do %>
        <%!--
          Native <dialog>, opened and closed by the .DeleteDialog hook below. The
          form posts to a controller (phx-trigger-action) because only the plug
          layer can clear the session cookie after the account is gone.
        --%>
        <dialog
          id="delete-account-dialog"
          phx-hook=".DeleteDialog"
          phx-mounted={JS.ignore_attributes(["open"])}
          class="m-auto w-full max-w-md rounded-2xl bg-white p-0 text-gray-800 shadow-xl backdrop:bg-black/50"
        >
          <.form
            for={@delete_form}
            id="delete-account-form"
            action={~p"/users/account"}
            method="delete"
            phx-change="delete_account_change"
            phx-submit="delete_account_submit"
            phx-trigger-action={@submit_delete_form?}
            class="p-6"
          >
            <h2 class="text-lg font-bold text-red-700">Delete your account?</h2>
            <p class="mt-3 text-sm">
              This permanently deletes your account, all of your talks and sessions, and your
              reaction data. <strong>It cannot be undone, and we can't recover it.</strong>
            </p>
            <p class="mt-2 text-sm">Deleted data is removed from our backups within 30 days.</p>
            <label for="delete-account-email" class="mt-4 block text-sm">
              Type <strong>{@current_scope.user.email}</strong> to confirm:
            </label>
            <.input
              field={@delete_form[:email]}
              id="delete-account-email"
              type="text"
              autocomplete="off"
              spellcheck="false"
              placeholder={@current_scope.user.email}
              class="mt-1.5 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-red-600 focus:outline-none focus:ring-2 focus:ring-red-600/30"
            />
            <p :if={@delete_error} id="delete-account-error" class="mt-2 text-sm text-red-700">
              {@delete_error}
            </p>
            <div class="mt-5 flex justify-end gap-2.5">
              <button
                id="cancel-delete-account"
                type="button"
                phx-click={JS.dispatch("close-dialog", to: "#delete-account-dialog")}
                class="rounded-lg border border-gray-300 bg-white px-3.5 py-2 text-sm text-gray-800 transition-colors hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                id="confirm-delete-account"
                type="submit"
                disabled={!@delete_match?}
                class="rounded-lg bg-red-600 px-3.5 py-2 text-sm font-semibold text-white transition-colors hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-45 disabled:hover:bg-red-600"
              >
                Delete my account
              </button>
            </div>
          </.form>
        </dialog>
      <% end %>
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".DeleteDialog">
      export default {
        mounted() {
          this.el.addEventListener("open-dialog", () => this.el.showModal())
          this.el.addEventListener("close-dialog", () => this.el.close())
        }
      }
    </script>
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
      |> assign(:delete_form, to_form(%{"email" => ""}, as: :account))
      |> assign(:delete_match?, false)
      |> assign(:delete_error, nil)
      |> assign(:can_delete?, Accounts.can_delete_account?(user))
      |> assign(:submit_delete_form?, false)

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

  def handle_event("delete_account_change", params, socket) do
    typed = typed_email(params)

    {:noreply,
     socket
     |> assign(:delete_form, to_form(%{"email" => typed || ""}, as: :account))
     |> assign(:delete_match?, delete_confirmed?(socket, typed))
     |> assign(:delete_error, nil)}
  end

  # Re-checks the typed email on the server, then lets the form post to
  # UserAccountController, which checks again and does the deletion.
  def handle_event("delete_account_submit", params, socket) do
    if delete_confirmed?(socket, typed_email(params)) do
      {:noreply, assign(socket, :submit_delete_form?, true)}
    else
      {:noreply,
       assign(
         socket,
         :delete_error,
         "That doesn't match your account email, so nothing was deleted."
       )}
    end
  end

  def handle_event("clipboard_copy", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_event("regenerate_api_key", _params, socket) do
    user = socket.assigns.current_scope.user
    {:ok, updated_user} = Accounts.regenerate_api_key(user)

    SpeechwaveWeb.UserAuth.disconnect_extension(user)

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

  defp delete_confirmed?(socket, typed),
    do: Accounts.deletion_confirmed?(socket.assigns.current_scope.user, typed)

  # Tolerates malformed params the same way the controller does.
  defp typed_email(%{"account" => %{"email" => email}}), do: email
  defp typed_email(_params), do: nil
end
