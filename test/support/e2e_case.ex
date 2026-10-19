defmodule SpeechwaveWeb.E2ECase do
  @moduledoc """
  Test case for end-to-end tests that drive a real browser through Playwright.
  Use it in files under `test/e2e`:

      defmodule SpeechwaveWeb.E2E.MyFlowTest do
        use SpeechwaveWeb.E2ECase

        test "my flow", %{conn: conn} do
          conn
          |> log_in_as(user_fixture())
          |> visit("/dashboard")
        end
      end

  It wraps `PhoenixTest.Playwright.Case` and adds:

    * the `:e2e` tag, so `mix test` skips these and `mix test.browser` runs them
    * `async: false`, always. The Swoosh test process is global app env and the
      Ecto sandbox runs in shared mode, so two E2E modules must never overlap
    * `Speechwave.AccountsFixtures` imported
    * email delivery routed to the test process (see `log_in_with_magic_link/2`)

  In these tests `conn` is a Playwright session, not a `Plug.Conn`.
  """

  import ExUnit.Assertions

  alias PhoenixTest.Playwright.Config
  alias PhoenixTest.Playwright.Selector.Engines
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Page
  alias Speechwave.Accounts
  alias SpeechwaveWeb.Endpoint

  defmacro __using__(opts) do
    quote do
      use PhoenixTest.Playwright.Case, unquote(Keyword.put(opts, :async, false))

      import Speechwave.AccountsFixtures

      import SpeechwaveWeb.E2ECase,
        only: [
          log_in_with_magic_link: 2,
          log_in_as: 2,
          receive_magic_link: 0,
          new_browser_session: 1
        ]

      @moduletag :e2e

      setup {SpeechwaveWeb.E2ECase, :route_emails_to_test_process}
    end
  end

  @doc """
  Setup callback. The endpoint sends emails from its own process, so point
  Swoosh's test adapter at this test to receive them as `{:email, email}`
  messages.
  """
  def route_emails_to_test_process(_context) do
    previous = Application.fetch_env(:swoosh, :shared_test_process)
    Application.put_env(:swoosh, :shared_test_process, self())

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:swoosh, :shared_test_process, value)
        :error -> Application.delete_env(:swoosh, :shared_test_process)
      end
    end)

    :ok
  end

  @doc """
  Logs in through the real sign-in form: submits the email, takes the link out
  of the message that Swoosh delivers to the test, and follows it. Ends on
  `/dashboard`. Use `log_in_as/2` instead when login is not what's under test.
  """
  def log_in_with_magic_link(session, email) do
    session =
      session
      |> PhoenixTest.visit("/users/log-in")
      |> PhoenixTest.fill_in("Email address", with: email)
      |> PhoenixTest.click_button("Send sign-in link")
      |> PhoenixTest.assert_has("#magic-link-sent")

    magic_url = receive_magic_link()

    session
    |> PhoenixTest.visit(magic_url)
    |> PhoenixTest.visit("/dashboard")
    |> PhoenixTest.assert_has("#talk-form")
  end

  @doc """
  Opens another browser session (its own cookies and page) for tests that need
  two people at once, for example two attendees on the same talk. Takes the
  test context: `test "...", %{conn: first} = context do`. The first session is
  still the `conn` from the context.

  `PhoenixTest.Playwright.Case.new_session/2` can't be used for this: it checks
  out a second Ecto sandbox owner, and the test repo has `pool_size: 1`, so
  the checkout times out. The sandbox is already shared with the first
  session (E2E tests are `async: false`), so a bare browser context is enough.
  """
  def new_browser_session(%{browser_id: browser_id} = context) do
    config =
      context
      |> Map.take(Config.setup_keys())
      |> Config.validate!()

    timeout = config[:timeout]
    base_url = Application.fetch_env!(:phoenix_test, :base_url)

    context_opts =
      Keyword.merge(
        [base_url: base_url, locale: "en", timeout: timeout],
        config[:browser_context_opts]
      )

    {:ok, browser_context} = Browser.new_context(browser_id, context_opts)

    for {name, source} <- Engines.custom() do
      {:ok, _} =
        BrowserContext.register_selector_engine(browser_context.guid,
          selector_engine: [name: to_string(name), source: source],
          timeout: timeout
        )
    end

    page_opts = Keyword.merge([timeout: timeout], config[:browser_page_opts])
    {:ok, page} = BrowserContext.new_page(browser_context.guid, page_opts)

    {:ok, _} =
      Page.update_subscription(page.guid, event: :console, enabled: true, timeout: timeout)

    {:ok, _} =
      Page.update_subscription(page.guid, event: :dialog, enabled: true, timeout: timeout)

    ExUnit.Callbacks.on_exit(fn ->
      BrowserContext.close(browser_context.guid, timeout: timeout)
    end)

    PhoenixTest.Playwright.build(%{
      context_id: browser_context.guid,
      page_id: page.guid,
      frame_id: page.main_frame.guid,
      tracing_id: browser_context.tracing.guid,
      config: config
    })
  end

  @doc """
  Waits for the sign-in email and returns the magic link in it, query string
  included, so tests can check what the link carries before following it.
  """
  def receive_magic_link do
    assert_receive {:email, %{text_body: body}}, 5000

    [magic_url] =
      Regex.run(~r{https?://\S+/users/magic_link/\S+}, body) ||
        flunk("no magic link in the sign-in email:\n#{body}")

    magic_url
  end

  @doc """
  Logs `user` in by planting a session cookie in the browser, skipping the
  sign-in form. Fast, and the right choice for any test that is not about
  logging in.
  """
  def log_in_as(session, user) do
    token = Accounts.generate_user_session_token(user)

    PhoenixTest.Playwright.add_session_cookie(
      session,
      [value: %{user_token: token}],
      Endpoint.session_options()
    )
  end
end
