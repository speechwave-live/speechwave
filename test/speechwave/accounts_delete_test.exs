defmodule Speechwave.AccountsDeleteTest do
  # Not async: the deletion log is one shared file.
  use Speechwave.DataCase, async: false

  import Ecto.Query
  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Accounts
  alias Speechwave.Accounts.{User, UserConsent, UserIdentity, UserToken}
  alias Speechwave.DeletionLog
  alias Speechwave.Reactions.Reaction
  alias Speechwave.Talks.{Talk, TalkSession}

  setup do
    File.rm(DeletionLog.path())
    :ok
  end

  defp populate(user) do
    {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")
    identity_fixture(user)
    session_token_fixture(user)
    talk = talk_fixture(user)
    session = session_fixture(talk)
    Repo.insert!(%Reaction{talk_session_id: session.id, emoji: "👍"})
    :ok
  end

  defp count_for(user_id) do
    %{
      users: Repo.aggregate(from(u in User, where: u.id == ^user_id), :count),
      consents: Repo.aggregate(from(c in UserConsent, where: c.user_id == ^user_id), :count),
      identities: Repo.aggregate(from(i in UserIdentity, where: i.user_id == ^user_id), :count),
      tokens: Repo.aggregate(from(t in UserToken, where: t.user_id == ^user_id), :count),
      talks: Repo.aggregate(from(t in Talk, where: t.user_id == ^user_id), :count),
      sessions:
        Repo.aggregate(
          from(s in TalkSession,
            join: t in Talk,
            on: s.talk_id == t.id,
            where: t.user_id == ^user_id
          ),
          :count
        ),
      reactions:
        Repo.aggregate(
          from(r in Reaction,
            join: s in TalkSession,
            on: r.talk_session_id == s.id,
            join: t in Talk,
            on: s.talk_id == t.id,
            where: t.user_id == ^user_id
          ),
          :count
        )
    }
  end

  describe "delete_account/2" do
    test "deletes the user and cascades to everything they own" do
      user = user_fixture()
      other = user_fixture()
      populate(user)
      populate(other)

      assert Enum.all?(count_for(user.id), fn {_, n} -> n >= 1 end)

      assert {:ok, %User{}} = Accounts.delete_account(user, user.email)

      assert Enum.all?(count_for(user.id), fn {_, n} -> n == 0 end)
      assert Enum.all?(count_for(other.id), fn {_, n} -> n >= 1 end)
    end

    test "records exactly one log row with the user's id" do
      user = user_fixture()
      {:ok, _} = Accounts.delete_account(user, user.email)

      assert DeletionLog.logged_ids() == [user.id]
      assert [%DateTime{}] = DeletionLog.deleted_ats()
    end

    test "accepts the email with surrounding whitespace" do
      user = user_fixture()
      assert {:ok, _} = Accounts.delete_account(user, "  #{user.email}\n")
    end

    test "rejects a different case, a wrong email, a blank email and non-text input" do
      user = user_fixture()

      for typed <- [String.upcase(user.email), "someone@else.com", "", "   ", nil, 42] do
        assert {:error, :confirmation_mismatch} = Accounts.delete_account(user, typed)
      end

      assert Repo.get(User, user.id)
      assert DeletionLog.logged_ids() == []
    end

    test "refuses an admin even with the right email" do
      admin = admin_user_fixture()
      assert {:error, :admin} = Accounts.delete_account(admin, admin.email)
      assert Repo.get(User, admin.id)
      assert DeletionLog.logged_ids() == []
    end

    @tag :capture_log
    test "returns :log_failed and deletes nothing when the log cannot be written" do
      original = Application.fetch_env!(:speechwave, :deletions_db_path)
      on_exit(fn -> Application.put_env(:speechwave, :deletions_db_path, original) end)

      Application.put_env(
        :speechwave,
        :deletions_db_path,
        Path.join(System.tmp_dir!(), "no_such_dir_#{System.unique_integer([:positive])}/d.db")
      )

      user = user_fixture()
      assert {:error, :log_failed} = Accounts.delete_account(user, user.email)
      assert Repo.get(User, user.id)
    end

    test "scrubs old log rows while deleting" do
      :ok = DeletionLog.record(9_999, DateTime.add(DateTime.utc_now(), -31 * 24 * 3600, :second))
      user = user_fixture()

      {:ok, _} = Accounts.delete_account(user, user.email)

      assert DeletionLog.logged_ids() == [user.id]
      assert length(DeletionLog.deleted_ats()) == 2
    end

    test "deleting a user that is already gone returns {:ok, user} and logs it only once" do
      user = user_fixture()
      assert {:ok, _} = Accounts.delete_account(user, user.email)
      assert {:ok, _} = Accounts.delete_account(user, user.email)
      assert length(DeletionLog.deleted_ats()) == 1
    end
  end

  describe "reapply_recorded_deletions/0" do
    defp restore_user(id, email) do
      Repo.query!(
        "INSERT INTO users (id, email, inserted_at, updated_at) VALUES (?1, ?2, datetime('now'), datetime('now'))",
        [id, email]
      )
    end

    test "removes a user restored by hand and returns the count" do
      user = user_fixture()
      id = user.id
      {:ok, _} = Accounts.delete_account(user, user.email)

      restore_user(id, user.email)
      assert Repo.get(User, id)

      assert Accounts.reapply_recorded_deletions() == 1
      refute Repo.get(User, id)
    end

    test "returns 0 when no logged id has a user" do
      :ok = DeletionLog.record(123_456)
      assert Accounts.reapply_recorded_deletions() == 0
    end

    test "raises the users id sequence above the highest logged id" do
      :ok = DeletionLog.record(500)
      Accounts.reapply_recorded_deletions()

      assert user_fixture().id > 500
    end

    test "ignores rows whose user_id was scrubbed" do
      user = user_fixture()
      id = user.id
      {:ok, _} = Accounts.delete_account(user, user.email)
      :ok = DeletionLog.scrub(DateTime.add(DateTime.utc_now(), 31 * 24 * 3600, :second))

      restore_user(id, user.email)
      assert Accounts.reapply_recorded_deletions() == 0
      assert Repo.get(User, id)
    end
  end

  describe "reapply_recorded_deletions/1 with extra log files" do
    @describetag :capture_log
    # After restoring a whole Fly volume snapshot, deletions.db is rolled back
    # too, so the newer copy from object storage is passed in as an extra log.
    defp extra_log_with(ids) do
      path = Path.join(System.tmp_dir!(), "extra_log_#{System.unique_integer([:positive])}.db")
      live = DeletionLog.path()
      File.rm(path)
      Application.put_env(:speechwave, :deletions_db_path, path)
      Enum.each(ids, &DeletionLog.record/1)
      Application.put_env(:speechwave, :deletions_db_path, live)
      on_exit(fn -> File.rm(path) end)
      path
    end

    test "also deletes users whose ids are only in the extra log and records them in the live log" do
      user = user_fixture()
      extra = extra_log_with([user.id])

      assert DeletionLog.logged_ids() == []
      assert Accounts.reapply_recorded_deletions([extra]) == 1
      refute Repo.get(User, user.id)
      assert DeletionLog.logged_ids() == [user.id]
    end

    test "raises when an extra log file does not exist" do
      assert_raise ArgumentError, fn ->
        Accounts.reapply_recorded_deletions(["/nonexistent/dir/log.db"])
      end
    end

    test "raises the sequence using ids from the extra log" do
      extra = extra_log_with([800])
      Accounts.reapply_recorded_deletions([extra])
      assert user_fixture().id > 800
    end

    @tag :capture_log
    test "warns instead of silently returning 0 when the live log file is missing" do
      log =
        ExUnit.CaptureLog.capture_log([level: :warning], fn ->
          Accounts.reapply_recorded_deletions()
        end)

      assert log =~ "deletion log"
    end
  end
end
