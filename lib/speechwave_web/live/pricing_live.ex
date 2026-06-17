defmodule SpeechwaveWeb.PricingLive do
  use SpeechwaveWeb, :live_view

  alias Speechwave.{Accounts, Plans}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} full_width={true}>
      <div class="pt-8 pb-24 min-h-screen bg-surface">
        <div class="max-w-5xl mx-auto px-6">
          <%!-- Header --%>
          <div class="text-center pt-14 mb-16">
            <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">Pricing</p>
            <h1 class="text-4xl sm:text-5xl font-semibold text-ink tracking-tight mb-4">
              Simple, transparent pricing
            </h1>
            <p class="text-steel max-w-xs mx-auto text-sm leading-relaxed">
              Start free. Upgrade when you need more.
            </p>
          </div>

          <%!-- Pricing cards --%>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-5 items-start">
            <%!-- Free --%>
            <div class="bg-canvas rounded-xl border border-hairline p-8">
              <div class="mb-6">
                <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">Free</p>
                <div class="flex items-baseline gap-1 mb-1.5">
                  <span class="text-[40px] font-semibold text-ink tracking-tight leading-none">$0</span>
                  <span class="text-sm text-steel">/month</span>
                </div>
                <p class="text-sm text-steel">No credit card required.</p>
              </div>
              <a
                href={~p"/users/log-in"}
                class="block w-full text-center py-2.5 px-4 bg-ink text-canvas rounded-full text-sm font-medium hover:bg-charcoal transition-colors mb-8"
              >
                Get started free
              </a>
              <ul class="space-y-3">
                <%= for feature <- [
                  "Live emoji reactions",
                  "Session analytics",
                  "Fireworks mode",
                  "Single user",
                  "Up to #{@free_participant_limit} participants per talk",
                  "#{@free_session_limit} full talk sessions per month†",
                  "QR code sharing",
                  "Browser extension",
                  "Google Slides with per-slide analytics",
                  "Anything browser-based without per-slide analytics"
                ] do %>
                  <li class="flex items-center gap-2.5 text-sm text-ink">
                    <.icon name="hero-check" class="size-4 text-mint shrink-0" />
                    {feature}
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- Pro (featured, coming soon) --%>
            <div class="bg-canvas rounded-xl border-2 border-mint shadow-[rgba(0,212,164,0.08)_0px_8px_24px] p-8 relative">
              <div class="absolute -top-3.5 left-6">
                <span class="px-2.5 py-1 bg-mint text-ink text-xs font-semibold rounded-full">
                  Coming soon
                </span>
              </div>
              <div class="mb-6">
                <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">Pro</p>
                <div class="flex items-baseline gap-1 mb-1.5">
                  <span class="text-[40px] font-semibold text-ink tracking-tight leading-none">$9</span>
                  <span class="text-sm text-steel">/month (introductory offer)</span>
                </div>
                <p class="text-sm text-steel">Launching soon.</p>
              </div>
              <button
                id="notify-pro-btn"
                phx-click="open_notify_modal"
                phx-value-plan="pro"
                class="block w-full text-center py-2.5 px-4 bg-ink text-canvas rounded-full text-sm font-medium hover:bg-charcoal transition-colors mb-8"
              >
                Notify me
              </button>
              <ul class="space-y-3">
                <%= for feature <- [
                  "Everything in Free",
                  "Unlimited participants",
                  "Unlimited sessions",
                  "Data export",
                  "Customize emoji set",
                  "PowerPoint plugin",
                  "Keynote plugin"
                ] do %>
                  <li class="flex items-center gap-2.5 text-sm text-muted">
                    <.icon name="hero-check" class="size-4 text-mint-soft shrink-0" />
                    {feature}
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- Enterprise --%>
            <div class="bg-canvas rounded-xl border border-hairline p-8 opacity-60">
              <div class="mb-6">
                <p class="text-[11px] font-semibold text-steel uppercase tracking-[0.5px] mb-3">
                  Enterprise
                </p>
                <div class="flex items-baseline gap-1 mb-1.5">
                  <span class="text-[40px] font-semibold text-muted tracking-tight leading-none">
                    —
                  </span>
                </div>
                <p class="text-sm text-muted">Launches after Pro.</p>
              </div>
              <button
                id="notify-enterprise-btn"
                phx-click="open_notify_modal"
                phx-value-plan="enterprise"
                class="block w-full text-center py-2.5 px-4 bg-surface text-muted rounded-full text-sm font-medium hover:bg-hairline transition-colors mb-8"
              >
                Notify me
              </button>
              <ul class="space-y-3">
                <%= for feature <- [
                  "Everything in Pro",
                  "Priority support",
                  "Team pricing",
                  "Conference pricing",
                  "Organization analytics",
                  "Custom integrations"
                ] do %>
                  <li class="flex items-center gap-2.5 text-sm text-muted">
                    <.icon name="hero-check" class="size-4 text-muted shrink-0" />
                    {feature}
                  </li>
                <% end %>
              </ul>
            </div>
          </div>

          <p class="text-center text-xs text-muted mt-10">
            †A "full session" is a session lasting longer than 10 minutes.
          </p>
        </div>
      </div>

      <%!-- Notify Me Modal --%>
      <%= if @show_modal do %>
        <div
          id="notify-modal-overlay"
          class="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4"
        >
          <div id="notify-modal" class="bg-canvas rounded-2xl shadow-2xl w-full max-w-md p-8">
            <%= if @notify_sent do %>
              <div id="notify-sent-message" class="text-center space-y-3">
                <p class="text-lg font-semibold text-ink">Check your inbox!</p>
                <p class="text-sm text-steel leading-relaxed">
                  We sent a link to <strong>{@notify_email}</strong>. Click it to confirm your spot on the list.
                </p>
                <button
                  id="notify-close-btn"
                  phx-click="close_modal"
                  class="text-sm text-steel underline mt-2"
                >
                  Close
                </button>
              </div>
            <% else %>
              <div class="space-y-5">
                <div>
                  <h2 class="text-xl font-semibold text-ink mb-2">
                    Get notified when {String.capitalize(@show_modal)} launches
                  </h2>
                  <p class="text-sm text-steel leading-relaxed">
                    We'll let you know the moment it's ready — and keep you in the loop on product
                    updates. No spam, no selling your email.
                  </p>
                </div>
                <form id="notify-form" phx-submit="submit_notify" class="space-y-3">
                  <input
                    id="notify-email-input"
                    type="email"
                    name="email"
                    placeholder="you@example.com"
                    required
                    autocomplete="email"
                    class="w-full px-4 py-2.5 rounded-lg border border-hairline bg-surface text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-mint focus:border-transparent"
                  />
                  <button
                    type="submit"
                    class="w-full py-2.5 px-4 bg-ink text-canvas rounded-full text-sm font-medium hover:bg-charcoal transition-colors"
                  >
                    Notify me →
                  </button>
                </form>
                <button
                  id="notify-cancel-btn"
                  phx-click="close_modal"
                  class="w-full text-center text-xs text-muted hover:text-steel transition-colors"
                >
                  Cancel
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       free_participant_limit: Plans.limit(:max_participants, :free),
       free_session_limit: Plans.limit(:full_sessions_per_month, :free),
       show_modal: nil,
       notify_sent: false,
       notify_email: ""
     )}
  end

  @impl true
  def handle_event("open_notify_modal", %{"plan" => plan}, socket) do
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    cond do
      user && Accounts.consented?(user, "marketing_email") ->
        {:noreply, put_flash(socket, :info, "You're already on the list!")}

      user ->
        case Accounts.grant_consent(user, "marketing_email", source: "pricing_#{plan}") do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "You're on the list! We'll keep you posted.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
        end

      true ->
        {:noreply, assign(socket, show_modal: plan, notify_sent: false, notify_email: "")}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, show_modal: nil, notify_sent: false, notify_email: "")}
  end

  def handle_event("submit_notify", %{"email" => email}, socket) do
    plan = socket.assigns.show_modal || "unknown"
    email = email |> String.trim() |> String.downcase()
    url_fun = &(url(~p"/users/magic_link/#{&1}") <> "?" <> URI.encode_query(%{"updates" => "true", "notify" => plan}))

    case Accounts.register_or_get_user_by_email(email) do
      {:ok, user} -> Accounts.deliver_login_instructions(user, url_fun)
      {:error, _} -> nil
    end

    {:noreply, assign(socket, notify_sent: true, notify_email: email)}
  end
end
