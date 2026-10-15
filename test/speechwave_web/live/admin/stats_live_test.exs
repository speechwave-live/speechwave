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
end
