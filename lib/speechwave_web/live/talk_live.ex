defmodule SpeechwaveWeb.TalkLive do
  use SpeechwaveWeb, :live_view

  alias Plug.Crypto.KeyGenerator
  alias Speechwave.{AudienceSlots, Plans, RateLimiter, Reactions, Talks}

  @uuid_format ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  @emojis ["❤️", "😂", "👏", "🤯", "🎉", "😮", "🎯", "🔥", "💡"]

  # A place in the audience (`slot`) is what entitles a visitor to the
  # reaction stream and to react. It moves through three states:
  #
  #   * `:pending` - a limited (free) plan, waiting for the browser's audience
  #     id. Nothing is subscribed yet, so the visitor receives nothing.
  #   * `:held` - the visitor has a place: subscribed and allowed to react.
  #     Unlimited plans start here and never touch AudienceSlots.
  #   * `:full` - the talk was full when the id arrived. The page shows the
  #     "This talk is full" panel instead of the reaction UI.
  def mount(%{"slug" => slug}, _session, socket) do
    case Talks.get_talk_with_owner(slug) do
      nil ->
        {:ok, redirect(socket, to: "/")}

      talk ->
        limit = Plans.limit(:max_participants, talk.user.plan)
        slot = if limit == :unlimited, do: :held, else: :pending

        if slot == :held and connected?(socket), do: subscribe(talk)

        {:ok,
         assign(socket,
           talk: talk,
           participant_limit: limit,
           slot: slot,
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
  #
  # The same event claims the visitor's place on a limited plan, once per
  # LiveView process. The place is keyed by a hash of the UUID so two tabs or
  # a reconnect share one place. A missing or malformed id still claims, keyed
  # by a hash of `socket.id`, so the visitor holds exactly one place rather
  # than being stuck in `:pending`.
  def handle_event("audience_id", params, socket) do
    socket =
      socket
      |> put_client_id(params)
      |> claim_place()

    {:noreply, socket}
  end

  def handle_event("react", _params, %{assigns: %{slot: slot}} = socket) when slot != :held,
    do: {:noreply, socket}

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

  defp put_client_id(%{assigns: %{client_id: nil}} = socket, %{"id" => id})
       when is_binary(id) do
    if Regex.match?(@uuid_format, id),
      do: assign(socket, :client_id, String.downcase(id)),
      else: socket
  end

  defp put_client_id(socket, _params), do: socket

  defp claim_place(%{assigns: %{slot: :pending, talk: talk}} = socket) do
    key = place_key(socket.assigns.client_id || socket.id)

    case AudienceSlots.claim(talk.id, socket.assigns.participant_limit, key, self()) do
      :ok ->
        subscribe(talk)
        assign(socket, :slot, :held)

      {:error, :full} ->
        # Only the first turn-away of a session is stored. Once the time is
        # set, later turn-aways skip the write entirely.
        session = Talks.get_active_session(talk.id)

        if session && is_nil(session.participant_limit_hit_at),
          do: Talks.record_participant_limit_hit(session)

        assign(socket, :slot, :full)
    end
  end

  defp claim_place(socket), do: socket

  # AudienceSlots only needs a stable key per person, not the id itself, so
  # it gets a SHA-256 of it. The raw id then never reaches the server's
  # state, its call messages or a crash report. The same id always hashes to
  # the same key, so two tabs and reconnects still share one place.
  defp place_key(id), do: :crypto.hash(:sha256, id) |> Base.encode16(case: :lower)

  defp subscribe(talk) do
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "reactions:#{talk.slug}")
    Phoenix.PubSub.subscribe(Speechwave.PubSub, "slides:#{talk.slug}")
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
