defmodule Speechwave.Talks.SessionReaperTest do
  use Speechwave.DataCase, async: true

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Speechwave.Accounts.Scope
  alias Speechwave.Talks
  alias Speechwave.Talks.SessionReaper

  defp scope(user), do: %Scope{user: user}

  defp start_reaper!(opts \\ []) do
    pid =
      start_supervised!(
        {SessionReaper, Keyword.merge([name: nil, sweep_interval: :timer.hours(1)], opts)}
      )

    Sandbox.allow(Speechwave.Repo, self(), pid)
    pid
  end

  defp old_start(timeout_hours) do
    DateTime.utc_now()
    |> DateTime.add(-(timeout_hours + 1) * 3600, :second)
    |> DateTime.truncate(:second)
  end

  test ":sweep_now closes a session older than the configured timeout" do
    user = user_fixture()
    {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "reaper-old"})

    timeout_hours = Application.get_env(:speechwave, :session_timeout_hours, 4)
    session = session_fixture(talk, %{started_at: old_start(timeout_hours)})

    pid = start_reaper!()
    :ok = GenServer.call(pid, :sweep_now)

    assert Talks.get_session(session.id).ended_at != nil
  end

  test ":sweep_now leaves a session within the timeout untouched" do
    user = user_fixture()
    {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "reaper-fresh"})

    session =
      session_fixture(talk, %{started_at: DateTime.utc_now() |> DateTime.truncate(:second)})

    pid = start_reaper!()
    :ok = GenServer.call(pid, :sweep_now)

    assert Talks.get_session(session.id).ended_at == nil
  end

  test "processes an internal :sweep message by closing stale sessions" do
    user = user_fixture()
    {:ok, talk} = Talks.create_talk(scope(user), %{title: "Test", slug: "reaper-sweep-msg"})

    timeout_hours = Application.get_env(:speechwave, :session_timeout_hours, 4)
    session = session_fixture(talk, %{started_at: old_start(timeout_hours)})

    pid = start_reaper!()
    send(pid, :sweep)
    # :sys.get_state/1 blocks until pid has finished processing every message
    # already in its mailbox, including the :sweep we just sent — no sleep needed.
    _ = :sys.get_state(pid)

    assert Talks.get_session(session.id).ended_at != nil
  end
end
