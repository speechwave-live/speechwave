defmodule SpeechwaveWeb.UserAccountController do
  use SpeechwaveWeb, :controller

  alias Speechwave.Accounts
  alias SpeechwaveWeb.UserAuth

  @doc """
  Permanently deletes the signed-in user's account.

  The typed email is checked again here by `Accounts.delete_account/2`; the
  disabled button on the Settings page is only a convenience. On success every
  live connection of the user is ended, the session is cleared and the user
  lands on the home page logged out.
  """
  def delete(conn, params) do
    user = conn.assigns.current_scope.user

    typed_email =
      case params do
        %{"account" => %{"email" => email}} -> email
        _ -> nil
      end

    tokens = Accounts.list_session_tokens(user)

    case Accounts.delete_account(user, typed_email) do
      {:ok, _user} ->
        SpeechwaveWeb.Endpoint.broadcast!("user:#{user.id}:disconnect", "disconnect", %{})
        UserAuth.disconnect_sessions(tokens)

        conn
        |> put_flash(:info, "Your account and its data have been deleted.")
        |> UserAuth.log_out_user()

      {:error, reason} ->
        conn
        |> put_flash(:error, error_message(reason))
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp error_message(:confirmation_mismatch),
    do: "The email you typed does not match your account email, so nothing was deleted."

  defp error_message(:admin),
    do: "Admin accounts cannot be deleted from Settings."

  defp error_message(:log_failed),
    do: "We could not delete your account because of a problem on our side. Please try again."
end
