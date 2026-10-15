defmodule Speechwave.Admin.CSVTest do
  use ExUnit.Case, async: true

  alias Speechwave.Admin.CSV

  defp encode(headers, rows), do: headers |> CSV.encode(rows) |> IO.iodata_to_binary()

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
end
