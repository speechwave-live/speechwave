defmodule SpeechwaveWeb.UserDataExportController do
  use SpeechwaveWeb, :controller

  alias Speechwave.DataExport
  alias Speechwave.DataExportThrottle

  @doc """
  Sends the signed-in user a zip of their personal data.

  This is a controller action, not a LiveView event, because a LiveView
  cannot send a file download. It is a POST because it has a side effect (it
  claims the cooldown), so a link or prefetch cannot trigger it. The cooldown
  is claimed before the zip is built and released if the build returns an
  error, or if building or sending raises, throws or exits, so a failure never
  locks the user out. A request process killed outright cannot be caught, so
  that case keeps the cooldown until it expires. Tests can swap the builder with the `:data_export_zip_fun` app env.
  """
  def create(conn, _params) do
    scope = conn.assigns.current_scope
    user_id = scope.user.id

    case DataExportThrottle.claim(user_id) do
      :ok ->
        try do
          case build_zip(scope) do
            {:ok, zip} ->
              send_download(conn, {:binary, zip},
                filename: "speechwave-data.zip",
                content_type: "application/zip"
              )

            {:error, _reason} ->
              DataExportThrottle.release(user_id)

              conn
              |> put_flash(:error, "We could not build your download. Please try again.")
              |> redirect(to: ~p"/users/settings")
          end
        catch
          kind, value ->
            DataExportThrottle.release(user_id)
            :erlang.raise(kind, value, __STACKTRACE__)
        end

      {:error, seconds} ->
        minutes = ceil(seconds / 60)

        conn
        |> put_flash(
          :error,
          "You downloaded your data recently. Please try again in #{minutes} #{if minutes == 1, do: "minute", else: "minutes"}."
        )
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp build_zip(scope) do
    zip_fun = Application.get_env(:speechwave, :data_export_zip_fun, &DataExport.to_zip/1)
    zip_fun.(scope)
  end
end
