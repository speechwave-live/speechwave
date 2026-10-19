ExUnit.start(exclude: [:e2e])

# E2E tests drive a real browser and need Playwright (`npm install` in assets/
# plus `npx playwright install chromium`). Only start it when they were asked
# for (`mix test.browser`), so a plain `mix test` works without Node.
if :e2e in ExUnit.configuration()[:include] do
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
  Application.put_env(:phoenix_test, :base_url, SpeechwaveWeb.Endpoint.url())
end

Ecto.Adapters.SQL.Sandbox.mode(Speechwave.Repo, :manual)
