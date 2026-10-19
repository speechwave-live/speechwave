defmodule SpeechwaveWeb.E2E.DashboardTest do
  @moduledoc """
  Real-browser port of scripts/manual_tests/dashboard.sh (login, talk CRUD,
  sign out). Run with `mix test.browser`.
  """
  use PhoenixTest.Playwright.Case, async: false

  import Speechwave.AccountsFixtures, only: [unique_user_email: 0]

  @moduletag :e2e

  setup do
    # The login email is sent from the endpoint's process, not the test's, so
    # point Swoosh's test adapter at this process to receive it.
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)
  end

  defp log_in_with_magic_link(conn, email) do
    conn =
      conn
      |> visit("/users/log-in")
      |> fill_in("Email address", with: email)
      |> click_button("Send sign-in link")
      |> assert_has("#magic-link-sent")

    assert_receive {:email, %{text_body: body}}, 1000
    [magic_url] = Regex.run(~r{https?://\S+/users/magic_link/\S+}, body)

    conn
    |> visit(magic_url)
    |> visit("/dashboard")
    |> assert_has("#talk-form")
  end

  test "login, create and delete a talk, sign out", %{conn: conn} do
    title = "Browser spike talk"
    conn = log_in_with_magic_link(conn, unique_user_email())

    conn
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
end
