import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :speechwave, Speechwave.Repo,
  database:
    Path.expand("../priv/repo/test#{System.get_env("MIX_TEST_PARTITION", "")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

config :speechwave,
       :deletions_db_path,
       Path.expand(
         "../priv/repo/deletions_test#{System.get_env("MIX_TEST_PARTITION", "")}.db",
         __DIR__
       )

# The port is set in config/runtime.exs (4002 + MIX_TEST_PARTITION by default).
# The server runs during tests because the E2E tests (test/e2e) drive the app
# through a real browser.
config :speechwave, SpeechwaveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  secret_key_base: "ZNi8x7OBa7XcA37WQBQLYngfsJBZMA4Wmy+pkwb/YA0xYh9EDh82k1v5lZ2hpO8O",
  server: true

# In test we don't send emails
config :speechwave, Speechwave.Mailer, adapter: Swoosh.Adapters.Test

# AuthThrottle's ETS-backed cooldowns are wall-clock and global (BEAM-wide),
# which would make login_test.exs's async, repeated-email submissions
# flaky. AuthThrottle itself is covered directly by
# test/speechwave/auth_throttle_test.exs, and
# test/speechwave_web/live/user_live/login_auth_throttle_test.exs
# temporarily re-enables this flag to test the UserLive.Login wiring.
# See docs/specs/2026-06-11-magic-link-auth-throttle-design.md.
config :speechwave, :auth_throttle_enabled, false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Every E2E test records a screenshot and a trace. The formatter in
# test/support/e2e_artifacts_formatter.ex deletes the ones from passing tests
# when the run ends, so only failures are left in tmp/e2e (which is gitignored).
# Keep the directories in sync with that module.
config :phoenix_test,
  otp_app: :speechwave,
  endpoint: SpeechwaveWeb.Endpoint,
  playwright: [
    screenshot: true,
    screenshot_dir: "tmp/e2e/screenshots",
    trace: true,
    trace_dir: "tmp/e2e/traces"
  ]
