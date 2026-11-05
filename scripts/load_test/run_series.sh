#!/usr/bin/env bash
# Runs the load generator against a fresh container for each client count and
# prints one result block per run: aggregated generator output, how many
# reactions the database stored, container CPU/memory near the end, and error
# lines in the server log. The generator is split into shards of at most
# $SHARD_SIZE clients so a single Node process is never the bottleneck.
# Usage: ./run_series.sh 50 100 200      (env: DURATION=60 SHARD_SIZE=150)
set -uo pipefail
cd "$(dirname "$0")"
DURATION="${DURATION:-60}"
SHARD_SIZE="${SHARD_SIZE:-150}"
for N in "$@"; do
  read -r SLUG KEY SID < <(./start_container.sh | tail -1)
  echo "=== $N clients ==="
  ( sleep $((DURATION / 2 + 15)); docker stats --no-stream --format 'container cpu={{.CPUPerc}} mem={{.MemUsage}}' speechwave-loadtest ) &
  SHARDS=$(( (N + SHARD_SIZE - 1) / SHARD_SIZE ))
  for i in $(seq 1 "$SHARDS"); do
    COUNT=$(( N / SHARDS )); [ "$i" -le $(( N % SHARDS )) ] && COUNT=$((COUNT + 1))
    LISTENER=false; [ "$i" -eq 1 ] && LISTENER=true
    node audience_load.mjs --slug "$SLUG" --api-key "$KEY" --clients "$COUNT" --duration "$DURATION" --period "${PERIOD:-3200}" --listener "$LISTENER" 2>/dev/null | grep '^{' &
  done | node aggregate.mjs
  wait
  echo "db_stored: $(docker exec speechwave-loadtest /app/bin/speechwave rpc "IO.puts(Speechwave.Reactions.count_reactions($SID))" 2>&1 | tail -1)"
  echo "log_errors: $(docker logs speechwave-loadtest 2>&1 | grep -c '\[error\]')"
done
