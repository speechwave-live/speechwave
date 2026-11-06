defmodule SpeechwaveWeb.E2E.AudienceReconnectTest do
  @moduledoc """
  On a free-plan talk the audience page only joins the reaction stream once
  the browser has sent its audience id. LiveView does not call a hook's
  `mounted()` again after a reconnect, so this checks that a reconnected page
  still claims its place and can react. Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  import Speechwave.TalksFixtures

  @heart ~s([phx-value-emoji="❤️"])

  test "a free-plan audience page can still react after the socket reconnects",
       %{conn: conn} do
    %{talk: talk, session: session} = talk_with_active_session_fixture(user_fixture())

    conn
    |> visit("/t/#{talk.slug}")
    |> assert_has("#emoji-buttons")
    |> assert_has("[data-phx-main].phx-connected")
    |> evaluate("window.liveSocket.disconnect()")
    |> refute_has("[data-phx-main].phx-connected")
    |> evaluate("window.liveSocket.connect()")
    |> assert_has("[data-phx-main].phx-connected")
    |> click(@heart)
    # The floating emoji comes back over the reaction stream, so it only
    # appears when the reconnected LiveView holds a place.
    |> assert_has(".floating-emoji", text: "❤️")

    assert Speechwave.Reactions.count_reactions(session.id) == 1
  end

  test "a browser that blocks storage keeps the same place after a reconnect",
       %{conn: conn} do
    # The test database reuses talk ids, so start from an empty slot server
    # and the only place in it can be this page's.
    :ok = Supervisor.terminate_child(Speechwave.Supervisor, Speechwave.AudienceSlots)
    {:ok, _pid} = Supervisor.restart_child(Speechwave.Supervisor, Speechwave.AudienceSlots)

    %{talk: talk} = talk_with_active_session_fixture(user_fixture())

    conn =
      conn
      |> visit("/t/#{talk.slug}")
      |> assert_has("#emoji-buttons")
      |> assert_has("[data-phx-main].phx-connected")

    [key_before] = place_keys(talk)

    conn
    # From here on every localStorage access throws, as it does in some
    # private modes. The id has to come from memory, not from storage.
    |> evaluate("""
    Object.defineProperty(window, "localStorage", {
      configurable: true,
      get() { throw new DOMException("blocked", "SecurityError") }
    })
    """)
    |> evaluate("window.liveSocket.disconnect()")
    |> refute_has("[data-phx-main].phx-connected")
    |> evaluate("window.liveSocket.connect()")
    |> assert_has("[data-phx-main].phx-connected")
    |> click(@heart)
    |> assert_has(".floating-emoji", text: "❤️")

    assert place_keys(talk) == [key_before]
  end

  defp place_keys(talk) do
    :sys.get_state(Speechwave.AudienceSlots).talks |> Map.get(talk.id, %{}) |> Map.keys()
  end
end
