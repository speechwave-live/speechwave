defmodule Speechwave.Accounts.SuspiciousUserReaper do
  @moduledoc false
  # Periodically deletes "suspicious" users: accounts that were never
  # confirmed (no magic link or OAuth sign-in completed) and are older than
  # the retention cutoff. They never had a login session, so they hold no
  # data, and anyone with a real address can simply sign up again.
  #
  # Modeled on Talks.SessionReaper. The first sweep runs shortly after boot
  # (:initial_delay) rather than a full interval later, because production
  # machines auto-suspend and a 24 hour timer might never get to fire.
  use GenServer

  require Logger

  alias Speechwave.Accounts

  @sweep_interval :timer.hours(24)
  @initial_delay :timer.minutes(1)

  # `name: nil` starts the process unnamed, so tests can run several at once.
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :sweep_interval, @sweep_interval)
    initial_delay = Keyword.get(opts, :initial_delay, @initial_delay)
    schedule_sweep(initial_delay)
    {:ok, %{sweep_interval: interval}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep(state.sweep_interval)
    {:noreply, state}
  end

  # Synchronous test hook: runs a sweep immediately and replies only once
  # it's done, so tests don't need to wait on the internal timer.
  @impl true
  def handle_call(:sweep_now, _from, state) do
    sweep()
    {:reply, :ok, state}
  end

  defp sweep do
    case Accounts.delete_suspicious_users() do
      0 -> :ok
      count -> Logger.info("[SuspiciousUserReaper] Deleted #{count} suspicious users")
    end
  end

  # Process.send_after/3 delivers :sweep to this process after `ms` milliseconds.
  # With no delay we send directly: send_after goes through a timer process, so
  # even a 0 ms timer can arrive after messages sent later by someone else.
  defp schedule_sweep(0), do: send(self(), :sweep)
  defp schedule_sweep(ms), do: Process.send_after(self(), :sweep, ms)
end
