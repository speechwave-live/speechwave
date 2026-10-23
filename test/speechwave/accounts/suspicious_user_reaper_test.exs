defmodule Speechwave.Accounts.SuspiciousUserReaperTest do
  # async: false because the reaper writes to the deletion log, a single file
  # shared by the whole test run.
  use Speechwave.DataCase, async: false

  # Keep the info-level sweep summaries out of the test output.
  @moduletag :capture_log

  import ExUnit.CaptureLog
  import Speechwave.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Speechwave.Accounts.SuspiciousUserReaper
  alias Speechwave.Accounts.User
  alias Speechwave.DeletionLog
  alias Speechwave.Repo

  setup do
    File.rm(DeletionLog.path())

    # The test environment only logs warnings and above; the sweep summary is
    # logged at info level, so lower the threshold for this test and restore it.
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
    :ok
  end

  # Starts an unnamed reaper under the test supervisor. The long defaults mean
  # no sweep happens unless the test asks for one.
  defp start_reaper!(opts \\ []) do
    defaults = [name: nil, sweep_interval: :timer.hours(1), initial_delay: :timer.hours(1)]
    pid = start_supervised!({SuspiciousUserReaper, Keyword.merge(defaults, opts)})
    Sandbox.allow(Speechwave.Repo, self(), pid)
    pid
  end

  defp old_user(days) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    backdate_user(user_fixture(), DateTime.add(now, -days, :day))
  end

  test ":sweep_now deletes an unconfirmed user older than the cutoff" do
    user = old_user(16)

    pid = start_reaper!()
    assert GenServer.call(pid, :sweep_now) == :ok

    refute Repo.get(User, user.id)
  end

  test ":sweep_now leaves a recent unconfirmed user" do
    user = old_user(1)

    pid = start_reaper!()
    assert GenServer.call(pid, :sweep_now) == :ok

    assert Repo.get(User, user.id)
  end

  test "processes an internal :sweep message" do
    user = old_user(16)

    pid = start_reaper!()
    send(pid, :sweep)
    # :sys.get_state/1 returns only after the process has handled every message
    # already in its mailbox, including the :sweep above, so no sleep is needed.
    _ = :sys.get_state(pid)

    refute Repo.get(User, user.id)
  end

  test "sweeps shortly after boot" do
    user = old_user(16)

    pid = start_reaper!(initial_delay: 0)
    _ = :sys.get_state(pid)

    refute Repo.get(User, user.id)
  end

  test "does not sweep on its own before the initial delay has passed" do
    user = old_user(16)

    pid = start_reaper!()
    _ = :sys.get_state(pid)

    assert Repo.get(User, user.id)
  end

  test "logs how many users it deleted" do
    _user = old_user(16)

    pid = start_reaper!()
    log = capture_log(fn -> GenServer.call(pid, :sweep_now) end)

    assert log =~ "Deleted 1 suspicious"
  end
end
