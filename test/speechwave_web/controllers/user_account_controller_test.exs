defmodule SpeechwaveWeb.UserAccountControllerTest do
  # Not async: the deletion log is one shared file.
  use SpeechwaveWeb.ConnCase, async: false

  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts.User
  alias Speechwave.DeletionLog
  alias Speechwave.Repo

  setup do
    File.rm(DeletionLog.path())
    :ok
  end

  defp delete_account(conn, email),
    do: delete(conn, ~p"/users/account", %{"account" => %{"email" => email}})

  describe "DELETE /users/account" do
    setup :register_and_log_in_user

    test "deletes the account and redirects home with the flash", %{conn: conn, user: user} do
      conn = delete_account(conn, user.email)

      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Your account and its data have been deleted."

      refute Repo.get(User, user.id)
      assert DeletionLog.logged_ids() == [user.id]
    end

    test "the old session cookie no longer authenticates", %{conn: conn, user: user} do
      stale = conn
      conn = delete_account(conn, user.email)
      assert redirected_to(conn) == ~p"/"

      conn = get(stale, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "broadcasts the extension disconnect for that user", %{conn: conn, user: user} do
      SpeechwaveWeb.Endpoint.subscribe("user:#{user.id}:disconnect")

      delete_account(conn, user.email)

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "ends live sessions for every session token of the user", %{conn: conn, user: user} do
      {token, _} = session_token_fixture(user)
      SpeechwaveWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(token)}")

      delete_account(conn, user.email)

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "a wrong email leaves the account and redirects to settings with an error", %{
      conn: conn,
      user: user
    } do
      conn = delete_account(conn, "wrong@example.com")

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Repo.get(User, user.id)
      assert DeletionLog.logged_ids() == []
    end

    test "a request without the account params does not crash", %{conn: conn, user: user} do
      conn = delete(conn, ~p"/users/account", %{})

      assert redirected_to(conn) == ~p"/users/settings"
      assert Repo.get(User, user.id)
    end
  end

  test "an admin cannot delete via a forged request" do
    admin = admin_user_fixture()
    conn = build_conn() |> log_in_user(admin) |> delete_account(admin.email)

    assert redirected_to(conn) == ~p"/users/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
    assert Repo.get(User, admin.id)
  end

  test "a request without a session is sent to login" do
    conn = delete_account(build_conn(), "someone@example.com")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
