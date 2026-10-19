defmodule Speechwave.TalksFixtures do
  @moduledoc false
  # Test factory module. talk_fixture/2 and session_fixture/2 insert records
  # and return the structs, following the convention from phx.gen.auth's
  # AccountsFixtures. Import in test files with:
  #   import Speechwave.TalksFixtures

  import Ecto.Query

  alias Speechwave.Accounts.Scope

  def talk_fixture(user, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    {:ok, talk} =
      Speechwave.Talks.create_talk(
        %Scope{user: user},
        Enum.into(attrs, %{title: "Test Talk #{n}", slug: "test-talk-#{n}"})
      )

    talk
  end

  def session_fixture(talk, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
      talk_id: talk.id,
      label: Map.get(attrs, :label, "Session 1"),
      started_at: Map.get(attrs, :started_at, now),
      ended_at: Map.get(attrs, :ended_at, nil)
    })
  end

  def reaction_fixture(session, emoji, slide_number \\ 0, audience_id \\ nil) do
    {:ok, reaction} =
      Speechwave.Reactions.create_reaction(session, emoji, slide_number, audience_id)

    reaction
  end

  # A talk with two finished sessions and a few reactions on slides 1 and 2.
  # Replaces scripts/manual_tests/seed_sessions.exs for browser tests.
  # Session 1 has 3 reactions (slide 1: fire and heart, slide 2: party popper),
  # session 2 has 2 (slide 1: fire, slide 2: clapping hands).
  def talk_with_two_finished_sessions_fixture(user) do
    talk = talk_fixture(user)

    {:ok, session1} = Speechwave.Talks.start_session(talk)
    reaction_fixture(session1, "🔥", 1)
    reaction_fixture(session1, "❤️", 1)
    reaction_fixture(session1, "🎉", 2)
    {:ok, session1} = Speechwave.Talks.stop_session(session1)

    {:ok, session2} = Speechwave.Talks.start_session(talk)
    reaction_fixture(session2, "🔥", 1)
    reaction_fixture(session2, "👏", 2)
    {:ok, session2} = Speechwave.Talks.stop_session(session2)

    %{talk: talk, session1: session1, session2: session2}
  end

  def backdate_talk(talk, inserted_at) do
    Speechwave.Repo.update_all(
      from(t in Speechwave.Talks.Talk, where: t.id == ^talk.id),
      set: [inserted_at: inserted_at]
    )

    %{talk | inserted_at: inserted_at}
  end

  def backdate_session(session, inserted_at) do
    Speechwave.Repo.update_all(
      from(s in Speechwave.Talks.TalkSession, where: s.id == ^session.id),
      set: [inserted_at: inserted_at]
    )

    %{session | inserted_at: inserted_at}
  end
end
