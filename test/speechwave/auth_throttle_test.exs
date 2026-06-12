defmodule Speechwave.AuthThrottleTest do
  use ExUnit.Case, async: false

  alias Speechwave.AuthThrottle

  setup do
    :ets.delete_all_objects(:auth_throttle_email)
    :ets.delete_all_objects(:auth_throttle_ip)
    :ok
  end

  describe "allow_email?/1" do
    test "allows the first request for an unseen email" do
      assert AuthThrottle.allow_email?("new@example.com") == true
    end

    test "blocks a second request for the same email within 60 seconds" do
      assert AuthThrottle.allow_email?("repeat@example.com") == true
      assert AuthThrottle.allow_email?("repeat@example.com") == false
    end

    test "allows a request again once the cooldown has elapsed, with no escalation" do
      email = "expired@example.com"
      assert AuthThrottle.allow_email?(email) == true

      now = System.monotonic_time(:millisecond)
      :ets.insert(:auth_throttle_email, {email, now - 61_000})

      assert AuthThrottle.allow_email?(email) == true
      assert AuthThrottle.allow_email?(email) == false
    end
  end

  describe "allow_ip?/1" do
    test "allows the first request for an unseen ip" do
      assert AuthThrottle.allow_ip?("203.0.113.10") == true
    end

    test "allows different ips independently" do
      assert AuthThrottle.allow_ip?("203.0.113.11") == true
      assert AuthThrottle.allow_ip?("203.0.113.12") == true
    end

    test "escalates the cooldown on repeated violations, then resets after a long gap" do
      ip = "203.0.113.20"

      # Call 1: no entry yet -> allowed, seeds the base cooldown
      assert AuthThrottle.allow_ip?(ip) == true
      assert [{^ip, _last_at, 30_000, 0}] = :ets.lookup(:auth_throttle_ip, ip)

      # Call 2: 5s later, inside the 30s cooldown -> blocked, cooldown doubles
      backdate_ip(ip, 5_000)
      assert AuthThrottle.allow_ip?(ip) == false
      assert [{^ip, _last_at, 60_000, 1}] = :ets.lookup(:auth_throttle_ip, ip)

      # Call 3: 5s later, inside the 60s cooldown -> blocked, cooldown doubles again
      backdate_ip(ip, 5_000)
      assert AuthThrottle.allow_ip?(ip) == false
      assert [{^ip, _last_at, 120_000, 2}] = :ets.lookup(:auth_throttle_ip, ip)

      # Call 4: 125s later, past the 120s cooldown -> allowed, resets to base
      backdate_ip(ip, 125_000)
      assert AuthThrottle.allow_ip?(ip) == true
      assert [{^ip, _last_at, 30_000, 0}] = :ets.lookup(:auth_throttle_ip, ip)
    end

    test "caps the cooldown at 30 minutes" do
      ip = "203.0.113.30"
      now = System.monotonic_time(:millisecond)

      # Seed an entry already at the cap, just violated
      :ets.insert(:auth_throttle_ip, {ip, now, 1_800_000, 10})

      assert AuthThrottle.allow_ip?(ip) == false
      assert [{^ip, _last_at, 1_800_000, 11}] = :ets.lookup(:auth_throttle_ip, ip)
    end
  end

  defp backdate_ip(ip, ms_ago) do
    [{^ip, _last_at, cooldown_ms, violation_count}] = :ets.lookup(:auth_throttle_ip, ip)
    now = System.monotonic_time(:millisecond)
    :ets.insert(:auth_throttle_ip, {ip, now - ms_ago, cooldown_ms, violation_count})
  end
end
