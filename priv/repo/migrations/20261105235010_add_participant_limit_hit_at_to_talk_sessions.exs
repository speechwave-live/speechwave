defmodule Speechwave.Repo.Migrations.AddParticipantLimitHitAtToTalkSessions do
  use Ecto.Migration

  def change do
    alter table(:talk_sessions) do
      add :participant_limit_hit_at, :utc_datetime
    end
  end
end
