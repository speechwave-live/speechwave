defmodule Speechwave.QRCodeTest do
  use ExUnit.Case, async: true

  alias Speechwave.QRCode

  describe "cached_data_uri/2" do
    test "generates and stores a data URI for a new url" do
      url = "https://example.com/t/my-talk"

      {data_uri, cache} = QRCode.cached_data_uri(%{}, url)

      assert data_uri == QRCode.to_data_uri(url)
      assert cache == %{url => data_uri}
    end

    test "returns the cached data URI without regenerating it" do
      url = "https://example.com/t/my-talk"
      cache = %{url => "cached-value"}

      {data_uri, returned_cache} = QRCode.cached_data_uri(cache, url)

      assert data_uri == "cached-value"
      assert returned_cache == cache
    end
  end
end
