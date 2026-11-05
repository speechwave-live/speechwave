defmodule Speechwave.Talks.TalkSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "talk_sessions" do
    field :label, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :participant_limit_hit_at, :utc_datetime

    belongs_to :talk, Speechwave.Talks.Talk
    has_many :reactions, Speechwave.Reactions.Reaction

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:label, :started_at, :ended_at])
    |> validate_required([:label, :started_at])
  end
end
