defmodule SpeechwaveWeb.UserLive.Login do
  use SpeechwaveWeb, :live_view

  alias Speechwave.Accounts
  alias Speechwave.AuthThrottle

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-6">
        <div class="text-center">
          <.header>
            Sign in to Speechwave
            <:subtitle>Enter your email to receive a sign-in link</:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>Running the local mail adapter.</p>
            <p>
              Sign-in links appear at <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <%= if @link_sent do %>
          <div id="magic-link-sent" class="text-center space-y-2">
            <p class="font-medium">Check your inbox</p>
            <p class="text-sm text-base-content/70">
              We sent a sign-in link to <strong>{@submitted_email}</strong>.
              It expires in 15 minutes.
            </p>
            <.link navigate={~p"/users/log-in"} class="text-sm underline">
              Try a different email
            </.link>
          </div>
        <% else %>
          <.form
            for={@form}
            id="magic-link-form"
            phx-submit="submit_magic"
            phx-change="form_changed"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email address"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
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
            <.button class="btn btn-primary w-full" phx-disable-with="Sending…">
              Send sign-in link <span aria-hidden="true">→</span>
            </.button>
          </.form>

          <%= if any_oauth_provider_configured?() do %>
            <div class="flex items-center gap-3 my-1">
              <div class="flex-1 h-px bg-base-content/15"></div>
              <span class="text-xs font-medium tracking-widest uppercase text-base-content/40">
                or
              </span>
              <div class="flex-1 h-px bg-base-content/15"></div>
            </div>

            <div id="oauth-buttons" class="flex flex-col gap-2.5">
              <a
                :if={oauth_provider_configured?(:google)}
                href={if @marketing_consent, do: ~p"/auth/google" <> "?updates=true", else: ~p"/auth/google"}
                class="group flex items-center justify-center gap-3 w-full px-4 py-2.5 rounded-lg bg-white text-[#3c4043] text-sm font-medium shadow-sm border border-gray-200/80 hover:shadow-md hover:bg-gray-50 active:scale-[0.99] transition-all duration-150 select-none"
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  xmlns="http://www.w3.org/2000/svg"
                  aria-hidden="true"
                >
                  <path
                    d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                    fill="#4285F4"
                  />
                  <path
                    d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                    fill="#34A853"
                  />
                  <path
                    d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z"
                    fill="#FBBC05"
                  />
                  <path
                    d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                    fill="#EA4335"
                  />
                </svg>
                Continue with Google
              </a>
              <a
                :if={oauth_provider_configured?(:microsoft)}
                href={if @marketing_consent, do: ~p"/auth/microsoft" <> "?updates=true", else: ~p"/auth/microsoft"}
                class="group flex items-center justify-center gap-3 w-full px-4 py-2.5 rounded-lg bg-white text-[#3c4043] text-sm font-medium shadow-sm border border-gray-200/80 hover:shadow-md hover:bg-gray-50 active:scale-[0.99] transition-all duration-150 select-none"
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 21 21"
                  xmlns="http://www.w3.org/2000/svg"
                  aria-hidden="true"
                >
                  <rect x="0" y="0" width="10" height="10" fill="#F25022" />
                  <rect x="11" y="0" width="10" height="10" fill="#7FBA00" />
                  <rect x="0" y="11" width="10" height="10" fill="#00A4EF" />
                  <rect x="11" y="11" width="10" height="10" fill="#FFB900" />
                </svg>
                Continue with Microsoft
              </a>
              <a
                :if={oauth_provider_configured?(:github)}
                href={if @marketing_consent, do: ~p"/auth/github" <> "?updates=true", else: ~p"/auth/github"}
                class="group flex items-center justify-center gap-3 w-full px-4 py-2.5 rounded-lg bg-white text-[#24292e] text-sm font-medium shadow-sm border border-gray-200/80 hover:shadow-md hover:bg-gray-50 active:scale-[0.99] transition-all duration-150 select-none"
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  xmlns="http://www.w3.org/2000/svg"
                  aria-hidden="true"
                >
                  <path
                    fill="#24292e"
                    d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0 0 24 12c0-6.63-5.37-12-12-12z"
                  />
                </svg>
                Continue with GitHub
              </a>
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

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

  @impl true
  def handle_event("form_changed", %{"user" => params}, socket) do
    consent = Map.get(params, "marketing_consent") == "true"
    {:noreply, assign(socket, :marketing_consent, consent)}
  end

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

  defp local_mail_adapter? do
    Application.get_env(:speechwave, Speechwave.Mailer)[:adapter] == Swoosh.Adapters.Local
  end

  defp oauth_provider_configured?(provider) do
    providers = Application.get_env(:speechwave, :oauth_providers, [])
    Keyword.has_key?(providers, provider) && providers[provider] != nil
  end

  defp any_oauth_provider_configured? do
    Enum.any?([:google, :microsoft, :github], &oauth_provider_configured?/1)
  end

  defp format_ip(nil), do: nil
  defp format_ip(ip), do: ip |> :inet.ntoa() |> to_string()

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

  defp auth_throttle_enabled? do
    Application.get_env(:speechwave, :auth_throttle_enabled, true)
  end
end
