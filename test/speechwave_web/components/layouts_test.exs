defmodule SpeechwaveWeb.LayoutsTest do
  # async: false because two tests change the :docs_url app env.
  use SpeechwaveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Speechwave.AccountsFixtures

  alias Speechwave.Accounts.Scope

  defp render_app(user, extra \\ %{}) do
    assigns =
      Map.merge(
        %{
          flash: %{},
          current_scope: user && Scope.for_user(user),
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "" end}]
        },
        extra
      )

    render_component(&SpeechwaveWeb.Layouts.app/1, assigns)
    |> LazyHTML.from_fragment()
  end

  defp banner(doc), do: LazyHTML.query(doc, "#welcome-banner")

  test "shows the banner when welcomed_at is nil" do
    doc = render_app(user_fixture())
    assert Enum.count(banner(doc)) == 1
    assert Enum.count(LazyHTML.query(doc, "#welcome-banner-dismiss")) == 1
  end

  test "hides the banner when welcomed_at is set" do
    user = %{user_fixture() | welcomed_at: DateTime.utc_now(:second)}
    assert Enum.empty?(banner(render_app(user)))
  end

  test "hides the banner when show_welcome is false" do
    assert Enum.empty?(banner(render_app(user_fixture(), %{show_welcome: false})))
  end

  test "hides the banner when signed out" do
    assert Enum.empty?(banner(render_app(nil)))
  end

  test "links to getting-started.html on the docs base" do
    original = Application.get_env(:speechwave, :docs_url)
    on_exit(fn -> Application.put_env(:speechwave, :docs_url, original) end)

    for base <- ["https://docs.example.com", "https://docs.example.com/"] do
      Application.put_env(:speechwave, :docs_url, base)
      doc = render_app(user_fixture())
      link = LazyHTML.query(doc, "#welcome-banner-link")

      assert LazyHTML.attribute(link, "href") == ["https://docs.example.com/getting-started.html"]
      assert LazyHTML.attribute(link, "target") == ["_blank"]
      assert LazyHTML.attribute(link, "rel") == ["noopener noreferrer"]
    end
  end
end
