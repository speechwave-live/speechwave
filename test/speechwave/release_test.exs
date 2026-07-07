defmodule Speechwave.ReleaseTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures
  alias Speechwave.Accounts.User
  alias Speechwave.Release

  describe "unconfirmed_with_evidence_count/1" do
    test "counts a user with a session token but no confirmed_at" do
      user = user_fixture()
      session_token_fixture(user)

      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [confirmed_at: nil]
      )

      assert Release.unconfirmed_with_evidence_count(Repo) == 1
    end

    test "excludes a properly confirmed user" do
      user = user_fixture()
      session_token_fixture(user)

      assert Release.unconfirmed_with_evidence_count(Repo) == 0
    end

    test "excludes a genuinely unconfirmed user with no token or identity" do
      user_fixture()

      assert Release.unconfirmed_with_evidence_count(Repo) == 0
    end
  end
end
