defmodule SpeechwaveWeb.E2E.DashboardTest do
  @moduledoc """
  Real-browser port of scripts/manual_tests/dashboard.sh (login, talk CRUD,
  sign out). Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  test "login, create and delete a talk, sign out", %{conn: conn} do
    title = "Browser spike talk"

    conn
    |> log_in_with_magic_link(unique_user_email())
    |> assert_has("#sessions-used", text: "0", exact: true)
    |> assert_has("#session-limit", text: "50", exact: true)
    |> assert_has("#participant-limit", text: "15", exact: true)
    |> type("#talk_title", title)
    |> click_button("#talk-form button", "Create")
    |> assert_has("#created-talk", text: title)
    |> assert_has("#selected-talk-qr")
    |> assert_has("#talk-link", text: "#{SpeechwaveWeb.Endpoint.url()}/t/")
    |> assert_has("#download-qr-code")
    |> assert_has("#no-sessions")
    |> assert_has("#copy-talk-link .copy-icon-idle")
    |> refute_has("#copy-talk-link .copy-icon-copied")
    |> with_dialog(
      fn %{message: message} ->
        assert message =~ "Delete this talk"
        :accept
      end,
      &click(&1, "[id^=delete-talk-]")
    )
    |> refute_has("#selected-talk-qr")
    |> refute_has("[id^=delete-talk-]")
    |> click_link("Sign out")
    |> visit("/dashboard")
    |> assert_path("/users/log-in")
  end

  test "a session cookie gets a user to the dashboard without the sign-in form", %{conn: conn} do
    user = user_fixture()

    conn
    |> log_in_as(user)
    |> visit("/dashboard")
    |> assert_has("#talk-form")
    |> assert_has("span", text: user.email)
  end
end
