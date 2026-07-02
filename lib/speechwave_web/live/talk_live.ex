defmodule SpeechwaveWeb.TalkLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.{RateLimiter, Reactions, Talks}

  @emojis ["❤️", "😂", "👏", "🤯", "🎉", "😮", "🎯", "🔥", "💡"]

  def mount(%{"slug" => slug}, _session, socket) do
    case Talks.get_talk_by_slug(slug) do
      nil ->
        {:ok, redirect(socket, to: "/")}

      talk ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{slug}")
          Phoenix.PubSub.subscribe(Speechwave.PubSub, "slides:#{slug}")
        end

        {:ok,
         assign(socket, talk: talk, emojis: @emojis, session_id: socket.id, current_slide: 0)}
    end
  end

  def handle_event("react", %{"emoji" => emoji}, socket) do
    if RateLimiter.allow?(socket.assigns.session_id) do
      case Talks.get_active_session(socket.assigns.talk.id) do
        nil -> :ok
        session -> Reactions.create_reaction(session, emoji, socket.assigns.current_slide)
      end

      SpeechwaveWeb.Endpoint.broadcast!(
        "reactions:#{socket.assigns.talk.slug}",
        "new_reaction",
        %{emoji: emoji}
      )
    end

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "new_reaction", payload: %{emoji: emoji}},
        socket
      ) do
    {:noreply, push_event(socket, "new_reaction", %{emoji: emoji})}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "slide_changed", payload: %{slide: slide}},
        socket
      ) do
    {:noreply, assign(socket, :current_slide, slide)}
  end
end
