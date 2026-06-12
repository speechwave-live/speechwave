defmodule SpeechwaveWeb.DashboardLiveTest do
  use SpeechwaveWeb.ConnCase

  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "redirects to login when unauthenticated", %{conn: _conn} do
    conn = build_conn()
    {:error, {:redirect, %{to: path}}} = live(conn, "/dashboard")
    assert path =~ "/users/log"
  end

  test "renders new talk form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")
    assert has_element?(view, "#talk-form")
  end

  test "auto-generates slug from title on validate", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    view
    |> element("#talk-form")
    |> render_change(%{"talk" => %{"title" => "Elixir for Rubyists", "slug" => ""}})

    assert has_element?(view, "input[value='elixir-for-rubyists']")
  end

  test "creates talk, shows banner, and selects talk with QR code", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    view
    |> form("#talk-form", talk: %{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})
    |> render_submit()

    assert has_element?(view, "#created-talk")
    refute has_element?(view, "#qr-code")
    assert has_element?(view, "#selected-talk-qr")
  end

  test "selected talk panel shows a copyable link and QR download link", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    view
    |> form("#talk-form", talk: %{title: "Elixir for Rubyists", slug: "elixir-for-rubyists"})
    |> render_submit()

    html = render(view)
    assert html =~ "/t/elixir-for-rubyists"
    assert has_element?(view, "#talk-link[href$='/t/elixir-for-rubyists']")
    assert has_element?(view, "#copy-talk-link[data-clipboard-text$='/t/elixir-for-rubyists']")
    assert has_element?(view, "#download-qr-code[download='elixir-for-rubyists-qr-code.png']")
  end

  test "shows validation errors for blank fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")
    view |> form("#talk-form", talk: %{title: "", slug: ""}) |> render_submit()
    assert has_element?(view, "#talk-form [data-errors]") or render(view) =~ "can&#39;t be blank"
  end

  test "lists only the current user's talks", %{conn: conn, user: user} do
    other_user = user_fixture()
    _my_talk = talk_fixture(user, %{title: "My Talk", slug: "my-talk"})
    _their_talk = talk_fixture(other_user, %{title: "Their Talk", slug: "their-talk"})

    {:ok, _view, html} = live(conn, "/dashboard")
    assert html =~ "My Talk"
    refute html =~ "Their Talk"
  end

  test "clicking a talk in the list shows its QR code", %{conn: conn, user: user} do
    talk_fixture(user, %{title: "Prime Talk", slug: "prime"})
    {:ok, view, _html} = live(conn, "/dashboard")

    view |> element("#talk-list button", "Prime Talk") |> render_click()

    assert has_element?(view, "#selected-talk-qr")
  end

  test "show_qr for an id not in the user's talk list is a no-op", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/dashboard")

    render_click(view, "show_qr", %{"id" => "999999"})

    refute has_element?(view, "#selected-talk-qr")
  end

  test "trashcan button appears next to selected talk", %{conn: conn, user: user} do
    talk = talk_fixture(user, %{title: "Prime Talk", slug: "prime"})
    {:ok, view, _html} = live(conn, "/dashboard")

    view |> element("#talk-list button", "Prime Talk") |> render_click()

    assert has_element?(view, "#delete-talk-#{talk.id}")
  end

  test "clicking trashcan deletes the talk and removes it from the list", %{
    conn: conn,
    user: user
  } do
    talk = talk_fixture(user, %{title: "Prime Talk", slug: "prime"})
    {:ok, view, _html} = live(conn, "/dashboard")

    view |> element("#talk-list button", "Prime Talk") |> render_click()
    view |> element("#delete-talk-#{talk.id}") |> render_click()

    refute has_element?(view, "#talk-list button", "Prime Talk")
  end

  describe "sessions panel" do
    setup %{conn: conn, user: user} do
      talk = talk_fixture(user, %{title: "Prime Talk", slug: "prime"})
      {:ok, conn: conn, talk: talk}
    end

    test "shows empty sessions message when talk has no sessions", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      assert has_element?(view, "#sessions-panel")
      assert has_element?(view, "#no-sessions")
    end

    test "lists sessions with reaction counts when sessions exist", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      Speechwave.Reactions.create_reaction(session, "❤️")

      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      assert has_element?(view, "#session-#{session.id}")
      assert has_element?(view, "#session-label-#{session.id}", "Session 1")
      assert render(view) =~ "1 reaction"
    end

    test "shows Active badge for sessions without ended_at", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      assert has_element?(view, "#session-#{session.id} .session-active-badge")
    end

    test "can rename a session", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()
      assert has_element?(view, "#rename-form-#{session.id}")

      view
      |> form("#rename-form-#{session.id}", rename: %{label: "Denver Practice"})
      |> render_submit()

      assert has_element?(view, "#session-label-#{session.id}", "Denver Practice")
    end

    test "can delete a session", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#delete-session-#{session.id}") |> render_click()

      refute has_element?(view, "#session-#{session.id}")
      assert Speechwave.Talks.get_session(session.id) == nil
    end

    test "rename form shows validation error for blank label", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()

      view
      |> form("#rename-form-#{session.id}", rename: %{label: ""})
      |> render_submit()

      assert has_element?(view, "#rename-form-#{session.id}")
    end

    test "cancel_rename hides the rename form", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()

      view |> element("#rename-session-#{session.id}") |> render_click()
      assert has_element?(view, "#rename-form-#{session.id}")

      view |> element("button[phx-click='cancel_rename']") |> render_click()
      refute has_element?(view, "#rename-form-#{session.id}")
    end

    test "sessions panel is hidden after talk is deleted", %{conn: conn, talk: talk} do
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      view |> element("#delete-talk-#{talk.id}") |> render_click()
      refute has_element?(view, "#sessions-panel")
    end

    test "sessions panel shows link to analytics for each session", %{conn: conn, talk: talk} do
      {:ok, session} = Speechwave.Talks.start_session(talk)
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#talk-list button", "Prime Talk") |> render_click()
      assert has_element?(view, "#analytics-link-#{session.id}")
    end
  end

  describe "usage summary" do
    test "shows session usage count and limit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      assert has_element?(view, "#usage-summary")
      assert has_element?(view, "#sessions-used")
      assert has_element?(view, "#session-limit")
    end

    test "shows 0 sessions used when user has no completed sessions", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      assert has_element?(view, "#sessions-used", "0")
    end

    test "reflects full sessions completed this month", %{conn: conn, user: user} do
      # Create a talk and a completed full session (> 10 min) for this user
      talk = talk_fixture(user)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      session_fixture(talk, %{
        label: "Full Session",
        started_at: now,
        ended_at: DateTime.add(now, 15 * 60, :second)
      })

      {:ok, view, _html} = live(conn, "/dashboard")
      assert has_element?(view, "#sessions-used", "1")
    end

    test "shows participant cap", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      assert has_element?(view, "#participant-limit")
    end

    test "shows limit reached warning when monthly limit is hit", %{conn: conn, user: user} do
      talk = talk_fixture(user)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Insert 10 full sessions (the free tier limit)
      for i <- 1..10 do
        session_fixture(talk, %{
          label: "Session #{i}",
          started_at: now,
          ended_at: DateTime.add(now, 15 * 60, :second)
        })
      end

      {:ok, view, _html} = live(conn, "/dashboard")
      assert has_element?(view, "#sessions-used", "10")
      assert render(view) =~ "Monthly limit reached"
    end
  end
end
