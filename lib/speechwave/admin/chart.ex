defmodule Speechwave.Admin.Chart do
  @moduledoc """
  Renders a stat's 30-day history as a server-side SVG line chart via
  Contex — no JS dependency, consistent with the project's SSR-first
  LiveView style.
  """

  alias Contex.{Dataset, LinePlot, Plot}

  @doc "Renders `history` (a list of `{Date.t(), integer}`, oldest first) as an SVG line chart."
  def render_svg(history, opts \\ []) do
    width = Keyword.get(opts, :width, 240)
    height = Keyword.get(opts, :height, 60)

    data =
      Enum.map(history, fn {date, count} ->
        {NaiveDateTime.new!(date, ~T[00:00:00]), count}
      end)

    dataset = Dataset.new(data, [:date, :count])

    dataset
    |> Plot.new(LinePlot, width, height, mapping: %{x_col: :date, y_cols: [:count]})
    |> Plot.to_svg()
  end
end
