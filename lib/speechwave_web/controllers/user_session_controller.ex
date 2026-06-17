defmodule SpeechwaveWeb.UserSessionController do
  use SpeechwaveWeb, :controller

  alias Speechwave.Accounts
  alias SpeechwaveWeb.UserAuth

  @doc "Handles the magic link click — verifies token and creates a session directly."
  def magic_link(conn, %{"token" => token} = params) do
    updates = params["updates"] == "true"
    notify = if params["notify"] in ~w[pro enterprise], do: params["notify"], else: nil

    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _tokens}} ->
        if updates do
          source = if notify, do: "pricing_#{notify}", else: "login"
          Accounts.grant_consent(user, "marketing_email", source: source)
        end

        flash =
          if notify && updates,
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

  @known_providers ~w[google github microsoft]

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

  @doc "Handles the OAuth provider callback."
  def oauth_callback(conn, %{"provider" => provider} = params) do
    session_params = get_session(conn, :assent_session_params)
    config = assent_config(provider, conn)

    if is_nil(session_params) do
      conn
      |> put_flash(:error, "Your login session expired. Please try again.")
      |> redirect(to: ~p"/users/log-in")
    else
      result =
        config &&
          config
          |> Keyword.put(:session_params, session_params)
          |> config[:strategy].callback(params)

      handle_oauth_result(conn, provider, result)
    end
  end

  defp handle_oauth_result(conn, provider, {:ok, %{user: user_info}}) do
    context = get_session(conn, :oauth_context)
    current_user = conn.assigns.current_scope && conn.assigns.current_scope.user

    if context == "connect" && current_user do
      handle_oauth_connect(conn, provider, user_info, current_user)
    else
      handle_oauth_login(conn, provider, user_info)
    end
  end

  defp handle_oauth_result(conn, _provider, _error) do
    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/users/log-in")
  end

  defp handle_oauth_login(conn, provider, user_info) do
    marketing_updates = get_session(conn, :marketing_updates)

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

  defp handle_oauth_connect(conn, provider, user_info, current_user) do
    uid = user_info["sub"]

    case Accounts.get_identity_by_provider_uid(provider, uid) do
      nil ->
        case Accounts.link_identity_to_user(current_user, provider, uid) do
          {:ok, _} ->
            conn
            |> delete_session(:assent_session_params)
            |> delete_session(:oauth_context)
            |> put_flash(:info, "#{String.capitalize(provider)} account connected.")
            |> redirect(to: ~p"/users/settings")

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not connect your #{provider} account.")
            |> redirect(to: ~p"/users/settings")
        end

      existing_identity ->
        if existing_identity.user_id == current_user.id do
          conn
          |> put_flash(
            :info,
            "#{String.capitalize(provider)} is already connected to your account."
          )
          |> redirect(to: ~p"/users/settings")
        else
          conn
          |> put_flash(
            :error,
            "This #{provider} account is linked to a different Speechwave account."
          )
          |> redirect(to: ~p"/users/settings")
        end
    end
  end

  defp oauth_context(conn) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      "connect"
    else
      "login"
    end
  end

  # Returns nil for unknown providers to redirect gracefully rather than raising.
  defp assent_config(provider, _conn) when provider not in @known_providers, do: nil

  defp assent_config(provider, _conn) do
    provider_atom = String.to_existing_atom(provider)
    base_config = Application.get_env(:speechwave, :oauth_providers, [])[provider_atom] || []
    redirect_uri = url(~p"/auth/#{provider}/callback")

    base_config
    |> Keyword.put(:redirect_uri, redirect_uri)
    |> Keyword.put(:http_adapter, Assent.HTTPAdapter.Req)
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
