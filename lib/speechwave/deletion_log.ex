defmodule Speechwave.DeletionLog do
  @moduledoc """
  A log of deleted user ids, kept in its own SQLite file (`deletions.db`).

  Its job is to stop deleted accounts from coming back when `speechwave.db`
  is restored from a backup: after a restore, `Accounts.reapply_recorded_deletions/0`
  deletes every user whose id is in this log. If the log lived inside
  `speechwave.db`, a restore would roll it back along with everything else and
  it could not do that job. A separate file on the same volume is left alone
  by a normal restore.

  A row holds only `user_id` and `deleted_at`: no email, no hash, nothing else
  about the person. Rows older than 30 days are scrubbed (`user_id` set to NULL,
  the row kept) so the timing of deletions stays available for reporting
  without anything identifying an account.

  Only `record/2` ever creates the file. A lost `deletions.db` must stay
  visibly missing: if a read, the start-up scrub or a backup quietly created an
  empty one, the hourly backup would overwrite the good copy in object storage
  with it.

  This module talks to SQLite through `Exqlite.Sqlite3` directly instead of an
  Ecto repo. Deletions are rare, so each call opens a short-lived connection,
  creates the table if it is missing (no migration, nothing to set up at
  deploy time), does its work and closes the connection.
  """

  alias Exqlite.Sqlite3

  @scrub_after_days 30

  @doc "Path of the log file, from `config :speechwave, :deletions_db_path`."
  def path, do: Application.fetch_env!(:speechwave, :deletions_db_path)

  @doc "Records that `user_id` was deleted at `deleted_at`."
  def record(user_id, deleted_at \\ DateTime.utc_now()) when is_integer(user_id) do
    with_conn(
      path(),
      fn conn ->
        query(conn, "INSERT INTO deletions (user_id, deleted_at) VALUES (?1, ?2)", [
          user_id,
          timestamp(deleted_at)
        ])
      end,
      create: true
    )
    |> to_ok()
  end

  @doc """
  Sets `user_id` to NULL on rows deleted more than 30 days before `now`.
  The rows themselves are kept. Does nothing if the log file does not exist.
  """
  def scrub(now \\ DateTime.utc_now()) do
    cutoff = timestamp(DateTime.add(now, -@scrub_after_days * 24 * 3600, :second))

    if File.exists?(path()) do
      with_conn(path(), fn conn ->
        query(
          conn,
          "UPDATE deletions SET user_id = NULL WHERE user_id IS NOT NULL AND deleted_at < ?1",
          [cutoff]
        )
      end)
      |> to_ok()
    else
      :ok
    end
  end

  @doc """
  Ids still present in the log (rows not yet scrubbed), ascending. Reads the
  live log by default, or the log file at `log_path`. A missing file reads as
  empty and is not created.
  """
  def logged_ids(log_path \\ path()) do
    read_column(
      log_path,
      "SELECT user_id FROM deletions WHERE user_id IS NOT NULL ORDER BY user_id"
    )
  end

  @doc "Every row's deletion time, ascending."
  def deleted_ats do
    path()
    |> read_column("SELECT deleted_at FROM deletions ORDER BY deleted_at")
    |> Enum.map(fn iso ->
      {:ok, dt, _} = DateTime.from_iso8601(iso)
      dt
    end)
  end

  @doc """
  Writes a consistent copy of the log to `dest_path` using `VACUUM INTO`.
  Returns `{:error, :no_log}` without creating anything if the log file does
  not exist, so a lost log is never replaced by an empty one.
  """
  def snapshot_to(dest_path) when is_binary(dest_path) do
    if File.exists?(path()) do
      escaped = String.replace(dest_path, "'", "''")

      with_conn(path(), fn conn -> Sqlite3.execute(conn, "VACUUM INTO '#{escaped}'") end)
      |> to_ok()
    else
      {:error, :no_log}
    end
  end

  defp read_column(log_path, sql) do
    if File.exists?(log_path) do
      {:ok, rows} = with_conn(log_path, fn conn -> query(conn, sql, []) end)
      List.flatten(rows)
    else
      []
    end
  end

  # Second precision, always UTC, so plain string comparison orders correctly.
  defp timestamp(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp to_ok({:ok, _}), do: :ok
  defp to_ok(:ok), do: :ok
  defp to_ok({:error, _} = error), do: error

  # SQLite creates a missing file on open, so callers that must not create the
  # log check `File.exists?/1` first; only `record/2` passes `create: true`.
  defp with_conn(log_path, fun, opts \\ []) do
    if File.exists?(log_path) or Keyword.get(opts, :create, false) do
      open_and_run(log_path, fun)
    else
      {:error, :no_log}
    end
  end

  defp open_and_run(log_path, fun) do
    case Sqlite3.open(log_path) do
      {:ok, conn} ->
        try do
          with :ok <- Sqlite3.execute(conn, "PRAGMA busy_timeout = 5000"),
               :ok <- ensure_schema(conn) do
            fun.(conn)
          end
        after
          Sqlite3.close(conn)
        end

      {:error, _} = error ->
        error
    end
  end

  defp ensure_schema(conn) do
    with :ok <-
           Sqlite3.execute(
             conn,
             "CREATE TABLE IF NOT EXISTS deletions (user_id INTEGER, deleted_at TEXT NOT NULL)"
           ) do
      Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS deletions_deleted_at_index ON deletions (deleted_at)"
      )
    end
  end

  defp query(conn, sql, args) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(stmt, args), do: Sqlite3.fetch_all(conn, stmt)
      after
        Sqlite3.release(conn, stmt)
      end
    end
  end
end
