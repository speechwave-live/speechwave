defmodule SpeechwaveWeb.UserDataExportControllerTest do
  # Not async: the throttle is one shared ETS table.
  use SpeechwaveWeb.ConnCase, async: false

  import Speechwave.AccountsFixtures

  @moduletag :capture_log

  setup do
    :ets.delete_all_objects(:data_export_throttle)
    :ok
  end

  describe "POST /users/settings/export" do
    setup :register_and_log_in_user

    test "GET /users/settings/export is no longer routed", %{conn: conn} do
      assert conn |> get(~p"/users/settings/export") |> response(404)
    end

    test "sends the zip", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/export")

      assert response(conn, 200)
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/zip"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "speechwave-data.zip"

      {:ok, files} = :zip.unzip(conn.resp_body, [:memory])

      assert files |> Enum.map(&to_string(elem(&1, 0))) |> Enum.sort() ==
               ["README.md", "speechwave_data.json", "speechwave_data.schema.json"]
    end

    test "a second request inside the cooldown is redirected with a flash", %{conn: conn} do
      _ = post(conn, ~p"/users/settings/export")
      conn = post(conn, ~p"/users/settings/export")

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "minutes"
      assert get_resp_header(conn, "content-disposition") == []
    end

    test "another user is not affected by this user's cooldown", %{conn: conn} do
      _ = post(conn, ~p"/users/settings/export")

      other = build_conn() |> log_in_user(user_fixture()) |> post(~p"/users/settings/export")
      assert response(other, 200)
    end

    test "a failed build releases the cooldown", %{conn: conn} do
      Application.put_env(:speechwave, :data_export_zip_fun, fn _scope -> raise "boom" end)
      on_exit(fn -> Application.delete_env(:speechwave, :data_export_zip_fun) end)

      assert_raise RuntimeError, "boom", fn -> post(conn, ~p"/users/settings/export") end

      Application.delete_env(:speechwave, :data_export_zip_fun)
      assert conn |> post(~p"/users/settings/export") |> response(200)
    end

    test "a build that returns {:error, _} releases the cooldown and redirects with a flash",
         %{conn: conn} do
      Application.put_env(:speechwave, :data_export_zip_fun, fn _scope -> {:error, :boom} end)
      on_exit(fn -> Application.delete_env(:speechwave, :data_export_zip_fun) end)

      failed = post(conn, ~p"/users/settings/export")
      assert redirected_to(failed) == ~p"/users/settings"
      assert Phoenix.Flash.get(failed.assigns.flash, :error) =~ "try again"

      Application.delete_env(:speechwave, :data_export_zip_fun)
      assert conn |> post(~p"/users/settings/export") |> response(200)
    end

    test "a send that raises releases the cooldown", %{conn: conn} do
      Application.put_env(:speechwave, :data_export_zip_fun, fn _scope -> {:ok, :not_a_binary} end)

      on_exit(fn -> Application.delete_env(:speechwave, :data_export_zip_fun) end)

      assert_raise FunctionClauseError, fn -> post(conn, ~p"/users/settings/export") end

      Application.delete_env(:speechwave, :data_export_zip_fun)
      assert conn |> post(~p"/users/settings/export") |> response(200)
    end
  end

  test "a logged-out request redirects to login and sends no file" do
    conn = post(build_conn(), ~p"/users/settings/export")

    assert redirected_to(conn) =~ "/users/log-in"
    assert get_resp_header(conn, "content-disposition") == []
  end
end
