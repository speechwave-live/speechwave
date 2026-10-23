defmodule Speechwave.DataExportThrottle do
  @moduledoc """
  Limits each user to one data export (`Speechwave.DataExport`) per five
  minutes.

  A `:public` ETS table owned by this GenServer holds `{user_id, claimed_at}`
  (monotonic ms). It is recreated empty on restart, so the throttle fails
  open, matching `Speechwave.AuthThrottle`.

  `claim/1` is atomic: `:ets.insert_new/2` and `:ets.select_replace/2` are
  single operations, so two simultaneous requests cannot both pass. The
  caller claims before building the export and calls `release/1` if the
  build fails, so an error does not lock the user out.
  """

  use GenServer

  require Logger

  @table :data_export_throttle
  @cooldown_ms 300_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  Returns `:ok` and starts the cooldown, or `{:error, seconds}` with the
  whole seconds left to wait.
  """
  def claim(user_id) do
    now = System.monotonic_time(:millisecond)

    cond do
      :ets.insert_new(@table, {user_id, now}) -> :ok
      replace_expired(user_id, now) -> :ok
      true -> blocked(user_id, now)
    end
  end

  @doc "Clears the user's cooldown, used when building the export failed."
  def release(user_id) do
    :ets.delete(@table, user_id)
    :ok
  end

  # Atomically swaps in a fresh claim only if the stored one has expired.
  defp replace_expired(user_id, now) do
    spec = [{{user_id, :"$1"}, [{:<, :"$1", now - @cooldown_ms}], [{{user_id, now}}]}]
    :ets.select_replace(@table, spec) == 1
  end

  defp blocked(user_id, now) do
    case :ets.lookup(@table, user_id) do
      [{^user_id, claimed_at}] ->
        Logger.warning("data_export_throttle: cooldown for user #{user_id}")
        remaining_ms = @cooldown_ms - (now - claimed_at)
        {:error, max(1, ceil(remaining_ms / 1000))}

      # Released between our attempts: try again.
      [] ->
        claim(user_id)
    end
  end
end
