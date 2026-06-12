defmodule SpeechwaveWeb.UserLive.LoginAuthThrottleTest do
  use SpeechwaveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Speechwave.Accounts
  alias Speechwave.Accounts.UserToken
  alias Speechwave.Repo

  @moduletag :capture_log

  setup do
    Application.put_env(:speechwave, :auth_throttle_enabled, true)
    :ets.delete_all_objects(:auth_throttle_email)
    :ets.delete_all_objects(:auth_throttle_ip)

    on_exit(fn ->
      Application.put_env(:speechwave, :auth_throttle_enabled, false)
    end)

    :ok
  end

  # Test conns never carry forwarded-IP headers, so `client_ip` is always
  # `nil` here, exercising only the `is_nil(ip)` branch of
  # `maybe_send_magic_link/2` (the email-cooldown path). The IP-cooldown
  # branches are covered directly by test/speechwave/auth_throttle_test.exs.
  test "throttles a second magic-link submission for the same email", %{conn: conn} do
    email = "throttle-test@example.com"

    {:ok, view, _html} = live(conn, ~p"/users/log-in")
    view |> form("#magic-link-form", %{"user" => %{"email" => email}}) |> render_submit()
    assert has_element?(view, "#magic-link-sent")

    {:ok, view2, _html} = live(conn, ~p"/users/log-in")
    view2 |> form("#magic-link-form", %{"user" => %{"email" => email}}) |> render_submit()
    assert has_element?(view2, "#magic-link-sent")

    user = Accounts.get_user_by_email(email)

    login_token_count =
      Repo.aggregate(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "login"),
        :count
      )

    assert login_token_count == 1
  end
end
