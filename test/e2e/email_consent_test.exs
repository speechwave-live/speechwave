defmodule SpeechwaveWeb.E2E.EmailConsentTest do
  @moduledoc """
  Real-browser port of scripts/manual_tests/email_consent.sh. The pieces are
  unit tested elsewhere (the controller's handling of `?updates=` and
  `?notify=`, the settings revoke button, the pricing modal). What only a
  browser shows is the whole chain: the real checkbox and modal produce the
  right query params in the emailed link, and following that link leaves the
  right consent state on the settings page. Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  @consent_label "Keep me updated on new features and product announcements " <>
                   "(no spam, no selling your email)"

  defp sign_in_form(conn, email) do
    conn
    |> visit("/users/log-in")
    |> fill_in("Email address", with: email)
  end

  test "login with the consent box checked grants consent, and revoke removes it", %{conn: conn} do
    conn =
      conn
      |> sign_in_form(unique_user_email())
      |> check(@consent_label)
      |> click_button("Send sign-in link")
      |> assert_has("#magic-link-sent")

    magic_url = receive_magic_link()
    assert magic_url =~ "updates=true"

    conn
    |> visit(magic_url)
    |> visit("/users/settings")
    |> assert_has("#email-prefs-section[data-consented=true]")
    |> click("#revoke-consent-btn")
    |> assert_has("#email-prefs-section[data-consented=false]")
    |> refute_has("#revoke-consent-btn")
  end

  test "login without the consent box leaves the user unconsented", %{conn: conn} do
    conn =
      conn
      |> sign_in_form(unique_user_email())
      |> click_button("Send sign-in link")
      |> assert_has("#magic-link-sent")

    magic_url = receive_magic_link()
    refute magic_url =~ "updates"

    conn
    |> visit(magic_url)
    |> visit("/users/settings")
    |> assert_has("#email-prefs-section[data-consented=false]")
    |> refute_has("#revoke-consent-btn")
  end

  test "the pricing Notify Me modal records consent through the emailed link", %{conn: conn} do
    conn =
      conn
      |> visit("/pricing")
      |> click("#notify-pro-btn")
      |> assert_has("#notify-modal")
      |> type("#notify-email-input", unique_user_email())
      |> click("#notify-form button[type=submit]")
      |> assert_has("#notify-sent-message")

    magic_url = receive_magic_link()
    assert magic_url =~ "updates=true"
    assert magic_url =~ "notify=pro"

    conn
    |> visit(magic_url)
    |> assert_has("#flash-info", text: "on the list")
    |> visit("/users/settings")
    |> assert_has("#email-prefs-section[data-consented=true]")
  end
end
