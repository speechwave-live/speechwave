defmodule Speechwave.Admin.CSV do
  @moduledoc """
  Minimal CSV encoder for admin exports.

  Cells may be strings, integers, `nil` (written blank), `DateTime`s
  (ISO 8601) or atoms. Lines end in `\\r\\n`.

  String cells are checked for spreadsheet formula injection: a cell that
  starts with `=`, `+`, `-`, `@`, tab or CR is prefixed with a single quote
  so Excel, Numbers and Sheets show it as text instead of evaluating it.
  This matters because values like a consent `source` or an email address
  originate from user input.
  """

  @formula_prefixes ["=", "+", "-", "@", "\t", "\r"]

  @spec encode([String.t()], [[term()]]) :: iodata()
  def encode(headers, rows) do
    Enum.map([headers | rows], fn row ->
      [Enum.intersperse(Enum.map(row, &cell/1), ","), "\r\n"]
    end)
  end

  defp cell(nil), do: ""
  defp cell(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp cell(value) when is_integer(value), do: Integer.to_string(value)
  defp cell(value) when is_atom(value), do: value |> Atom.to_string() |> cell()

  defp cell(value) when is_binary(value) do
    value
    |> neutralize_formula()
    |> quote_if_needed()
  end

  defp neutralize_formula(value) do
    if String.starts_with?(value, @formula_prefixes), do: "'" <> value, else: value
  end

  defp quote_if_needed(value) do
    if String.contains?(value, [",", "\"", "\r", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end
end
