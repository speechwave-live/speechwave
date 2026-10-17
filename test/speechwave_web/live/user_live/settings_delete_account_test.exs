defmodule SpeechwaveWeb.UserLive.SettingsDeleteAccountTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts.User
  alias Speechwave.Repo

  defp settings_view(conn, user) do
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")
    view
  end

  defp type_email(view, email) do
    view
    |> form("#delete-account-form", account: %{email: email})
    |> render_change()
  end

  test "renders the danger zone with the open button", %{conn: conn} do
    view = settings_view(conn, user_fixture())

    assert has_element?(view, "#danger-zone")
    assert has_element?(view, "#open-delete-dialog")
    assert has_element?(view, "#delete-account-dialog #delete-account-form")
    refute has_element?(view, "#danger-zone-admin-note")
  end

  test "admins see the explanation and no button", %{conn: conn} do
    view = settings_view(conn, admin_user_fixture())

    assert has_element?(view, "#danger-zone-admin-note")
    refute has_element?(view, "#open-delete-dialog")
    refute has_element?(view, "#delete-account-form")
  end

  test "the confirm button is disabled until the typed email matches exactly", %{conn: conn} do
    user = user_fixture()
    view = settings_view(conn, user)

    assert has_element?(view, "#confirm-delete-account[disabled]")

    type_email(view, "wrong@example.com")
    assert has_element?(view, "#confirm-delete-account[disabled]")

    type_email(view, user.email)
    refute has_element?(view, "#confirm-delete-account[disabled]")
  end

  test "the typed email is trimmed but compared case-sensitively", %{conn: conn} do
    user = user_fixture()
    view = settings_view(conn, user)

    type_email(view, "  #{user.email}  ")
    refute has_element?(view, "#confirm-delete-account[disabled]")

    type_email(view, String.upcase(user.email))
    assert has_element?(view, "#confirm-delete-account[disabled]")
  end

  test "submitting a wrong email does not submit the form and leaves the account", %{conn: conn} do
    user = user_fixture()
    view = settings_view(conn, user)

    view
    |> form("#delete-account-form", account: %{email: "wrong@example.com"})
    |> render_submit()

    refute has_element?(view, "#delete-account-form[phx-trigger-action]")
    assert has_element?(view, "#delete-account-error")
    assert Repo.get(User, user.id)
  end

  test "submitting the right email triggers the form action", %{conn: conn} do
    user = user_fixture()
    view = settings_view(conn, user)

    view
    |> form("#delete-account-form", account: %{email: user.email})
    |> render_submit()

    assert has_element?(view, "#delete-account-form[phx-trigger-action]")
    # The deletion itself happens in the controller (see UserAccountControllerTest).
    assert Repo.get(User, user.id)
  end
end
