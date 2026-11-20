# Checks, in the real release, that a saturated database makes
# Reactions.record_reaction/4 return {:error, :db_busy} instead of raising.
# Run it against the container from start_container.sh (it uses that script's
# "load-test" talk):
#
#   docker exec speechwave-loadtest /app/bin/speechwave rpc "$(cat db_busy_check.exs)"
#
# Scenario A holds every pooled connection. Scenario B holds SQLite's write
# lock while a connection is free. Both should print {:error, :db_busy}.
# Takes about 40 seconds.
talk = Speechwave.Talks.get_talk_by_slug("load-test")
alias Speechwave.{Reactions, Repo}
parent = self()

probe = fn label, fun ->
  started = System.monotonic_time(:millisecond)
  result =
    try do
      {:returned, fun.()}
    rescue
      e -> {:raised, e.__struct__, String.slice(Exception.message(e), 0, 140)}
    end
  IO.puts("#{label}: #{inspect(result)} after #{System.monotonic_time(:millisecond) - started} ms")
end

# Scenario A: both pool connections checked out (pool_size is 2 in this container).
holders =
  for _ <- 1..2 do
    spawn(fn ->
      Repo.checkout(fn -> send(parent, :held); Process.sleep(12_000) end)
    end)
  end
for _ <- holders, do: (receive do :held -> :ok end)

probe.("A raw query, pool exhausted", fn -> Repo.query!("select 1") end)
probe.("A record_reaction, pool exhausted", fn -> Reactions.record_reaction(talk.id, "🔥", 0, nil) end)
Process.sleep(12_500)

# Scenario B: one connection holds the SQLite write lock, the other is free.
writer =
  spawn(fn ->
    Repo.transaction(fn ->
      Repo.query!("insert into reactions (talk_session_id, emoji, slide_number, inserted_at, updated_at) values (1, 'x', 0, datetime('now'), datetime('now'))")
      send(parent, :locked)
      Process.sleep(12_000)
    end)
  end)
receive do :locked -> :ok end

probe.("B raw write, write lock held", fn -> Repo.query!("insert into reactions (talk_session_id, emoji, slide_number, inserted_at, updated_at) values (1, 'y', 0, datetime('now'), datetime('now'))") end)
probe.("B record_reaction, write lock held", fn -> Reactions.record_reaction(talk.id, "🔥", 0, nil) end)
IO.puts("done")
