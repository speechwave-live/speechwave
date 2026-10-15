defmodule Speechwave.Admin.ConsentExportTest do
  use Speechwave.DataCase

  import Ecto.Query
  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Accounts
  alias Speechwave.Accounts.UserConsent
  alias Speechwave.Admin.ConsentExport

  # A user with granted marketing consent who has also confirmed their email.
  # `session_token_fixture/1` is what marks the user confirmed.
  defp confirmed_consented(source \\ "login") do
    user = consented_user_fixture(%{source: source})
    session_token_fixture(user)
    user
  end

  defp set_granted_at(user, granted_at) do
    Repo.update_all(from(c in UserConsent, where: c.user_id == ^user.id),
      set: [granted_at: granted_at]
    )
  end

  defp emails(rows), do: Enum.map(rows, & &1.email)

  describe "list/1" do
    test "includes granted, confirmed users with all columns" do
      user = confirmed_consented("pricing_pro")

      assert [row] = ConsentExport.list(%{})
      assert row.email == user.email
      assert row.source == "pricing_pro"
      assert row.plan == :free
      assert %DateTime{} = row.consented_at
      assert %DateTime{} = row.signed_up_at
    end

    test "excludes unconfirmed users" do
      consented_user_fixture()
      assert ConsentExport.list(%{}) == []
    end

    test "excludes revoked consent" do
      user = confirmed_consented()
      {:ok, _} = Accounts.revoke_consent(user, "marketing_email")
      assert ConsentExport.list(%{}) == []
    end

    test "revoked then re-granted appears once" do
      user = confirmed_consented()
      {:ok, _} = Accounts.revoke_consent(user, "marketing_email")
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "settings")

      assert [row] = ConsentExport.list(%{})
      assert row.email == user.email
      assert row.source == "settings"
    end

    test "excludes users who never granted consent" do
      session_token_fixture(user_fixture())
      assert ConsentExport.list(%{}) == []
    end

    test "source filter is an exact match" do
      pro = confirmed_consented("pricing_pro")
      _login = confirmed_consented("login")

      assert emails(ConsentExport.list(%{source: "pricing_pro"})) == [pro.email]
      assert ConsentExport.list(%{source: "pricing"}) == []
    end

    test "date range is inclusive on both ends" do
      first = confirmed_consented()
      last = confirmed_consented()
      set_granted_at(first, ~U[2026-10-01 00:00:00Z])
      set_granted_at(last, ~U[2026-10-10 23:59:59Z])

      both = ConsentExport.list(%{from: ~D[2026-10-01], to: ~D[2026-10-10]})
      assert Enum.sort(emails(both)) == Enum.sort([first.email, last.email])

      assert emails(ConsentExport.list(%{from: ~D[2026-10-01], to: ~D[2026-10-09]})) ==
               [first.email]

      assert emails(ConsentExport.list(%{from: ~D[2026-10-02]})) == [last.email]
    end

    test "user with no talks has zero counts and nil last_session_at" do
      confirmed_consented()

      assert [row] = ConsentExport.list(%{})
      assert row.talk_count == 0
      assert row.session_count == 0
      assert row.last_session_at == nil
    end

    test "user with a talk but no sessions has talk_count 1, session_count 0" do
      user = confirmed_consented()
      talk_fixture(user)

      assert [row] = ConsentExport.list(%{})
      assert row.talk_count == 1
      assert row.session_count == 0
      assert row.last_session_at == nil
    end

    test "counts are not multiplied across joins" do
      user = confirmed_consented()
      talk_a = talk_fixture(user)
      talk_b = talk_fixture(user)
      session_fixture(talk_a, %{started_at: ~U[2026-09-01 10:00:00Z]})
      session_fixture(talk_a, %{started_at: ~U[2026-09-05 10:00:00Z]})
      session_fixture(talk_b, %{started_at: ~U[2026-09-03 10:00:00Z]})

      assert [row] = ConsentExport.list(%{})
      assert row.talk_count == 2
      assert row.session_count == 3
      assert row.last_session_at == ~U[2026-09-05 10:00:00Z]
    end

    test "orders by consented_at then email" do
      later = confirmed_consented()
      earlier = confirmed_consented()
      set_granted_at(later, ~U[2026-10-05 00:00:00Z])
      set_granted_at(earlier, ~U[2026-10-01 00:00:00Z])

      assert emails(ConsentExport.list(%{})) == [earlier.email, later.email]
    end
  end

  describe "sources/0" do
    test "lists distinct sources of currently granted consents, sorted" do
      confirmed_consented("pricing_pro")
      confirmed_consented("login")
      confirmed_consented("login")
      revoked = confirmed_consented("pricing_enterprise")
      {:ok, _} = Accounts.revoke_consent(revoked, "marketing_email")

      assert ConsentExport.sources() == ["login", "pricing_pro"]
    end

    test "is empty when nobody has consented" do
      assert ConsentExport.sources() == []
    end
  end

  describe "parse_filters/1" do
    test "ignores blank and unparseable values" do
      assert ConsentExport.parse_filters(%{"source" => "", "from" => "nope", "to" => ""}) ==
               %{source: nil, from: nil, to: nil}

      assert ConsentExport.parse_filters(%{}) == %{source: nil, from: nil, to: nil}
    end

    test "parses valid values" do
      assert ConsentExport.parse_filters(%{
               "source" => "login",
               "from" => "2026-10-01",
               "to" => "2026-10-10"
             }) == %{source: "login", from: ~D[2026-10-01], to: ~D[2026-10-10]}
    end
  end

  describe "to_csv/1 and filename/1" do
    test "has the exact header and one line per row" do
      confirmed_consented()
      csv = ConsentExport.list(%{}) |> ConsentExport.to_csv() |> IO.iodata_to_binary()

      assert <<0xEF, 0xBB, 0xBF, csv::binary>> = csv
      assert [header, _row, ""] = String.split(csv, "\r\n")

      assert header ==
               "email,source,consented_at,plan,signed_up_at,talk_count,session_count,last_session_at"
    end

    test "filename is dated" do
      assert ConsentExport.filename(~D[2026-10-15]) == "marketing-consent-2026-10-15.csv"
    end
  end
end
