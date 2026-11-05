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
end
