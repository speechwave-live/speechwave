defmodule SpeechwaveWeb.UserDataExportController do
  use SpeechwaveWeb, :controller

  alias Speechwave.DataExport
  alias Speechwave.DataExportThrottle

  @doc """
  Sends the signed-in user a zip of their personal data.

  This is a controller action, not a LiveView event, because a LiveView
  cannot send a file download. The cooldown is claimed before the zip is
  built and released if the build raises, so a failure never locks the user
  out. Tests can swap the builder with the `:data_export_zip_fun` app env.
  """
  def show(conn, _params) do
    scope = conn.assigns.current_scope

    case DataExportThrottle.claim(scope.user.id) do
      :ok ->
        {:ok, zip} = build_zip(scope)

        send_download(conn, {:binary, zip},
          filename: "speechwave-data.zip",
          content_type: "application/zip"
        )

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
  rescue
    exception ->
      DataExportThrottle.release(scope.user.id)
      reraise exception, __STACKTRACE__
  end
end
