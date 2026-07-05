defmodule SpeechwaveWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SpeechwaveWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :full_width, :boolean,
    default: false,
    doc:
      "when true, skips the max-w-2xl wrapper — for marketing pages that handle their own width"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= if @current_scope do %>
      <header class="fixed top-0 left-0 right-0 z-50 bg-canvas border-b border-hairline">
        <div class="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between gap-4">
          <a href={~p"/"} class="flex items-center gap-2 text-ink font-semibold text-sm shrink-0">
            <img src={~p"/images/logo.svg"} alt="" class="w-5 h-5" /> Speechwave
          </a>
          <div class="flex items-center gap-4 text-sm ml-auto">
            <a href={~p"/dashboard"} class="text-steel hover:text-ink transition-colors">Dashboard</a>
            <a href={~p"/users/settings"} class="text-steel hover:text-ink transition-colors">
              Settings
            </a>
            <a
              id="help-nav-link"
              href="https://docs.speechwave.live"
              target="_blank"
              rel="noopener noreferrer"
              class="text-steel hover:text-ink transition-colors"
            >
              Help
            </a>
            <span class="hidden sm:inline text-xs text-muted">{@current_scope.user.email}</span>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="px-3 py-1.5 text-xs font-medium text-ink border border-hairline rounded-full hover:bg-surface transition-colors"
            >
              Log out
            </.link>
          </div>
        </div>
      </header>
      <main class={["pt-14", not @full_width && "px-4 py-8 sm:px-6 lg:px-8"]}>
        <div class={[@full_width || "mx-auto max-w-2xl space-y-4"]}>
          {render_slot(@inner_block)}
        </div>
      </main>
    <% else %>
      <.public_nav current_scope={@current_scope} />
      <main class={["pt-16", not @full_width && "px-4 py-8 sm:px-6 lg:px-8"]}>
        <div class={[@full_width || "mx-auto max-w-2xl space-y-4"]}>
          {render_slot(@inner_block)}
        </div>
      </main>
    <% end %>

    <.public_footer />
    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, default: nil

  def public_nav(assigns) do
    ~H"""
    <header class="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-hairline">
      <div class="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between gap-4">
        <a
          href="/"
          class="flex items-center gap-2 text-ink font-semibold text-[15px] tracking-tight shrink-0"
        >
          <img src={~p"/images/logo.svg"} alt="" class="w-6 h-6" /> Speechwave
        </a>
        <nav class="flex items-center gap-1">
          <a href={~p"/pricing"} class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors">
            Pricing
          </a>
          <a
            id="help-nav-link"
            href="https://docs.speechwave.live"
            target="_blank"
            rel="noopener noreferrer"
            class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
          >
            Help
          </a>
          <%= if @current_scope do %>
            <a
              href={~p"/dashboard"}
              class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
            >
              Dashboard
            </a>
            <a
              href={~p"/users/settings"}
              class="hidden sm:block px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
            >
              Settings
            </a>
            <span class="hidden md:inline text-xs text-muted px-2 truncate max-w-40">
              {@current_scope.user.email}
            </span>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="ml-2 px-4 py-2 text-sm font-medium text-ink border border-hairline rounded-full hover:bg-surface transition-colors whitespace-nowrap"
            >
              Log out
            </.link>
          <% else %>
            <a
              href={~p"/users/log-in"}
              class="hidden sm:block px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
            >
              Log in
            </a>
            <a
              href={~p"/users/log-in"}
              class="ml-2 px-4 py-2 text-sm font-medium text-canvas bg-ink rounded-full hover:bg-charcoal transition-colors whitespace-nowrap"
            >
              <span class="hidden sm:inline">Get started free</span>
              <span class="sm:hidden">Sign up</span>
            </a>
          <% end %>
        </nav>
      </div>
    </header>
    """
  end

  def public_footer(assigns) do
    ~H"""
    <footer class="py-12 px-6 bg-canvas-dark">
      <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-6 text-sm">
        <a href="/" class="flex items-center gap-2 text-on-dark font-medium">
          <img src={~p"/images/logo.svg"} alt="" class="w-5 h-5" /> Speechwave
        </a>
        <div class="flex gap-6 text-on-dark-muted">
          <a href={~p"/pricing"} class="hover:text-on-dark transition-colors">Pricing</a>
          <a href={~p"/terms"} class="hover:text-on-dark transition-colors">Terms</a>
          <a href={~p"/privacy"} class="hover:text-on-dark transition-colors">Privacy</a>
        </div>
        <span class="text-on-dark-muted">© {Date.utc_today().year} Speechwave</span>
      </div>
    </footer>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
