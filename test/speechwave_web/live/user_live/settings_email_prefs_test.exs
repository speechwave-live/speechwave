defmodule SpeechwaveWeb.UserLive.SettingsEmailPrefsTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts

  describe "email preferences section" do
    test "shows email preferences section on settings page", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert has_element?(view, "#email-prefs-section")
    end

    test "shows subscribed state when user has marketing consent", %{conn: conn} do
      user = consented_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert has_element?(view, "#email-prefs-section[data-consented=true]")
    end

    test "shows not-subscribed state when user has no consent", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert has_element?(view, "#email-prefs-section[data-consented=false]")
    end

    test "revoke button is present when user has consent", %{conn: conn} do
      user = consented_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert has_element?(view, "#revoke-consent-btn")
    end

    test "revoke button is absent when user has no consent", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      refute has_element?(view, "#revoke-consent-btn")
    end

    test "clicking revoke button revokes consent and updates UI", %{conn: conn} do
      user = consented_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert has_element?(view, "#email-prefs-section[data-consented=true]")

      view |> element("#revoke-consent-btn") |> render_click()

      assert has_element?(view, "#email-prefs-section[data-consented=false]")
      refute has_element?(view, "#revoke-consent-btn")

      # Verify DB was updated
      refute Accounts.consented?(user, "marketing_email")
    end
  end
end
