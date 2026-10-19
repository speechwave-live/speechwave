defmodule SpeechwaveWeb.E2E.AuthThrottleTest do
  @moduledoc """
  Real-browser port of the `email` mode of scripts/manual_tests/auth_throttle.sh.
  The page looks the same whether or not the second request was throttled, so
  the proof is in the mailbox: submitting the sign-in form twice for one email
  must deliver exactly one message. The throttle's rules are unit tested in
  test/speechwave/auth_throttle_test.exs.

  The script's `ip` mode stays manual: it needs a reverse proxy (and the
  production logs) to see a client IP, and tests never carry one.
  Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  @moduletag :capture_log

  setup {SpeechwaveWeb.E2ECase, :enable_auth_throttle}

  defp request_sign_in_link(conn, email) do
    conn
    |> visit("/users/log-in")
    |> fill_in("Email address", with: email)
    |> click_button("Send sign-in link")
    |> assert_has("#magic-link-sent")
  end

  test "a second request for the same email sends no second message", %{conn: conn} do
    email = unique_user_email()
    other_email = unique_user_email()

    conn
    |> request_sign_in_link(email)
    |> request_sign_in_link(email)
    |> request_sign_in_link(other_email)

    assert_receive {:email, %{to: [{_, ^email}]}}, 5000
    refute_receive {:email, %{to: [{_, ^email}]}}, 500

    # A different address is not affected, so the silence above is the throttle
    # and not a broken mailer.
    assert_receive {:email, %{to: [{_, ^other_email}]}}, 5000
  end
end
