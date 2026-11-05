defmodule Speechwave.AudienceSlotsTest do
  use ExUnit.Case, async: true

  alias Speechwave.AudienceSlots

  # Each test starts its own named instance, so tests never share places
  # with each other or with the application's global server.
  defp start_slots(grace_ms) do
    name = :"slots_test_#{System.unique_integer([:positive])}"
    start_supervised!({AudienceSlots, name: name, grace_ms: grace_ms, notify: self()})
    name
  end

  # A throwaway process standing in for a LiveView connection.
  defp conn_pid, do: spawn(fn -> receive do: (:stop -> :ok) end)

  # Ends a connection and waits until the server has handled its :DOWN.
  # The test's own monitor fires once the process is gone; :sys.get_state/1
  # then waits for the server to drain its mailbox, which includes the
  # server's own :DOWN for the same process.
  defp end_conn(pid, server) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    :sys.get_state(server)
  end

  test "admits limit participants and turns away the next new key" do
    server = start_slots(60_000)

    assert :ok = AudienceSlots.claim(1, 2, "a", conn_pid(), server)
    assert :ok = AudienceSlots.claim(1, 2, "b", conn_pid(), server)
    assert {:error, :full} = AudienceSlots.claim(1, 2, "c", conn_pid(), server)
    assert AudienceSlots.count(1, server) == 2
  end

  test "a turned-away claim stores and monitors nothing" do
    server = start_slots(60_000)
    assert :ok = AudienceSlots.claim(1, 1, "a", conn_pid(), server)
    before = :sys.get_state(server)

    assert {:error, :full} = AudienceSlots.claim(1, 1, "b", conn_pid(), server)
    assert :sys.get_state(server) == before
  end

  test "the same key from two connections holds one place" do
    server = start_slots(60_000)

    assert :ok = AudienceSlots.claim(1, 1, "a", conn_pid(), server)
    assert :ok = AudienceSlots.claim(1, 1, "a", conn_pid(), server)
    assert AudienceSlots.count(1, server) == 1
  end

  test "ending one of two connections keeps the place" do
    server = start_slots(0)
    first = conn_pid()

    :ok = AudienceSlots.claim(1, 1, "a", first, server)
    :ok = AudienceSlots.claim(1, 1, "a", conn_pid(), server)
    end_conn(first, server)

    assert AudienceSlots.count(1, server) == 1
    refute_received {:slot_released, _, _}
  end

  test "ending the last connection keeps the place during the grace period" do
    server = start_slots(60_000)
    pid = conn_pid()

    :ok = AudienceSlots.claim(1, 1, "a", pid, server)
    end_conn(pid, server)

    assert AudienceSlots.count(1, server) == 1
    refute_received {:slot_released, _, _}
  end

  test "the place is released after the grace period" do
    server = start_slots(10)
    pid = conn_pid()

    :ok = AudienceSlots.claim(1, 1, "a", pid, server)
    end_conn(pid, server)

    assert_receive {:slot_released, 1, "a"}
    assert AudienceSlots.count(1, server) == 0
    # The empty talk entry is removed too.
    assert :sys.get_state(server).talks == %{}
  end

  test "after a release a new key can claim" do
    server = start_slots(10)
    pid = conn_pid()

    :ok = AudienceSlots.claim(1, 1, "a", pid, server)
    end_conn(pid, server)
    assert_receive {:slot_released, 1, "a"}

    assert :ok = AudienceSlots.claim(1, 1, "b", conn_pid(), server)
  end

  test "a reconnect inside the grace period keeps the place" do
    server = start_slots(60_000)
    pid = conn_pid()

    :ok = AudienceSlots.claim(1, 1, "a", pid, server)
    end_conn(pid, server)

    assert :ok = AudienceSlots.claim(1, 1, "a", conn_pid(), server)
    assert {:error, :full} = AudienceSlots.claim(1, 1, "b", conn_pid(), server)
  end

  test "a stale release timer does not free a reclaimed place" do
    server = start_slots(50)
    pid = conn_pid()

    :ok = AudienceSlots.claim(1, 1, "a", pid, server)
    end_conn(pid, server)
    :ok = AudienceSlots.claim(1, 1, "a", conn_pid(), server)

    refute_receive {:slot_released, _, _}, 100
    assert AudienceSlots.count(1, server) == 1
  end

  test "places in different talks are counted separately" do
    server = start_slots(60_000)

    :ok = AudienceSlots.claim(1, 1, "a", conn_pid(), server)
    assert :ok = AudienceSlots.claim(2, 1, "a", conn_pid(), server)
    assert AudienceSlots.count(1, server) == 1
    assert AudienceSlots.count(2, server) == 1
  end

  test "a stray message does not clear places" do
    server = start_slots(60_000)
    :ok = AudienceSlots.claim(1, 2, "a", conn_pid(), server)

    send(server, :unexpected)
    :sys.get_state(server)

    assert AudienceSlots.count(1, server) == 1
  end

  test "format_status hides audience ids from crash reports" do
    server = start_slots(60_000)
    pid = conn_pid()
    :ok = AudienceSlots.claim(1, 2, "secret-audience-id", pid, server)
    state = :sys.get_state(server)

    status =
      AudienceSlots.format_status(%{
        state: state,
        message: {:claim, 1, 2, "secret-audience-id", pid},
        reason: :boom,
        log: []
      })

    refute inspect(status) =~ "secret-audience-id"
    # Still useful for debugging: how many places each talk holds.
    assert status.state.places_per_talk == %{1 => 1}
  end

  test "unlimited admits any number of keys and tracks nothing" do
    server = start_slots(60_000)

    for key <- ~w(a b c d e) do
      assert :ok = AudienceSlots.claim(1, :unlimited, key, conn_pid(), server)
    end

    assert AudienceSlots.count(1, server) == 0
    assert :sys.get_state(server).monitors == %{}
  end
end
