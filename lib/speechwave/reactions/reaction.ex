defmodule Speechwave.Reactions.Reaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reactions" do
    field :emoji, :string
    field :slide_number, :integer, default: 0
    field :audience_id, :string

    belongs_to :talk_session, Speechwave.Talks.TalkSession

    timestamps(type: :utc_datetime)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :slide_number])
    |> validate_required([:emoji])
  end
end
