defmodule Speechwave.Repo.Migrations.AddConfirmedAtToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :confirmed_at, :utc_datetime
    end

    execute("""
    UPDATE users
    SET confirmed_at = sub.min_ts
    FROM (
      SELECT user_id, MIN(inserted_at) AS min_ts FROM (
        SELECT user_id, inserted_at FROM users_tokens WHERE context = 'session'
        UNION ALL
        SELECT user_id, inserted_at FROM user_identities
      )
      GROUP BY user_id
    ) AS sub
    WHERE users.id = sub.user_id
    """)
  end

  def down do
    alter table(:users) do
      remove :confirmed_at
    end
  end
end
