defmodule Speechwave.DataExportTest do
  use Speechwave.DataCase, async: true

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Accounts
  alias Speechwave.Accounts.Scope
  alias Speechwave.DataExport

  describe "build/2" do
    test "a user with no data gets empty lists and their account fields" do
      user = user_fixture()
      export = DataExport.build(Scope.for_user(user))

      assert export.format_version == 1
      assert %DateTime{} = export.exported_at
      assert export.account.email == user.email
      assert export.account.plan == "free"
      assert export.account.is_admin == false
      assert export.account.fireworks_enabled == true
      assert export.account.confirmed_at == user.confirmed_at
      assert export.sign_in_providers == []
      assert export.consents == []
      assert export.talks == []
    end

    test "includes provider uids and consents" do
      user = user_fixture()
      identity_fixture(user, %{provider: "github", uid: "gh-123"})
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "pricing_pro")

      export = DataExport.build(Scope.for_user(user))

      assert [%{provider: "github", uid: "gh-123", linked_at: %DateTime{}}] =
               export.sign_in_providers

      assert [
               %{
                 consent_type: "marketing_email",
                 granted: true,
                 source: "pricing_pro",
                 revoked_at: nil
               }
             ] = export.consents
    end

    test "summarises reactions per session without raw rows" do
      user = user_fixture()
      talk = talk_fixture(user, %{title: "My Talk"})
      session = session_fixture(talk, %{label: "Morning"})
      reaction_fixture(session, "🔥", 1, "aud-a")
      reaction_fixture(session, "🔥", 2, "aud-b")
      reaction_fixture(session, "❤️", 2, nil)

      export = DataExport.build(Scope.for_user(user))

      assert [%{title: "My Talk", sessions: [s]}] = export.talks
      assert s.label == "Morning"
      assert s.reactions.total == 3
      assert s.reactions.audience_size == 2
      assert s.reactions.by_emoji == %{"🔥" => 2, "❤️" => 1}

      assert Enum.sort_by(s.reactions.by_slide, &{&1.slide_number, &1.emoji}) == [
               %{slide_number: 1, emoji: "🔥", count: 1},
               %{slide_number: 2, emoji: "❤️", count: 1},
               %{slide_number: 2, emoji: "🔥", count: 1}
             ]
    end

    test "a talk without sessions and a session without reactions are empty, not missing" do
      user = user_fixture()
      _empty_talk = talk_fixture(user)
      talk = talk_fixture(user)
      session_fixture(talk)

      export = DataExport.build(Scope.for_user(user))
      by_sessions = Enum.map(export.talks, &length(&1.sessions))

      assert Enum.sort(by_sessions) == [0, 1]

      [%{reactions: r}] = Enum.flat_map(export.talks, & &1.sessions)
      assert r == %{total: 0, audience_size: nil, by_emoji: %{}, by_slide: []}
    end

    test "never includes another user's data" do
      user = user_fixture()
      other = user_fixture()
      talk = talk_fixture(other, %{title: "Other Talk"})
      reaction_fixture(session_fixture(talk), "🔥", 1, "aud-x")
      identity_fixture(other, %{uid: "other-uid"})
      {:ok, _} = Accounts.grant_consent(other, "marketing_email")

      json = user |> Scope.for_user() |> DataExport.build() |> Jason.encode!()

      refute json =~ "Other Talk"
      refute json =~ "other-uid"
      refute json =~ other.email
      assert DataExport.build(Scope.for_user(user)).consents == []
    end

    test "leaves out the api key and audience ids" do
      user = user_fixture()
      talk = talk_fixture(user)
      reaction_fixture(session_fixture(talk), "🔥", 1, "audience-secret-id")

      json = user |> Scope.for_user() |> DataExport.build() |> Jason.encode!()

      assert is_binary(user.api_key)
      refute json =~ user.api_key
      refute json =~ "audience-secret-id"
    end
  end
end
