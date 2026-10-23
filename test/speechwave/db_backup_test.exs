defmodule Speechwave.DbBackupTest do
  # Not async: touches the shared deletion log file and application env.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL.Sandbox
  alias Speechwave.{DbBackup, DeletionLog, Repo}

  setup do
    File.rm(DeletionLog.path())

    tmp_dir = Path.join(System.tmp_dir!(), "db_backup_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    original = Application.fetch_env!(:speechwave, DbBackup)

    Application.put_env(:speechwave, DbBackup,
      storage: [
        url: "http://storage.test",
        bucket: "bucket",
        access_key_id: "key",
        secret_access_key: "secret"
      ],
      req_options: [plug: {Req.Test, DbBackup}, retry: false],
      tmp_dir: tmp_dir
    )

    on_exit(fn ->
      Application.put_env(:speechwave, DbBackup, original)
      File.rm_rf(tmp_dir)
    end)

    test_pid = self()

    Req.Test.stub(DbBackup, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:put, conn.request_path, body})
      Plug.Conn.send_resp(conn, 200, "")
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  # VACUUM INTO cannot run inside a transaction, so run outside the sandbox.
  defp run_now, do: Sandbox.unboxed_run(Repo, fn -> DbBackup.run_now() end)

  defp read_user_ids(sqlite_binary) do
    path = Path.join(System.tmp_dir!(), "uploaded_#{System.unique_integer([:positive])}.db")
    File.write!(path, sqlite_binary)
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT user_id FROM deletions")
    {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    Exqlite.Sqlite3.close(conn)
    File.rm(path)
    List.flatten(rows)
  end

  test "uploads both databases under their own keys" do
    :ok = DeletionLog.record(1, :self)
    run_now()

    assert_received {:put, "/bucket/backup/speechwave.db", main_body}
    assert_received {:put, "/bucket/backup/deletions.db", _}
    assert String.starts_with?(main_body, "SQLite format 3")
  end

  test "the deletions upload is a SQLite file containing the logged ids" do
    :ok = DeletionLog.record(99, :self)

    run_now()

    assert_received {:put, "/bucket/backup/deletions.db", body}
    assert read_user_ids(body) == [99]
  end

  test "a failing upload of one file does not stop the other" do
    :ok = DeletionLog.record(1, :self)
    test_pid = self()

    Req.Test.stub(DbBackup, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:put, conn.request_path, body})

      if String.ends_with?(conn.request_path, "speechwave.db"),
        do: Plug.Conn.send_resp(conn, 500, "boom"),
        else: Plug.Conn.send_resp(conn, 200, "")
    end)

    log = capture_log(fn -> run_now() end)

    assert log =~ "Backup of backup/speechwave.db failed"
    assert_received {:put, "/bucket/backup/deletions.db", _}
  end

  test "scrubs ids older than 30 days before uploading the log" do
    :ok = DeletionLog.record(5, :self, DateTime.add(DateTime.utc_now(), -31 * 24 * 3600, :second))
    :ok = DeletionLog.record(6, :self)

    run_now()

    assert_received {:put, "/bucket/backup/deletions.db", body}
    assert read_user_ids(body) |> Enum.sort() == [6, nil]
  end

  test "removes its temp files", %{tmp_dir: tmp_dir} do
    run_now()
    assert File.ls!(tmp_dir) == []
  end

  test "does not upload deletions.db when there is no log yet" do
    run_now()

    assert_received {:put, "/bucket/backup/speechwave.db", _}
    refute_received {:put, "/bucket/backup/deletions.db", _}
    refute File.exists?(DeletionLog.path())
  end
end
