defmodule Speechwave.DeletionLogTest do
  # Not async: the log is one shared file.
  use ExUnit.Case, async: false

  alias Speechwave.DeletionLog

  setup do
    File.rm(DeletionLog.path())
    :ok
  end

  defp days_ago(days, extra_hours \\ 0) do
    DateTime.add(DateTime.utc_now(), -(days * 24 + extra_hours) * 3600, :second)
  end

  test "record stores the id and timestamp and nothing else" do
    assert :ok = DeletionLog.record(42)
    assert DeletionLog.logged_ids() == [42]
    assert [%DateTime{}] = DeletionLog.deleted_ats()

    {:ok, conn} = Exqlite.Sqlite3.open(DeletionLog.path())
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT name FROM pragma_table_info('deletions')")
    {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    Exqlite.Sqlite3.close(conn)

    assert rows |> List.flatten() |> Enum.sort() == ["deleted_at", "user_id"]
  end

  test "creates the file and table on first use" do
    refute File.exists?(DeletionLog.path())
    assert :ok = DeletionLog.record(1)
    assert File.exists?(DeletionLog.path())
  end

  test "scrub nulls ids older than 30 days and keeps the row" do
    :ok = DeletionLog.record(1, days_ago(31))
    :ok = DeletionLog.record(2, DateTime.utc_now())
    assert :ok = DeletionLog.scrub()
    assert DeletionLog.logged_ids() == [2]
    assert length(DeletionLog.deleted_ats()) == 2
  end

  test "scrub leaves a row just inside 30 days" do
    :ok = DeletionLog.record(3, days_ago(29, 23))
    assert :ok = DeletionLog.scrub()
    assert DeletionLog.logged_ids() == [3]
  end

  test "scrub is idempotent" do
    :ok = DeletionLog.record(1, days_ago(40))
    :ok = DeletionLog.record(2)
    :ok = DeletionLog.scrub()
    :ok = DeletionLog.scrub()
    assert DeletionLog.logged_ids() == [2]
    assert length(DeletionLog.deleted_ats()) == 2
  end

  test "record returns an error tuple when the directory does not exist" do
    original = Application.fetch_env!(:speechwave, :deletions_db_path)
    on_exit(fn -> Application.put_env(:speechwave, :deletions_db_path, original) end)

    Application.put_env(
      :speechwave,
      :deletions_db_path,
      Path.join(System.tmp_dir!(), "no_such_dir_#{System.unique_integer([:positive])}/d.db")
    )

    assert {:error, _} = DeletionLog.record(1)
  end

  test "snapshot_to writes a readable copy" do
    :ok = DeletionLog.record(7)

    dest =
      Path.join(System.tmp_dir!(), "deletions_snapshot_#{System.unique_integer([:positive])}.db")

    on_exit(fn -> File.rm(dest) end)

    assert :ok = DeletionLog.snapshot_to(dest)

    {:ok, conn} = Exqlite.Sqlite3.open(dest)
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT user_id FROM deletions")
    {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)
    Exqlite.Sqlite3.close(conn)

    assert rows == [[7]]
  end

  describe "when the log file does not exist" do
    # An empty log must never be created by a read, scrub or backup: a lost
    # deletions.db has to stay visibly missing, not turn into an empty file
    # that then overwrites the good copy in object storage.
    test "scrub, logged_ids and deleted_ats do not create it" do
      assert :ok = DeletionLog.scrub()
      assert DeletionLog.logged_ids() == []
      assert DeletionLog.deleted_ats() == []
      refute File.exists?(DeletionLog.path())
    end

    test "snapshot_to returns :skip and writes nothing" do
      dest =
        Path.join(System.tmp_dir!(), "no_log_snapshot_#{System.unique_integer([:positive])}.db")

      assert :skip = DeletionLog.snapshot_to(dest)
      refute File.exists?(dest)
      refute File.exists?(DeletionLog.path())
    end
  end

  test "scrub keeps a row exactly 30 days old" do
    now = ~U[2026-11-15 12:00:00Z]
    :ok = DeletionLog.record(5, DateTime.add(now, -30 * 24 * 3600, :second))
    :ok = DeletionLog.record(6, DateTime.add(now, -30 * 24 * 3600 - 1, :second))

    assert :ok = DeletionLog.scrub(now)
    assert DeletionLog.logged_ids() == [5]
  end

  test "entries can read another log file by path" do
    :ok = DeletionLog.record(11)
    copy = Path.join(System.tmp_dir!(), "other_log_#{System.unique_integer([:positive])}.db")
    on_exit(fn -> File.rm(copy) end)
    :ok = DeletionLog.snapshot_to(copy)
    File.rm(DeletionLog.path())

    assert [{11, %DateTime{}}] = DeletionLog.entries(copy)
    assert DeletionLog.logged_ids() == []
  end

  describe "entries/1" do
    test "returns unscrubbed {id, deleted_at} pairs from the given file" do
      at = DateTime.utc_now() |> DateTime.truncate(:second)
      :ok = DeletionLog.record(1, at)
      :ok = DeletionLog.record(2, days_ago(40))
      :ok = DeletionLog.scrub()

      assert DeletionLog.entries(DeletionLog.path()) == [{1, at}]
    end

    test "raises for a SQLite file without a deletions table and does not modify it" do
      other = Path.join(System.tmp_dir!(), "other_#{System.unique_integer([:positive])}.db")
      {:ok, conn} = Exqlite.Sqlite3.open(other)
      :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE unrelated (x INTEGER)")
      Exqlite.Sqlite3.close(conn)
      on_exit(fn -> File.rm(other) end)
      before = File.read!(other)

      assert_raise ArgumentError, ~r/deletions/, fn -> DeletionLog.entries(other) end
      assert File.read!(other) == before
    end
  end

  describe "scrub_logging_errors/0" do
    @tag :capture_log
    test "returns :ok and logs a warning when the scrub fails" do
      original = Application.fetch_env!(:speechwave, :deletions_db_path)
      on_exit(fn -> Application.put_env(:speechwave, :deletions_db_path, original) end)
      File.rm(original)
      File.touch!(original)
      File.chmod!(original, 0o000)
      on_exit(fn -> File.chmod(original, 0o644) end)

      log =
        ExUnit.CaptureLog.capture_log([level: :warning], fn ->
          assert :ok = DeletionLog.scrub_logging_errors()
        end)

      assert log =~ "scrub deletion log"
    end
  end
end
