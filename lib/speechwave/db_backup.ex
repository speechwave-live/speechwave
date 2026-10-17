defmodule Speechwave.DbBackup do
  @moduledoc false
  # GenServer that runs a SQLite backup on a schedule (5-minute initial delay,
  # then every hour). Uses SQLite's VACUUM INTO for a live, consistent snapshot,
  # then uploads the file to S3-compatible object storage via Req.
  # Registered under its own module name so `run_now/0` can be called from
  # IEx or a Mix task during development without waiting for the timer.
  use GenServer
  require Logger

  alias Ecto.Adapters.SQL
  alias Speechwave.DeletionLog

  @initial_delay :timer.minutes(5)
  @interval :timer.hours(1)

  @doc "True when backup storage is configured, so the backup process should run."
  def configured?, do: config(:storage) != nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :backup, @initial_delay)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:backup, state) do
    run_now()
    Process.send_after(self(), :backup, @interval)
    {:noreply, state}
  end

  @doc """
  Backs up both databases once, now: `speechwave.db` to `backup/speechwave.db` and
  the deletion log `deletions.db` to `backup/deletions.db`. The two are
  independent, so a failure in one is logged and does not stop the other.
  Old ids are scrubbed from the deletion log first.

  Each target is written by a snapshot function that returns `:ok` (upload the
  file), `:skip` (nothing to back up yet) or `{:error, reason}`.
  """
  def run_now do
    Logger.info("[DbBackup] Starting backup")

    # Hourly scrubbing keeps the 30 day promise even with no deploys or deletions,
    # and keeps unscrubbed ids out of the uploaded copy.
    DeletionLog.scrub_logging_errors()

    backup_target("backup/speechwave.db", "speechwave_backup.db", &snapshot_main/1)
    backup_target("backup/deletions.db", "deletions_backup.db", &DeletionLog.snapshot_to/1)

    :ok
  end

  defp backup_target(key, filename, snapshot) do
    path = Path.join(tmp_dir(), filename)
    # VACUUM INTO refuses to write over an existing file
    File.rm(path)

    try do
      case snapshot.(path) do
        :ok ->
          upload(path, key)
          Logger.info("[DbBackup] Uploaded #{key}")

        :skip ->
          Logger.info("[DbBackup] No #{key} to back up yet, skipping")

        {:error, reason} ->
          raise "snapshot failed: #{inspect(reason)}"
      end
    rescue
      e -> Logger.error("[DbBackup] Backup of #{key} failed: #{Exception.message(e)}")
    after
      File.rm(path)
    end
  end

  # VACUUM INTO creates a consistent, compacted snapshot while the DB is live
  defp snapshot_main(path) do
    escaped = String.replace(path, "'", "''")
    SQL.query!(Speechwave.Repo, "VACUUM INTO '#{escaped}'", [])
    :ok
  end

  defp upload(path, key) do
    storage = Map.new(config(:storage))

    response =
      Req.put!(
        "#{storage.url}/#{storage.bucket}/#{key}",
        [
          body: File.read!(path),
          aws_sigv4: [
            access_key_id: storage.access_key_id,
            secret_access_key: storage.secret_access_key,
            region: "auto",
            service: "s3"
          ]
        ] ++ config(:req_options)
      )

    if response.status not in 200..299 do
      raise "storage responded with HTTP #{response.status}"
    end
  end

  defp tmp_dir, do: config(:tmp_dir)

  # Settings come from `config :speechwave, Speechwave.DbBackup` (see config.exs
  # for the keys and runtime.exs for how `storage` is filled in).
  defp config(key), do: Application.fetch_env!(:speechwave, __MODULE__) |> Keyword.fetch!(key)
end
