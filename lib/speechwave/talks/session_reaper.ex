defmodule Speechwave.Talks.SessionReaper do
  @moduledoc false
  # Periodically closes TalkSessions that were never explicitly stopped
  # (extension crash, laptop closed, network drop) so a session never stays
  # "active" forever. This is the backstop for Talks.start_session/1's
  # always-fresh behavior: it catches sessions on talks nobody ever
  # explicitly restarts, so they eventually count toward the monthly
  # full-session limit instead of hiding from it indefinitely.
  use GenServer

  @sweep_interval :timer.minutes(15)

  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :sweep_interval, @sweep_interval)
    schedule_sweep(interval)
    {:ok, %{sweep_interval: interval}}
  end

  @impl true
  def handle_info(:sweep, state) do
    Speechwave.Talks.close_stale_sessions()
    schedule_sweep(state.sweep_interval)
    {:noreply, state}
  end

  # Synchronous test hook — runs a sweep immediately and replies only once
  # it's done, so tests don't need to wait on the internal timer.
  @impl true
  def handle_call(:sweep_now, _from, state) do
    Speechwave.Talks.close_stale_sessions()
    {:reply, :ok, state}
  end

  defp schedule_sweep(ms), do: Process.send_after(self(), :sweep, ms)
end
