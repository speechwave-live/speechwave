defmodule Speechwave.PlansTest do
  use ExUnit.Case, async: true

  alias Speechwave.Plans

  describe "limit/2 — free plan" do
    test "max_participants is 15" do
      assert Plans.limit(:max_participants, :free) == 15
    end

    test "full_sessions_per_month is 50" do
      assert Plans.limit(:full_sessions_per_month, :free) == 50
    end
  end

  describe "limit/2 — pro plan" do
    test "max_participants is unlimited" do
      assert Plans.limit(:max_participants, :pro) == :unlimited
    end

    test "full_sessions_per_month is unlimited" do
      assert Plans.limit(:full_sessions_per_month, :pro) == :unlimited
    end
  end

  describe "limit/2 — org plan" do
    test "inherits pro max_participants" do
      assert Plans.limit(:max_participants, :org) == Plans.limit(:max_participants, :pro)
    end

    test "inherits pro full_sessions_per_month" do
      assert Plans.limit(:full_sessions_per_month, :org) ==
               Plans.limit(:full_sessions_per_month, :pro)
    end
  end

  describe "check/3" do
    test "returns :ok when count is below the free limit" do
      assert Plans.check(:max_participants, :free, 14) == :ok
    end

    test "returns {:error, :limit_reached} when count equals the free limit" do
      assert Plans.check(:max_participants, :free, 15) == {:error, :limit_reached}
    end

    test "returns {:error, :limit_reached} when count exceeds the free limit" do
      assert Plans.check(:max_participants, :free, 16) == {:error, :limit_reached}
    end

    test "returns :ok for pro plan regardless of count" do
      assert Plans.check(:max_participants, :pro, 1_000_000) == :ok
    end

    test "returns :ok for org plan regardless of count" do
      assert Plans.check(:max_participants, :org, 1_000_000) == :ok
    end

    test "returns :ok for full_sessions_per_month when under free limit" do
      assert Plans.check(:full_sessions_per_month, :free, 49) == :ok
    end

    test "returns {:error, :limit_reached} for full_sessions_per_month at free limit" do
      assert Plans.check(:full_sessions_per_month, :free, 50) == {:error, :limit_reached}
    end
  end
end
