defmodule SpeechwaveWeb.PageControllerTest do
  use SpeechwaveWeb.ConnCase

  test "GET / returns 200", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Speechwave"
  end

  test "pages are pinned to the light theme", %{conn: conn} do
    # The app is light-only (docs/decisions.md, 2026-10-15). Without this pin
    # the stock form components would follow the OS dark setting.
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.filter(document, ~s(html[data-theme="light"])) |> Enum.count() == 1
  end

  test "public pages show flash messages, e.g. after account deletion", %{conn: conn} do
    for path <- [~p"/", ~p"/terms", ~p"/privacy"] do
      document =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        # What a redirect leaves behind for the next request. "phoenix_flash" is
        # Phoenix's own session key; the redirect flow is covered in the
        # UserAccountController test.
        |> Plug.Conn.put_session("phoenix_flash", %{"info" => "Your account has been deleted."})
        |> get(path)
        |> html_response(200)
        |> LazyHTML.from_document()

      assert LazyHTML.query(document, "#public-flash-group #flash-info") |> Enum.count() == 1
    end
  end

  test "GET /health returns 200", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert text_response(conn, 200) == "ok"
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

    assert html =~ ~s(<link rel="canonical" href="#{SpeechwaveWeb.Endpoint.url()}/">)
    assert html =~ ~s(<meta property="og:site_name" content="Speechwave">)
    assert html =~ ~s(<meta property="og:type" content="website">)
    assert html =~ ~s(<meta property="og:title" content="Speechwave">)
    assert html =~ ~s(<meta property="og:url" content="#{SpeechwaveWeb.Endpoint.url()}/">)

    assert html =~
             ~s(<meta property="og:image" content="#{SpeechwaveWeb.Endpoint.url()}/images/og-hero.png">)

    assert html =~ ~s(<meta property="og:image:width" content="1200">)
    assert html =~ ~s(<meta property="og:image:height" content="630">)
    assert html =~ ~s(<meta name="twitter:card" content="summary_large_image">)

    assert html =~
             ~s(<meta name="twitter:image" content="#{SpeechwaveWeb.Endpoint.url()}/images/og-hero.png">)
  end

  test "GET /terms returns 200 with SEO meta tags", %{conn: conn} do
    html = get(conn, ~p"/terms") |> html_response(200)

    assert html =~ "Terms"
    assert html =~ ~r/<title[^>]*>\s*Terms of Service · Speechwave\s*<\/title>/
    assert html =~ ~s(<meta name="description" content="Speechwave&#39;s terms of service.">)
    assert html =~ ~s(<meta property="og:title" content="Terms of Service · Speechwave">)
  end

  test "GET /privacy describes the self-service data download", %{conn: conn} do
    html = get(conn, ~p"/privacy") |> html_response(200)

    matches = html |> LazyHTML.from_document() |> LazyHTML.query("#privacy-data-export")
    assert Enum.count(matches) == 1
  end

  test "GET /privacy returns 200 with SEO meta tags", %{conn: conn} do
    html = get(conn, ~p"/privacy") |> html_response(200)

    assert html =~ "Privacy"
    assert html =~ ~r/<title[^>]*>\s*Privacy Policy · Speechwave\s*<\/title>/

    assert html =~
             ~s(<meta name="description" content="How Speechwave collects, uses, and protects your data.">)

    assert html =~ ~s(<meta property="og:title" content="Privacy Policy · Speechwave">)
  end
end
