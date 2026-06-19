defmodule SpeechwaveWeb.UserLive.SettingsTest do
  use SpeechwaveWeb.ConnCase, async: true

  alias Speechwave.Accounts
  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Connected accounts"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "connected accounts" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "shows connected accounts section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#connected-accounts")
    end

    test "shows connect links for unlinked providers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#connect-google")
    end

    test "disconnect removes an identity", %{conn: conn, user: user} do
      {:ok, _} =
        Accounts.find_or_create_user_from_oauth("google", %{
          "sub" => "g-test-uid",
          "email" => user.email,
          "email_verified" => true
        })

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#disconnect-google")

      view
      |> element("#disconnect-google")
      |> render_click()

      refute has_element?(view, "#disconnect-google")
    end
  end

  describe "API key section" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "shows the user's api_key in a read-only field", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#api-key-display")
      assert render(view) =~ user.api_key
    end

    test "regenerate button generates a new api_key", %{conn: conn, user: user} do
      old_key = user.api_key
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      view |> element("#regenerate-api-key-btn") |> render_click()
      refute render(view) =~ old_key
      updated_user = Speechwave.Accounts.get_user!(user.id)
      assert updated_user.api_key != old_key
    end

    test "regenerate broadcasts disconnect to active channel connections", %{
      conn: conn,
      user: user
    } do
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "user:#{user.id}:disconnect")
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      view |> element("#regenerate-api-key-btn") |> render_click()
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 500
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
