# Browser tests are slower and need Playwright (`npm install` in assets/ plus
# `npx playwright install chromium`), so they only run via `mix test.browser`.
ExUnit.start(exclude: [:e2e])
{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
Application.put_env(:phoenix_test, :base_url, SpeechwaveWeb.Endpoint.url())
Ecto.Adapters.SQL.Sandbox.mode(Speechwave.Repo, :manual)
