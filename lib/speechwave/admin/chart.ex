defmodule Speechwave.Admin.Chart do
  @moduledoc """
  Renders a stat's 30-day history as a server-side SVG line chart via
  Contex — no JS dependency, consistent with the project's SSR-first
  LiveView style.
  """

  alias Contex.{Dataset, LinePlot, Plot, Scale, TimeScale}

  # Contex reserves a fixed ~70px margin per axis for tick labels regardless
  # of chart size, so the chart needs to be sized generously enough for real
  # date/value labels to render without crowding — see stat card layout,
  # which is single-column specifically to give charts this much room.
  @default_width 680
  @default_height 220

  # The deletions strip is much shorter than the line chart. Its plot area
  # starts at the same x (70) and leaves the same right margin (30) as the
  # line chart's, so the bars sit roughly under the days above them.
  @bar_height 90
  @plot_left 70
  @plot_right_margin 30
  @plot_top 8
  @plot_bottom_margin 22
  # Hex values mirror the --color-steel, --color-hairline and error tones in
  # assets/css/app.css; an inline SVG string cannot use Tailwind classes.
  @bar_colour "#d9534f"
  @text_colour "#5a5a5c"
  @axis_colour "#e5e5e5"

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

  @doc """
  Renders `history` (a list of `{Date.t(), non_neg_integer}`, oldest first) as
  a short SVG bar chart, one bar per day, for the deletions strip.

  Built by hand instead of with `Contex.BarChart`: Contex treats each day as a
  category and tries to label all 30 of them, which crowds a strip this short,
  and its fixed ~70px margins would not line up with the line chart above.
  Drawing the rectangles ourselves lets the strip share the line chart's plot
  margins and date scale and label only a handful of days. The y scale runs from 0 to the
  largest count (at least 1), and any non-zero day gets at least a 2px bar so
  a single deletion is visible.
  """
  def render_bar_svg(history, opts \\ []) do
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @bar_height)

    plot_width = width - @plot_left - @plot_right_margin
    plot_height = height - @plot_top - @plot_bottom_margin
    max_value = history |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end) |> max(1)

    # Use the same kind of date scale Contex builds for the line chart, over the
    # same first and last day and the same plot width. Contex widens the domain
    # to "nice" tick boundaries, so a plain even split would put each bar a day
    # or two away from its point on the line above.
    {first_date, _} = List.first(history)
    {last_date, _} = List.last(history)

    x_scale =
      TimeScale.new()
      |> TimeScale.domain(to_naive(first_date), to_naive(last_date))
      |> Scale.set_range(0, plot_width)

    x_of = fn date -> @plot_left + Scale.domain_to_range(x_scale, to_naive(date)) end
    day_width = x_of.(Date.add(first_date, 1)) - x_of.(first_date)
    bar_width = day_width * 0.6

    bars =
      Enum.map(history, fn {date, value} ->
        bar_h = if value > 0, do: max(value / max_value * plot_height, 2), else: 0
        x = x_of.(date) - bar_width / 2
        y = @plot_top + plot_height - bar_h

        ~s(<rect x="#{fmt(x)}" y="#{fmt(y)}" width="#{fmt(bar_width)}" ) <>
          ~s(height="#{fmt(bar_h)}" fill="#{@bar_colour}"/>)
      end)

    # Label the same tick days, with the same text, as the line chart's x axis:
    # both come from an identical TimeScale, so a bar can be matched to the line
    # above by its label.
    labels =
      x_scale
      |> Scale.ticks_domain()
      |> Enum.map(fn tick ->
        x = @plot_left + Scale.domain_to_range(x_scale, tick)

        ~s(<text x="#{fmt(x)}" y="#{height - 6}" text-anchor="middle" font-size="10" ) <>
          ~s(fill="#{@text_colour}">#{Scale.get_formatted_tick(x_scale, tick)}</text>)
      end)

    baseline_y = @plot_top + plot_height

    svg =
      [
        ~s(<svg xmlns="http://www.w3.org/2000/svg" class="chart" viewBox="0 0 #{width} #{height}" role="img" aria-label="Suspicious users deleted per day">),
        ~s(<line x1="#{@plot_left}" x2="#{width - @plot_right_margin}" y1="#{baseline_y}" y2="#{baseline_y}" stroke="#{@axis_colour}"/>),
        ~s(<text x="#{@plot_left - 9}" y="#{@plot_top + 4}" text-anchor="end" font-size="10" fill="#{@text_colour}">#{max_value}</text>),
        ~s(<text x="#{@plot_left - 9}" y="#{baseline_y + 3}" text-anchor="end" font-size="10" fill="#{@text_colour}">0</text>),
        bars,
        labels,
        "</svg>"
      ]
      |> IO.iodata_to_binary()

    # Safe to mark as HTML: everything interpolated above is a number or a
    # date formatted by Calendar.strftime/2, never user input.
    Phoenix.HTML.raw(svg)
  end

  defp to_naive(date), do: NaiveDateTime.new!(date, ~T[00:00:00])

  defp fmt(number), do: :erlang.float_to_binary(number / 1, decimals: 1)
end
