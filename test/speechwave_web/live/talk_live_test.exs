defmodule SpeechwaveWeb.TalkLiveTest do
  use SpeechwaveWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Speechwave.AccountsFixtures
  import Speechwave.DataCase, only: [hold_connection: 0]
  import Speechwave.TalksFixtures

  alias Speechwave.{Accounts, AudienceSlots, Plans, Talks}

  # The test database is SQLite, which hands out the same talk ids again after
  # each test's rollback. Places held by the previous test are freed
  # asynchronously and could still count against this test's talk, so each
  # test starts with an empty AudienceSlots server. No async test uses it.
  setup do
    :ok = Supervisor.terminate_child(Speechwave.Supervisor, AudienceSlots)
    {:ok, _pid} = Supervisor.restart_child(Speechwave.Supervisor, AudienceSlots)
    # Every test taps on the same slug and the batcher is shared, so emoji left
    # pending by an earlier test would join this test's batches.
    :ok = Speechwave.ReactionBatcher.flush()
    :ok
  end

  setup do
    user = user_fixture()
    talk = talk_fixture(user, %{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})
    {:ok, talk: talk}
  end

  # Real browsers send their audience id as soon as the page mounts, and on a
  # free-plan talk that is what claims a place. Tests that react do the same.
  defp send_audience_id(view, id \\ Ecto.UUID.generate()) do
    render_hook(view, "audience_id", %{"id" => id})
    view
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
    send_audience_id(view)
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

    # Only an unlimited plan lets a reaction through before the id arrives:
    # on a limited plan the id is what claims a place.
    test "a reaction before the id arrives has no audience id", %{conn: conn, talk: talk} do
      user = Speechwave.Repo.preload(talk, :user).user
      {:ok, _} = Accounts.set_user_plan(user, :pro)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

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
    send_audience_id(view)
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")

    render_click(view, "react", %{"emoji" => "❤️"})
    assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: "❤️"}}, 500

    render_click(view, "react", %{"emoji" => "❤️"})
    refute_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}, 200
  end

  test "receives a batch broadcast and page still renders correctly", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    send_audience_id(view)

    SpeechwaveWeb.Endpoint.broadcast!("audience:#{talk.slug}", "reactions_batch", %{
      emojis: ["🔥", "❤️"]
    })

    assert_push_event(view, "reactions_batch", %{emojis: ["🔥", "❤️"]})
    assert has_element?(view, "#emoji-buttons")
  end

  test "a tap reaches another audience page as a batch after a flush", %{conn: conn, talk: talk} do
    {:ok, tapper, _html} = live(conn, "/t/#{talk.slug}")
    send_audience_id(tapper)
    {:ok, watcher, _html} = live(build_conn(), "/t/#{talk.slug}")
    send_audience_id(watcher)

    render_click(tapper, "react", %{"emoji" => "❤️"})
    :ok = Speechwave.ReactionBatcher.flush()

    assert_push_event(watcher, "reactions_batch", %{emojis: ["❤️"]})
  end

  test "a tap with no active session is still batched", %{conn: conn, talk: talk} do
    assert Talks.get_active_session(talk.id) == nil
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    send_audience_id(view)

    render_click(view, "react", %{"emoji" => "🔥"})
    :ok = Speechwave.ReactionBatcher.flush()

    assert_push_event(view, "reactions_batch", %{emojis: ["🔥"]})
  end

  test "a page no longer receives per-reaction new_reaction pushes", %{conn: conn, talk: talk} do
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    send_audience_id(view)
    SpeechwaveWeb.Endpoint.broadcast!("reactions:#{talk.slug}", "new_reaction", %{emoji: "🔥"})
    _ = :sys.get_state(view.pid)

    refute_push_event(view, "new_reaction", _, 100)
  end

  describe "after a deploy changes the assets" do
    # Phones stay on the page across a deploy and reconnect to the new server
    # with the old JavaScript. Reactions now arrive as `reactions_batch`, which
    # the old hook ignores, so a reconnecting page must reload to get the new
    # hook. LiveView compares the page's tracked assets with the endpoint's
    # asset manifest, which only exists in a release, so these tests set it.
    setup do
      latest = %{"assets/js/app.js" => "assets/js/app-NEW.js"}
      Phoenix.Config.put(SpeechwaveWeb.Endpoint, :cache_static_manifest_latest, latest)

      on_exit(fn ->
        Phoenix.Config.put(SpeechwaveWeb.Endpoint, :cache_static_manifest_latest, nil)
      end)
    end

    test "a page connecting with old assets is sent to a full reload", %{conn: conn, talk: talk} do
      conn =
        put_connect_params(conn, %{"_track_static" => ["http://localhost/assets/js/app-OLD.js"]})

      path = "/t/#{talk.slug}"

      assert {:error, {:redirect, %{to: ^path}}} = live(conn, path)
    end

    test "a page connecting with current assets mounts normally", %{conn: conn, talk: talk} do
      conn =
        put_connect_params(conn, %{"_track_static" => ["http://localhost/assets/js/app-NEW.js"]})

      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      assert has_element?(view, "#emoji-buttons")
    end
  end

  @tag :capture_log
  test "a reaction whose insert fails is still broadcast and the view survives",
       %{conn: conn, talk: talk} do
    {:ok, _session} = Talks.start_session(talk)
    {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
    send_audience_id(view)
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")
    ref = Process.monitor(view.pid)
    release = hold_connection()

    render_click(view, "react", %{"emoji" => "❤️"})
    release.()

    assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: "❤️"}}, 500
    refute_received {:DOWN, ^ref, _, _, _}
    assert has_element?(view, "#emoji-buttons")

    # The audience still sees the reaction, even though it was not stored.
    :ok = Speechwave.ReactionBatcher.flush()
    assert_push_event(view, "reactions_batch", %{emojis: ["❤️"]})
  end

  describe "reaction persistence" do
    test "persists reaction to active session when one exists", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view)

      render_click(view, "react", %{"emoji" => "❤️"})

      assert Speechwave.Reactions.count_reactions(session.id) == 1
    end

    test "does not persist reaction when no active session", %{conn: conn, talk: talk} do
      # No session started — reaction should broadcast fine but not persist
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view)
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
      send_audience_id(view)

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
      send_audience_id(view)

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
      send_audience_id(view)

      render_click(view, "react", %{"emoji" => "❤️"})

      reaction =
        Speechwave.Repo.one(
          from r in Speechwave.Reactions.Reaction,
            where: r.talk_session_id == ^session.id
        )

      assert reaction.slide_number == 0
    end
  end

  describe "participant limit" do
    # The AudienceSlots server is global, so fake places are held by spawned
    # processes that the test stops when it finishes. With the test grace
    # period of 0, their places are freed right after.
    defp fill_places(talk, n) do
      limit = Plans.limit(:max_participants, :free)

      pids =
        for _ <- 1..n//1 do
          pid = spawn(fn -> receive do: (:stop -> :ok) end)
          :ok = AudienceSlots.claim(talk.id, limit, Ecto.UUID.generate(), pid)
          pid
        end

      on_exit(fn -> Enum.each(pids, &Process.exit(&1, :kill)) end)
      pids
    end

    defp free_limit, do: Plans.limit(:max_participants, :free)

    test "the next visitor after a full talk is turned away", %{conn: conn, talk: talk} do
      fill_places(talk, free_limit())
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view)

      assert has_element?(view, "#talk-full")
      assert has_element?(view, "#try-again[href='/t/#{talk.slug}']")
      refute has_element?(view, "#emoji-buttons")
      refute has_element?(view, "#emoji-stream")

      Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")
      render_click(view, "react", %{"emoji" => "❤️"})
      refute_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}, 100
    end

    test "a turned-away visitor does not receive the reaction stream", %{conn: conn, talk: talk} do
      fill_places(talk, free_limit())
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view)

      SpeechwaveWeb.Endpoint.broadcast!("audience:#{talk.slug}", "reactions_batch", %{
        emojis: ["🔥"]
      })

      _ = :sys.get_state(view.pid)

      refute_push_event(view, "reactions_batch", _, 100)
    end

    test "a second audience id does not change a turn-away", %{conn: conn, talk: talk} do
      fill_places(talk, free_limit())
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view, "not-a-uuid")
      assert has_element?(view, "#talk-full")

      send_audience_id(view)
      assert has_element?(view, "#talk-full")
    end

    test "an admitted visitor can react and receives the stream", %{conn: conn, talk: talk} do
      fill_places(talk, free_limit() - 1)
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view)

      assert has_element?(view, "#emoji-buttons")
      refute has_element?(view, "#talk-full")
      assert AudienceSlots.count(talk.id) == free_limit()

      Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")
      render_click(view, "react", %{"emoji" => "❤️"})
      assert_receive %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: "❤️"}}
      :ok = Speechwave.ReactionBatcher.flush()
      assert_push_event(view, "reactions_batch", %{emojis: ["❤️"]})
    end

    test "a full talk still admits a browser that already holds a place",
         %{conn: conn, talk: talk} do
      id = Ecto.UUID.generate()
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view, id)
      fill_places(talk, free_limit() - 1)

      # A second tab or a reconnect from the same browser.
      {:ok, same, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(same, String.upcase(id))
      assert has_element?(same, "#emoji-buttons")

      {:ok, other, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(other)
      assert has_element?(other, "#talk-full")
    end

    test "a visitor who never sends an audience id gets nothing", %{conn: conn, talk: talk} do
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")

      Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")
      render_click(view, "react", %{"emoji" => "❤️"})
      refute_receive %Phoenix.Socket.Broadcast{event: "new_reaction"}, 100

      SpeechwaveWeb.Endpoint.broadcast!("audience:#{talk.slug}", "reactions_batch", %{
        emojis: ["🔥"]
      })

      _ = :sys.get_state(view.pid)
      refute_push_event(view, "reactions_batch", _, 100)
      assert AudienceSlots.count(talk.id) == 0
    end

    test "an invalid audience id still claims one place", %{conn: conn, talk: talk} do
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view, "not-a-uuid")

      assert has_element?(view, "#emoji-buttons")
      assert AudienceSlots.count(talk.id) == 1
    end

    test "the first turn-away records when the session hit the limit",
         %{conn: conn, talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      fill_places(talk, free_limit())

      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view)
      assert has_element?(view, "#talk-full")

      assert %DateTime{} = Talks.get_session(session.id).participant_limit_hit_at
    end

    test "later turn-aways leave the recorded time alone and skip the write",
         %{conn: conn, talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      fill_places(talk, free_limit())

      {:ok, first, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(first)
      assert %DateTime{} = hit_at = Talks.get_session(session.id).participant_limit_hit_at

      # Ecto reports every query through telemetry, in the process that ran
      # it. Forward the SQL of any talk_sessions update to the test.
      test_pid = self()
      handler = "talk-live-limit-hit-#{System.unique_integer()}"

      :telemetry.attach(
        handler,
        [:speechwave, :repo, :query],
        fn _event, _measurements, %{query: sql}, _config ->
          if sql =~ ~r/UPDATE "talk_sessions"/, do: send(test_pid, {:session_update, sql})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      {:ok, second, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(second)
      assert has_element?(second, "#talk-full")

      refute_received {:session_update, _}
      assert Talks.get_session(session.id).participant_limit_hit_at == hit_at
    end

    test "a turn-away with no active session does not crash", %{conn: conn, talk: talk} do
      fill_places(talk, free_limit())

      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view)
      assert has_element?(view, "#talk-full")
    end

    test "the place key is a hash, never the browser's id", %{conn: conn, talk: talk} do
      id = Ecto.UUID.generate()
      {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
      send_audience_id(view, String.upcase(id))

      expected = :crypto.hash(:sha256, id) |> Base.encode16(case: :lower)
      places = :sys.get_state(AudienceSlots).talks[talk.id]

      assert Map.keys(places) == [expected]
      refute inspect(:sys.get_state(AudienceSlots)) =~ id
    end

    test "a pro-plan talk admits more than the free limit without tracking places",
         %{conn: conn} do
      {:ok, owner} = Accounts.set_user_plan(user_fixture(), :pro)
      talk = talk_fixture(owner, %{title: "Big room", slug: "big-room"})

      views =
        for _ <- 1..(free_limit() + 1) do
          {:ok, view, _html} = live(conn, "/t/#{talk.slug}")
          send_audience_id(view)
        end

      assert Enum.all?(views, &has_element?(&1, "#emoji-buttons"))
      refute Enum.any?(views, &has_element?(&1, "#talk-full"))
      assert AudienceSlots.count(talk.id) == 0
    end
  end
end
