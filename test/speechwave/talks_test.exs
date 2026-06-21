defmodule Speechwave.TalksTest do
  use Speechwave.DataCase

  alias Speechwave.Accounts.Scope
  alias Speechwave.Talks
  alias Speechwave.Talks.Talk

  import Speechwave.AccountsFixtures

  defp scope(user), do: %Scope{user: user}

  describe "Talk.changeset/2" do
    test "valid with title and slug" do
      cs = Talk.changeset(%Talk{}, %{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})
      assert cs.valid?
    end

    test "requires title" do
      cs = Talk.changeset(%Talk{}, %{slug: "test"})
      assert "can't be blank" in errors_on(cs).title
    end

    test "requires slug" do
      cs = Talk.changeset(%Talk{}, %{title: "Test"})
      assert "can't be blank" in errors_on(cs).slug
    end

    test "rejects slug with uppercase letters" do
      cs = Talk.changeset(%Talk{}, %{title: "Test", slug: "My-Slug"})
      assert "only lowercase letters, numbers, and hyphens" in errors_on(cs).slug
    end

    test "rejects slug with spaces" do
      cs = Talk.changeset(%Talk{}, %{title: "Test", slug: "test slug"})
      assert "only lowercase letters, numbers, and hyphens" in errors_on(cs).slug
    end

    test "rejects slug longer than 100 chars" do
      cs = Talk.changeset(%Talk{}, %{title: "Test", slug: String.duplicate("a", 101)})
      assert "should be at most 100 character(s)" in errors_on(cs).slug
    end
  end

  describe "create_talk/2" do
    test "creates a talk owned by the user" do
      user = user_fixture()

      assert {:ok, talk} =
               Talks.create_talk(scope(user), %{
                 title: "Elixir for Rubyists",
                 slug: "elixir-for-rubyists"
               })

      assert talk.title == "Elixir for Rubyists"
      assert talk.slug == "elixir-for-rubyists"
      assert talk.user_id == user.id
    end

    test "returns error on duplicate slug" do
      user = user_fixture()
      {:ok, _} = Talks.create_talk(scope(user), %{title: "Talk 1", slug: "my-talk"})
      assert {:error, cs} = Talks.create_talk(scope(user), %{title: "Talk 2", slug: "my-talk"})
      assert "has already been taken" in errors_on(cs).slug
    end
  end

  describe "list_talks/1" do
    test "returns only talks owned by the scoped user" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, _} = Talks.create_talk(scope(user_a), %{title: "Talk A", slug: "talk-a"})
      {:ok, _} = Talks.create_talk(scope(user_b), %{title: "Talk B", slug: "talk-b"})

      assert [talk] = Talks.list_talks(scope(user_a))
      assert talk.title == "Talk A"
    end
  end

  describe "get_talk!/2" do
    test "returns the talk when owned by the scoped user" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "test-talk"})
      assert Talks.get_talk!(scope(user), talk.id).id == talk.id
    end

    test "raises when talk belongs to a different user" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user_a), %{title: "Test", slug: "test-talk"})

      assert_raise Ecto.NoResultsError, fn ->
        Talks.get_talk!(scope(user_b), talk.id)
      end
    end
  end

  describe "get_talk_by_slug/1" do
    test "returns talk when found (no scope — public)" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "test-talk"})
      assert Talks.get_talk_by_slug("test-talk").id == talk.id
    end

    test "returns nil when not found" do
      assert Talks.get_talk_by_slug("nonexistent") == nil
    end
  end

  describe "get_talk_with_owner/1" do
    test "returns talk with user preloaded" do
      user = user_fixture()
      {:ok, _} = Talks.create_talk(scope(user), %{title: "Test", slug: "owner-test"})
      talk = Talks.get_talk_with_owner("owner-test")
      assert talk.user.id == user.id
    end

    test "returns nil when not found" do
      assert Talks.get_talk_with_owner("nonexistent") == nil
    end
  end

  describe "generate_slug/1" do
    test "lowercases and hyphenates words" do
      assert Talks.generate_slug("Elixir for Rubyists") == "elixir-for-rubyists"
    end

    test "removes special characters" do
      assert Talks.generate_slug("Hello, World!") == "hello-world"
    end

    test "collapses multiple spaces" do
      assert Talks.generate_slug("a  b") == "a-b"
    end

    test "trims leading/trailing spaces" do
      assert Talks.generate_slug("  island  ") == "island"
    end
  end

  describe "count_full_sessions_this_month/1" do
    test "counts only sessions longer than 10 minutes this month" do
      user = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "full-count"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      short_end = DateTime.add(now, 5 * 60, :second)
      full_end = DateTime.add(now, 15 * 60, :second)

      # Short session (5 min) — should not count
      Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
        talk_id: talk.id,
        label: "Short",
        started_at: now,
        ended_at: short_end
      })

      # Full session (15 min) — should count
      Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
        talk_id: talk.id,
        label: "Full",
        started_at: now,
        ended_at: full_end
      })

      # Active session (no ended_at) — should not count
      Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
        talk_id: talk.id,
        label: "Active",
        started_at: now,
        ended_at: nil
      })

      assert Talks.count_full_sessions_this_month(scope(user)) == 1
    end

    test "does not count sessions from another user's talks" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, talk} = Talks.create_talk(scope(user_a), %{title: "Talk A", slug: "count-isolation"})

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      full_end = DateTime.add(now, 15 * 60, :second)

      Speechwave.Repo.insert!(%Speechwave.Talks.TalkSession{
        talk_id: talk.id,
        label: "Full",
        started_at: now,
        ended_at: full_end
      })

      assert Talks.count_full_sessions_this_month(scope(user_b)) == 0
    end
  end
end
