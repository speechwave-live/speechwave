defmodule Speechwave.ReactionBatcher do
  @moduledoc """
  Collects audience taps and pushes them to audience pages in batches.

  Without batching, every accepted tap was broadcast to every audience page,
  so the work per second grew with `people x taps per second`. Here the tap
  handler only hands the emoji to this process (`add/3`). A timer then fires
  every `tick_ms` milliseconds (250 by default) and the batcher broadcasts
  one `reactions_batch` message per talk, carrying everything collected since
  the last tick. Each page now receives about four messages a second no matter
  how busy the room is.

  This is a GenServer: a single process that owns some state (here, the
  emoji waiting to be sent) and handles one message at a time. Handling one
  message at a time is what makes it safe for many LiveViews to call `add/3`
  at once, with no locks. Casts (`GenServer.cast/2`) are fire and forget, so a
  tap never waits on the batcher.

  Nothing held here is durable. If the process crashes, its supervisor
  restarts it empty and at most one tick of floating emoji is lost. The
  taps themselves are stored by `Speechwave.Reactions.record_reaction/4`.

  Audience pages listen on the PubSub topic `audience:<slug>`. The extension
  listens on `reactions:<slug>` and is not served by this module.

  ## Options

    * `:name` - the registered name (default `#{inspect(__MODULE__)}`)
    * `:tick_ms` - milliseconds between batches, or `:infinity` for no timer.
      Tests use `:infinity` and call `flush/1` themselves.
    * `:max_batch` - most emoji sent per talk per tick (default 50). Past that
      a random sample is sent, since no screen can show more legibly.

  Defaults can be set under `config :speechwave, #{inspect(__MODULE__)}`.
  """
  use GenServer

  @default_tick_ms 250
  @default_max_batch 50

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Queues one emoji for the next batch to the talk with this slug."
  def add(server \\ __MODULE__, slug, emoji) do
    GenServer.cast(server, {:add, slug, emoji})
  end

  @doc """
  Sends everything pending right now, as a tick would. Waits until it is sent.
  Meant for tests, which cannot sleep until the next tick.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:speechwave, __MODULE__, [])

    state = %{
      pending: %{},
      tick_ms: Keyword.get(opts, :tick_ms, Keyword.get(config, :tick_ms, @default_tick_ms)),
      max_batch:
        Keyword.get(opts, :max_batch, Keyword.get(config, :max_batch, @default_max_batch))
    }

    schedule_tick(state)
    {:ok, state}
  end

  @impl true
  def handle_cast({:add, slug, emoji}, state) do
    # Newest first, because prepending to a list is cheap. Reversed on send.
    pending = Map.update(state.pending, slug, [emoji], &[emoji | &1])
    {:noreply, %{state | pending: pending}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {:reply, :ok, send_batches(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    state = send_batches(state)
    schedule_tick(state)
    {:noreply, state}
  end

  defp schedule_tick(%{tick_ms: :infinity}), do: :ok
  defp schedule_tick(%{tick_ms: tick_ms}), do: Process.send_after(self(), :tick, tick_ms)

  defp send_batches(%{pending: pending, max_batch: max_batch} = state) do
    for {slug, newest_first} <- pending do
      emojis = newest_first |> Enum.reverse() |> cap(max_batch)

      SpeechwaveWeb.Endpoint.broadcast("audience:#{slug}", "reactions_batch", %{emojis: emojis})
    end

    %{state | pending: %{}}
  end

  defp cap(emojis, max_batch) when length(emojis) <= max_batch, do: emojis
  defp cap(emojis, max_batch), do: Enum.take_random(emojis, max_batch)
end
