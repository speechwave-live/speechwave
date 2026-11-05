defmodule Speechwave.AudienceSlots do
  @moduledoc """
  Counts how many audience members hold a place in each talk, so a plan's
  participant limit can turn away the next person once a talk is full.

  ## Places

  A place belongs to a participant key (the browser's audience ID), not to a
  connection. One person with two tabs open, or a phone that reconnects,
  still holds a single place. `claim/5` either joins an existing place
  (the key already holds one) or creates a new place, which is allowed only
  while the talk has fewer places than the limit.

  ## The grace period

  Phones drop connections all the time: the screen locks, the network
  switches from wifi to cellular, the browser suspends a background tab.
  If a place were freed the instant its last connection closed, a stranger
  could take it during that gap and the original person would come back to
  "This talk is full". So when the last connection of a place goes away, the
  place is kept for a grace period (30 seconds by default) before it is
  freed. A reconnect inside that window simply picks the place up again.

  Each scheduled release carries a fresh reference that is also stored on the
  place. When the timer message arrives, the place is freed only if the
  reference still matches. A reconnect clears the stored reference, so a
  timer that was already in flight finds a mismatch and does nothing.

  ## Why a GenServer and not Phoenix Presence

  Presence already tracks who is connected, but it drops an entry the moment
  the last process for it leaves, so it cannot hold a place through a grace
  period. Presence is also eventually consistent: two people asking for the
  last place at the same moment would both see a free place and both get in.
  A single GenServer handles one message at a time, so every claim is checked
  and recorded before the next one is looked at, and the last place can only
  be taken once.

  The state is in memory only. A restart forgets every place, which is fine:
  connected LiveViews claim again when they reconnect.

  ## Options for `start_link/1`

    * `:name` - registered name, defaults to `#{inspect(__MODULE__)}`
    * `:grace_ms` - how long an empty place is held, defaults to the
      `:audience_slot_grace_ms` app env or 30 seconds
    * `:notify` - a pid that receives `{:slot_released, talk_id, key}` each
      time a place is freed (used by tests), or `nil`
  """
  use GenServer

  @default_grace_ms 30_000

  @typedoc "A plan's participant limit."
  @type limit :: non_neg_integer() | :unlimited

  # State shape:
  #
  #   %{
  #     grace_ms: integer,
  #     notify: pid | nil,
  #     # one map of places per talk; empty talks are removed
  #     talks: %{talk_id => %{key => place}},
  #     # reverse index so a :DOWN message can find its place quickly
  #     monitors: %{monitor_ref => {talk_id, key}}
  #   }
  #
  #   place = %{conns: %{monitor_ref => pid}, release: nil | {release_ref, timer_ref}}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Claims a place in `talk_id` for `key`, on behalf of the connection `pid`.

  Returns `:ok` when the key already holds a place or a new one is free, and
  `{:error, :full}` when the talk has `limit` places taken. The server
  monitors `pid` and starts the grace period when the key's last connection
  ends. An `:unlimited` limit returns `:ok` without contacting the server, so
  paid plans cost nothing to track.
  """
  @spec claim(term(), limit(), String.t(), pid(), GenServer.server()) :: :ok | {:error, :full}
  def claim(talk_id, limit, key, pid, server \\ __MODULE__)

  def claim(_talk_id, :unlimited, _key, _pid, _server), do: :ok

  def claim(talk_id, limit, key, pid, server) when is_integer(limit) and limit >= 0 do
    GenServer.call(server, {:claim, talk_id, limit, key, pid})
  end

  @doc "Number of places held in `talk_id`, counting places in their grace period."
  @spec count(term(), GenServer.server()) :: non_neg_integer()
  def count(talk_id, server \\ __MODULE__) do
    GenServer.call(server, {:count, talk_id})
  end

  @impl true
  def init(opts) do
    grace_ms =
      Keyword.get_lazy(opts, :grace_ms, fn ->
        Application.get_env(:speechwave, :audience_slot_grace_ms, @default_grace_ms)
      end)

    {:ok, %{grace_ms: grace_ms, notify: Keyword.get(opts, :notify), talks: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:claim, talk_id, limit, key, pid}, _from, state) do
    places = Map.get(state.talks, talk_id, %{})

    case Map.fetch(places, key) do
      {:ok, place} ->
        {:reply, :ok, join_place(state, talk_id, key, place, pid)}

      :error when map_size(places) < limit ->
        place = %{conns: %{}, release: nil}
        {:reply, :ok, join_place(state, talk_id, key, place, pid)}

      :error ->
        # Turned away: nothing is stored or monitored, so visitors who are
        # refused do not make the state grow.
        {:reply, {:error, :full}, state}
    end
  end

  def handle_call({:count, talk_id}, _from, state) do
    {:reply, state.talks |> Map.get(talk_id, %{}) |> map_size(), state}
  end

  @impl true
  def handle_info({:DOWN, mref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, mref) do
      {nil, _monitors} ->
        {:noreply, state}

      {{talk_id, key}, monitors} ->
        state = %{state | monitors: monitors}
        place = state.talks |> Map.fetch!(talk_id) |> Map.fetch!(key)
        place = %{place | conns: Map.delete(place.conns, mref)}

        place =
          if map_size(place.conns) == 0,
            do: schedule_release(place, talk_id, key, state),
            else: place

        {:noreply, put_place(state, talk_id, key, place)}
    end
  end

  def handle_info({:release, talk_id, key, release_ref}, state) do
    case get_in(state.talks, [talk_id, key]) do
      # Free the place only if this is the timer it is still waiting for. A
      # reconnect sets release back to nil, so an old timer falls through.
      %{release: {^release_ref, _timer}} ->
        notify(state, {:slot_released, talk_id, key})
        {:noreply, delete_place(state, talk_id, key)}

      _ ->
        {:noreply, state}
    end
  end

  # Adds a connection to a place (new or existing) and cancels any pending
  # release, since the place has someone in it again.
  defp join_place(state, talk_id, key, place, pid) do
    place = cancel_release(place)

    if pid in Map.values(place.conns) do
      # The same connection claiming twice is already monitored.
      put_place(state, talk_id, key, place)
    else
      mref = Process.monitor(pid)
      place = %{place | conns: Map.put(place.conns, mref, pid)}
      state = %{state | monitors: Map.put(state.monitors, mref, {talk_id, key})}
      put_place(state, talk_id, key, place)
    end
  end

  defp schedule_release(place, talk_id, key, state) do
    release_ref = make_ref()
    timer = Process.send_after(self(), {:release, talk_id, key, release_ref}, state.grace_ms)
    %{place | release: {release_ref, timer}}
  end

  defp cancel_release(%{release: nil} = place), do: place

  defp cancel_release(%{release: {_ref, timer}} = place) do
    # If the timer already fired, its message is in the mailbox; clearing
    # release below makes handle_info ignore it.
    Process.cancel_timer(timer)
    %{place | release: nil}
  end

  defp put_place(state, talk_id, key, place) do
    places = state.talks |> Map.get(talk_id, %{}) |> Map.put(key, place)
    %{state | talks: Map.put(state.talks, talk_id, places)}
  end

  # Only called for places with no connections, so there are no monitors
  # left to clean up.
  defp delete_place(state, talk_id, key) do
    places = state.talks |> Map.fetch!(talk_id) |> Map.delete(key)

    talks =
      if map_size(places) == 0,
        do: Map.delete(state.talks, talk_id),
        else: Map.put(state.talks, talk_id, places)

    %{state | talks: talks}
  end

  defp notify(%{notify: nil}, _message), do: :ok
  defp notify(%{notify: pid}, message), do: send(pid, message)
end
