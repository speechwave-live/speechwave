defmodule Speechwave.AuthThrottle do
  @moduledoc """
  Throttles magic-link auth requests by email and by client IP, to slow
  casual scripted abuse of `UserLive.Login`'s `submit_magic` event.

  Two `:public` ETS tables, owned by this GenServer and recreated empty on
  restart (fail open, matching `Speechwave.RateLimiter`):

    * `:auth_throttle_email` — key: normalized email (trimmed + downcased),
      value: `last_sent_at` (monotonic ms). Fixed 60s cooldown, no
      escalation.
    * `:auth_throttle_ip` — key: client IP string, value:
      `{last_at, cooldown_ms, violation_count}`. Cooldown starts at 30s,
      doubles on each violation up to a 30-minute cap, and resets to the
      base cooldown on any allowed request. `violation_count` is carried
      for logging only — it does not influence the cooldown math.

  Both `allow_email?/1` and `allow_ip?/1` log a warning when they return
  `false`, so repeated-violation patterns are visible in logs.
  """

  use GenServer

  require Logger

  @email_table :auth_throttle_email
  @ip_table :auth_throttle_ip

  @email_cooldown_ms 60_000
  @ip_base_cooldown_ms 30_000
  @ip_max_cooldown_ms 1_800_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@email_table, [:named_table, :public, read_concurrency: true])
    :ets.new(@ip_table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  Returns `true` if a magic-link request for `email` is allowed, `false` if
  the same email was sent a link within the last 60 seconds. `email` should
  already be normalized (trimmed + downcased) by the caller.
  """
  def allow_email?(email) when is_binary(email) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@email_table, email) do
      [{^email, last_sent_at}] when now - last_sent_at < @email_cooldown_ms ->
        Logger.warning("auth_throttle: email cooldown", email_domain: email_domain(email))
        false

      _ ->
        :ets.insert(@email_table, {email, now})
        true
    end
  end

  defp email_domain(email) do
    case String.split(email, "@") do
      [_local, domain] -> domain
      _ -> "unknown"
    end
  end
end
