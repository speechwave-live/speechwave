defmodule SpeechwaveWeb.UserSessionControllerTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "magic_link/2" do
    test "logs in via valid token", %{conn: conn, user: user} do
      {token, _} = generate_user_magic_link_token(user)

      conn = get(conn, ~p"/users/magic_link/#{token}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "redirects to login on invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/magic_link/invalid-token")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "token is single-use — second use redirects to login", %{conn: conn, user: user} do
      {token, _} = generate_user_magic_link_token(user)

      get(conn, ~p"/users/magic_link/#{token}")
      conn2 = get(build_conn(), ~p"/users/magic_link/#{token}")

      assert redirected_to(conn2) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "invalid or has expired"
    end

    test "malformed (non-base64) token redirects to login", %{conn: conn} do
      conn = get(conn, ~p"/users/magic_link/not!!valid!!base64")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end

  describe "oauth_authorize/2" do
    test "unknown provider redirects to login with error", %{conn: conn} do
      conn = get(conn, "/auth/notaprovider")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not configured"
    end
  end

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

    test "shows 'Welcome!' flash when ?notify present but ?updates absent",
         %{conn: conn, token: token} do
      conn = get(conn, ~p"/users/magic_link/#{token}?notify=pro")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Welcome!"
    end

    test "preserves existing consent on login without ?updates", %{conn: conn} do
      user = consented_user_fixture()
      {token, _} = generate_user_magic_link_token(user)

      get(conn, ~p"/users/magic_link/#{token}")

      assert Accounts.consented?(user, "marketing_email")
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
