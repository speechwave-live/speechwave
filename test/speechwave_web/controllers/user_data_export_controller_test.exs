defmodule SpeechwaveWeb.UserDataExportControllerTest do
  # Not async: the throttle is one shared ETS table.
  use SpeechwaveWeb.ConnCase, async: false

  import Speechwave.AccountsFixtures

  @moduletag :capture_log

  setup do
    :ets.delete_all_objects(:data_export_throttle)
    :ok
  end

  describe "GET /users/settings/export" do
    setup :register_and_log_in_user

    test "sends the zip", %{conn: conn} do
      conn = get(conn, ~p"/users/settings/export")

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
      _ = get(conn, ~p"/users/settings/export")
      conn = get(conn, ~p"/users/settings/export")

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "minutes"
      assert get_resp_header(conn, "content-disposition") == []
    end

    test "another user is not affected by this user's cooldown", %{conn: conn} do
      _ = get(conn, ~p"/users/settings/export")

      other = build_conn() |> log_in_user(user_fixture()) |> get(~p"/users/settings/export")
      assert response(other, 200)
    end

    test "a failed build releases the cooldown", %{conn: conn} do
      Application.put_env(:speechwave, :data_export_zip_fun, fn _scope -> raise "boom" end)
      on_exit(fn -> Application.delete_env(:speechwave, :data_export_zip_fun) end)

      assert_raise RuntimeError, "boom", fn -> get(conn, ~p"/users/settings/export") end

      Application.delete_env(:speechwave, :data_export_zip_fun)
      assert conn |> get(~p"/users/settings/export") |> response(200)
    end
  end

  test "a logged-out request redirects to login and sends no file" do
    conn = get(build_conn(), ~p"/users/settings/export")

    assert redirected_to(conn) =~ "/users/log-in"
    assert get_resp_header(conn, "content-disposition") == []
  end
end
