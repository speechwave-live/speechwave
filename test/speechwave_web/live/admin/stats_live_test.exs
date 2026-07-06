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

  test "admin users can view the page", %{conn: conn} do
    admin = admin_user_fixture()
    conn = log_in_user(conn, admin)

    {:ok, _view, html} = live(conn, ~p"/admin/stats")
    assert html =~ "Admin Stats"
  end
end
