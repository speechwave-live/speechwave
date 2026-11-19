defmodule Speechwave.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Speechwave.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Speechwave.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Speechwave.DataCase
    end
  end

  setup tags do
    Speechwave.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Speechwave.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  Makes every other database caller wait, the way a saturated pool does.

  A helper process takes the sandbox connection and holds it inside a
  transaction. Until the returned function is called, another process that
  queries waits about a second and then raises `DBConnection.ConnectionError`,
  which is what a pool checkout timeout looks like in production.
  """
  def hold_connection do
    parent = self()

    holder =
      spawn_link(fn ->
        Speechwave.Repo.transaction(fn ->
          send(parent, :connection_held)

          receive do
            :release -> :ok
          end
        end)
      end)

    Sandbox.allow(Speechwave.Repo, parent, holder)

    receive do
      :connection_held -> :ok
    end

    # Release waits for the holder to finish its transaction, so the
    # connection is back in the pool before the test ends.
    fn ->
      ref = Process.monitor(holder)
      send(holder, :release)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      end
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
