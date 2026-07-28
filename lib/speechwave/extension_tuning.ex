defmodule Speechwave.ExtensionTuning do
  @moduledoc """
  Tuning constants for the Chrome extension's emoji-overlay rendering,
  delivered to the extension via the reactions channel join reply instead
  of being hardcoded in the extension itself. Change these values and
  redeploy (or, locally, let the code reloader pick up the change) to
  adjust overlay/animation behavior without a new extension version.

  Deliberately a plain module, not a database-backed config with an admin
  UI — see docs/specs/2026-07-27-overlay-size-and-remote-config-design.md
  for why that was considered and rejected.
  """

  def current do
    %{
      default_overlay_size_percent: 20,
      min_overlay_size_percent: 10,
      overlay_margin_px: 8,
      emoji_font_size_ratio: 0.14,
      firework_font_size_ratio: 0.12,
      firework_center_x_ratio: 0.5,
      firework_center_y_ratio: 0.5,
      firework_spread_min_ratio: 0.375,
      firework_spread_range_ratio: 0.25,
      emoji_rise_ratio: 0.3
    }
  end
end
