defmodule Speechwave.QRCode do
  @moduledoc """
  Generates QR codes as base64-encoded PNG data URIs.

  Wraps the `EQRCode` library. The output of `to_data_uri/1` can be used
  directly in an `<img src={...}>` tag without a separate HTTP request or
  file on disk.
  """
  def to_data_uri(url) do
    png_binary =
      url
      |> EQRCode.encode()
      |> EQRCode.png()
      |> IO.iodata_to_binary()

    "data:image/png;base64," <> Base.encode64(png_binary)
  end

  @doc """
  Returns the data URI for `url`, generating and storing it in `cache` if not
  already present. Returns `{data_uri, updated_cache}`.
  """
  def cached_data_uri(cache, url) do
    case Map.fetch(cache, url) do
      {:ok, data_uri} ->
        {data_uri, cache}

      :error ->
        data_uri = to_data_uri(url)
        {data_uri, Map.put(cache, url, data_uri)}
    end
  end
end
