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

      assert {:ok, %{user: %User{}}} = Accounts.delete_account(user, user.email)

      assert Enum.all?(count_for(user.id), fn {_, n} -> n == 0 end)
      assert Enum.all?(count_for(other.id), fn {_, n} -> n >= 1 end)
    end

    test "returns the session tokens the user had, so the caller can end live sessions" do
      user = user_fixture()
      session_token_fixture(user)

      expected =
        Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == "session")

      assert expected != []

      assert {:ok, %{session_tokens: tokens}} = Accounts.delete_account(user, user.email)
      assert Enum.sort(Enum.map(tokens, & &1.token)) == Enum.sort(Enum.map(expected, & &1.token))
    end

    test "records exactly one log row with the user's id" do
      user = user_fixture()
      {:ok, _} = Accounts.delete_account(user, user.email)

      assert DeletionLog.logged_ids() == [user.id]
      assert [%DateTime{}] = DeletionLog.deleted_ats()
      assert [{%DateTime{}, :self}] = DeletionLog.deletions_by_source()
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
      :ok =
        DeletionLog.record(
          9_999,
          :self,
          DateTime.add(DateTime.utc_now(), -31 * 24 * 3600, :second)
        )

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

  describe "deletion_confirmed?/2 and can_delete_account?/1" do
    test "match the trimmed, case-sensitive email for a non-admin" do
      user = user_fixture()
      assert Accounts.can_delete_account?(user)
      assert Accounts.deletion_confirmed?(user, "  #{user.email} ")
      refute Accounts.deletion_confirmed?(user, String.upcase(user.email))
      refute Accounts.deletion_confirmed?(user, nil)
    end

    test "never confirm an admin" do
      admin = admin_user_fixture()
      refute Accounts.can_delete_account?(admin)
      refute Accounts.deletion_confirmed?(admin, admin.email)
    end
  end

  describe "foreign keys to users" do
    # delete_account relies on the database cascade. A future table that
    # references users without ON DELETE CASCADE would make deletion fail.
    test "every one cascades on delete" do
      %{rows: tables} =
        Repo.query!(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        )

      offenders =
        for [table] <- tables,
            %{rows: fks} =
              Repo.query!(
                ~s|SELECT "table", "on_delete" FROM pragma_foreign_key_list('#{table}')|
              ),
            ["users", on_delete] <- fks,
            on_delete != "CASCADE",
            do: table

      assert offenders == []
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
      :ok = DeletionLog.record(123_456, :self)
      assert Accounts.reapply_recorded_deletions() == 0
    end

    test "raises the users id sequence above the highest logged id" do
      :ok = DeletionLog.record(500, :self)
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

  describe "reapply_recorded_deletions/0 with no log file" do
    @tag :capture_log
    test "warns instead of silently returning 0 when the live log file is missing" do
      log =
        ExUnit.CaptureLog.capture_log([level: :warning], fn ->
          Accounts.reapply_recorded_deletions()
        end)

      assert log =~ "deletion log"
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

      Enum.each(ids, fn
        {id, at, source} -> DeletionLog.record(id, source, at)
        {id, at} -> DeletionLog.record(id, :self, at)
        id -> DeletionLog.record(id, :self)
      end)

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

    test "keeps the original deletion time, so the 30 day window is not restarted" do
      user = user_fixture()

      extra =
        extra_log_with([{user.id, DateTime.add(DateTime.utc_now(), -31 * 24 * 3600, :second)}])

      assert Accounts.reapply_recorded_deletions([extra]) == 1
      :ok = DeletionLog.scrub()
      assert DeletionLog.logged_ids() == []
    end

    test "keeps the original source" do
      user = user_fixture()
      extra = extra_log_with([{user.id, DateTime.utc_now(), :suspicious}])

      assert Accounts.reapply_recorded_deletions([extra]) == 1
      assert [{_, :suspicious}] = DeletionLog.deletions_by_source()
    end

    test "records an id that appears twice in the extra log once" do
      extra = extra_log_with([700, 700])
      Accounts.reapply_recorded_deletions([extra])
      assert length(DeletionLog.deleted_ats()) == 1
    end

    test "raises instead of reporting success when the live log cannot be written" do
      extra = extra_log_with([701])
      original = Application.fetch_env!(:speechwave, :deletions_db_path)
      on_exit(fn -> Application.put_env(:speechwave, :deletions_db_path, original) end)
      Application.put_env(:speechwave, :deletions_db_path, "/nonexistent_dir_for_test/d.db")

      assert_raise RuntimeError, ~r/deletion log/, fn ->
        Accounts.reapply_recorded_deletions([extra])
      end
    end

    test "raises on a file that is not a deletion log and leaves it untouched" do
      other = Path.join(System.tmp_dir!(), "not_a_log_#{System.unique_integer([:positive])}.db")
      {:ok, conn} = Exqlite.Sqlite3.open(other)
      :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE unrelated (x INTEGER)")
      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(other) end)

      assert_raise ArgumentError, ~r/deletions/, fn ->
        Accounts.reapply_recorded_deletions([other])
      end

      {:ok, conn} = Exqlite.Sqlite3.open(other)
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master")
      {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
      Exqlite.Sqlite3.release(conn, stmt)
      Exqlite.Sqlite3.close(conn)
      assert rows == [["unrelated"]]
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
  end

  describe "delete_suspicious_users/0" do
    defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
    defp days_ago(n), do: DateTime.add(now(), -n, :day)

    defp confirmed_user_fixture do
      user = user_fixture()
      # confirmed_at is only set when a session token is generated.
      _token = session_token_fixture(user)
      user
    end

    test "deletes an unconfirmed user older than the cutoff and logs it as :suspicious" do
      user = user_fixture()
      backdate_user(user, days_ago(16))

      assert Accounts.delete_suspicious_users() == 1
      refute Repo.get(User, user.id)
      assert [{_, :suspicious}] = DeletionLog.deletions_by_source()
    end

    test "keeps an unconfirmed user inside the cutoff" do
      user = user_fixture()
      backdate_user(user, days_ago(14))

      assert Accounts.delete_suspicious_users() == 0
      assert Repo.get(User, user.id)
    end

    test "keeps a confirmed user of any age" do
      user = confirmed_user_fixture()
      backdate_user(user, days_ago(400))

      assert Accounts.delete_suspicious_users() == 0
      assert Repo.get(User, user.id)
    end

    test "keeps an unconfirmed admin" do
      admin = admin_user_fixture()
      backdate_user(admin, days_ago(400))

      assert Accounts.delete_suspicious_users() == 0
      assert Repo.get(User, admin.id)
    end

    test "returns 0 and does not create the log when nothing is eligible" do
      _ = user_fixture()

      assert Accounts.delete_suspicious_users() == 0
      refute File.exists?(DeletionLog.path())
    end

    test "a second sweep deletes nothing" do
      user = user_fixture()
      backdate_user(user, days_ago(16))

      assert Accounts.delete_suspicious_users() == 1
      assert Accounts.delete_suspicious_users() == 0
      assert [_one_row] = DeletionLog.deletions_by_source()
    end

    test "honours :suspicious_user_retention_days" do
      original = Application.get_env(:speechwave, :suspicious_user_retention_days)

      on_exit(fn ->
        if original,
          do: Application.put_env(:speechwave, :suspicious_user_retention_days, original),
          else: Application.delete_env(:speechwave, :suspicious_user_retention_days)
      end)

      Application.put_env(:speechwave, :suspicious_user_retention_days, 1)

      user = user_fixture()
      backdate_user(user, days_ago(2))

      assert Accounts.delete_suspicious_users() == 1
      refute Repo.get(User, user.id)
    end

    # Making exactly one deletion fail is impractical, so this all-fail case
    # stands in for "one failure does not stop the others".
    @tag :capture_log
    test "deletes nobody and does not raise when the log cannot be written" do
      original = Application.fetch_env!(:speechwave, :deletions_db_path)
      on_exit(fn -> Application.put_env(:speechwave, :deletions_db_path, original) end)

      Application.put_env(
        :speechwave,
        :deletions_db_path,
        Path.join(System.tmp_dir!(), "no_such_dir_#{System.unique_integer([:positive])}/d.db")
      )

      users = for _ <- 1..2, do: user_fixture()
      Enum.each(users, &backdate_user(&1, days_ago(16)))

      assert Accounts.delete_suspicious_users() == 0
      assert Enum.all?(users, &Repo.get(User, &1.id))
    end
  end
end
