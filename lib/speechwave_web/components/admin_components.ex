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
    <div id={@id} class="rounded-2xl border border-base-300 bg-base-200 p-5">
      <div class="text-sm text-base-content/70">{@title}</div>
      <div class="mt-1 text-3xl font-semibold text-base-content">{@current}</div>
      <%!--
        Contex hard-codes black axis text and lines (a <style> block plus a stroke
        attribute on the axis paths). The style block is unlayered CSS, which beats
        Tailwind's layered utilities, hence the important (!) modifiers. The axes
        then follow the theme instead of vanishing on a dark card. The data line
        is not touched.
      --%>
      <div
        :if={@chart_svg}
        class="mt-3 text-base-content [&_text]:fill-current! [&_line]:stroke-current! [&_.exc-domain]:stroke-current"
      >
        {@chart_svg}
      </div>
    </div>
    """
  end
end
