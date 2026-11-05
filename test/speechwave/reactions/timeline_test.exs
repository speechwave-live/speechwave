defmodule Speechwave.Reactions.TimelineTest do
  use ExUnit.Case, async: true

  alias Speechwave.Reactions.Timeline

  describe "bucket_seconds/1" do
    test "picks the smallest size that keeps the axis at 60 buckets or fewer" do
      assert Timeline.bucket_seconds(0) == 10
      assert Timeline.bucket_seconds(599) == 10
      assert Timeline.bucket_seconds(600) == 15
      assert Timeline.bucket_seconds(1200) == 30
      assert Timeline.bucket_seconds(2700) == 60
      assert Timeline.bucket_seconds(3600) == 120
      assert Timeline.bucket_seconds(14_400) == 300
      assert Timeline.bucket_seconds(100_000) == 600
    end
  end
end
