#!/bin/zsh
# Two headless instances on this machine, both AI-controlled, over real ENet on localhost.
# They start from the main menu (host / join buttons pressed via flags), play short matches and
# rematch automatically. Passes if both peers agree on every shared state checkpoint.
# Usage: tools/net_smoke.sh [seconds] [latency,jitter,loss]
set -uo pipefail
cd "${0:A:h}/.."

seconds="${1:-20}"
lag="${2:-0,0,0}"
logs="${TMPDIR:-/tmp}/boxing-net-smoke"
mkdir -p "$logs"

flags=(--short-rounds --auto-rematch --lag="$lag")
godot --headless -- --host --ai=hard "${flags[@]}" --test-seconds=$((seconds + 3)) > "$logs/host.log" 2>&1 &
host_pid=$!
sleep 1
godot --headless -- --join=127.0.0.1 --ai=normal "${flags[@]}" --test-seconds="$seconds" > "$logs/client.log" 2>&1
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
