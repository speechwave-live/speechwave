defmodule SpeechwaveWeb.ReactionChannelTest do
  use SpeechwaveWeb.ChannelCase

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Plans

  setup do
    user = user_fixture()
    talk = talk_fixture(user, %{title: "Test Talk", slug: "test-talk"})
    {:ok, socket} = connect(SpeechwaveWeb.UserSocket, %{})
    {:ok, socket: socket, talk: talk, user: user}
  end

  defp channel_join(socket, slug, api_key) do
    subscribe_and_join(socket, "reactions:#{slug}", %{"api_key" => api_key})
  end

  test "joins when api_key is valid and user owns the talk", %{
    socket: socket,
    talk: talk,
    user: user
  } do
    assert {:ok, _, _} = channel_join(socket, talk.slug, user.api_key)
  end

  test "join reply includes settings and tuning", %{socket: socket, talk: talk, user: user} do
    assert {:ok, payload, _joined} = channel_join(socket, talk.slug, user.api_key)

    tuning = Speechwave.ExtensionTuning.current()

    assert payload.settings == %{
             overlay_size_percent: tuning.default_overlay_size_percent,
             fireworks_enabled: true
           }

    assert payload.tuning == tuning
  end

  test "join reply uses the user's explicit overlay_size_percent when set", %{
    socket: socket,
    talk: talk,
    user: user
  } do
    {:ok, user} =
      Speechwave.Accounts.update_extension_settings(user, %{"overlay_size_percent" => 55})

    assert {:ok, payload, _joined} = channel_join(socket, talk.slug, user.api_key)
    assert payload.settings.overlay_size_percent == 55
  end

  test "rejects join for unknown slug", %{socket: socket, user: user} do
    assert {:error, %{reason: "not_found"}} = channel_join(socket, "nonexistent", user.api_key)
  end

  test "rejects join for invalid api_key", %{socket: socket, talk: talk} do
    assert {:error, %{reason: "unauthorized"}} = channel_join(socket, talk.slug, "badkey")
  end

  test "rejects join when api_key belongs to a user who does not own the talk", %{
    socket: socket,
    talk: talk
  } do
    other_user = user_fixture()

    assert {:error, %{reason: "unauthorized"}} =
             channel_join(socket, talk.slug, other_user.api_key)
  end

  test "pushes new_reaction to client when Endpoint broadcasts", %{
    socket: socket,
    talk: talk,
    user: user
  } do
    {:ok, _, _} = channel_join(socket, talk.slug, user.api_key)
    SpeechwaveWeb.Endpoint.broadcast!("reactions:#{talk.slug}", "new_reaction", %{emoji: "❤️"})
    assert_push "new_reaction", %{emoji: "❤️"}
  end

  describe "session management via channel" do
    setup %{socket: socket, talk: talk, user: user} do
      {:ok, _, joined} = channel_join(socket, talk.slug, user.api_key)
      %{joined: joined, talk: talk, user: user}
    end

    test "start_session creates a session and replies with session_id and label", %{
      joined: joined
    } do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id, label: "Session 1"}
      assert Speechwave.Talks.get_session(session_id) != nil
    end

    test "start_session always creates a fresh session, closing any prior active one", %{
      joined: joined
    } do
      ref1 = push(joined, "start_session", %{})
      assert_reply ref1, :ok, %{session_id: id1}
      ref2 = push(joined, "start_session", %{})
      assert_reply ref2, :ok, %{session_id: id2}
      refute id1 == id2
      assert Speechwave.Talks.get_session(id1).ended_at != nil
    end

    test "stop_session ends the active session", %{joined: joined} do
      ref = push(joined, "start_session", %{})
      assert_reply ref, :ok, %{session_id: session_id}
      ref2 = push(joined, "stop_session", %{"session_id" => session_id})
      assert_reply ref2, :ok
      assert Speechwave.Talks.get_session(session_id).ended_at != nil
    end

    test "stop_session returns error for unknown session_id", %{joined: joined} do
      ref = push(joined, "stop_session", %{"session_id" => 999_999})
      assert_reply ref, :error, %{reason: "not_found"}
    end

    test "stop_session returns error for a session belonging to a different talk",
         %{joined: joined, user: user} do
      other_talk = talk_fixture(user, %{slug: "other-#{System.unique_integer()}"})
      {:ok, other_session} = Speechwave.Talks.start_session(other_talk)
      ref = push(joined, "stop_session", %{"session_id" => other_session.id})
      assert_reply ref, :error, %{reason: "unauthorized"}
    end

    test "rejects start_session when monthly full-session limit is reached",
         %{joined: joined, talk: talk} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      full_end = DateTime.add(now, 15 * 60, :second)

      limit = Plans.limit(:full_sessions_per_month, :free)

      for i <- 1..limit do
        Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
          talk_id: talk.id,
          label: "Seed #{i}",
          started_at: now,
          ended_at: full_end
        })
      end

      ref = push(joined, "start_session", %{})
      assert_reply ref, :error, %{reason: "session_limit_reached"}
    end
  end

  describe "slide_changed" do
    setup %{socket: socket, talk: talk, user: user} do
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "slides:#{talk.slug}")
      {:ok, _, joined} = channel_join(socket, talk.slug, user.api_key)
      %{joined: joined, talk: talk}
    end

    test "broadcasts slide number to slides PubSub topic", %{joined: joined} do
      ref = push(joined, "slide_changed", %{"slide" => 5})
      assert_reply ref, :ok
      assert_receive %Phoenix.Socket.Broadcast{event: "slide_changed", payload: %{slide: 5}}, 500
    end

    test "broadcasts slide 0 so attendees reset to the general pool when presenting stops", %{
      joined: joined
    } do
      ref = push(joined, "slide_changed", %{"slide" => 0})
      assert_reply ref, :ok
      assert_receive %Phoenix.Socket.Broadcast{event: "slide_changed", payload: %{slide: 0}}, 500
    end
  end
end
