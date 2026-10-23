defmodule Speechwave.DeletionLog do
  @moduledoc """
  A log of deleted user ids, kept in its own SQLite file (`deletions.db`).

  Its job is to stop deleted accounts from coming back when `speechwave.db`
  is restored from a backup: after a restore, `Accounts.reapply_recorded_deletions/1`
  deletes every user whose id is in this log. If the log lived inside
  `speechwave.db`, a restore would roll it back along with everything else and
  it could not do that job. A separate file on the same volume is left alone
  by a normal restore.

  A row holds only `user_id`, `deleted_at` and `source` (why the account was
  deleted: `:self`, `:suspicious` or `:inactive`; it identifies no one): no
  email, no hash, nothing else about the person. Rows older than 30 days are
  scrubbed (`user_id` set to NULL, the row kept) so the timing of deletions stays available for reporting
  without anything identifying an account.

  Only `record/3` ever creates the file. A lost `deletions.db` must stay
  visibly missing: if a read, the start-up scrub or a backup quietly created an
  empty one, the hourly backup would overwrite the good copy in object storage
  with it.

  This module talks to SQLite through `Exqlite.Sqlite3` directly instead of an
  Ecto repo. Deletions are rare, so each call opens a short-lived connection,
  creates the table if it is missing (no migration, nothing to set up at
  deploy time), does its work and closes the connection.
  """

  require Logger

  alias Exqlite.Sqlite3

  @scrub_after_days 30

  # The only reasons a deletion can be recorded for. In SQLite they are stored
  # as text and mapped back to atoms explicitly (see `source_atom/1`), never
  # with `String.to_atom/1`.
  @sources [:self, :suspicious, :inactive]

  @doc "Path of the log file, from `config :speechwave, :deletions_db_path`."
  def path, do: Application.fetch_env!(:speechwave, :deletions_db_path)

  @doc """
  Records that `user_id` was deleted at `deleted_at` for the reason `source`
  (`:self`, `:suspicious` or `:inactive`). Raises `ArgumentError` for any other
  source, before the file is touched.
  """
  def record(user_id, source, deleted_at \\ DateTime.utc_now()) when is_integer(user_id) do
    # Checked in the body rather than a guard so the caller gets a clear
    # ArgumentError instead of a FunctionClauseError.
    source in @sources ||
      raise ArgumentError, "unknown deletion source: #{inspect(source)}"

    with_conn(
      path(),
      fn conn ->
        query(
          conn,
          "INSERT INTO deletions (user_id, deleted_at, source) VALUES (?1, ?2, ?3)",
          [user_id, timestamp(deleted_at), Atom.to_string(source)]
        )
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
  Like `scrub/1`, but a failure is logged as a warning instead of returned.
  For callers that must carry on regardless (app boot, the hourly backup, a
  deletion that has already been recorded).
  """
  def scrub_logging_errors do
    case scrub() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("[DeletionLog] Could not scrub deletion log: #{inspect(reason)}")
    end
  end

  @doc """
  Ids still present in the live log (rows not yet scrubbed), ascending. A
  missing file reads as empty and is not created.
  """
  def logged_ids do
    if File.exists?(path()), do: path() |> entries() |> Enum.map(&elem(&1, 0)), else: []
  end

  @doc """
  The unscrubbed `{user_id, deleted_at, source}` rows of the log file at
  `log_path`, ascending by id. A log written before the `source` column existed
  reads as `:self`. The file is opened read-only, so reading never creates or
  changes anything. Raises `ArgumentError` if the file is missing or is not a
  deletion log (for example a `speechwave.db` passed by mistake).
  """
  def entries(log_path) when is_binary(log_path) do
    File.exists?(log_path) || raise ArgumentError, "deletion log not found: #{log_path}"

    with_read_only(log_path, fn conn ->
      query(
        conn,
        "SELECT user_id, deleted_at, #{source_select(conn)} FROM deletions " <>
          "WHERE user_id IS NOT NULL ORDER BY user_id",
        []
      )
    end)
    |> Enum.map(fn [id, iso, source] -> {id, parse_timestamp(iso), source_atom(source)} end)
  end

  @doc "Every row's deletion time (scrubbed or not), ascending. For reporting."
  def deleted_ats do
    if File.exists?(path()) do
      "SELECT deleted_at FROM deletions ORDER BY deleted_at"
      |> read_only(path())
      |> Enum.map(fn [iso] -> parse_timestamp(iso) end)
    else
      []
    end
  end

  @doc """
  Every row's `{deleted_at, source}` (scrubbed or not), ascending by time. For
  reporting. A missing file reads as empty and is not created.
  """
  def deletions_by_source do
    if File.exists?(path()) do
      with_read_only(path(), fn conn ->
        query(
          conn,
          "SELECT deleted_at, #{source_select(conn)} FROM deletions ORDER BY deleted_at",
          []
        )
      end)
      |> Enum.map(fn [iso, source] -> {parse_timestamp(iso), source_atom(source)} end)
    else
      []
    end
  end

  @doc """
  Writes a consistent copy of the log to `dest_path` using `VACUUM INTO`.
  Returns `:skip` without creating anything if the log file does
  not exist, so a lost log is never replaced by an empty one.
  """
  def snapshot_to(dest_path) when is_binary(dest_path) do
    if File.exists?(path()) do
      escaped = String.replace(dest_path, "'", "''")

      with_conn(path(), fn conn -> Sqlite3.execute(conn, "VACUUM INTO '#{escaped}'") end)
      |> to_ok()
    else
      :skip
    end
  end

  defp read_only(sql, log_path) do
    with_read_only(log_path, fn conn -> query(conn, sql, []) end)
  end

  # Runs `fun` (conn -> {:ok, rows} | {:error, reason}) on one read-only
  # connection, so a schema check and the query that follows share it.
  defp with_read_only(log_path, fun) do
    {:ok, conn} = Sqlite3.open(log_path, mode: :readonly)

    try do
      case fun.(conn) do
        {:ok, rows} ->
          rows

        {:error, reason} ->
          raise ArgumentError,
                "#{log_path} is not a deletion log (expected a `deletions` table): #{inspect(reason)}"
      end
    after
      Sqlite3.close(conn)
    end
  end

  # The SELECT expression for the source column. Logs written before the
  # column existed are read as `:self` without being modified (the connection
  # is read-only). `PRAGMA table_info` on a file with no `deletions` table
  # returns no rows, so the caller's SELECT is what fails for a non-log file.
  defp source_select(conn) do
    case query(conn, "PRAGMA table_info(deletions)", []) do
      {:ok, rows} -> if source_column?(rows), do: "source", else: "'self'"
      _ -> "'self'"
    end
  end

  # Each table_info row is [cid, name, type, notnull, default, pk].
  defp source_column?(rows), do: Enum.any?(rows, fn row -> Enum.at(row, 1) == "source" end)

  # Explicit mapping from stored text to atom; never String.to_atom/1.
  defp source_atom("self"), do: :self
  defp source_atom("suspicious"), do: :suspicious
  defp source_atom("inactive"), do: :inactive

  defp parse_timestamp(iso) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    dt
  end

  # Second precision, always UTC, so plain string comparison orders correctly.
  defp timestamp(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp to_ok({:ok, _}), do: :ok
  defp to_ok(:ok), do: :ok
  defp to_ok({:error, _} = error), do: error

  # SQLite creates a missing file on open, so callers that must not create the
  # log check `File.exists?/1` first; only `record/3` passes `create: true`.
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

  # `scrub/1` and `snapshot_to/1` also go through here, so an old-schema live
  # file is upgraded at the first boot scrub or backup, not only by `record/3`.
  defp ensure_schema(conn) do
    with :ok <-
           Sqlite3.execute(
             conn,
             "CREATE TABLE IF NOT EXISTS deletions (user_id INTEGER, deleted_at TEXT NOT NULL, " <>
               "source TEXT NOT NULL DEFAULT 'self')"
           ),
         :ok <- add_source_column(conn) do
      Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS deletions_deleted_at_index ON deletions (deleted_at)"
      )
    end
  end

  # Files created before the `source` column existed get it added in place;
  # their existing rows take the default, 'self'.
  defp add_source_column(conn) do
    with {:ok, rows} <- query(conn, "PRAGMA table_info(deletions)", []) do
      if source_column?(rows) do
        :ok
      else
        Sqlite3.execute(
          conn,
          "ALTER TABLE deletions ADD COLUMN source TEXT NOT NULL DEFAULT 'self'"
        )
      end
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
