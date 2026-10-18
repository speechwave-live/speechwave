defmodule SpeechwaveWeb.TalkLive do
  use SpeechwaveWeb, :live_view

  alias Plug.Crypto.KeyGenerator
  alias Speechwave.{RateLimiter, Reactions, Talks}

  @uuid_format ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

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
         assign(socket,
           talk: talk,
           emojis: @emojis,
           session_id: socket.id,
           client_id: nil,
           current_slide: 0
         )}
    end
  end

  # The browser sends a random UUID kept in localStorage so a reload or a
  # reconnect is still counted as the same person. It is accepted once per
  # connection and only if it looks like a UUID. Rate limiting keeps using
  # `session_id`, which a client cannot choose.
  def handle_event("audience_id", %{"id" => id}, %{assigns: %{client_id: nil}} = socket)
      when is_binary(id) do
    if Regex.match?(@uuid_format, id) do
      {:noreply, assign(socket, :client_id, String.downcase(id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("audience_id", _params, socket), do: {:noreply, socket}

  def handle_event("react", %{"emoji" => emoji}, socket) do
    if RateLimiter.allow?(socket.assigns.session_id) do
      case Talks.get_active_session(socket.assigns.talk.id) do
        nil ->
          :ok

        session ->
          Reactions.create_reaction(
            session,
            emoji,
            socket.assigns.current_slide,
            audience_id(session, socket.assigns.client_id)
          )
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

  # What we store is a keyed hash of the session and the browser's UUID, never
  # the UUID itself. Reloads within a session hash to the same value, so the
  # people count works, but the same browser in another session hashes to an
  # unrelated value, so reactions cannot be linked across sessions. Reactions
  # sent before the browser's UUID arrives have no audience id (nil) and are
  # not counted as people.
  defp audience_id(_session, nil), do: nil

  defp audience_id(session, client_id) do
    key =
      KeyGenerator.generate(
        SpeechwaveWeb.Endpoint.config(:secret_key_base),
        "audience id",
        length: 32
      )

    :crypto.mac(:hmac, :sha256, key, "#{session.id}:#{client_id}")
    |> Base.encode16(case: :lower)
  end
end
