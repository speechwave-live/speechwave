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
end
