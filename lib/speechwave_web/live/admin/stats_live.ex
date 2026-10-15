defmodule SpeechwaveWeb.Admin.StatsLive do
  use SpeechwaveWeb, :live_view

  import SpeechwaveWeb.AdminComponents

  alias Speechwave.Admin.Chart
  alias Speechwave.Admin.ConsentExport
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

  # Passing `class` to <.input> replaces its defaults entirely, so this is the
  # complete styling for the export fields. color-scheme:light keeps the native
  # date picker light too.
  @export_field_class "w-full rounded-lg border border-hairline bg-white px-3 py-2 text-sm text-ink [color-scheme:light] focus:border-ink focus:outline-none"

  def mount(_params, _session, socket) do
    stats =
      Enum.map(Stats.dashboard(), fn {key, stat} ->
        {key, Map.put(stat, :chart_svg, Chart.render_svg(stat.history))}
      end)

    # The export form submits as a plain GET to ConsentExportController (no
    # phx-submit), so the browser downloads the CSV. Fields nest under "export".
    export_form = to_form(%{"source" => "", "from" => "", "to" => ""}, as: :export)

    {:ok,
     assign(socket,
       stats: stats,
       export_form: export_form,
       source_options: ConsentExport.sources(),
       field_class: @export_field_class
     )}
  end

  defp title_for(key), do: Map.fetch!(@titles, key)

  defp dom_id(key), do: "stat-#{key |> to_string() |> String.replace("_", "-")}"
end
