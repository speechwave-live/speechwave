defmodule SpeechwaveWeb.SessionAnalyticsLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.{Reactions, Talks}

  def mount(%{"id" => id} = params, _session, socket) do
    session_id =
      case Integer.parse(id) do
        {n, ""} -> n
        _ -> nil
      end

    case session_id && Talks.get_session(session_id) do
      nil ->
        {:ok, redirect(socket, to: "/dashboard")}

      session ->
        talk = Talks.get_talk!(socket.assigns.current_scope, session.talk_id)
        totals = Reactions.slide_reaction_totals(session.id)
        by_slide = group_by_slide(totals)

        other_sessions =
          Talks.list_sessions(talk.id)
          |> Enum.reject(fn %{session: s} -> s.id == session.id end)

        compare_session = resolve_compare_session(params)

        compare_totals =
          if compare_session,
            do: group_by_slide(Reactions.slide_reaction_totals(compare_session.id)),
            else: %{}

        {:ok,
         assign(socket,
           session: session,
           talk: talk,
           by_slide: by_slide,
           total_reactions: Reactions.count_reactions(session.id),
           audience_count: Reactions.count_audience(session.id),
           other_sessions: other_sessions,
           compare_session: compare_session,
           compare_by_slide: compare_totals
         )}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp resolve_compare_session(%{"other_id" => other_id}) do
    case Integer.parse(other_id) do
      {n, ""} -> Talks.get_session(n)
      _ -> nil
    end
  end

  defp resolve_compare_session(_), do: nil

  defp group_by_slide(totals) do
    totals
    |> Enum.group_by(& &1.slide_number)
    |> Map.new(fn {slide, entries} ->
      {slide, Enum.map(entries, &%{emoji: &1.emoji, count: &1.count})}
    end)
  end
end
