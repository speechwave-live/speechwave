defmodule Speechwave.Admin.ConsentExport do
  @moduledoc """
  Builds the super-admin marketing email consent export
  (docs/specs/2026-10-15-email-consent-export-design.md).

  `list/1` returns one row map per user whose `marketing_email` consent is
  currently granted and who has confirmed their email. Each row also carries
  talk and session aggregates so the CSV can be segmented in a spreadsheet
  (new vs. inactive users, by plan, and so on).
  """

  import Ecto.Query

  alias Speechwave.Accounts.{User, UserConsent}
  alias Speechwave.Admin.CSV
  alias Speechwave.Repo
  alias Speechwave.Talks.{Talk, TalkSession}

  @columns [
    :email,
    :source,
    :consented_at,
    :plan,
    :signed_up_at,
    :talk_count,
    :session_count,
    :last_session_at
  ]

  @doc """
  Returns export rows, ordered by consent date then email.

  `filters` may contain `:source` (exact match), and `:from` / `:to`
  (`Date`s, inclusive, compared against `granted_at` in UTC). Missing or
  nil keys apply no filter.
  """
  def list(filters) do
    # Talk counts and session aggregates come from separate grouped
    # subqueries. Joining talks and sessions directly onto users would
    # multiply the talk count by the number of sessions per talk.
    talk_counts =
      from t in Talk,
        group_by: t.user_id,
        select: %{user_id: t.user_id, talk_count: count(t.id)}

    session_stats =
      from s in TalkSession,
        join: t in Talk,
        on: t.id == s.talk_id,
        group_by: t.user_id,
        select: %{
          user_id: t.user_id,
          session_count: count(s.id),
          last_session_at: max(s.started_at)
        }

    from(c in UserConsent,
      join: u in User,
      on: u.id == c.user_id,
      left_join: tc in subquery(talk_counts),
      on: tc.user_id == u.id,
      left_join: ss in subquery(session_stats),
      on: ss.user_id == u.id,
      where:
        c.consent_type == "marketing_email" and c.granted == true and is_nil(c.revoked_at) and
          not is_nil(u.confirmed_at),
      order_by: [asc: c.granted_at, asc: u.email],
      select: %{
        email: u.email,
        source: c.source,
        consented_at: c.granted_at,
        plan: u.plan,
        signed_up_at: u.inserted_at,
        talk_count: coalesce(tc.talk_count, 0),
        session_count: coalesce(ss.session_count, 0),
        last_session_at: ss.last_session_at
      }
    )
    |> filter_source(Map.get(filters, :source))
    |> filter_from(Map.get(filters, :from))
    |> filter_to(Map.get(filters, :to))
    |> Repo.all()
  end

  defp filter_source(query, nil), do: query
  defp filter_source(query, source), do: where(query, [c], c.source == ^source)

  defp filter_from(query, nil), do: query

  defp filter_from(query, %Date{} = from) do
    start = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    where(query, [c], c.granted_at >= ^start)
  end

  defp filter_to(query, nil), do: query

  defp filter_to(query, %Date{} = to) do
    finish = DateTime.new!(to, ~T[23:59:59], "Etc/UTC")
    where(query, [c], c.granted_at <= ^finish)
  end

  @doc """
  Turns string-keyed form params (`"source"`, `"from"`, `"to"`) into the
  filters map `list/1` expects. Blank or unparseable values become nil, so a
  hand-edited URL can never crash the download.
  """
  def parse_filters(params) do
    %{
      source: parse_source(params["source"]),
      from: parse_date(params["from"]),
      to: parse_date(params["to"])
    }
  end

  defp parse_source(source) when is_binary(source) do
    case String.trim(source) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp parse_source(_), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_date(_), do: nil

  @doc "Encodes `rows` from `list/1` as CSV, with the header row first."
  def to_csv(rows) do
    CSV.encode(
      Enum.map(@columns, &Atom.to_string/1),
      Enum.map(rows, fn row -> Enum.map(@columns, &Map.fetch!(row, &1)) end)
    )
  end

  @doc "Download filename for an export made on `date`."
  def filename(%Date{} = date), do: "marketing-consent-#{Date.to_iso8601(date)}.csv"
end
