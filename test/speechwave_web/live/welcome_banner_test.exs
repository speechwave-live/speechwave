defmodule SpeechwaveWeb.WelcomeBannerTest do
  use SpeechwaveWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts.User
  alias Speechwave.Repo

  defp stored_welcomed_at(user), do: Repo.get!(User, user.id).welcomed_at

  # True when the LiveView's socket has a :welcome_banner handle_event hook.
  defp welcome_hook?(view) do
    socket = :sys.get_state(view.pid).socket
    Enum.any?(socket.private.lifecycle.handle_event, &(&1.id == :welcome_banner))
  end

  test "dismissing records welcomed_at and removes the banner", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/users/settings")

    assert has_element?(view, "#welcome-banner")
    render_click(element(view, "#welcome-banner-dismiss"))

    refute has_element?(view, "#welcome-banner")
    assert %DateTime{} = stored_welcomed_at(user)
  end

  test "works from the admin live session (double mount)", %{conn: conn} do
    admin = admin_user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, admin), ~p"/admin/stats")

    assert has_element?(view, "#welcome-banner")
    render_click(element(view, "#welcome-banner-dismiss"))

    refute has_element?(view, "#welcome-banner")
    assert %DateTime{} = stored_welcomed_at(admin)
  end

  test "dismissing twice keeps the first timestamp", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/users/settings")

    render_click(element(view, "#welcome-banner-dismiss"))

    first = ~U[2026-01-01 00:00:00Z]
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [welcomed_at: first])

    render_hook(view, "dismiss_welcome", %{})

    assert stored_welcomed_at(user) == first
  end

  test "keeps sudo mode after dismissing", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/users/settings")

    # Guard against a vacuous pass: authenticated_at must be set before dismissing.
    before_scope = :sys.get_state(view.pid).socket.assigns.current_scope
    assert %DateTime{} = before_scope.user.authenticated_at
    assert is_nil(before_scope.user.welcomed_at)

    render_click(element(view, "#welcome-banner-dismiss"))

    scope = :sys.get_state(view.pid).socket.assigns.current_scope
    assert %DateTime{} = scope.user.authenticated_at
    assert %DateTime{} = scope.user.welcomed_at
  end

  test "signed-out visitors get no banner", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/pricing")

    refute has_element?(view, "#welcome-banner")

    # No hook is attached for signed-out visitors, so there is nothing to
    # dismiss. We inspect the socket rather than send the event, because an
    # unhandled event correctly crashes PricingLive.
    refute welcome_hook?(view)
  end

  test "signed-in users do have the welcome hook attached", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/users/settings")
    assert welcome_hook?(view)
  end

  test "a user with welcomed_at nil sees the banner on dashboard", %{conn: conn} do
    {:ok, view, _html} = live(log_in_user(conn, user_fixture()), ~p"/dashboard")
    assert has_element?(view, "#welcome-banner")
  end

  test "a user with welcomed_at set sees no banner on dashboard", %{conn: conn} do
    user = user_fixture()
    {:ok, user} = Speechwave.Accounts.mark_welcomed(user)
    assert user.welcomed_at

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/dashboard")
    refute has_element?(view, "#welcome-banner")
  end
end
