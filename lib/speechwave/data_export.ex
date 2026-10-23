defmodule Speechwave.DataExport do
  @moduledoc """
  Builds the copy of a user's personal data behind the "Download my data"
  button (GDPR Articles 15 and 20).

  `build/2` returns a plain map that is encoded to `speechwave_data.json`.
  Its shape is described by `priv/data_export/speechwave_data.schema.json`.

  Deliberately left out: the API key and login tokens (credentials), and
  individual reactions with their times and audience IDs. Reactions describe
  audience members, not the account holder, so they are summarised as counts.
  """

  import Ecto.Query

  alias Speechwave.Accounts
  alias Speechwave.Accounts.Scope
  alias Speechwave.Accounts.UserConsent
  alias Speechwave.Reactions.Reaction
  alias Speechwave.Repo
  alias Speechwave.Talks.Talk

  @format_version 1

  @schema_path Path.join(
                 :code.priv_dir(:speechwave) |> to_string(),
                 "data_export/speechwave_data.schema.json"
               )
  @readme_path Path.join(:code.priv_dir(:speechwave) |> to_string(), "data_export/README.md")
  @external_resource @schema_path
  @external_resource @readme_path
  @schema File.read!(@schema_path)
  @readme File.read!(@readme_path)

  @doc "Builds the export map for the scope's user."
  def build(%Scope{user: user}, exported_at \\ DateTime.utc_now()) do
    talks = list_talks(user)
    reaction_summaries = summarise_reactions(talks)

    %{
      format_version: @format_version,
      exported_at: exported_at,
      account: account(user),
      sign_in_providers: sign_in_providers(user),
      consents: consents(user),
      talks: Enum.map(talks, &talk(&1, reaction_summaries))
    }
  end

  @doc """
  Packs the export into an in-memory zip with the data, its JSON Schema and a
  README. The README's `{{exported_at}}` placeholder is filled in here.
  """
  def to_zip(%Scope{} = scope, exported_at \\ DateTime.utc_now()) do
    json = scope |> build(exported_at) |> Jason.encode!(pretty: true)
    readme = String.replace(@readme, "{{exported_at}}", DateTime.to_iso8601(exported_at))

    files = [
      {~c"speechwave_data.json", json},
      {~c"speechwave_data.schema.json", @schema},
      {~c"README.md", readme}
    ]

    {:ok, {_name, zip}} = :zip.create(~c"speechwave-data.zip", files, [:memory])
    {:ok, zip}
  end

  defp account(user) do
    %{
      email: user.email,
      plan: Atom.to_string(user.plan),
      is_admin: user.is_admin,
      confirmed_at: user.confirmed_at,
      welcomed_at: user.welcomed_at,
      overlay_size_percent: user.overlay_size_percent,
      fireworks_enabled: user.fireworks_enabled,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end

  defp sign_in_providers(user) do
    for identity <- Accounts.list_user_identities(user) do
      %{provider: identity.provider, uid: identity.uid, linked_at: identity.inserted_at}
    end
  end

  defp consents(user) do
    from(c in UserConsent, where: c.user_id == ^user.id, order_by: c.id)
    |> Repo.all()
    |> Enum.map(fn c ->
      Map.take(c, [:consent_type, :granted, :granted_at, :revoked_at, :source])
    end)
  end

  defp list_talks(user) do
    sessions = from(s in Speechwave.Talks.TalkSession, order_by: [asc: s.started_at, asc: s.id])

    from(t in Talk,
      where: t.user_id == ^user.id,
      order_by: [asc: t.inserted_at, asc: t.id],
      preload: [talk_sessions: ^sessions]
    )
    |> Repo.all()
  end

  defp talk(talk, summaries) do
    %{
      title: talk.title,
      slug: talk.slug,
      inserted_at: talk.inserted_at,
      updated_at: talk.updated_at,
      sessions:
        for session <- talk.talk_sessions do
          %{
            label: session.label,
            started_at: session.started_at,
            ended_at: session.ended_at,
            reactions: Map.get(summaries, session.id, empty_reactions())
          }
        end
    }
  end

  defp empty_reactions, do: %{total: 0, audience_size: nil, by_emoji: %{}, by_slide: []}

  # One grouped query for counts and one for audience size across all of the
  # user's sessions, so the number of queries does not grow with the data.
  defp summarise_reactions(talks) do
    session_ids = for t <- talks, s <- t.talk_sessions, do: s.id

    counts =
      from(r in Reaction,
        where: r.talk_session_id in ^session_ids,
        group_by: [r.talk_session_id, r.slide_number, r.emoji],
        order_by: [asc: r.talk_session_id, asc: r.slide_number, asc: r.emoji],
        select: {r.talk_session_id, r.slide_number, r.emoji, count(r.id)}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0))

    audiences =
      from(r in Reaction,
        where: r.talk_session_id in ^session_ids,
        group_by: r.talk_session_id,
        select: {r.talk_session_id, count(r.audience_id, :distinct)}
      )
      |> Repo.all()
      |> Map.new()

    Map.new(counts, fn {session_id, rows} ->
      {session_id, session_reactions(rows, Map.get(audiences, session_id, 0))}
    end)
  end

  defp session_reactions(rows, audience_count) do
    %{
      total: rows |> Enum.map(&elem(&1, 3)) |> Enum.sum(),
      # Same convention as `Reactions.count_audience/1`: nil when no reaction
      # carries an audience ID.
      audience_size: if(audience_count == 0, do: nil, else: audience_count),
      by_emoji:
        rows
        |> Enum.group_by(&elem(&1, 2), &elem(&1, 3))
        |> Map.new(fn {emoji, counts} -> {emoji, Enum.sum(counts)} end),
      by_slide:
        for {_sid, slide, emoji, count} <- rows do
          %{slide_number: slide, emoji: emoji, count: count}
        end
    }
  end
end
