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

  def mount(_params, _session, socket) do
    stats =
      Enum.map(Stats.dashboard(), fn {key, stat} ->
        stat = Map.put(stat, :chart_svg, Chart.render_svg(stat.history))
        {key, with_deletions_strip(stat)}
      end)

    # The export form submits as a plain GET to ConsentExportController (no
    # phx-submit), so the browser downloads the CSV. Fields nest under "export".
    # Default range is the last month; "Any time" ignores it. Dates are UTC to
    # match how consent timestamps are stored.
    today = Date.utc_today()

    export_form =
      to_form(
        %{
          "source" => "",
          "from" => Date.to_iso8601(Date.shift(today, month: -1)),
          "to" => Date.to_iso8601(today)
        },
        as: :export
      )

    {:ok,
     assign(socket,
       stats: stats,
       export_form: export_form,
       source_options: ConsentExport.sources(),
       any_time: false
     )}
  end

  # Keeps the any-time checkbox in step so the date fields can be disabled.
  # Disabled inputs aren't submitted, so merge into the existing params to keep
  # the dates when the box is unchecked again.
  def handle_event("export_changed", %{"export" => params}, socket) do
    merged = Map.merge(socket.assigns.export_form.params, params)

    {:noreply,
     assign(socket,
       export_form: to_form(merged, as: :export),
       any_time: params["any_time"] == "true"
     )}
  end

  # Only the Suspicious Users stat carries `:deletions`. The strip is shown only
  # when the reaper deleted someone in the window, so the card is unchanged
  # until then.
  defp with_deletions_strip(%{deletions: deletions} = stat) do
    total = deletions |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total > 0 do
      stat
      |> Map.put(:strip_svg, Chart.render_bar_svg(deletions))
      |> Map.put(:strip_label, "Deleted by the reaper, per day. #{total} in the last 30 days.")
    else
      stat
    end
  end

  defp with_deletions_strip(stat), do: stat

  defp title_for(key), do: Map.fetch!(@titles, key)

  defp dom_id(key), do: "stat-#{key |> to_string() |> String.replace("_", "-")}"
end
