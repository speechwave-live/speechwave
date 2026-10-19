defmodule SpeechwaveWeb.E2E.WelcomeBannerTest do
  @moduledoc """
  Real-browser port of the "Welcome banner" manual check. The banner hides
  itself with a client-side JS command and tells the server to record the
  dismissal, so only a browser can show both halves working together.
  Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  alias Speechwave.Accounts
  alias Speechwave.Repo

  test "new user sees the banner, dismisses it, and it stays gone", %{conn: conn} do
    user = user_fixture()
    assert is_nil(user.welcomed_at)

    conn
    |> log_in_as(user)
    |> visit("/users/settings")
    |> assert_has("#welcome-banner")
    |> assert_has("#welcome-banner-link[target=_blank][href*='getting-started.html']")
    |> click("#welcome-banner-dismiss")
    |> refute_has("#welcome-banner")
    |> visit("/users/settings")
    |> refute_has("#welcome-banner")
    |> visit("/dashboard")
    |> assert_has("#talk-form")
    |> refute_has("#welcome-banner")

    refute is_nil(Repo.reload!(user).welcomed_at)
  end

  test "user who was already welcomed does not see the banner", %{conn: conn} do
    user = user_fixture()
    {:ok, _} = Accounts.mark_welcomed(user)

    conn
    |> log_in_as(user)
    |> visit("/users/settings")
    |> assert_has("#email_form")
    |> refute_has("#welcome-banner")
  end

  describe "on a phone-sized screen" do
    @describetag browser_context_opts: [viewport: %{width: 375, height: 667}]

    test "banner and dismiss button stay inside the viewport", %{conn: conn} do
      conn
      |> log_in_as(user_fixture())
      |> visit("/users/settings")
      |> assert_has("#welcome-banner")
      |> evaluate(
        """
        (() => {
          const banner_el = document.querySelector("#welcome-banner");
          const banner = banner_el.getBoundingClientRect();
          const button = document.querySelector("#welcome-banner-dismiss").getBoundingClientRect();
          return {
            bannerRight: banner.right,
            buttonRight: button.right,
            bannerOverflow: banner_el.scrollWidth > banner_el.clientWidth
          };
        })()
        """,
        fn metrics ->
          assert metrics["bannerRight"] <= 375
          assert metrics["buttonRight"] <= 375
          refute metrics["bannerOverflow"]
        end
      )
    end
  end
end
