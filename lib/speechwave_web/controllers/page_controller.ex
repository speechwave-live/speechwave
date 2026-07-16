defmodule SpeechwaveWeb.PageController do
  use SpeechwaveWeb, :controller

  alias Speechwave.Plans

  def home(conn, _params) do
    render(conn, :home)
  end

  @doc "Liveness probe for Fly.io's http_service health check — no DB access, just confirms Bandit is serving requests."
  def health(conn, _params) do
    text(conn, "ok")
  end

  def terms(conn, _params) do
    render(
      conn,
      :terms,
      Keyword.merge(free_limits(),
        page_title: "Terms of Service · Speechwave",
        page_description: "Speechwave's terms of service."
      )
    )
  end

  def privacy(conn, _params) do
    render(conn, :privacy,
      page_title: "Privacy Policy · Speechwave",
      page_description: "How Speechwave collects, uses, and protects your data."
    )
  end

  defp free_limits do
    [
      free_participant_limit: Plans.limit(:max_participants, :free),
      free_session_limit: Plans.limit(:full_sessions_per_month, :free)
    ]
  end
end
