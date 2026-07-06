defmodule SpeechwaveWeb.Admin.StatsLive do
  use SpeechwaveWeb, :live_view

  import SpeechwaveWeb.AdminComponents

  alias Speechwave.Admin.Chart
  alias Speechwave.Admin.Stats

  @titles %{
    total_users: "Total Users",
    confirmed: "Confirmed Users",
    unconfirmed: "Unconfirmed Users",
    onboarding: "Onboarding Users",
    suspicious: "Suspicious Users",
    pro_signups: "Pro Notify Signups",
    enterprise_signups: "Enterprise Notify Signups",
    total_signups: "Total Notify Signups",
    talks: "Talks",
    talks_with_sessions: "Talks With Sessions",
    sessions: "Sessions"
  }

  def mount(_params, _session, socket) do
    stats =
      Enum.map(Stats.dashboard(), fn {key, stat} ->
        {key, Map.put(stat, :chart_svg, Chart.render_svg(stat.history))}
      end)

    {:ok, assign(socket, stats: stats)}
  end

  defp title_for(key), do: Map.fetch!(@titles, key)

  defp dom_id(key), do: "stat-#{key |> to_string() |> String.replace("_", "-")}"
end
