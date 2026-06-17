defmodule SpeechwaveWeb.UserLive.LoginTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

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

  describe "login page" do
    test "renders the magic link form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      assert has_element?(view, "#magic-link-form")
    end

    test "shows confirmation after email submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      view
      |> form("#magic-link-form", %{"user" => %{"email" => "test@example.com"}})
      |> render_submit()

      assert has_element?(view, "#magic-link-sent")
    end

    test "sends a magic link for existing user", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      view
      |> form("#magic-link-form", %{"user" => %{"email" => user.email}})
      |> render_submit()

      assert has_element?(view, "#magic-link-sent")

      assert Speechwave.Repo.get_by!(Speechwave.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "creates a new user and sends magic link for unknown email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")

      view
      |> form("#magic-link-form", %{"user" => %{"email" => "brandnew@example.com"}})
      |> render_submit()

      assert has_element?(view, "#magic-link-sent")
      user = Speechwave.Accounts.get_user_by_email("brandnew@example.com")
      assert user

      assert Speechwave.Repo.get_by!(Speechwave.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end
  end
end
