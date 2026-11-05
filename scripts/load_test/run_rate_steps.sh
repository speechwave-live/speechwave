#!/usr/bin/env bash
# Holds the audience at one size and steps the TOTAL reaction rate up by
# shortening how long each person waits between taps (period = people / rate).
# Usage: ./run_rate_steps.sh 400 40 60 80 100   (people, then target taps/s...)
set -uo pipefail
cd "$(dirname "$0")"
N="$1"; shift
for RATE in "$@"; do
  PERIOD_MS=$(( N * 1000 / RATE ))
  echo "##### $N people, target $RATE taps/s (period ${PERIOD_MS} ms)"
  PERIOD="$PERIOD_MS" DURATION=60 ./run_series.sh "$N" | grep -v "^==="
done
