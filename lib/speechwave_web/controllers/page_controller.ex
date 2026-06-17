defmodule SpeechwaveWeb.PageController do
  use SpeechwaveWeb, :controller

  alias Speechwave.Plans

  def home(conn, _params) do
    render(conn, :home)
  end

  def pricing(conn, _params), do: render(conn, :pricing, free_limits())
  def terms(conn, _params), do: render(conn, :terms, free_limits())
  def privacy(conn, _params), do: render(conn, :privacy)

  defp free_limits do
    [
      free_participant_limit: Plans.limit(:max_participants, :free),
      free_session_limit: Plans.limit(:full_sessions_per_month, :free)
    ]
  end
end
