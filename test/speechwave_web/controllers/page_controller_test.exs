defmodule SpeechwaveWeb.PageControllerTest do
  use SpeechwaveWeb.ConnCase

  test "GET / returns 200", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Speechwave"
  end

  test "GET /terms returns 200", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms"
  end

  test "GET /privacy returns 200", %{conn: conn} do
    conn = get(conn, ~p"/privacy")
    assert html_response(conn, 200) =~ "Privacy"
  end
end
