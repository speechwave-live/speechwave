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

  test "GET / includes SEO and Open Graph meta tags", %{conn: conn} do
    html = get(conn, ~p"/") |> html_response(200)

    assert html =~
             ~s(<meta name="description" content="Speechwave lets your audience react with emoji in real time during your talk, then gives you per-slide analytics to see what landed.">)

    assert html =~ ~s(<link rel="canonical" href="http://localhost:4000/">)
    assert html =~ ~s(<meta property="og:site_name" content="Speechwave">)
    assert html =~ ~s(<meta property="og:type" content="website">)
    assert html =~ ~s(<meta property="og:title" content="Speechwave">)
    assert html =~ ~s(<meta property="og:url" content="http://localhost:4000/">)
    assert html =~ ~s(<meta property="og:image" content="http://localhost:4000/images/og-hero.png">)
    assert html =~ ~s(<meta property="og:image:width" content="1200">)
    assert html =~ ~s(<meta property="og:image:height" content="630">)
    assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)
    assert html =~ ~s(<meta name="twitter:image" content="http://localhost:4000/images/og-hero.png">)
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
