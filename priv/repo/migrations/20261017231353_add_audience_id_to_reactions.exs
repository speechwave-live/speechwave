defmodule Speechwave.Repo.Migrations.AddAudienceIdToReactions do
  use Ecto.Migration

  def change do
    alter table(:reactions) do
      # Opaque per-connection ID of the audience member; null for reactions
      # recorded before this column existed.
      add :audience_id, :string
    end
  end
end
