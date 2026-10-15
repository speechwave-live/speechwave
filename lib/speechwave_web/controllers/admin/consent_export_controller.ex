defmodule SpeechwaveWeb.Admin.ConsentExportController do
  @moduledoc """
  Serves the marketing consent export as a CSV download. The filter form on
  `/admin/stats` submits here as a plain GET, with fields nested under
  `export`. Admin-only via the router pipeline.
  """
  use SpeechwaveWeb, :controller

  alias Speechwave.Admin.ConsentExport

  def show(conn, params) do
    csv =
      params
      |> Map.get("export", %{})
      |> ConsentExport.parse_filters()
      |> ConsentExport.list()
      |> ConsentExport.to_csv()

    filename = ConsentExport.filename(Date.utc_today())

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, csv)
  end
end
