defmodule Speechwave.Admin.ChartTest do
  use ExUnit.Case, async: true

  alias Phoenix.HTML.Safe
  alias Speechwave.Admin.Chart

  test "renders a 30-day history as an SVG line chart" do
    history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), 30 - i}

    svg = Chart.render_svg(history)
    html = svg |> Safe.to_iodata() |> IO.iodata_to_binary()

    assert html =~ "<svg"
  end

  test "renders a flat history (all-zero counts) without raising" do
    history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), 0}

    svg = Chart.render_svg(history)
    html = svg |> Safe.to_iodata() |> IO.iodata_to_binary()

    assert html =~ "<svg"
  end

  test "renders different SVG output for different history data" do
    history_a = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), i}
    history_b = for i <- 29..0//-1, do: {Date.add(~D[2020-01-01], -i), 100 - i}

    svg_a = Chart.render_svg(history_a) |> Safe.to_iodata() |> IO.iodata_to_binary()
    svg_b = Chart.render_svg(history_b) |> Safe.to_iodata() |> IO.iodata_to_binary()

    refute svg_a == svg_b
  end

  test "renders real axis tick labels (dates and values) at the default size" do
    history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), 30 - i}

    html = Chart.render_svg(history) |> Safe.to_iodata() |> IO.iodata_to_binary()

    # The default size is deliberately generous (see @default_width/@default_height)
    # so Contex's ~70px-per-axis tick-label margin has room to render real,
    # non-overlapping date and value labels rather than a bare sparkline.
    assert html =~ "exc-tick"
  end

  describe "render_bar_svg/2" do
    defp svg_string(svg), do: svg |> Safe.to_iodata() |> IO.iodata_to_binary()

    defp svg_height(html) do
      [_, height] = Regex.run(~r/<svg[^>]*\sviewBox="0 0 [\d.]+ ([\d.]+)"/, html)
      {height, _rest} = Float.parse(height)
      height
    end

    test "renders a 30-day history as an SVG" do
      history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), rem(i, 3)}

      assert Chart.render_bar_svg(history) |> svg_string() =~ "<svg"
    end

    test "renders a history with a single non-zero day without raising" do
      history =
        for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), if(i == 5, do: 1, else: 0)}

      assert Chart.render_bar_svg(history) |> svg_string() =~ "<svg"
    end

    test "renders different SVG output for different data" do
      a = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), rem(i, 3)}
      b = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), rem(i, 4)}

      refute svg_string(Chart.render_bar_svg(a)) == svg_string(Chart.render_bar_svg(b))
    end

    test "is shorter than the line chart" do
      history = for i <- 29..0//-1, do: {Date.add(Date.utc_today(), -i), rem(i, 3)}

      bar_height = history |> Chart.render_bar_svg() |> svg_string() |> svg_height()
      line_height = history |> Chart.render_svg() |> svg_string() |> svg_height()

      assert bar_height < line_height
    end
  end
end
