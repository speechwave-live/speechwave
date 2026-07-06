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
end
