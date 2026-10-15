defmodule SpeechwaveWeb.AdminComponents do
  @moduledoc """
  Function components for the super-admin stats dashboard.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :current, :integer, required: true
  attr :chart_svg, :any, default: nil

  def admin_stat_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-2xl border border-hairline bg-surface p-5">
      <div class="text-sm text-steel">{@title}</div>
      <div class="mt-1 text-3xl font-semibold text-ink">{@current}</div>
      <div :if={@chart_svg} class="mt-3">{@chart_svg}</div>
    </div>
    """
  end
end
