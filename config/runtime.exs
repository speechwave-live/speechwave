import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/speechwave start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :speechwave, SpeechwaveWeb.Endpoint, server: true
end

config :speechwave, SpeechwaveWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  config :speechwave, run_migrations_on_start: true

  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      Set it to the SQLite file path, e.g. /data/speechwave.db
      """

  config :speechwave, Speechwave.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :speechwave,
         :admin_password,
         System.get_env("ADMIN_PASSWORD") ||
           raise("ADMIN_PASSWORD environment variable is missing")

  host = System.get_env("PHX_HOST") || "speechwave.live"

  config :speechwave, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :speechwave, SpeechwaveWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :speechwave, SpeechwaveWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :speechwave, SpeechwaveWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :speechwave, Speechwave.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
  config :speechwave, Speechwave.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key: System.fetch_env!("RESEND_API_KEY")
end

# OAuth provider configuration
# Set these environment variables to enable each provider.
oauth_providers =
  [
    google:
      if(client_id = System.get_env("GOOGLE_CLIENT_ID"),
        do: [
          client_id: client_id,
          client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
          strategy: Assent.Strategy.Google
        ]
      ),
    github:
      if(client_id = System.get_env("GITHUB_CLIENT_ID"),
        do: [
          client_id: client_id,
          client_secret: System.get_env("GITHUB_CLIENT_SECRET"),
          strategy: Assent.Strategy.Github
        ]
      ),
    microsoft:
      if(client_id = System.get_env("MICROSOFT_CLIENT_ID"),
        do: [
          client_id: client_id,
          client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
          tenant_id: System.get_env("MICROSOFT_TENANT_ID", "common"),
          strategy: Assent.Strategy.AzureAD,
          authorization_params: [response_mode: "query", scope: "openid profile email"]
        ]
      )
  ]
  |> Enum.reject(fn {_k, v} -> is_nil(v) end)

config :speechwave, :oauth_providers, oauth_providers
