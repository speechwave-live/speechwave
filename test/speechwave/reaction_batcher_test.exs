defmodule Speechwave.ReactionBatcherTest do
  use ExUnit.Case, async: true

  alias Speechwave.ReactionBatcher

  # Each test gets its own batcher and its own slugs, so tests can run
  # concurrently and cannot hear each other's broadcasts. `tick_ms: :infinity`
  # turns the timer off; tests trigger a tick by calling `flush/1`.
  setup do
    name = :"batcher_#{System.unique_integer([:positive])}"
    a = "slug-a-#{System.unique_integer([:positive])}"
    b = "slug-b-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "audience:#{a}")
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "audience:#{b}")
    start_supervised!({ReactionBatcher, name: name, tick_ms: :infinity, max_batch: 3})
    %{batcher: name, a: a, b: b}
  end

  test "flush broadcasts one reactions_batch per slug, emojis in arrival order",
       %{batcher: batcher, a: a, b: b} do
    ReactionBatcher.add(batcher, a, "🔥")
    ReactionBatcher.add(batcher, a, "❤️")
    ReactionBatcher.add(batcher, b, "👏")
    :ok = ReactionBatcher.flush(batcher)

    topic_a = "audience:#{a}"
    topic_b = "audience:#{b}"

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^topic_a,
      event: "reactions_batch",
      payload: %{emojis: ["🔥", "❤️"]}
    }

    assert_receive %Phoenix.Socket.Broadcast{
      topic: ^topic_b,
      event: "reactions_batch",
      payload: %{emojis: ["👏"]}
    }
  end

  test "flush with nothing pending broadcasts nothing", %{batcher: batcher} do
    :ok = ReactionBatcher.flush(batcher)
    refute_receive %Phoenix.Socket.Broadcast{}, 50
  end

  test "a second flush does not repeat emojis already sent", %{batcher: batcher, a: a} do
    ReactionBatcher.add(batcher, a, "🔥")
    :ok = ReactionBatcher.flush(batcher)
    assert_receive %Phoenix.Socket.Broadcast{event: "reactions_batch"}

    :ok = ReactionBatcher.flush(batcher)
    refute_receive %Phoenix.Socket.Broadcast{}, 50
  end

  test "more than max_batch emojis are capped to a sample drawn from those added",
       %{batcher: batcher, a: a} do
    added = ~w(1 2 3 4 5 6 7 8 9 10)
    Enum.each(added, &ReactionBatcher.add(batcher, a, &1))
    :ok = ReactionBatcher.flush(batcher)

    assert_receive %Phoenix.Socket.Broadcast{event: "reactions_batch", payload: %{emojis: sent}}
    assert length(sent) == 3
    assert Enum.all?(sent, &(&1 in added))
    assert sent == Enum.uniq(sent)
  end

  test "ticks on its own when tick_ms is a number", %{a: a} do
    name = :"ticking_#{System.unique_integer([:positive])}"
    start_supervised!({ReactionBatcher, name: name, tick_ms: 10}, id: :ticking)
    ReactionBatcher.add(name, a, "🔥")

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "reactions_batch",
                     payload: %{emojis: ["🔥"]}
                   },
                   1_000
  end

  test "stops before the endpoint on shutdown, so a last tick can still broadcast" do
    # Supervisors stop children in the reverse of the order they started, and
    # `which_children/1` lists the most recently started first. The batcher
    # broadcasts through the endpoint's configuration, so it must start after
    # the endpoint and therefore stop before it.
    ids = Speechwave.Supervisor |> Supervisor.which_children() |> Enum.map(&elem(&1, 0))
    batcher = Enum.find_index(ids, &(&1 == ReactionBatcher))
    endpoint = Enum.find_index(ids, &(&1 == SpeechwaveWeb.Endpoint))

    assert is_integer(batcher) and is_integer(endpoint)
    assert batcher < endpoint
  end
end
