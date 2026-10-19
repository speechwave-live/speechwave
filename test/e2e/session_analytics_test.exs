defmodule SpeechwaveWeb.E2E.SessionAnalyticsTest do
  @moduledoc """
  Real-browser port of scripts/manual_tests/session_analytics.sh: view a
  session's analytics, compare two sessions, then rename and delete sessions
  from the dashboard. The pages are covered in detail by
  test/speechwave_web/live/session_analytics_live_test.exs; this walks the
  whole journey with real navigation, the rename form and the confirm dialogs.
  Run with `mix test.browser`.
  """
  use SpeechwaveWeb.E2ECase

  import Speechwave.TalksFixtures

  test "view, compare, rename and delete sessions", %{conn: conn} do
    user = user_fixture()

    %{talk: talk, session1: session1, session2: session2} =
      talk_with_two_finished_sessions_fixture(user)

    conn
    |> log_in_as(user)
    |> visit("/sessions/#{session1.id}")
    |> assert_has("#total-reactions", text: "3", exact: true)
    |> assert_has("#slide-row-1", text: "🔥")
    |> assert_has("#slide-row-1", text: "❤️")
    |> assert_has("#slide-row-2", text: "🎉")
    |> visit("/sessions/#{session1.id}/compare/#{session2.id}")
    |> assert_has("#compare-section", text: "Session 1")
    |> assert_has("#compare-section", text: "Session 2")
    |> visit("/dashboard")
    |> click("#talk-list li button", talk.title)
    |> assert_has("#session-#{session1.id}")
    |> assert_has("#session-#{session2.id}")
    |> click("#rename-session-#{session1.id}")
    |> press("#rename_label", "ControlOrMeta+a")
    |> type("#rename_label", "Opening Keynote")
    |> click_button("#rename-form-#{session1.id} button", "Save")
    |> assert_has("#session-label-#{session1.id}", text: "Opening Keynote", exact: true)
    |> with_dialog(
      fn %{message: message} ->
        assert message =~ "Delete this session"
        :accept
      end,
      &click(&1, "#delete-session-#{session2.id}")
    )
    |> refute_has("#session-#{session2.id}")
    |> assert_has("#session-#{session1.id}")
    |> with_dialog(
      fn %{message: message} ->
        assert message =~ "Delete this talk"
        :accept
      end,
      &click(&1, "#delete-talk-#{talk.id}")
    )
    |> refute_has("#delete-talk-#{talk.id}")
    |> click_link("Sign out")
    |> visit("/dashboard")
    |> assert_path("/users/log-in")
  end
end
