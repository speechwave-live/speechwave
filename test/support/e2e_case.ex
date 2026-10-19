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

  alias Speechwave.Accounts
  alias SpeechwaveWeb.Endpoint

  defmacro __using__(opts) do
    quote do
      use PhoenixTest.Playwright.Case, unquote(Keyword.put(opts, :async, false))

      import Speechwave.AccountsFixtures
      import SpeechwaveWeb.E2ECase, only: [log_in_with_magic_link: 2, log_in_as: 2]

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

    assert_receive {:email, %{text_body: body}}, 5000

    [magic_url] =
      Regex.run(~r{https?://\S+/users/magic_link/\S+}, body) ||
        flunk("no magic link in the sign-in email:\n#{body}")

    session
    |> PhoenixTest.visit(magic_url)
    |> PhoenixTest.visit("/dashboard")
    |> PhoenixTest.assert_has("#talk-form")
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
