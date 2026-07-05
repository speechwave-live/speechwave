defmodule SpeechwaveWeb.PageControllerTest do
  use SpeechwaveWeb.ConnCase

  test "GET / returns 200", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Speechwave"
  end

  test "GET / includes a Help link to the docs site", %{conn: conn} do
    html = get(conn, ~p"/") |> html_response(200)

    assert html =~ ~s(id="help-nav-link")
    assert html =~ ~s(href="https://docs.speechwave.live")
    assert html =~ ~s(target="_blank")
    assert html =~ ~s(rel="noopener noreferrer")
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
