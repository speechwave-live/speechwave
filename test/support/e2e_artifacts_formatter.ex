defmodule SpeechwaveWeb.E2EArtifactsFormatter do
  @moduledoc """
  ExUnit formatter that keeps Playwright screenshots and traces only for E2E
  tests that failed.

  The Playwright driver can't capture on failure only, so config/test.exs makes
  it record both for every E2E test. When the run ends this formatter deletes
  the files that belong to passing tests (and anything over a week old), and
  prints where the rest are. Open a trace with
  `npx --prefix assets playwright show-trace tmp/e2e/traces/<file>.zip`.
  """
  use GenServer

  @dirs ["tmp/e2e/screenshots", "tmp/e2e/traces"]
  @max_age_seconds 7 * 24 * 60 * 60

  @impl true
  def init(_opts), do: {:ok, %{started_at: System.os_time(:second), failed: []}}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: {kind, _}} = test}, state)
      when kind in [:failed, :invalid] do
    {:noreply, %{state | failed: [file_prefix(test) | state.failed]}}
  end

  def handle_cast({:suite_finished, _times}, state) do
    kept = prune(state)

    if kept != [] do
      IO.puts("\nE2E screenshots and traces for failed tests:")
      Enum.each(kept, &IO.puts("  #{&1}"))
    end

    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  # Mirrors how PhoenixTest.Playwright.Case names its files:
  # "<Module>.<test name>_<unix time>[_<n>].<ext>" with odd characters as "_".
  defp file_prefix(%ExUnit.Test{module: module, name: name}) do
    String.replace("#{inspect(module)}.#{name}", ~r/[^a-zA-Z0-9\.]/, "_")
  end

  defp prune(state) do
    now = System.os_time(:second)

    for dir <- @dirs, file <- File.ls(dir) |> elem(1) |> Enum.sort(), reduce: [] do
      kept ->
        path = Path.join(dir, file)
        mtime = File.stat!(path, time: :posix).mtime

        cond do
          now - mtime > @max_age_seconds ->
            File.rm!(path)
            kept

          mtime >= state.started_at and not failed_file?(file, state.failed) ->
            File.rm!(path)
            kept

          mtime >= state.started_at ->
            kept ++ [path]

          true ->
            kept
        end
    end
  end

  defp failed_file?(file, failed_prefixes) do
    Enum.any?(failed_prefixes, fn prefix ->
      String.starts_with?(file, prefix) and
        String.slice(file, String.length(prefix)..-1//1) =~ ~r/^_\d+(_\d+)?\.(png|zip)$/
    end)
  end
end
