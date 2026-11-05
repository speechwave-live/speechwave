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

  test "shows distinct people reacting", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 1, "a")
    Speechwave.Reactions.create_reaction(session, "😂", 1, "a")
    Speechwave.Reactions.create_reaction(session, "😂", 1, "b")
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#audience-count", "2")
  end

  test "shows people reacting on each slide card", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 1, "a")
    Speechwave.Reactions.create_reaction(session, "😂", 1, "b")
    Speechwave.Reactions.create_reaction(session, "❤️", 2, "a")
    Speechwave.Reactions.create_reaction(session, "❤️", 3)
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#slide-people-1", "2 people")
    assert has_element?(view, "#slide-people-2", "1 person")
    refute has_element?(view, "#slide-people-3")
  end

  test "hides people reacting when reactions have no audience id", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 1)
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    refute has_element?(view, "#audience-count")
  end

  test "shows the top slide and top reaction", %{conn: conn, session: session} do
    for {emoji, slide} <- [{"❤️", 2}, {"😂", 2}, {"😂", 2}, {"❤️", 3}, {"😂", 0}, {"😂", 0}, {"😂", 0}] do
      Speechwave.Reactions.create_reaction(session, emoji, slide)
    end

    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#top-slide", "2")
    assert has_element?(view, "#top-emoji", "😂")
  end

  test "ties go to the lowest slide and the first emoji", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "😂", 5)
    Speechwave.Reactions.create_reaction(session, "❤️", 2)
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#top-slide", "2")
    assert has_element?(view, "#top-emoji", "❤️")
  end

  test "people reacting ignores reactions without an audience id", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 1)
    Speechwave.Reactions.create_reaction(session, "❤️", 1, "a")
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    assert has_element?(view, "#audience-count", "1")
  end

  test "hides top slide and top reaction without reactions", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    refute has_element?(view, "#top-slide")
    refute has_element?(view, "#top-emoji")
  end

  test "hides top slide when only general reactions exist", %{conn: conn, session: session} do
    Speechwave.Reactions.create_reaction(session, "❤️", 0)
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")
    refute has_element?(view, "#top-slide")
    assert has_element?(view, "#top-emoji", "❤️")
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
    refute has_element?(view, "#stats #compare-link")
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

  test "ignores a compare session that belongs to another user",
       %{conn: conn, session: session} do
    other_talk = talk_fixture(user_fixture())
    {:ok, other_session} = Speechwave.Talks.start_session(other_talk)
    Speechwave.Reactions.create_reaction(other_session, "🔥", 1)

    {:ok, view, _html} = live(conn, "/sessions/#{session.id}/compare/#{other_session.id}")

    refute has_element?(view, "#compare-section")
  end

  test "ignores a compare session from a different talk of the same user",
       %{conn: conn, user: user, session: session} do
    other_talk = talk_fixture(user)
    {:ok, other_session} = Speechwave.Talks.start_session(other_talk)

    {:ok, view, _html} = live(conn, "/sessions/#{session.id}/compare/#{other_session.id}")

    refute has_element?(view, "#compare-section")
  end

  test "shows the authenticated header nav, not the public nav", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

    assert has_element?(view, "header a[href='/users/settings']")
    refute render(view) =~ "Get started free"
  end

  describe "reaction timeline" do
    # Five reactions over 70 seconds: the axis is 70 s long, so buckets are
    # 10 s wide and there are 8 of them (0..7). Bucket 2 (0:20) is the peak.
    defp seed_timeline(session) do
      timed_reaction_fixture(session, 0, "❤️", 1)
      timed_reaction_fixture(session, 22, "😂", 2, "aud-a")
      timed_reaction_fixture(session, 25, "😂", 2, "aud-b")
      timed_reaction_fixture(session, 28, "❤️", 2, "aud-a")
      timed_reaction_fixture(session, 70, "🔥", 3)
    end

    # Reads the JSON in the chart container's data-timeline attribute.
    defp timeline_data(view) do
      [json] =
        view
        |> element("#reaction-timeline")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-timeline")

      Jason.decode!(json)
    end

    defp aria_label(view) do
      [label] =
        view
        |> element("#reaction-timeline")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("aria-label")

      label
    end

    test "renders the timeline container with its data", %{conn: conn, session: session} do
      seed_timeline(session)
      {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

      assert has_element?(view, "#reaction-timeline[phx-update='ignore'][role='img']")

      assert timeline_data(view) == %{
               "bucket_seconds" => 10,
               "counts" => [1, 0, 3, 0, 0, 0, 0, 1],
               "peak" => %{"index" => 2, "count" => 3},
               "slide_starts" => [
                 %{"slide" => 1, "offset_seconds" => 0},
                 %{"slide" => 2, "offset_seconds" => 22},
                 %{"slide" => 3, "offset_seconds" => 70}
               ]
             }
    end

    test "aria-label mentions the total and the peak", %{conn: conn, session: session} do
      seed_timeline(session)
      {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

      assert aria_label(view) == "Reactions over time: 5 reactions, busiest at 0:20"
    end

    test "has no timeline for an empty session", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

      refute has_element?(view, "#reaction-timeline")
      assert has_element?(view, "#no-reactions", "No reactions recorded in this session.")
    end

    test "data attribute never includes audience ids", %{conn: conn, session: session} do
      seed_timeline(session)
      {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

      json = view |> timeline_data() |> Jason.encode!()
      refute json =~ "aud-a"
      refute json =~ "aud-b"
      refute json =~ "audience"
    end

    test "only general reactions give a timeline with no slide starts", %{
      conn: conn,
      session: session
    } do
      timed_reaction_fixture(session, 0, "❤️", 0)
      timed_reaction_fixture(session, 15, "❤️", 0)
      {:ok, view, _html} = live(conn, "/sessions/#{session.id}")

      assert has_element?(view, "#reaction-timeline")
      assert %{"slide_starts" => [], "counts" => [1, 1]} = timeline_data(view)
    end
  end
end
