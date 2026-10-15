defmodule SpeechwaveWeb.Admin.ConsentExportControllerTest do
  use SpeechwaveWeb.ConnCase

  import Speechwave.AccountsFixtures

  # A user with granted marketing consent who has confirmed their email.
  defp confirmed_consented(source) do
    user = consented_user_fixture(%{source: source})
    session_token_fixture(user)
    user
  end

  test "logged-out request redirects to login and returns no CSV" do
    subscriber = confirmed_consented("login")
    conn = get(build_conn(), ~p"/admin/consent-export")

    assert redirected_to(conn) =~ "/users/log-in"
    refute conn.resp_body =~ subscriber.email
  end

  test "non-admin is redirected home and gets no CSV" do
    subscriber = confirmed_consented("login")
    conn = build_conn() |> log_in_user(user_fixture()) |> get(~p"/admin/consent-export")

    assert redirected_to(conn) == ~p"/"
    refute conn.resp_body =~ subscriber.email
    refute conn |> get_resp_header("content-type") |> Enum.any?(&(&1 =~ "text/csv"))
  end

  test "admin gets a CSV attachment" do
    subscriber = confirmed_consented("login")
    conn = build_conn() |> log_in_user(admin_user_fixture()) |> get(~p"/admin/consent-export")

    assert response(conn, 200)
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/csv"

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~r/attachment; filename="marketing-consent-\d{4}-\d{2}-\d{2}\.csv"/

    [header | _] = String.split(conn.resp_body, "\r\n")
    assert String.starts_with?(header, "email,source,consented_at")
    assert conn.resp_body =~ subscriber.email
  end

  test "filters nested under the export param are applied" do
    pro = confirmed_consented("pricing_pro")
    login = confirmed_consented("login")

    conn =
      build_conn()
      |> log_in_user(admin_user_fixture())
      |> get(~p"/admin/consent-export", %{"export" => %{"source" => "pricing_pro"}})

    assert conn.resp_body =~ pro.email
    refute conn.resp_body =~ login.email
  end

  test "garbage dates do not crash" do
    conn =
      build_conn()
      |> log_in_user(admin_user_fixture())
      |> get(~p"/admin/consent-export", %{"export" => %{"from" => "nope", "to" => "x"}})

    assert response(conn, 200)
  end

  test "non-map export params do not crash" do
    conn = build_conn() |> log_in_user(admin_user_fixture())

    assert conn |> get("/admin/consent-export?export=string") |> response(200)
    assert conn |> get("/admin/consent-export?export[]=1") |> response(200)
  end
end
