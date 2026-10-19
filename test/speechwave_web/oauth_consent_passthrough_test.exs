defmodule SpeechwaveWeb.OAuthConsentPassthroughTest do
  @moduledoc """
  The marketing consent checkbox has to survive an OAuth sign-in: the login
  page puts `?updates=true` on each provider button, and `/auth/:provider`
  remembers it in the session for the callback. The callback itself (which
  turns the session flag into a consent record) needs a real token exchange
  and is not covered here.

  Not async: these tests swap the global `:oauth_providers` config.
  """
  use SpeechwaveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  # Providers with fake credentials. Google and GitHub build their redirect URL
  # locally. Microsoft is OIDC, so we hand it a discovery document up front to
  # keep Assent from fetching one over the network.
  @providers [
    google: [client_id: "test-google", client_secret: "secret", strategy: Assent.Strategy.Google],
    github: [client_id: "test-github", client_secret: "secret", strategy: Assent.Strategy.Github],
    microsoft: [
      client_id: "test-microsoft",
      client_secret: "secret",
      tenant_id: "common",
      strategy: Assent.Strategy.AzureAD,
      authorization_params: [response_mode: "query", scope: "openid profile email"],
      openid_configuration: %{
        "issuer" => "https://login.example.test/common/v2.0",
        "authorization_endpoint" => "https://login.example.test/common/oauth2/v2.0/authorize",
        "token_endpoint" => "https://login.example.test/common/oauth2/v2.0/token",
        "jwks_uri" => "https://login.example.test/common/discovery/v2.0/keys"
      }
    ]
  ]

  setup do
    previous = Application.fetch_env(:speechwave, :oauth_providers)
    Application.put_env(:speechwave, :oauth_providers, @providers)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:speechwave, :oauth_providers, value)
        :error -> Application.delete_env(:speechwave, :oauth_providers)
      end
    end)
  end

  describe "login page buttons" do
    test "link to the plain provider URL until the consent box is ticked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      for provider <- ~w[google microsoft github] do
        assert has_element?(view, ~s(#oauth-buttons a[href="/auth/#{provider}"]))
        refute has_element?(view, ~s(#oauth-buttons a[href="/auth/#{provider}?updates=true"]))
      end

      view |> form("#magic-link-form", user: %{marketing_consent: "true"}) |> render_change()

      for provider <- ~w[google microsoft github] do
        assert has_element?(view, ~s(#oauth-buttons a[href="/auth/#{provider}?updates=true"]))
        refute has_element?(view, ~s(#oauth-buttons a[href="/auth/#{provider}"]))
      end
    end

    test "go back to the plain URL when the box is unticked again", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      view |> form("#magic-link-form", user: %{marketing_consent: "true"}) |> render_change()
      view |> form("#magic-link-form", user: %{marketing_consent: "false"}) |> render_change()

      assert has_element?(view, ~s(#oauth-buttons a[href="/auth/google"]))
      refute has_element?(view, ~s(#oauth-buttons a[href="/auth/google?updates=true"]))
    end
  end

  describe "oauth_authorize/2" do
    for provider <- ~w[google microsoft github] do
      test "#{provider}: redirects to the provider and remembers the consent choice", %{
        conn: conn
      } do
        with_consent = get(conn, "/auth/#{unquote(provider)}?updates=true")
        assert redirected_to(with_consent) =~ ~r{^https://}
        assert get_session(with_consent, :marketing_updates) == true

        without_consent = get(build_conn(), "/auth/#{unquote(provider)}")
        assert redirected_to(without_consent) =~ ~r{^https://}
        assert get_session(without_consent, :marketing_updates) == false
      end
    end
  end
end
