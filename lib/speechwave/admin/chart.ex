defmodule Speechwave.Admin.Chart do
  @moduledoc """
  Renders a stat's 30-day history as a server-side SVG line chart via
  Contex — no JS dependency, consistent with the project's SSR-first
  LiveView style.
  """

  alias Contex.{Dataset, LinePlot, Plot}

  # Contex reserves a fixed ~70px margin per axis for tick labels regardless
  # of chart size, so the chart needs to be sized generously enough for real
  # date/value labels to render without crowding — see stat card layout,
  # which is single-column specifically to give charts this much room.
  @default_width 680
  @default_height 220

  @doc "Renders `history` (a list of `{Date.t(), integer}`, oldest first) as an SVG line chart."
  def render_svg(history, opts \\ []) do
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)

    data =
      Enum.map(history, fn {date, count} ->
        {NaiveDateTime.new!(date, ~T[00:00:00]), count}
      end)

    dataset = Dataset.new(data, ["date", "count"])

    dataset
    |> Plot.new(LinePlot, width, height, mapping: %{x_col: "date", y_cols: ["count"]})
    # The last x-axis tick label is centered on its tick mark, so it needs
    # room to extend past the right edge of the plot area — Contex's default
    # right margin (10px) clips it (e.g. "10 Jul" truncates to "10 Ju").
    |> Plot.plot_options(%{right_margin: 30})
    |> Plot.to_svg()
  end
end
