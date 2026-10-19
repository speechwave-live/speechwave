defmodule SpeechwaveWeb.E2E.ReactionFlowTest do
  @moduledoc """
  Real-browser port of scripts/manual_tests/reaction_flow.sh: two attendees on
  the same talk page, a reaction broadcast from one to the other, the
  client-side cooldown, and the reactions landing in the session's analytics.
  Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  import Speechwave.TalksFixtures

  @heart ~s([phx-value-emoji="❤️"])
  @laugh ~s([phx-value-emoji="😂"])

  test "a reaction floats up for every attendee, cools down, and is recorded",
       %{conn: device_a} = context do
    owner = user_fixture()
    %{talk: talk, session: session} = talk_with_active_session_fixture(owner)
    talk_path = "/t/#{talk.slug}"

    device_a = device_a |> visit(talk_path) |> assert_has("#emoji-buttons")

    device_b =
      context |> new_browser_session() |> visit(talk_path) |> assert_has("#emoji-buttons")

    # Device A taps a heart: it floats up on both devices, but only A cools down.
    device_a
    |> click(@heart)
    |> assert_has(".floating-emoji", text: "❤️")
    |> assert_has("#emoji-buttons.cooling-down")
    |> assert_has("#{@heart}[disabled]")
    |> assert_has(".cooldown-label", text: "Cooling down")

    device_b
    |> assert_has(".floating-emoji", text: "❤️")
    |> refute_has("#emoji-buttons.cooling-down")
    |> refute_has("#{@heart}[disabled]")
    |> assert_has(".cooldown-label", text: "Tap to react", exact: true)

    # After the cooldown (about 3 seconds) A can react again.
    device_a
    |> assert_has(".cooldown-label", text: "Tap to react", exact: true, timeout: 6_000)
    |> refute_has("#emoji-buttons.cooling-down")
    |> tap(fn _ -> wait_out_server_rate_limit() end)
    |> click(@laugh)
    |> assert_has(".floating-emoji", text: "😂")

    assert_has(device_b, ".floating-emoji", text: "😂")

    # Both reactions were stored on the active session, as general (slide 0).
    device_a
    |> log_in_as(owner)
    |> visit("/sessions/#{session.id}")
    |> assert_has("#total-reactions", text: "2", exact: true)
    |> assert_has("#slide-row-0", text: "General")
    |> assert_has("#slide-row-0", text: "❤️")
    |> assert_has("#slide-row-0", text: "😂")
  end

  # The page re-enables its buttons 3 seconds after the click, and the server
  # drops a reaction that arrives less than 3 seconds after the previous one.
  # The two clocks start a few milliseconds apart, so give the server's window
  # a little extra to close before tapping again.
  defp wait_out_server_rate_limit, do: Process.sleep(300)
end
