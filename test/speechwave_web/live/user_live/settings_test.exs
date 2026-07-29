defmodule SpeechwaveWeb.UserLive.SettingsTest do
  use SpeechwaveWeb.ConnCase, async: true

  alias Speechwave.Accounts
  import Phoenix.LiveViewTest
  import Speechwave.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Connected accounts"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "connected accounts" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "shows connected accounts section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#connected-accounts")
    end

    test "shows connect links for unlinked providers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#connect-google")
    end

    test "disconnect removes an identity", %{conn: conn, user: user} do
      {:ok, _} =
        Accounts.find_or_create_user_from_oauth("google", %{
          "sub" => "g-test-uid",
          "email" => user.email,
          "email_verified" => true
        })

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#disconnect-google")

      view
      |> element("#disconnect-google")
      |> render_click()

      refute has_element?(view, "#disconnect-google")
    end
  end

  describe "API key section" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "shows the user's api_key in a read-only field", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert has_element?(view, "#api-key-display")
      assert render(view) =~ user.api_key
    end

    test "regenerate button generates a new api_key", %{conn: conn, user: user} do
      old_key = user.api_key
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      view |> element("#regenerate-api-key-btn") |> render_click()
      refute render(view) =~ old_key
      updated_user = Speechwave.Accounts.get_user!(user.id)
      assert updated_user.api_key != old_key
    end

    test "regenerate broadcasts disconnect to active channel connections", %{
      conn: conn,
      user: user
    } do
      Phoenix.PubSub.subscribe(Speechwave.PubSub, "user:#{user.id}:disconnect")
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      view |> element("#regenerate-api-key-btn") |> render_click()
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 500
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end

  describe "extension settings form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders the tuning module's default percent when unset", %{conn: conn} do
      default = Speechwave.ExtensionTuning.current().default_overlay_size_percent
      {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Overlay size (#{default}%)"
    end

    test "updates overlay size and fireworks toggle", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      # The slider is only visually/interactively disabled for a user who has
      # never customized it; the underlying overlay_size_percent submitted
      # while unchecked is discarded by maybe_clear_overlay_size_percent/1
      # regardless. Check "customize" first so the submitted percent is
      # actually the one that gets persisted.
      lv
      |> form("#extension_settings_form", %{"user" => %{"customize_overlay_size" => "true"}})
      |> render_change()

      lv
      |> form("#extension_settings_form", %{
        "user" => %{
          "overlay_size_percent" => "45",
          "fireworks_enabled" => "false",
          "customize_overlay_size" => "true"
        }
      })
      |> render_submit()

      updated = Speechwave.Repo.get!(Speechwave.Accounts.User, user.id)
      assert updated.overlay_size_percent == 45
      assert updated.fireworks_enabled == false
    end

    test "renders the customize overlay size checkbox", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Customize overlay size"
    end

    test "first-time visitor (never customized) sees the checkbox unchecked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      refute has_element?(lv, "#user_customize_overlay_size[checked]")
    end

    test "submitting with the toggle unchecked clears overlay_size_percent even if the slider moved",
         %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      # Enable the slider first so the test helper can locate and move it,
      # then submit with the toggle switched back off. The handler must
      # still clear overlay_size_percent even though the slider's own
      # submitted value is 45.
      lv
      |> form("#extension_settings_form", %{"user" => %{"customize_overlay_size" => "true"}})
      |> render_change()

      lv
      |> form("#extension_settings_form", %{
        "user" => %{
          "overlay_size_percent" => "45",
          "fireworks_enabled" => "true",
          "customize_overlay_size" => "false"
        }
      })
      |> render_submit()

      updated = Speechwave.Repo.get!(Speechwave.Accounts.User, user.id)
      assert updated.overlay_size_percent == nil
    end

    test "renders the range input's styling classes and debounce attribute", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      # Substring, not an exact `class="..."` match: the non-customizing
      # default state also appends "opacity-50 pointer-events-none" (see
      # "visually disables the slider..." below), so this only pins that
      # range/range-primary/w-full survive, not the full attribute value.
      assert html =~ ~s(class="range range-primary w-full)
      assert html =~ ~s(phx-debounce="100")
    end

    test "visually disables the slider (but still submits its value) when not customizing", %{
      conn: conn
    } do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "opacity-50 pointer-events-none"
      assert html =~ ~s(tabindex="-1")
      assert html =~ ~s(aria-disabled="true")
    end

    test "does not visually disable the slider once customizing is checked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html =
        lv
        |> form("#extension_settings_form", %{"user" => %{"customize_overlay_size" => "true"}})
        |> render_change()

      refute html =~ "opacity-50 pointer-events-none"
      refute html =~ ~s(tabindex="-1")
      refute html =~ ~s(aria-disabled="true")
    end

    test "checking customize overlay size does not blank out the overlay size value", %{
      conn: conn
    } do
      default = Speechwave.ExtensionTuning.current().default_overlay_size_percent
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html =
        lv
        |> form("#extension_settings_form", %{"user" => %{"customize_overlay_size" => "true"}})
        |> render_change()

      assert html =~ "Overlay size (#{default}%)"
      refute html =~ "Overlay size (%)"
    end

    test "rejects an overlay size below the tuning minimum", %{conn: conn} do
      min = Speechwave.ExtensionTuning.current().min_overlay_size_percent
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      lv
      |> form("#extension_settings_form", %{"user" => %{"customize_overlay_size" => "true"}})
      |> render_change()

      result =
        lv
        |> form("#extension_settings_form", %{
          "user" => %{
            "overlay_size_percent" => to_string(min - 1),
            "fireworks_enabled" => "true",
            "customize_overlay_size" => "true"
          }
        })
        |> render_change()

      assert result =~ "must be greater than or equal to #{min}"
      assert result =~ "range-error"
    end
  end
end
