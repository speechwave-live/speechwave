defmodule SpeechwaveWeb.ReactionChannel do
  @moduledoc false
  # Phoenix Channel that gives the presenter's slide controller a WebSocket
  # connection authenticated by API key on join. Handles starting/stopping
  # sessions, broadcasting slide-change events to the audience topic, and
  # enforcing the monthly full-session limit.
  #
  # Audience size limits are NOT handled here (see Speechwave.AudienceSlots).
  # The only connection limit here is an account-sharing guardrail: one user
  # may have at most @max_extension_connections extension connections open at
  # the same time, across all of their talks. Each connection registers itself
  # in Phoenix Presence on the topic "presenters:<user id>". Presence removes
  # the entry automatically when the channel process exits, so we never need
  # to clean up by hand.
  use Phoenix.Channel

  alias Speechwave.Accounts
  alias Speechwave.Plans
  alias Speechwave.Talks
  alias SpeechwaveWeb.Presence

  @max_extension_connections 3

  def join("reactions:" <> slug, %{"api_key" => api_key}, socket) do
    with {:talk, %Talks.Talk{} = talk} <- {:talk, Talks.get_talk_by_slug(slug)},
         {:user, %Accounts.User{} = user} <- {:user, Accounts.get_user_by_api_key(api_key)},
         {:owner, true} <- {:owner, talk.user_id == user.id},
         {:capacity, true} <- {:capacity, under_connection_limit?(user)} do
      Phoenix.PubSub.subscribe(
        Speechwave.PubSub,
        SpeechwaveWeb.UserAuth.extension_disconnect_topic(user.id)
      )

      send(self(), :after_join)
      {:ok, join_payload(user), assign(socket, talk: talk, user: user)}
    else
      {:talk, nil} -> {:error, %{reason: "not_found"}}
      {:user, nil} -> {:error, %{reason: "unauthorized"}}
      {:owner, false} -> {:error, %{reason: "unauthorized"}}
      {:capacity, false} -> {:error, %{reason: "capacity_reached"}}
    end
  end

  def join("reactions:" <> _slug, _params, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  # Counts this user's live extension connections. This check and the later
  # Presence.track in :after_join are not atomic, so two joins that arrive at
  # the same instant can both pass. That is acceptable: the limit is a soft
  # guardrail against account sharing, not a billing boundary.
  defp under_connection_limit?(user) do
    map_size(Presence.list("presenters:#{user.id}")) < @max_extension_connections
  end

  defp join_payload(user) do
    tuning = Speechwave.ExtensionTuning.current()

    %{
      settings: %{
        overlay_size_percent: user.overlay_size_percent || tuning.default_overlay_size_percent,
        fireworks_enabled: user.fireworks_enabled
      },
      tuning: tuning
    }
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, "anon:#{inspect(self())}", %{
        joined_at: System.system_time(:second)
      })

    # Track this connection under the user's own topic too, so the join check
    # can count connections across all of the user's talks. `self()` is the
    # channel process, so each connection gets a distinct key.
    {:ok, _} =
      Presence.track(self(), "presenters:#{socket.assigns.user.id}", "conn:#{inspect(self())}", %{
        joined_at: System.system_time(:second)
      })

    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "disconnect"}, socket) do
    {:stop, :normal, socket}
  end

  def handle_in("start_session", _payload, socket) do
    talk = socket.assigns.talk
    user = socket.assigns.user
    scope = %Speechwave.Accounts.Scope{user: user}
    full_count = Talks.count_full_sessions_this_month(scope)

    case Plans.check(:full_sessions_per_month, user.plan, full_count) do
      :ok ->
        case Talks.start_session(talk) do
          {:ok, session} ->
            {:reply, {:ok, %{session_id: session.id, label: session.label}}, socket}

          {:error, _changeset} ->
            {:reply, {:error, %{reason: "failed"}}, socket}
        end

      {:error, :limit_reached} ->
        {:reply, {:error, %{reason: "session_limit_reached"}}, socket}
    end
  end

  def handle_in("stop_session", %{"session_id" => session_id}, socket) do
    case Talks.get_session(session_id) do
      nil ->
        {:reply, {:error, %{reason: "not_found"}}, socket}

      %{ended_at: ended_at} when not is_nil(ended_at) ->
        {:reply, :ok, socket}

      %{talk_id: talk_id} = session when talk_id == socket.assigns.talk.id ->
        {:ok, _} = Talks.stop_session(session)
        {:reply, :ok, socket}

      _session ->
        {:reply, {:error, %{reason: "unauthorized"}}, socket}
    end
  end

  def handle_in("slide_changed", %{"slide" => slide}, socket)
      when is_integer(slide) and slide >= 0 do
    SpeechwaveWeb.Endpoint.broadcast!(
      "slides:#{socket.assigns.talk.slug}",
      "slide_changed",
      %{slide: slide}
    )

    {:reply, :ok, socket}
  end

  def handle_in("slide_changed", _payload, socket) do
    {:reply, :ok, socket}
  end
end
