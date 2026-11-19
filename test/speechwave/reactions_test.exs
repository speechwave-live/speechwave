defmodule Speechwave.ReactionsTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.{Reactions, Talks}

  setup do
    user = user_fixture()
    talk = talk_fixture(user)
    {:ok, session} = Talks.start_session(talk)
    %{session: session}
  end

  describe "record_reaction/4" do
    import ExUnit.CaptureLog

    test "stores the reaction and returns :ok", %{session: session} do
      assert :ok = Reactions.record_reaction(session.talk_id, "🔥", 2, nil)
      assert Reactions.count_reactions(session.id) == 1
    end

    test "stores an audience id derived from the client id", %{session: session} do
      client_id = Ecto.UUID.generate()
      assert :ok = Reactions.record_reaction(session.talk_id, "🔥", 0, client_id)
      assert Reactions.count_audience(session.id) == 1
    end

    test "returns :ok and stores nothing when the talk has no active session", %{session: session} do
      {:ok, _} = Talks.stop_session(session)
      assert :ok = Reactions.record_reaction(session.talk_id, "🔥", 0, nil)
      assert Reactions.count_reactions(session.id) == 0
    end

    test "returns {:error, :db_busy}, logs and emits telemetry when the database is saturated",
         %{session: session} do
      :telemetry_test.attach_event_handlers(self(), [[:speechwave, :reaction, :insert_failed]])
      client_id = Ecto.UUID.generate()
      release = hold_connection()

      log =
        capture_log(fn ->
          assert {:error, :db_busy} =
                   Reactions.record_reaction(session.talk_id, "🔥", 0, client_id)
        end)

      release.()

      assert_received {[:speechwave, :reaction, :insert_failed], _ref, %{count: 1}, _meta}
      assert log =~ "reaction"
      refute log =~ "🔥"
      refute log =~ client_id
    end
  end

  describe "create_reaction/3" do
    test "creates a reaction with default slide 0", %{session: session} do
      assert {:ok, reaction} = Reactions.create_reaction(session, "❤️")
      assert reaction.emoji == "❤️"
      assert reaction.slide_number == 0
      assert reaction.talk_session_id == session.id
    end

    test "creates a reaction with a specified slide number", %{session: session} do
      assert {:ok, reaction} = Reactions.create_reaction(session, "😂", 5)
      assert reaction.slide_number == 5
    end

    test "requires emoji", %{session: session} do
      assert {:error, changeset} = Reactions.create_reaction(session, nil)
      assert "can't be blank" in errors_on(changeset).emoji
    end
  end

  describe "count_reactions/1" do
    test "returns count of reactions for a session", %{session: session} do
      Reactions.create_reaction(session, "❤️")
      Reactions.create_reaction(session, "😂")
      assert Reactions.count_reactions(session.id) == 2
    end

    test "returns 0 for a session with no reactions", %{session: session} do
      assert Reactions.count_reactions(session.id) == 0
    end
  end

  describe "slide_reaction_totals/1" do
    test "returns per-slide per-emoji counts ordered by slide number", %{session: session} do
      Reactions.create_reaction(session, "❤️", 1)
      Reactions.create_reaction(session, "❤️", 1)
      Reactions.create_reaction(session, "😂", 1)
      Reactions.create_reaction(session, "❤️", 3)
      Reactions.create_reaction(session, "❤️", 0)

      totals = Reactions.slide_reaction_totals(session.id)

      # Ordered by slide number ascending
      assert Enum.map(totals, & &1.slide_number) == [0, 1, 1, 3]

      slide1_heart = Enum.find(totals, &(&1.slide_number == 1 and &1.emoji == "❤️"))
      assert slide1_heart.count == 2

      slide1_laugh = Enum.find(totals, &(&1.slide_number == 1 and &1.emoji == "😂"))
      assert slide1_laugh.count == 1
    end

    test "returns empty list for session with no reactions", %{session: session} do
      assert Reactions.slide_reaction_totals(session.id) == []
    end
  end

  describe "slide_audience_counts/1" do
    test "counts distinct audience ids per slide", %{session: session} do
      Reactions.create_reaction(session, "❤️", 1, "a")
      Reactions.create_reaction(session, "😂", 1, "a")
      Reactions.create_reaction(session, "😂", 1, "b")
      Reactions.create_reaction(session, "❤️", 2, "a")
      Reactions.create_reaction(session, "❤️", 3)
      Reactions.create_reaction(session, "❤️", 0, "c")

      {:ok, other} =
        Talks.start_session(Speechwave.Repo.get!(Speechwave.Talks.Talk, session.talk_id))

      Reactions.create_reaction(other, "❤️", 1, "z")

      assert Reactions.slide_audience_counts(session.id) == %{0 => 1, 1 => 2, 2 => 1}
    end
  end

  describe "timeline/1" do
    @start ~U[2026-01-01 10:00:00Z]

    setup %{session: session} do
      talk = Speechwave.Repo.get!(Speechwave.Talks.Talk, session.talk_id)
      %{talk: talk, timed: session_fixture(talk, %{started_at: @start, ended_at: nil})}
    end

    test "returns nil when the session has no reactions", %{timed: timed} do
      assert Reactions.timeline(timed) == nil
    end

    test "counts reactions per bucket and finds the peak", %{timed: timed} do
      for offset <- [0, 3, 12, 14, 15], do: timed_reaction_fixture(timed, offset)

      assert %{bucket_seconds: 10, counts: [2, 3], peak: %{index: 1, count: 3}} =
               Reactions.timeline(timed)
    end

    test "a peak tie goes to the earliest bucket", %{timed: timed} do
      for offset <- [0, 1, 25, 26], do: timed_reaction_fixture(timed, offset)

      assert %{counts: [2, 0, 2], peak: %{index: 0, count: 2}} = Reactions.timeline(timed)
    end

    test "slide_starts use the earliest reaction per slide, sorted by offset", %{timed: timed} do
      timed_reaction_fixture(timed, 2, "❤️", 0)
      timed_reaction_fixture(timed, 5, "❤️", 2)
      timed_reaction_fixture(timed, 8, "❤️", 1)
      timed_reaction_fixture(timed, 20, "❤️", 2)
      timed_reaction_fixture(timed, 40, "❤️", 3)
      # A later return to slide 1 adds no second entry.
      timed_reaction_fixture(timed, 50, "❤️", 1)

      assert Reactions.timeline(timed).slide_starts == [
               %{slide: 2, offset_seconds: 5},
               %{slide: 1, offset_seconds: 8},
               %{slide: 3, offset_seconds: 40}
             ]
    end

    test "all reactions at offset 0 give a single bucket", %{timed: timed} do
      for _ <- 1..3, do: timed_reaction_fixture(timed, 0)

      assert %{counts: [3], peak: %{index: 0, count: 3}} = Reactions.timeline(timed)
    end

    test "the axis follows the last reaction, not a much later ended_at", %{talk: talk} do
      session =
        session_fixture(talk, %{started_at: @start, ended_at: DateTime.add(@start, 4, :hour)})

      timed_reaction_fixture(session, 0)
      timed_reaction_fixture(session, 600)

      timeline = Reactions.timeline(session)
      assert timeline.bucket_seconds == 15
      assert length(timeline.counts) == 41
    end

    test "reactions outside the session are clamped into the first and last buckets",
         %{talk: talk} do
      session =
        session_fixture(talk, %{started_at: @start, ended_at: DateTime.add(@start, 100, :second)})

      timed_reaction_fixture(session, -5)
      timed_reaction_fixture(session, 50)
      timed_reaction_fixture(session, 130)

      timeline = Reactions.timeline(session)
      assert timeline.bucket_seconds == 10
      assert length(timeline.counts) == 11
      assert hd(timeline.counts) == 1
      assert List.last(timeline.counts) == 1
      assert Enum.sum(timeline.counts) == 3
    end

    test "only slide 0 reactions give no slide starts", %{timed: timed} do
      timed_reaction_fixture(timed, 0, "❤️", 0)
      timed_reaction_fixture(timed, 30, "❤️", 0)

      assert %{slide_starts: [], counts: [1, 0, 0, 1]} = Reactions.timeline(timed)
    end

    test "works for an active session", %{talk: talk} do
      session = session_fixture(talk, %{started_at: @start, ended_at: nil})
      timed_reaction_fixture(session, 12)

      assert %{counts: [0, 1], slide_starts: [%{slide: 1, offset_seconds: 12}]} =
               Reactions.timeline(session)
    end

    test "contains no audience data", %{timed: timed} do
      timed_reaction_fixture(timed, 0, "❤️", 1, "audience-secret-aaa")
      timed_reaction_fixture(timed, 9, "🔥", 2, "audience-secret-bbb")

      json = Jason.encode!(Reactions.timeline(timed))
      refute json =~ "audience-secret-aaa"
      refute json =~ "audience-secret-bbb"
    end
  end
end
