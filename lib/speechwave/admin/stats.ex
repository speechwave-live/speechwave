defmodule Speechwave.Admin.Stats do
  @moduledoc """
  Aggregate queries for the super-admin stats dashboard
  (docs/specs/2026-07-06-super-admin-stats-design.md).

  Each metric is `%{current: integer, history: [{Date.t(), integer}]}`.
  `history` covers the last `@history_days` days, oldest first; each day's
  count reflects state as of 23:59:59 UTC that day, and `current` is always
  the same value as the last entry of `history` (state as of "now", which
  falls within today's bucket since no future rows can exist in the DB).

  History is reconstructed by walking backward from a current aggregate
  total using only rows that changed within the history window — never a
  full scan of all-time data. See the design doc for why this is valid
  (state transitions tracked here — signup, confirmation, consent,
  talk/session creation — are monotonic or single-event within the window).
  """

  import Ecto.Query

  alias Speechwave.Repo
  alias Speechwave.Accounts.{User, UserToken, UserIdentity, UserConsent}

  @history_days 30
  @onboarding_threshold_days 3

  @doc "Number of days of history returned by each metric's `history` list."
  def history_days, do: @history_days

  @doc "Account age (in days) below which an unconfirmed user is 'onboarding' rather than 'suspicious'."
  def onboarding_threshold_days, do: @onboarding_threshold_days

  @doc "Total, confirmed, unconfirmed, onboarding, and suspicious user counts, current and 30-day history."
  def user_categories(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    cutoff = DateTime.add(now, -@history_days, :day)
    days = last_n_days(now, @history_days)

    total_current = Repo.aggregate(User, :count)
    confirmed_current = Repo.aggregate(confirmed_users_query(), :count)

    recent_signups = Repo.all(from(u in User, where: u.inserted_at >= ^cutoff, select: u.inserted_at))
    recent_confirmations = recent_confirmation_timestamps(cutoff)
    recent_confirmers = recent_confirmers(recent_confirmations)
    unconfirmed_now = Repo.all(from(u in unconfirmed_users_query(), select: u.inserted_at))

    total_history = history_from_baseline(total_current, recent_signups, days)
    confirmed_history = history_from_baseline(confirmed_current, Map.values(recent_confirmations), days)

    unconfirmed_history =
      Enum.zip_with(total_history, confirmed_history, fn {date, t}, {_date, c} -> {date, t - c} end)

    {onboarding_history, suspicious_history} =
      age_split_history(unconfirmed_now, recent_confirmers, days)

    %{
      total_users: metric(total_history),
      confirmed: metric(confirmed_history),
      unconfirmed: metric(unconfirmed_history),
      onboarding: metric(onboarding_history),
      suspicious: metric(suspicious_history)
    }
  end

  @doc "Pro, enterprise, and total marketing-email notification signup counts, current and 30-day history."
  def notification_signups(now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)
    cutoff = DateTime.add(now, -@history_days, :day)
    days = last_n_days(now, @history_days)

    pro_history = consent_history(days, cutoff, "pricing_pro")
    enterprise_history = consent_history(days, cutoff, "pricing_enterprise")

    total_history =
      Enum.zip_with(pro_history, enterprise_history, fn {date, p}, {_date, e} -> {date, p + e} end)

    %{
      pro_signups: metric(pro_history),
      enterprise_signups: metric(enterprise_history),
      total_signups: metric(total_history)
    }
  end

  defp consent_history(days, cutoff, source) do
    current_total =
      Repo.aggregate(
        from(c in UserConsent,
          where: c.consent_type == "marketing_email" and c.source == ^source and c.granted == true
        ),
        :count
      )

    recent_changes =
      Repo.all(
        from c in UserConsent,
          where:
            c.consent_type == "marketing_email" and c.source == ^source and
              ((not is_nil(c.granted_at) and c.granted_at >= ^cutoff) or
                 (not is_nil(c.revoked_at) and c.revoked_at >= ^cutoff)),
          select: {c.granted, c.granted_at, c.revoked_at}
      )

    Enum.map(days, fn day ->
      day_cutoff = day_end(day)

      adjustment =
        Enum.reduce(recent_changes, 0, fn {granted, granted_at, revoked_at}, acc ->
          active_then = consent_active_as_of?(granted_at, revoked_at, day_cutoff)

          cond do
            granted and not active_then -> acc - 1
            not granted and active_then -> acc + 1
            true -> acc
          end
        end)

      {day, current_total + adjustment}
    end)
  end

  # Reconstructs whether a consent row was active as of `day_cutoff`, based on
  # its most recent grant/revoke cycle only. `grant_consent/3`/`revoke_consent/2`
  # overwrite `granted_at`/`revoked_at` on each cycle rather than keeping full
  # history, so a user who has toggled consent more than once within the
  # history window can have earlier cycles undercounted. Acceptable for a
  # traction-tracking dashboard — this isn't an audit log.
  defp consent_active_as_of?(granted_at, revoked_at, day_cutoff) do
    not is_nil(granted_at) and DateTime.compare(granted_at, day_cutoff) != :gt and
      (is_nil(revoked_at) or DateTime.compare(revoked_at, day_cutoff) == :gt)
  end

  defp confirmed_users_query do
    from u in User,
      as: :user,
      where:
        exists(
          from t in UserToken,
            where: t.user_id == parent_as(:user).id and t.context == "session",
            select: 1
        ) or
          exists(
            from i in UserIdentity,
              where: i.user_id == parent_as(:user).id,
              select: 1
          )
  end

  defp unconfirmed_users_query do
    from u in User,
      as: :user,
      where:
        not exists(
          from t in UserToken,
            where: t.user_id == parent_as(:user).id and t.context == "session",
            select: 1
        ),
      where:
        not exists(
          from i in UserIdentity,
            where: i.user_id == parent_as(:user).id,
            select: 1
        )
  end

  # Returns %{user_id => confirmed_at} for users whose earliest confirmation
  # (first session token OR first identity, whichever is earlier) falls
  # within the last `@history_days` days. Users confirmed earlier than that
  # don't need to appear here — they were already confirmed at the start of
  # the history window and are fully accounted for by `confirmed_current`.
  #
  # Two-phase because a user with e.g. an old session token (outside the
  # window) and a newer identity (inside the window) must NOT be reported
  # using just the newer timestamp — their true confirmed_at is the older
  # one, which means they don't belong in this map at all. Phase 1 finds
  # candidates where *either* channel shows recent activity (bounded: only
  # users with something confirmation-related in the last 30 days). Phase 2
  # recomputes each candidate's TRUE earliest timestamp across ALL their
  # tokens/identities (still bounded — scoped to the small candidate set)
  # before applying the recency cutoff for real.
  defp recent_confirmation_timestamps(cutoff) do
    candidate_ids =
      (Repo.all(
         from t in UserToken,
           where: t.context == "session",
           group_by: t.user_id,
           having: min(t.inserted_at) >= ^cutoff,
           select: t.user_id
       ) ++
         Repo.all(
           from i in UserIdentity,
             group_by: i.user_id,
             having: min(i.inserted_at) >= ^cutoff,
             select: i.user_id
         ))
      |> Enum.uniq()

    token_mins =
      Repo.all(
        from t in UserToken,
          where: t.context == "session" and t.user_id in ^candidate_ids,
          group_by: t.user_id,
          select: {t.user_id, min(t.inserted_at)}
      )
      |> Map.new()

    identity_mins =
      Repo.all(
        from i in UserIdentity,
          where: i.user_id in ^candidate_ids,
          group_by: i.user_id,
          select: {i.user_id, min(i.inserted_at)}
      )
      |> Map.new()

    candidate_ids
    |> Map.new(fn user_id ->
      true_min =
        [Map.get(token_mins, user_id), Map.get(identity_mins, user_id)]
        |> Enum.reject(&is_nil/1)
        |> Enum.min(DateTime)

      {user_id, true_min}
    end)
    |> Enum.filter(fn {_user_id, ts} -> DateTime.compare(ts, cutoff) != :lt end)
    |> Map.new()
  end

  # Fetches inserted_at for users who confirmed within the history window, so
  # `age_split_history/3` can determine what age bucket they were in on days
  # before they confirmed.
  defp recent_confirmers(recent_confirmations) do
    user_ids = Map.keys(recent_confirmations)

    inserted_ats =
      Repo.all(from(u in User, where: u.id in ^user_ids, select: {u.id, u.inserted_at}))
      |> Map.new()

    Enum.map(recent_confirmations, fn {user_id, confirmed_at} ->
      %{inserted_at: Map.fetch!(inserted_ats, user_id), confirmed_at: confirmed_at}
    end)
  end

  # For each day, the "still unconfirmed as of that day" population is:
  #   - users who are unconfirmed today, who already existed by that day, plus
  #   - users who confirmed later (within the window) but hadn't yet as of that day.
  # This exactly reconstructs the unconfirmed set for any day in the window
  # without needing to touch the full users table (see stats_test.exs for the
  # invariant this maintains: onboarding + suspicious == unconfirmed, every day).
  defp age_split_history(unconfirmed_now, recent_confirmers, days) do
    Enum.map(days, fn day ->
      day_cutoff = day_end(day)

      still_unconfirmed =
        Enum.filter(unconfirmed_now, &(DateTime.compare(&1, day_cutoff) != :gt))

      not_yet_confirmed =
        recent_confirmers
        |> Enum.filter(fn %{inserted_at: ia, confirmed_at: ca} ->
          DateTime.compare(ia, day_cutoff) != :gt and DateTime.compare(ca, day_cutoff) == :gt
        end)
        |> Enum.map(& &1.inserted_at)

      ages = still_unconfirmed ++ not_yet_confirmed

      onboarding_count =
        Enum.count(ages, &(DateTime.diff(day_cutoff, &1, :day) < @onboarding_threshold_days))

      {{day, onboarding_count}, {day, length(ages) - onboarding_count}}
    end)
    |> Enum.unzip()
  end

  # Reconstructs a daily history by subtracting, from `current_total`, the
  # count of `recent_event_timestamps` that happened after each day's end.
  defp history_from_baseline(current_total, recent_event_timestamps, days) do
    Enum.map(days, fn day ->
      day_cutoff = day_end(day)
      count_after = Enum.count(recent_event_timestamps, &(DateTime.compare(&1, day_cutoff) == :gt))
      {day, current_total - count_after}
    end)
  end

  defp metric(history) do
    {_date, current} = List.last(history)
    %{current: current, history: history}
  end

  defp last_n_days(now, n) do
    today = DateTime.to_date(now)
    for offset <- (n - 1)..0//-1, do: Date.add(today, -offset)
  end

  defp day_end(date), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
end
