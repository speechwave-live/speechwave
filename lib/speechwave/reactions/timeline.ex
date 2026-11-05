defmodule Speechwave.Reactions.Timeline do
  @moduledoc """
  Pure helpers that shape per-bucket reaction counts into the timeline map
  returned by `Speechwave.Reactions.timeline/1`.

  The database does the heavy lifting (grouping reactions by time bucket);
  this module only picks the bucket size, lays the counts out as a dense
  list, and finds the peak. Everything here works on plain integers so the
  result encodes straight to JSON for the chart.
  """

  # Candidate bucket sizes in seconds, smallest first.
  @sizes [10, 15, 30, 60, 120, 300, 600]
  @max_buckets 60

  @doc """
  Bucket size in seconds for an axis `axis_seconds` long: the smallest
  candidate that keeps the chart at #{@max_buckets} buckets or fewer, else
  the largest candidate (600).

  The bucket count is `div(axis_seconds, size) + 1` because the axis runs
  from offset 0 up to and including `axis_seconds`.
  """
  def bucket_seconds(axis_seconds) when is_integer(axis_seconds) and axis_seconds >= 0 do
    Enum.find(@sizes, List.last(@sizes), fn size ->
      div(axis_seconds, size) + 1 <= @max_buckets
    end)
  end

  @doc """
  Turns `{bucket_index, count}` pairs (sparse, as grouped by SQL) into a
  dense list with one entry per bucket from 0 to `last_index`. Indexes past
  `last_index` are folded into the last bucket; missing buckets are 0.
  """
  def dense_counts(pairs, last_index) when is_integer(last_index) and last_index >= 0 do
    by_index =
      Enum.reduce(pairs, %{}, fn {index, count}, acc ->
        Map.update(acc, min(index, last_index), count, &(&1 + count))
      end)

    Enum.map(0..last_index, &Map.get(by_index, &1, 0))
  end

  @doc """
  The highest bucket as `%{index: i, count: c}`. Ties go to the earliest
  bucket, because `Enum.max_by/2` keeps the first maximum it sees.
  """
  def peak(counts) do
    {count, index} = counts |> Enum.with_index() |> Enum.max_by(fn {count, _} -> count end)
    %{index: index, count: count}
  end
end
