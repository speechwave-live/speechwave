defmodule SpeechwaveWeb.PricingLiveTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts

  describe "pricing page" do
    test "renders all three pricing tiers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pricing")

      assert html =~ "Free"
      assert html =~ "Pro"
      assert html =~ "Enterprise"
    end

    test "shows Notify me buttons for Pro and Enterprise", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      assert has_element?(view, "#notify-pro-btn")
      assert has_element?(view, "#notify-enterprise-btn")
    end

    test "sets page title and SEO/OG meta tags", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/pricing")

      assert html =~ ~r/<title[^>]*>\s*Pricing · Speechwave\s*<\/title>/

      assert html =~
               ~s(<meta name="description" content="Compare Speechwave&#39;s free and paid plans. Start free, no credit card required, and upgrade when you need more participants or sessions."/>)

      assert html =~ ~s(<meta property="og:title" content="Pricing · Speechwave"/>)
      assert html =~ ~s(<meta property="og:url" content="http://localhost:4000/pricing"/>)
    end
  end

  describe "Notify me modal — logged-out user" do
    test "opens modal when Notify me clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()

      assert has_element?(view, "#notify-modal")
      assert has_element?(view, "#notify-form")
    end

    test "closes modal on cancel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()
      view |> element("#notify-cancel-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
    end

    test "shows confirmation after form submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()
      view |> form("#notify-form", %{"email" => "interested@example.com"}) |> render_submit()

      assert has_element?(view, "#notify-sent-message")
    end
  end

  describe "Notify me — logged-in user without consent" do
    test "applies consent directly with source 'pricing_pro' and shows flash", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
      assert render(view) =~ "You&#39;re on the list"

      consent = Accounts.get_consent(user, "marketing_email")
      assert consent
      assert consent.granted
      assert consent.source == "pricing_pro"
    end
  end

  describe "Notify me — logged-in user already consented" do
    test "shows already-on-list flash without modal", %{conn: conn} do
      user = consented_user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/pricing")

      view |> element("#notify-pro-btn") |> render_click()

      refute has_element?(view, "#notify-modal")
      assert render(view) =~ "already on the list"
    end
  end
end
