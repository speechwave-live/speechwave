defmodule SpeechwaveWeb.Admin.StatsLiveTest do
  use SpeechwaveWeb.ConnCase

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  test "redirects to login when logged out" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/stats")
    assert path =~ "/users/log-in"
  end

  test "redirects non-admin users to the home page" do
    user = user_fixture()
    conn = log_in_user(build_conn(), user)

    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/stats")
    assert path == ~p"/"
  end

  test "admin users see all 11 stat cards with correct current values", %{conn: conn} do
    admin = admin_user_fixture()

    talk = Speechwave.TalksFixtures.talk_fixture(admin)
    Speechwave.TalksFixtures.session_fixture(talk)

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    for id <- ~w(
          stat-total-users stat-confirmed stat-unconfirmed stat-onboarding
          stat-suspicious stat-pro-signups stat-enterprise-signups
          stat-total-signups stat-talks stat-talks-with-sessions stat-sessions
        ) do
      assert has_element?(view, "##{id}"), "expected ##{id} to be rendered"
    end

    assert has_element?(view, "#stat-talks", "1")
    assert has_element?(view, "#stat-confirmed", "1")
  end

  test "each stat card renders an SVG trend chart", %{conn: conn} do
    admin = admin_user_fixture()
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert view
           |> element("#stat-total-users")
           |> render() =~ "<svg"
  end

  test "shows an Admin nav link for admin users", %{conn: conn} do
    admin = admin_user_fixture()
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/stats")
    assert has_element?(view, "#admin-nav-link")
  end

  test "admin sees the consent export form", %{conn: conn} do
    conn = log_in_user(conn, admin_user_fixture())
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "#consent-export")

    assert has_element?(
             view,
             ~s(#consent-export-form[action="/admin/consent-export"][method="get"])
           )

    assert has_element?(view, "#export-source")
    assert has_element?(view, "#export-from")
    assert has_element?(view, "#export-to")
    assert has_element?(view, "#consent-export-submit")
  end

  test "export source dropdown lists existing sources", %{conn: conn} do
    user = consented_user_fixture(%{source: "pricing_pro"})
    session_token_fixture(user)

    conn = log_in_user(conn, admin_user_fixture())
    {:ok, view, _html} = live(conn, ~p"/admin/stats")

    assert has_element?(view, "select#export-source")
    assert has_element?(view, ~s(#export-source option[value=""]))
    assert has_element?(view, ~s(#export-source option[value="pricing_pro"]))
    assert has_element?(view, "#export-source-hint")
  end

  describe "export date range" do
    test "defaults to one month ago through today", %{conn: conn} do
      today = Date.utc_today()
      month_ago = Date.shift(today, month: -1)

      conn = log_in_user(conn, admin_user_fixture())
      {:ok, view, _html} = live(conn, ~p"/admin/stats")

      assert has_element?(view, ~s(#export-from[value="#{month_ago}"]))
      assert has_element?(view, ~s(#export-to[value="#{today}"]))
      assert has_element?(view, "#export-any-time")
      refute has_element?(view, "#export-any-time[checked]")
      refute has_element?(view, "#export-from[disabled]")
    end

    test "checking any time disables the dates and unchecking restores them", %{conn: conn} do
      conn = log_in_user(conn, admin_user_fixture())
      {:ok, view, _html} = live(conn, ~p"/admin/stats")
      from = Date.shift(Date.utc_today(), month: -1)

      view |> form("#consent-export-form", export: %{any_time: "true"}) |> render_change()
      assert has_element?(view, "#export-any-time[checked]")
      assert has_element?(view, "#export-from[disabled]")
      assert has_element?(view, "#export-to[disabled]")

      # Unchecking submits no any_time key (and no dates, as they were disabled).
      render_change(view, "export_changed", %{"export" => %{"source" => ""}})
      refute has_element?(view, "#export-from[disabled]")
      assert has_element?(view, ~s(#export-from[value="#{from}"]))
    end
  end
end
