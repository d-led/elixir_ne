#!/usr/bin/env bash
# Run the demo. Single node by default; set NODE_COUNT=2+ to run distributed.
# Usage: scripts/run.sh
#        NODE_COUNT=2 scripts/run.sh
#        NODE_COUNT=3 N_NEURONS=50000 scripts/run.sh
set -e
cd "$(dirname "$0")/.."
export ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS:-+P 5000000}"
n="${NODE_COUNT:-1}"

if [ "$n" -eq 1 ]; then
  exec mix run
fi

# Worker nodes (node2, ...) in background; skip their demo so only front-end runs it
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT
export DEMO_SKIP_AUTO_START=1

for i in $(seq 2 "$n"); do
  elixir --name "node${i}@127.0.0.1" -S mix run --no-halt -e "IO.puts(:ready)" &
  pids+=($!)
done
# Wait for workers to boot and accept connections
sleep 5

# Front-end node: run script that connects to workers (retry until ready) and runs demo
export NODE_COUNT="$n"
elixir --name node1@127.0.0.1 -S mix run scripts/run_distributed.exs || true
