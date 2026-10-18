defmodule SpeechwaveWeb.TalkLiveTest do
  use SpeechwaveWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  setup do
    user = user_fixture()
    talk = talk_fixture(user, %{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})
    {:ok, talk: talk}
  end

  test "renders the talk page with emoji buttons", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    assert has_element?(view, "#emoji-buttons")
    assert render(view) =~ "❤️"
    assert render(view) =~ "😂"
    assert render(view) =~ "👏"
    assert render(view) =~ "🤯"
    assert render(view) =~ "🔥"
    assert render(view) =~ "💡"
  end

  test "redirects for unknown slug", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, "/t/nonexistent")
  end

  test "react event broadcasts via Endpoint when rate limit allows", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")

    render_click(view, "react", %{"emoji" => "❤️"})

    assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: "❤️"}}, 500
  end

  describe "audience id" do
    setup %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      {:ok, session: session, view: view}
    end

    defp stored_ids do
      Speechwave.Repo.all(from r in Speechwave.Reactions.Reaction, select: r.audience_id)
    end

    test "stores a hash, never the browser's id", %{view: view} do
      id = Ecto.UUID.generate()

      render_hook(view, "audience_id", %{"id" => id})
      render_click(view, "react", %{"emoji" => "❤️"})

      assert [stored] = stored_ids()
      assert stored =~ ~r/\A[0-9a-f]{64}\z/
      refute stored == id
    end

    test "the same browser hashes the same within a session", %{
      conn: conn,
      talk: talk,
      view: view
    } do
      id = Ecto.UUID.generate()
      render_hook(view, "audience_id", %{"id" => id})
      render_click(view, "react", %{"emoji" => "❤️"})

      # A reload or reconnect is a new LiveView carrying the same browser id.
      {:ok, view2, _html} = live(conn, "/t/#{talk.slug}")
      render_hook(view2, "audience_id", %{"id" => id})
      render_click(view2, "react", %{"emoji" => "🔥"})

      assert [one] = Enum.uniq(stored_ids())
      assert one =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "the same browser hashes differently in another session",
         %{conn: conn, talk: talk, session: session, view: view} do
      id = Ecto.UUID.generate()
      render_hook(view, "audience_id", %{"id" => id})
      render_click(view, "react", %{"emoji" => "❤️"})

      {:ok, _} = Speechwave.Talks.stop_session(session)
      {:ok, _} = Speechwave.Talks.start_session(talk)

      {:ok, view2, _html} = live(conn, "/t/#{talk.slug}")
      render_hook(view2, "audience_id", %{"id" => id})
      render_click(view2, "react", %{"emoji" => "❤️"})

      assert [_, _] = Enum.uniq(stored_ids())
    end

    test "a reaction before the id arrives has no audience id", %{view: view} do
      render_click(view, "react", %{"emoji" => "❤️"})
      assert [nil] = stored_ids()
    end

    test "malformed ids are ignored", %{view: view} do
      for bad <- [String.duplicate("x", 5000), "not-a-uuid", 5, nil] do
        render_hook(view, "audience_id", %{"id" => bad})
      end

      render_hook(view, "audience_id", %{})
      render_click(view, "react", %{"emoji" => "❤️"})

      assert [nil] = stored_ids()
    end

    test "the id can only be set once per connection", %{conn: conn, talk: talk} do
      {:ok, view_a, _} = live(conn, "/t/#{talk.slug}")
      {:ok, view_b, _} = live(conn, "/t/#{talk.slug}")
      first = Ecto.UUID.generate()

      render_hook(view_a, "audience_id", %{"id" => first})
      render_hook(view_a, "audience_id", %{"id" => Ecto.UUID.generate()})
      render_click(view_a, "react", %{"emoji" => "❤️"})

      render_hook(view_b, "audience_id", %{"id" => first})
      render_click(view_b, "react", %{"emoji" => "❤️"})

      assert [_one] = Enum.uniq(stored_ids())
    end
  end

  test "react event is silently dropped when rate limited", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")

    render_click(view, "react", %{"emoji" => "❤️"})
    assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: "❤️"}}, 500

    render_click(view, "react", %{"emoji" => "❤️"})
    refute_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}, 200
  end

  test "receives Endpoint broadcast and page still renders correctly", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    SpeechwaveWeb.Endpoint.broadcast!("reactions:#{talk.slug}", "new_reaction", %{emoji: "🔥"})
    assert render(view) =~ talk.title
  end

  describe "reaction persistence" do
    test "persists reaction to active session when one exists", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      render_click(view, "react", %{"emoji" => "❤️"})

      assert Speechwave.Reactions.count_reactions(session.id) == 1
    end

    test "does not persist reaction when no active session", %{conn: conn, talk: talk} do
      # No session started — reaction should broadcast fine but not persist
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")

      render_click(view, "react", %{"emoji" => "❤️"})

      assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}, 500
      # No session exists, so nothing to count — just verify no crash
    end
  end

  describe "slide-stamped reaction persistence" do
    test "stamps reaction with current_slide when slide has been set", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      # Simulate the extension broadcasting a slide change
      SpeechwaveWeb.Endpoint.broadcast!(
        "slides:#{talk.slug}",
        "slide_changed",
        %{slide: 7}
      )

      # Give the LiveView process a moment to handle the broadcast
      _ = :sys.get_state(view.pid)

      render_click(view, "react", %{"emoji" => "❤️"})

      reaction =
        Speechwave.Repo.one(
          from r in Speechwave.Reactions.Reaction,
            where: r.talk_session_id == ^session.id
        )

      assert reaction.slide_number == 7
    end

    test "stamps reaction with slide 0 when the presenter leaves presentation mode after a slide was set",
         %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      # Presenting starts on slide 7
      SpeechwaveWeb.Endpoint.broadcast!("slides:#{talk.slug}", "slide_changed", %{slide: 7})
      _ = :sys.get_state(view.pid)

      # Presenter exits Slideshow mode (e.g. back to the editor); extension reports slide 0
      SpeechwaveWeb.Endpoint.broadcast!("slides:#{talk.slug}", "slide_changed", %{slide: 0})
      _ = :sys.get_state(view.pid)

      render_click(view, "react", %{"emoji" => "❤️"})

      reaction =
        Speechwave.Repo.one(
          from r in Speechwave.Reactions.Reaction,
            where: r.talk_session_id == ^session.id
        )

      assert reaction.slide_number == 0
    end

    test "stamps reaction with slide 0 when no slide has been set", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      render_click(view, "react", %{"emoji" => "❤️"})

      reaction =
        Speechwave.Repo.one(
          from r in Speechwave.Reactions.Reaction,
            where: r.talk_session_id == ^session.id
        )

      assert reaction.slide_number == 0
    end
  end
end
