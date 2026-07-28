defmodule Speechwave.ExtensionTuningTest do
  use ExUnit.Case, async: true

  alias Speechwave.ExtensionTuning

  test "current/0 returns all expected keys with correct types" do
    tuning = ExtensionTuning.current()

    assert is_integer(tuning.default_overlay_size_percent)
    assert is_integer(tuning.min_overlay_size_percent)
    assert is_integer(tuning.overlay_margin_px)
    assert is_float(tuning.emoji_font_size_ratio)
    assert is_float(tuning.firework_font_size_ratio)
    assert is_float(tuning.firework_center_x_ratio)
    assert is_float(tuning.firework_center_y_ratio)
    assert is_float(tuning.firework_spread_min_ratio)
    assert is_float(tuning.firework_spread_range_ratio)
    assert is_float(tuning.emoji_rise_ratio)
  end

  test "min_overlay_size_percent is below default_overlay_size_percent" do
    tuning = ExtensionTuning.current()
    assert tuning.min_overlay_size_percent < tuning.default_overlay_size_percent
  end
end
