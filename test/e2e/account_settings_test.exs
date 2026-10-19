defmodule SpeechwaveWeb.E2E.AccountSettingsTest do
  @moduledoc """
  Real-browser port of scripts/manual_tests/account_settings.sh (API key
  regeneration, email change, sign out). Page contents and the individual
  forms are already covered by test/speechwave_web/live/user_live; this checks
  the pieces that only a browser exercises: the confirm dialog, the emailed
  confirmation link, and the redirect that follows it.
  Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  alias Speechwave.Repo

  test "regenerate the API key, change the email, sign out", %{conn: conn} do
    user = user_fixture()
    old_key = user.api_key
    new_email = unique_user_email()

    conn =
      conn
      |> log_in_as(user)
      |> visit("/users/settings")
      |> assert_has("#email_form")
      |> assert_has("#api-key-display", value: old_key)
      |> assert_has("#connected-accounts")
      |> assert_has("#connect-google")
      |> assert_has("#connect-microsoft")
      |> assert_has("#connect-github")
      |> with_dialog(
        fn %{message: message} ->
          assert message =~ "Regenerate your API key"
          :accept
        end,
        &click(&1, "#regenerate-api-key-btn")
      )
      |> refute_has("#api-key-display", value: old_key)

    new_key = Repo.reload!(user).api_key
    refute new_key == old_key
    assert_has(conn, "#api-key-display", value: new_key)

    conn
    |> fill_in("Email", with: new_email)
    |> click_button("#change-email-btn", "Change Email")
    |> assert_has("#flash-info")

    assert_receive {:email, %{to: [{_, ^new_email}], subject: subject, text_body: body}}, 5000
    assert subject =~ "Update email instructions"

    [confirm_url] =
      Regex.run(~r{https?://\S+/users/settings/confirm-email/\S+}, body) ||
        flunk("no confirm-email link in the email:\n#{body}")

    conn
    |> visit(confirm_url)
    |> assert_has("#flash-info")
    |> assert_has("#email_form input[name='user[email]']", value: new_email)
    |> visit("/dashboard")
    |> click_link("Sign out")
    |> visit("/dashboard")
    |> assert_path("/users/log-in")
  end
end
