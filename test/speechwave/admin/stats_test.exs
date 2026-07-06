defmodule Speechwave.Admin.StatsTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures
  import Speechwave.TalksFixtures

  alias Speechwave.Admin.Stats

  describe "user_categories/1" do
    test "counts total, confirmed, and unconfirmed users" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _unconfirmed = user_fixture()

      confirmed_via_token = user_fixture()
      {_token, _user_token} = session_token_fixture(confirmed_via_token)

      confirmed_via_identity = user_fixture()
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
      {_token, user_token} = session_token_fixture(old_confirmed)
      backdate_token(user_token.id, DateTime.add(now, -40, :day))

      _recent_signup = user_fixture() |> backdate_user(DateTime.add(now, -5, :day))

      recently_confirmed = user_fixture() |> backdate_user(DateTime.add(now, -20, :day))
      {_token, user_token2} = session_token_fixture(recently_confirmed)
      backdate_token(user_token2.id, DateTime.add(now, -2, :day))

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

    test "a user confirmed via an old token isn't misreported as recently confirmed via a newer identity" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      user = user_fixture() |> backdate_user(DateTime.add(now, -70, :day))
      {_token, user_token} = session_token_fixture(user)
      backdate_token(user_token.id, DateTime.add(now, -60, :day))

      identity = identity_fixture(user)
      backdate_identity(identity.id, DateTime.add(now, -10, :day))

      %{confirmed: confirmed} = Stats.user_categories(now)

      # This user was confirmed 60 days ago (via token) — well before the
      # 30-day history window even starts — so every day in the window
      # should already count them as confirmed. If the bug were present,
      # they'd incorrectly show as unconfirmed until 10 days ago.
      fifteen_days_ago = Date.add(DateTime.to_date(now), -15)

      assert {^fifteen_days_ago, count} =
               Enum.find(confirmed.history, fn {d, _} -> d == fifteen_days_ago end)

      assert count == 1
      assert confirmed.current == 1
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

      {_token, user_token} = session_token_fixture(confirmed_recently)
      backdate_token(user_token.id, DateTime.add(now, -2, :day))

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
  end
end
