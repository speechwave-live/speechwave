defmodule Speechwave.Admin.StatsTest do
  use Speechwave.DataCase

  import Speechwave.AccountsFixtures

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
      {^ten_days_ago, total_10d_ago} = Enum.find(total.history, fn {d, _} -> d == ten_days_ago end)
      {^ten_days_ago, confirmed_10d_ago} = Enum.find(confirmed.history, fn {d, _} -> d == ten_days_ago end)

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
      assert {^fifteen_days_ago, count} = Enum.find(confirmed.history, fn {d, _} -> d == fifteen_days_ago end)
      assert count == 1
      assert confirmed.current == 1
    end
  end
end
