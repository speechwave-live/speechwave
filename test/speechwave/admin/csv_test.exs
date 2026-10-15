defmodule Speechwave.Admin.CSVTest do
  use ExUnit.Case, async: true

  alias Speechwave.Admin.CSV

  # Format tests opt out of the BOM so they compare the exact cells and lines.
  defp encode(headers, rows),
    do: headers |> CSV.encode(rows, bom: false) |> IO.iodata_to_binary()

  test "header row then rows joined with CRLF" do
    assert encode(["a", "b"], [["x", 1]]) == "a,b\r\nx,1\r\n"
  end

  test "nil is blank, DateTime is ISO 8601, atom is stringified" do
    assert encode(["a", "b", "c"], [[nil, ~U[2026-10-15 12:00:00Z], :pro]]) ==
             "a,b,c\r\n,2026-10-15T12:00:00Z,pro\r\n"
  end

  test "quotes fields with comma, quote or newline" do
    assert encode(["a"], [["a,b"]]) == "a\r\n\"a,b\"\r\n"
    assert encode(["a"], [[~s(say "hi")]]) == "a\r\n\"say \"\"hi\"\"\"\r\n"
    assert encode(["a"], [["a\nb"]]) == "a\r\n\"a\nb\"\r\n"
  end

  test "neutralizes formula prefixes" do
    for prefix <- ["=", "+", "-", "@"] do
      assert encode(["a"], [[prefix <> "1"]]) == "a\r\n'#{prefix}1\r\n"
    end

    # Tab and CR prefixes: CR also forces quoting, so the quote precedes the apostrophe.
    assert encode(["a"], [["\tx"]]) == "a\r\n'\tx\r\n"
    assert encode(["a"], [["\rx"]]) == "a\r\n\"'\rx\"\r\n"
  end

  test "does not prefix a plain negative integer" do
    assert encode(["a"], [[-5]]) == "a\r\n-5\r\n"
  end

  describe "UTF-8 BOM" do
    test "is prepended by default so Excel detects UTF-8" do
      out = ["a"] |> CSV.encode([["😀"]]) |> IO.iodata_to_binary()
      assert out == <<0xEF, 0xBB, 0xBF>> <> "a\r\n😀\r\n"
    end

    test "bom: false omits it" do
      out = ["a"] |> CSV.encode([["x"]], bom: false) |> IO.iodata_to_binary()
      assert out == "a\r\nx\r\n"
    end
  end
end
