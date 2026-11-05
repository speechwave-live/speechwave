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
  alias Speechwave.Reactions.Timeline
  alias Speechwave.Repo
  alias Speechwave.Talks.TalkSession

  # Seconds between a timestamp column and `start_unix`, computed in SQL.
  # SQLite stores :utc_datetime as text, so strftime('%s', ...) converts it
  # to a Unix epoch (as text) and CAST makes it an integer. A macro, because
  # Ecto query fragments must be known at compile time.
  defmacrop offset_seconds(field, start_unix) do
    quote do
      fragment(
        "CAST(strftime('%s', ?) AS INTEGER) - ?",
        unquote(field),
        unquote(start_unix)
      )
    end
  end

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

  @doc """
  Distinct audience members who reacted on each slide, as `%{slide_number => count}`.
  Slide 0 is the general bucket. Slides where no reaction carries an audience
  ID are absent from the map.
  """
  def slide_audience_counts(session_id) do
    from(r in Reaction,
      where: r.talk_session_id == ^session_id,
      group_by: r.slide_number,
      having: count(r.audience_id, :distinct) > 0,
      select: {r.slide_number, count(r.audience_id, :distinct)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Reactions over time for one session, for the timeline chart, or `nil`
  when the session has no reactions.

  Returns `%{bucket_seconds:, counts:, peak:, slide_starts:}`:

    * `counts` has one reaction count per time bucket, starting at the
      session start. The axis ends at the last reaction, capped at
      `ended_at` when the session has ended. (Sessions closed by the
      stale-session sweep get an `ended_at` hours after the talk really
      finished, so `ended_at` alone would stretch the chart.)
    * Reactions stamped before the start count in bucket 0; reactions past
      the axis end count in the last bucket.
    * `peak` is the busiest bucket, ties going to the earliest.
    * `slide_starts` gives, for each slide above 0, the offset of its first
      reaction, sorted by offset then slide.

  Only integers are returned, so the map encodes with `Jason`, and no
  audience data is included.
  """
  def timeline(%TalkSession{} = session) do
    start = DateTime.to_unix(session.started_at)
    base = from(r in Reaction, where: r.talk_session_id == ^session.id)

    # Query 1: the latest reaction offset; nil means no reactions at all.
    case Repo.one(from(r in base, select: max(offset_seconds(r.inserted_at, ^start)))) do
      nil -> nil
      last_offset -> build_timeline(session, base, start, last_offset)
    end
  end

  defp build_timeline(session, base, start, last_offset) do
    axis_seconds = axis_seconds(session, max(last_offset, 0))
    bucket = Timeline.bucket_seconds(axis_seconds)

    # Query 2: counts per bucket. SQLite's two-argument MAX is a scalar
    # "greater of", which folds early reactions into bucket 0; integer
    # division of two integers truncates, giving the bucket index.
    pairs =
      from(r in base,
        group_by: selected_as(:bucket),
        select:
          {selected_as(
             fragment("MAX(?, 0) / ?", offset_seconds(r.inserted_at, ^start), ^bucket),
             :bucket
           ), count(r.id)}
      )
      |> Repo.all()

    counts = Timeline.dense_counts(pairs, div(axis_seconds, bucket))

    # Query 3: first reaction on each real slide (slide 0 is "no slide").
    slide_starts =
      from(r in base,
        where: r.slide_number > 0,
        group_by: r.slide_number,
        select: {r.slide_number, min(offset_seconds(r.inserted_at, ^start))}
      )
      |> Repo.all()
      |> Enum.map(fn {slide, offset} -> %{slide: slide, offset_seconds: max(offset, 0)} end)
      |> Enum.sort_by(&{&1.offset_seconds, &1.slide})

    %{
      bucket_seconds: bucket,
      counts: counts,
      peak: Timeline.peak(counts),
      slide_starts: slide_starts
    }
  end

  # The axis runs to the last reaction, but never past the session's end.
  defp axis_seconds(%TalkSession{ended_at: nil}, last_offset), do: last_offset

  defp axis_seconds(%TalkSession{ended_at: ended_at, started_at: started_at}, last_offset) do
    min(last_offset, max(DateTime.diff(ended_at, started_at, :second), 0))
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
