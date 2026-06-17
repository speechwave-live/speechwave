defmodule Speechwave.Plans do
  @moduledoc """
  Defines tier limits for each plan and provides enforcement checks.

  Plans: :free, :pro, :org
  Features: :max_participants, :full_sessions_per_month

  A "full session" is a session lasting longer than 10 minutes.
  """

  @type plan :: :free | :pro | :org
  @type feature :: :max_participants | :full_sessions_per_month
  @type limit :: non_neg_integer() | :unlimited

  @spec limit(feature(), plan()) :: limit()
  def limit(:max_participants, :free), do: 15
  def limit(:full_sessions_per_month, :free), do: 50
  def limit(:max_participants, :pro), do: :unlimited
  def limit(:full_sessions_per_month, :pro), do: :unlimited
  def limit(feature, :org), do: limit(feature, :pro)

  @spec check(feature(), plan(), non_neg_integer()) :: :ok | {:error, :limit_reached}
  def check(feature, plan, current_count) when is_integer(current_count) and current_count >= 0 do
    case limit(feature, plan) do
      :unlimited -> :ok
      max when current_count < max -> :ok
      _ -> {:error, :limit_reached}
    end
  end
end
