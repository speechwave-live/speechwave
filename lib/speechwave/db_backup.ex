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
    backup_once()
    Process.send_after(self(), :backup, @interval)
    {:noreply, state}
  end

  def run_now, do: backup_once()

  @doc """
  Backs up both databases once: `speechwave.db` to `backup/speechwave.db` and
  the deletion log `deletions.db` to `backup/deletions.db`. The two are
  independent, so a failure in one is logged and does not stop the other.
  """
  def backup_once do
    Logger.info("[DbBackup] Starting backup")

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
    SQL.query!(Speechwave.Repo, "VACUUM INTO '#{path}'", [])
    :ok
  end

  defp upload(path, key) do
    storage = storage_config()

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
        ] ++ Application.get_env(:speechwave, :db_backup_req_options, [])
      )

    if response.status not in 200..299 do
      raise "storage responded with HTTP #{response.status}"
    end
  end

  # Tests supply :db_backup_storage; production reads the STORAGE_* variables.
  defp storage_config do
    case Application.get_env(:speechwave, :db_backup_storage) do
      nil ->
        %{
          url: System.fetch_env!("STORAGE_URL"),
          bucket: System.fetch_env!("STORAGE_BUCKET"),
          access_key_id: System.fetch_env!("STORAGE_ACCESS_KEY_ID"),
          secret_access_key: System.fetch_env!("STORAGE_SECRET_ACCESS_KEY")
        }

      config ->
        Map.new(config)
    end
  end

  defp tmp_dir, do: Application.get_env(:speechwave, :db_backup_tmp_dir, "/tmp")
end
