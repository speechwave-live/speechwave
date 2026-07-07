defmodule Speechwave.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """

  alias Ecto.Adapters.SQL

  @app :speechwave

  def migrate do
    load_app()

    for repo <- repos() do
      # `with_repo/2` starts the repo only for the duration of the callback and
      # stops it again once the callback returns. Anything that needs the repo
      # -- including this backfill verification -- must run inside the
      # callback, not after the `for` loop, or it will raise because the repo
      # has already been stopped (this bit us in production: `bin/migrate`
      # loads but doesn't start the app, so `with_repo` is the only thing
      # keeping the repo alive).
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn r ->
          Ecto.Migrator.run(r, :up, all: true)
          verify_confirmed_at_backfill(r)
        end)
    end
  end

  def unconfirmed_with_evidence_count(repo \\ Speechwave.Repo) do
    {:ok, %{rows: [[count]]}} =
      SQL.query(
        repo,
        """
        SELECT COUNT(*) FROM users u
        WHERE u.confirmed_at IS NULL
          AND (EXISTS (SELECT 1 FROM users_tokens t WHERE t.user_id = u.id AND t.context = 'session')
            OR EXISTS (SELECT 1 FROM user_identities i WHERE i.user_id = u.id))
        """,
        []
      )

    count
  end

  defp verify_confirmed_at_backfill(repo) do
    count = unconfirmed_with_evidence_count(repo)

    if count != 0 do
      raise "confirmed_at backfill left #{count} users unconfirmed despite having a session token or identity"
    end
  end

  def seed do
    load_app()
    admin_email = System.get_env("ADMIN_EMAIL") || "admin@speechwave.live"

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Speechwave.Repo, fn _repo -> ensure_admin(admin_email) end)
  end

  defp ensure_admin(admin_email) do
    case Speechwave.Accounts.get_user_by_email(admin_email) do
      nil ->
        {:ok, user} = Speechwave.Accounts.register_user(%{email: admin_email})
        Speechwave.Repo.update!(Ecto.Changeset.change(user, is_admin: true))
        IO.puts("Admin user created: #{admin_email}")

      existing ->
        unless existing.is_admin do
          Speechwave.Repo.update!(Ecto.Changeset.change(existing, is_admin: true))
        end

        IO.puts("Admin user confirmed: #{existing.email}")
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
