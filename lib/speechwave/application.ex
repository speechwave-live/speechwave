defmodule Speechwave.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        SpeechwaveWeb.Telemetry,
        Speechwave.Repo,
        {DNSCluster, query: Application.get_env(:speechwave, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Speechwave.PubSub},
        Speechwave.RateLimiter,
        Speechwave.AuthThrottle,
        SpeechwaveWeb.Endpoint,
        SpeechwaveWeb.Presence
      ] ++ backup_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Speechwave.Supervisor]

    Supervisor.start_link(children, opts)
  end

  defp backup_children do
    if System.get_env("STORAGE_BUCKET"), do: [Speechwave.DbBackup], else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    SpeechwaveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
