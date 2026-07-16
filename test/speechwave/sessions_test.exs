defmodule Speechwave.SessionsTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Talks
  alias Speechwave.Talks.TalkSession

  setup do
    user = user_fixture()
    talk = talk_fixture(user)
    %{talk: talk}
  end

  describe "TalkSession.changeset/2" do
    test "valid with label and started_at" do
      cs =
        TalkSession.changeset(%TalkSession{}, %{
          label: "Session 1",
          started_at: ~U[2026-01-01 10:00:00Z]
        })

      assert cs.valid?
    end

    test "requires label" do
      cs = TalkSession.changeset(%TalkSession{}, %{started_at: ~U[2026-01-01 10:00:00Z]})
      assert "can't be blank" in errors_on(cs).label
    end

    test "requires started_at" do
      cs = TalkSession.changeset(%TalkSession{}, %{label: "Session 1"})
      assert "can't be blank" in errors_on(cs).started_at
    end
  end

  describe "start_session/1" do
    test "creates a session labeled 'Session 1' for a new talk", %{talk: talk} do
      assert {:ok, session} = Talks.start_session(talk)
      assert session.label == "Session 1"
      assert session.talk_id == talk.id
      assert session.started_at != nil
      assert session.ended_at == nil
    end

    test "labels the second session 'Session 2'", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      {:ok, _} = Talks.stop_session(s1)
      assert {:ok, s2} = Talks.start_session(talk)
      assert s2.label == "Session 2"
    end

    test "closes an existing active session and starts a fresh one", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      assert {:ok, s2} = Talks.start_session(talk)
      refute s1.id == s2.id
      assert Talks.get_session(s1.id).ended_at != nil
      assert s2.ended_at == nil
    end
  end

  describe "stop_session/1" do
    test "sets ended_at on the session", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert {:ok, stopped} = Talks.stop_session(session)
      assert stopped.ended_at != nil
    end

    test "does not overwrite ended_at when called twice", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      {:ok, stopped} = Talks.stop_session(session)
      {:ok, stopped2} = Talks.stop_session(stopped)
      assert stopped.ended_at == stopped2.ended_at
    end
  end

  describe "get_active_session/1" do
    test "returns the active session when one exists", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert Talks.get_active_session(talk.id).id == session.id
    end

    test "returns nil when no session has been started", %{talk: talk} do
      assert Talks.get_active_session(talk.id) == nil
    end

    test "returns nil after the session is stopped", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      Talks.stop_session(session)
      assert Talks.get_active_session(talk.id) == nil
    end
  end

  describe "get_session/1 and get_session!/1" do
    test "get_session/1 returns the session by id", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert Talks.get_session(session.id).id == session.id
    end

    test "get_session/1 returns nil for unknown id" do
      assert Talks.get_session(999_999) == nil
    end

    test "get_session!/1 raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Talks.get_session!(999_999) end
    end
  end

  describe "list_sessions/1" do
    test "returns sessions with reaction counts ordered newest first", %{talk: talk} do
      {:ok, s1} = Talks.start_session(talk)
      {:ok, _} = Talks.stop_session(s1)
      {:ok, s2} = Talks.start_session(talk)

      Speechwave.Reactions.create_reaction(s1, "❤️")
      Speechwave.Reactions.create_reaction(s1, "😂")

      entries = Talks.list_sessions(talk.id)

      assert length(entries) == 2
      [first, second] = entries
      assert first.session.id == s2.id
      assert first.reaction_count == 0
      assert second.session.id == s1.id
      assert second.reaction_count == 2
    end

    test "returns empty list for a talk with no sessions", %{talk: talk} do
      assert Talks.list_sessions(talk.id) == []
    end
  end

  describe "rename_session/2" do
    test "updates the session label", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert {:ok, renamed} = Talks.rename_session(session, "Denver Practice")
      assert renamed.label == "Denver Practice"
    end
  end

  describe "delete_session/1" do
    test "removes the session", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      assert {:ok, _} = Talks.delete_session(session)
      assert Talks.get_session(session.id) == nil
    end

    test "cascade-deletes its reactions", %{talk: talk} do
      {:ok, session} = Talks.start_session(talk)
      {:ok, reaction} = Speechwave.Reactions.create_reaction(session, "❤️")
      Talks.delete_session(session)
      assert Speechwave.Repo.get(Speechwave.Reactions.Reaction, reaction.id) == nil
    end
  end
end
