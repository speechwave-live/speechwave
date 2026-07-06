defmodule Speechwave.Admin.ChartTest do
  use ExUnit.Case, async: true

  alias Speechwave.Admin.Chart

  test "renders a 30-day history as an SVG line chart" do
    history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), 30 - i}

    svg = Chart.render_svg(history)
    html = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    assert html =~ "<svg"
  end

  test "renders a flat history (all-zero counts) without raising" do
    history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), 0}

    svg = Chart.render_svg(history)
    html = svg |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    assert html =~ "<svg"
  end

  test "renders different SVG output for different history data" do
    history_a = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), i}
    history_b = for i <- 29..0//-1, do: {Date.add(~D[2020-01-01], -i), 100 - i}

    svg_a = Chart.render_svg(history_a) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    svg_b = Chart.render_svg(history_b) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

    refute svg_a == svg_b
  end
end
