defmodule Speechwave.Repo.Migrations.AddExtensionSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :overlay_size_percent, :integer
      add :fireworks_enabled, :boolean, default: true, null: false
    end
  end
end
