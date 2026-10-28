#!/bin/zsh
# Two headless instances on this machine, both AI-controlled, over real ENet on localhost.
# Passes if both peers agree on every shared state checkpoint and nobody desynced.
# Usage: tools/net_smoke.sh [seconds] [latency,jitter,loss] [port]
set -uo pipefail
cd "${0:A:h}/.."

seconds="${1:-20}"
lag="${2:-0,0,0}"
port="${3:-24680}"
logs="${TMPDIR:-/tmp}/boxing-net-smoke"
mkdir -p "$logs"

godot --headless res://game/online_match.tscn -- --host --ai=hard --lag="$lag" \
	--test-seconds=$((seconds + 3)) > "$logs/host.log" 2>&1 &
host_pid=$!
sleep 1
godot --headless res://game/online_match.tscn -- --join=127.0.0.1 --ai=normal --lag="$lag" \
	--test-seconds="$seconds" > "$logs/client.log" 2>&1
wait $host_pid

grep -hE "RESULT|SESSION ENDED|ERROR|SCRIPT ERROR" "$logs/host.log" "$logs/client.log"

python3 - "$logs/host.log" "$logs/client.log" <<'EOF'
import sys
def checkpoints(path):
    for line in open(path):
        if line.startswith("HASHES"):
            return dict(item.split(":") for item in line.split()[1:])
    return {}
host, client = (checkpoints(p) for p in sys.argv[1:3])
shared = sorted(set(host) & set(client), key=int)
bad = [t for t in shared if host[t] != client[t]]
print(f"shared checkpoints: {len(shared)}  mismatched: {len(bad)}")
sys.exit(0 if shared and not bad else 1)
EOF
