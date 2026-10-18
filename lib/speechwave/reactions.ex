defmodule Speechwave.Reactions do
  @moduledoc """
  The Reactions context — records and aggregates audience emoji reactions.

  Reactions are attached to a `TalkSession` and optionally to a slide number
  (defaults to 0 when slide tracking is not in use). The main write path is
  `create_reaction/3`, called from the audience LiveView on each tap.

  The read functions (`count_reactions/1`, `slide_reaction_totals/1`) power
  the analytics dashboard in `SessionAnalyticsLive`.
  """
  import Ecto.Query

  alias Speechwave.Reactions.Reaction
  alias Speechwave.Repo
  alias Speechwave.Talks.TalkSession

  # `audience_id` is set on the struct rather than cast, since it is
  # assigned by the server and never taken from user input.
  def create_reaction(%TalkSession{} = session, emoji, slide_number \\ 0, audience_id \\ nil) do
    %Reaction{talk_session_id: session.id, audience_id: audience_id}
    |> Reaction.changeset(%{emoji: emoji, slide_number: slide_number})
    |> Repo.insert()
  end

  def count_reactions(session_id) do
    Repo.aggregate(from(r in Reaction, where: r.talk_session_id == ^session_id), :count)
  end

  @doc """
  Number of distinct audience members who reacted in the session, or `nil`
  when no reaction carries an audience ID (sessions recorded before audience
  tracking existed).
  """
  def count_audience(session_id) do
    count =
      Repo.one(
        from(r in Reaction,
          where: r.talk_session_id == ^session_id,
          select: count(r.audience_id, :distinct)
        )
      )

    if count == 0, do: nil, else: count
  end

  def slide_reaction_totals(session_id) do
    from(r in Reaction,
      where: r.talk_session_id == ^session_id,
      group_by: [r.slide_number, r.emoji],
      select: %{slide_number: r.slide_number, emoji: r.emoji, count: count(r.id)},
      order_by: [asc: r.slide_number]
    )
    |> Repo.all()
  end
end
