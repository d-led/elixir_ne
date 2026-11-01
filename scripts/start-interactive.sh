#!/usr/bin/env bash
# Single front-end IEx (node1). Optional workers (node2, ...) are started in background
# and destroyed when this script exits or is aborted.
# Usage: scripts/start-interactive.sh              # one node (node1 only)
#        NODE_COUNT=2 scripts/start-interactive.sh # node1 + node2 (worker, killed on exit)
set -e
cd "$(dirname "$0")/.."
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+P 5000000}"
n="${NODE_COUNT:-1}"
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

if [ "$n" -ge 2 ]; then
  for i in $(seq 2 "$n"); do
    iex --name "node${i}@127.0.0.1" -S mix &
    pids+=($!)
  done
  sleep 3
fi

exec iex --name node1@127.0.0.1 -S mix
