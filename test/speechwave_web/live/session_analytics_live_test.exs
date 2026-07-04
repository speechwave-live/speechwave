defmodule SpeechwaveWeb.SessionAnalyticsLiveTest do
  use SpeechwaveWeb.ConnCase

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  setup %{user: user} do
    talk = talk_fixture(user)
    {:ok, session} = Speechwave.Talks.start_session(talk)
    {:ok, talk: talk, session: session}
  end

  test "renders session label and talk title", %{conn: conn, talk: talk, session: session} do
    {:ok, _view, html} = live(conn, "/sessions/#{session.id}")
    assert html =~ session.label
    assert html =~ talk.title
  end

  test "shows total reaction count", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 1)
    Speechwave.Reactions.create_reaction(session, "😂", 1)
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#total-reactions", "2")
  end

  test "renders a row for each slide that has reactions", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 1)
    Speechwave.Reactions.create_reaction(session, "❤️", 3)
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#slide-row-1")
    assert has_element?(view, "#slide-row-3")
    refute has_element?(view, "#slide-row-2")
  end

  test "labels slide 0 as General", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 0)
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#slide-row-0", "General")
  end

  test "shows compare link when talk has multiple sessions", %{
    conn: conn,
    talk: talk,
    session: session
  } do
    {:ok, s1} = Speechwave.Talks.stop_session(session)
    {:ok, _s2} = Speechwave.Talks.start_session(talk)

    {:ok, view, _html} = live(conn, "/sessions/#{s1.id}")
    assert has_element?(view, "#compare-link")
  end

  test "redirects to dashboard when session id is unknown", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/sessions/999999")
  end

  test "redirects to dashboard for non-integer session id", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, "/sessions/notanumber")
  end

  test "renders compare section when compare_session param is present",
       %{conn: conn, talk: talk, session: session} do
    {:ok, _} = Speechwave.Talks.stop_session(session)
    {:ok, s2} = Speechwave.Talks.start_session(talk)

    {:ok, view, _html} = live(conn, "/sessions/#{session.id}/compare/#{s2.id}")
    assert has_element?(view, "#compare-section")
    assert render(view) =~ session.label
    assert render(view) =~ s2.label
  end

  test "shows the authenticated header nav, not the public nav", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

    assert has_element?(view, "header a[href='/users/settings']")
    refute render(view) =~ "Get started free"
  end
end
