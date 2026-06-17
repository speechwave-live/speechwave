defmodule Speechwave.Repo.Migrations.CreateUserConsents do
  use Ecto.Migration

  def change do
    create table(:user_consents) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :consent_type, :string, null: false
      add :granted, :boolean, null: false, default: false
      add :granted_at, :utc_datetime
      add :source, :string
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_consents, [:user_id, :consent_type])
  end
end
