# Reaction load test

Throwaway tooling that answers "how many people can react at once before
reactions are dropped or delayed". Local only, never point it at production.

1. `docker build -t speechwave-loadtest .` from the repo root.
2. `cd scripts/load_test && npm install`
3. `./run_series.sh 100 200 400` (env: `DURATION=60`, `PERIOD=3200` ms between
   one person's taps, `SHARD_SIZE=150`).

`start_container.sh` runs the production image with fly.toml's limits (1 CPU
pinned to one core so the BEAM gets one scheduler like Fly, 512 MB, DB pool 2),
a throwaway database and fake secrets. `audience_load.mjs` simulates audience
LiveView connections plus an extension-style channel listener and times probe
reactions. `aggregate.mjs` merges the shards.

Results and caveats: see docs/load_test_results.md.
