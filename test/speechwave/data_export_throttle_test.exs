defmodule Speechwave.DataExportThrottleTest do
  use ExUnit.Case, async: false

  alias Speechwave.DataExportThrottle

  @moduletag :capture_log

  setup do
    :ets.delete_all_objects(:data_export_throttle)
    :ok
  end

  test "allows the first claim for a user" do
    assert DataExportThrottle.claim(1) == :ok
  end

  test "blocks a second claim within the cooldown and reports seconds to wait" do
    assert DataExportThrottle.claim(1) == :ok
    assert {:error, secs} = DataExportThrottle.claim(1)
    assert secs in 1..300
  end

  test "does not block a different user" do
    assert DataExportThrottle.claim(1) == :ok
    assert DataExportThrottle.claim(2) == :ok
  end

  test "release lets the user claim again" do
    assert DataExportThrottle.claim(1) == :ok
    assert DataExportThrottle.release(1) == :ok
    assert DataExportThrottle.claim(1) == :ok
  end

  test "allows a claim once the cooldown has elapsed" do
    now = System.monotonic_time(:millisecond)
    :ets.insert(:data_export_throttle, {1, now - 301_000})

    assert DataExportThrottle.claim(1) == :ok
    assert {:error, _} = DataExportThrottle.claim(1)
  end
end
