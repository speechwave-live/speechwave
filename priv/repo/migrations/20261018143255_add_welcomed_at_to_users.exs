defmodule Speechwave.Repo.Migrations.AddWelcomedAtToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :welcomed_at, :utc_datetime
    end

    # Existing users have already found their way around, so they should not
    # see the first-login welcome banner. Only users created after this
    # migration start with a nil welcomed_at.
    execute("UPDATE users SET welcomed_at = CURRENT_TIMESTAMP")
  end

  def down do
    alter table(:users) do
      remove :welcomed_at
    end
  end
end
