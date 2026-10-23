defmodule Speechwave.Admin.StatsTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Admin.Stats
  alias Speechwave.DeletionLog

  describe "user_categories/1" do
    test "counts total, confirmed, and unconfirmed users" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _unconfirmed = user_fixture()

      confirmed_via_token = user_fixture()
      {_token, _user_token} = session_token_fixture(confirmed_via_token)

      confirmed_via_identity = user_fixture()
      session_token_fixture(confirmed_via_identity)
      identity_fixture(confirmed_via_identity)

      %{total_users: total, confirmed: confirmed, unconfirmed: unconfirmed} =
        Stats.user_categories(now)

      assert total.current == 3
      assert confirmed.current == 2
      assert unconfirmed.current == 1
    end

    test "history reflects state as of each of the last 30 days" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      old_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -40, :day))
      {_token, _user_token} = session_token_fixture(old_confirmed, DateTime.add(now, -40, :day))

      _recent_signup = user_fixture() |> backdate_user(DateTime.add(now, -5, :day))

      recently_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -20, :day))

      {_token, _user_token2} =
        session_token_fixture(recently_confirmed, DateTime.add(now, -2, :day))

      %{total_users: total, confirmed: confirmed} = Stats.user_categories(now)

      # 10 days ago: only old_confirmed exists (signed up 40d ago) and is confirmed.
      # recent_signup (signed up 5d ago) and recently_confirmed (signed up 20d ago,
      # confirmed 2d ago) both already existed by 10 days ago.
      ten_days_ago = Date.add(DateTime.to_date(now), -10)

      {^ten_days_ago, total_10d_ago} =
        Enum.find(total.history, fn {d, _} -> d == ten_days_ago end)

      {^ten_days_ago, confirmed_10d_ago} =
        Enum.find(confirmed.history, fn {d, _} -> d == ten_days_ago end)

      assert total_10d_ago == 2
      # recently_confirmed hadn't confirmed yet 10 days ago (confirmed only 2 days ago)
      assert confirmed_10d_ago == 1

      assert total.current == 3
      assert confirmed.current == 2
    end

    test "splits unconfirmed users into onboarding and suspicious by account age" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _onboarding_user =
        user_fixture() |> backdate_user(DateTime.add(now, -1, :day))

      _suspicious_user =
        user_fixture() |> backdate_user(DateTime.add(now, -10, :day))

      %{onboarding: onboarding, suspicious: suspicious, unconfirmed: unconfirmed} =
        Stats.user_categories(now)

      assert onboarding.current == 1
      assert suspicious.current == 1
      assert unconfirmed.current == 2
    end

    test "onboarding + suspicious always sum to unconfirmed, including in history" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _user_a = user_fixture() |> backdate_user(DateTime.add(now, -1, :day))
      _user_b = user_fixture() |> backdate_user(DateTime.add(now, -35, :day))

      confirmed_recently =
        user_fixture() |> backdate_user(DateTime.add(now, -15, :day))

      session_token_fixture(confirmed_recently, DateTime.add(now, -2, :day))

      %{onboarding: onboarding, suspicious: suspicious, unconfirmed: unconfirmed} =
        Stats.user_categories(now)

      for i <- 0..(length(onboarding.history) - 1) do
        {date, ob} = Enum.at(onboarding.history, i)
        {_date, sp} = Enum.at(suspicious.history, i)
        {_date2, u} = Enum.at(unconfirmed.history, i)
        assert ob + sp == u, "mismatch on #{date}: #{ob} + #{sp} != #{u}"
      end
    end
  end

  describe "notification_signups/1" do
    test "counts current pro, enterprise, and total signups" do
      pro_user = user_fixture()

      {:ok, _} =
        Speechwave.Accounts.grant_consent(pro_user, "marketing_email", source: "pricing_pro")

      enterprise_user = user_fixture()

      {:ok, _} =
        Speechwave.Accounts.grant_consent(enterprise_user, "marketing_email",
          source: "pricing_enterprise"
        )

      _login_only_user = consented_user_fixture(%{source: "login"})

      %{pro_signups: pro, enterprise_signups: enterprise, total_signups: total} =
        Stats.notification_signups()

      assert pro.current == 1
      assert enterprise.current == 1
      assert total.current == 2
    end

    test "history reflects grant/revoke state as of each day" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      user = user_fixture()
      {:ok, _} = Speechwave.Accounts.grant_consent(user, "marketing_email", source: "pricing_pro")
      backdate_consent(user, "marketing_email", granted_at: DateTime.add(now, -10, :day))

      %{pro_signups: pro} = Stats.notification_signups(now)

      five_days_ago = Date.add(DateTime.to_date(now), -5)
      fifteen_days_ago = Date.add(DateTime.to_date(now), -15)

      assert {^five_days_ago, 1} = Enum.find(pro.history, fn {d, _} -> d == five_days_ago end)

      assert {^fifteen_days_ago, 0} =
               Enum.find(pro.history, fn {d, _} -> d == fifteen_days_ago end)

      assert pro.current == 1
    end

    test "history reflects a grant followed by a revoke" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      user = user_fixture()
      {:ok, _} = Speechwave.Accounts.grant_consent(user, "marketing_email", source: "pricing_pro")
      {:ok, _} = Speechwave.Accounts.revoke_consent(user, "marketing_email")

      backdate_consent(user, "marketing_email",
        granted_at: DateTime.add(now, -20, :day),
        revoked_at: DateTime.add(now, -8, :day)
      )

      %{pro_signups: pro} = Stats.notification_signups(now)

      active_day = Date.add(DateTime.to_date(now), -15)
      inactive_day = Date.add(DateTime.to_date(now), -3)

      assert {^active_day, 1} = Enum.find(pro.history, fn {d, _} -> d == active_day end)
      assert {^inactive_day, 0} = Enum.find(pro.history, fn {d, _} -> d == inactive_day end)
      assert pro.current == 0
    end
  end

  describe "talk_activity/1" do
    test "counts talks, talks with sessions, and sessions" do
      user = user_fixture()
      talk_with_session = talk_fixture(user)
      session_fixture(talk_with_session)
      _talk_without_session = talk_fixture(user)

      %{talks: talks, talks_with_sessions: with_sessions, sessions: sessions} =
        Stats.talk_activity()

      assert talks.current == 2
      assert with_sessions.current == 1
      assert sessions.current == 1
    end

    test "talks_with_sessions history reflects when each talk got its first session" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      user = user_fixture()

      # Create a talk far in the past (60 days ago)
      talk =
        talk_fixture(user)
        |> backdate_talk(DateTime.add(now, -60, :day))

      # Give it its first session more recently (10 days ago)
      _session =
        session_fixture(talk)
        |> backdate_session(DateTime.add(now, -10, :day))

      %{talks_with_sessions: with_sessions} = Stats.talk_activity(now)

      # Before the first session (20 days ago), the talk should not be counted
      before_first_session = Date.add(DateTime.to_date(now), -20)
      after_first_session = Date.add(DateTime.to_date(now), -5)

      assert {^before_first_session, 0} =
               Enum.find(with_sessions.history, fn {d, _} -> d == before_first_session end)

      # After the first session (5 days ago), the talk should be counted
      assert {^after_first_session, 1} =
               Enum.find(with_sessions.history, fn {d, _} -> d == after_first_session end)

      # Current count should be 1
      assert with_sessions.current == 1
    end
  end

  describe "suspicious_deletions/1" do
    # The deletion log is one shared file, and DataCase tests here are not async.
    setup do
      File.rm(DeletionLog.path())
      :ok
    end

    @now ~U[2026-11-15 12:00:00Z]

    defp count_on(deletions, date) do
      {^date, count} = List.keyfind(deletions, date, 0)
      count
    end

    test "counts only :suspicious rows per UTC day, zero-filled, oldest first" do
      :ok = DeletionLog.record(1, :suspicious, ~U[2026-11-14 08:00:00Z])
      :ok = DeletionLog.record(2, :suspicious, ~U[2026-11-14 20:00:00Z])
      :ok = DeletionLog.record(3, :suspicious, ~U[2026-11-15 01:00:00Z])
      :ok = DeletionLog.record(4, :self, ~U[2026-11-14 09:00:00Z])

      {:ok, deletions} = Stats.suspicious_deletions(@now)

      assert length(deletions) == Stats.history_days()
      assert {~D[2026-10-17], _} = List.first(deletions)
      assert {~D[2026-11-15], _} = List.last(deletions)
      assert count_on(deletions, ~D[2026-11-14]) == 2
      assert count_on(deletions, ~D[2026-11-15]) == 1
      assert deletions |> Enum.map(&elem(&1, 1)) |> Enum.sum() == 3
    end

    test "ignores rows older than the window" do
      :ok = DeletionLog.record(1, :suspicious, ~U[2026-10-16 12:00:00Z])
      :ok = DeletionLog.record(2, :suspicious, ~U[2026-10-17 12:00:00Z])

      {:ok, deletions} = Stats.suspicious_deletions(@now)

      assert deletions |> Enum.map(&elem(&1, 1)) |> Enum.sum() == 1
      assert count_on(deletions, ~D[2026-10-17]) == 1
    end

    test "splits days at UTC midnight" do
      :ok = DeletionLog.record(1, :suspicious, ~U[2026-11-13 23:59:59Z])
      :ok = DeletionLog.record(2, :suspicious, ~U[2026-11-14 00:00:00Z])

      {:ok, deletions} = Stats.suspicious_deletions(@now)

      assert count_on(deletions, ~D[2026-11-13]) == 1
      assert count_on(deletions, ~D[2026-11-14]) == 1
    end

    test "counts rows whose user_id has been scrubbed" do
      :ok = DeletionLog.record(1, :suspicious, ~U[2026-11-01 10:00:00Z])
      :ok = DeletionLog.scrub(~U[2026-12-15 00:00:00Z])
      assert DeletionLog.logged_ids() == []

      {:ok, deletions} = Stats.suspicious_deletions(@now)
      assert count_on(deletions, ~D[2026-11-01]) == 1
    end

    @tag :capture_log
    test "returns {:error, :unreadable} instead of raising when the log cannot be read" do
      # Stands in for a corrupt file. A busy or locked file takes the same path:
      # the read comes back as an error, and the stats page must still load.
      File.write!(DeletionLog.path(), "this is not a sqlite database")
      on_exit(fn -> File.rm(DeletionLog.path()) end)

      assert {:error, :unreadable} = Stats.suspicious_deletions(@now)
    end

    test "returns 30 zeros and creates no file when the log is missing" do
      {:ok, deletions} = Stats.suspicious_deletions(@now)

      assert length(deletions) == 30
      assert deletions |> Enum.map(&elem(&1, 1)) |> Enum.sum() == 0
      refute File.exists?(DeletionLog.path())
    end
  end

  describe "dashboard/1" do
    test "returns all 11 metrics in a fixed order" do
      user = user_fixture()
      talk = talk_fixture(user)
      session_fixture(talk)

      dashboard = Stats.dashboard()

      assert Enum.map(dashboard, fn {key, _} -> key end) == [
               :total_users,
               :confirmed,
               :unconfirmed,
               :onboarding,
               :suspicious,
               :pro_signups,
               :enterprise_signups,
               :total_signups,
               :talks,
               :talks_with_sessions,
               :sessions
             ]

      assert {_, %{current: _, history: _}} = List.keyfind(dashboard, :talks, 0)
    end

    test "only the suspicious metric carries a deletions history" do
      dashboard = Stats.dashboard()

      {:suspicious, suspicious} = List.keyfind(dashboard, :suspicious, 0)
      assert {:ok, deletions} = suspicious.deletions
      assert length(deletions) == Stats.history_days()

      for {key, metric} <- dashboard, key != :suspicious do
        refute Map.has_key?(metric, :deletions), "#{key} should not have :deletions"
      end
    end
  end
end
