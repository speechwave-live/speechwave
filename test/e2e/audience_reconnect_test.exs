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
end
