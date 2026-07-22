#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash -n start.sh stop.sh scripts/render-config.sh scripts/validate.sh
tests/test-runner.sh
python3 -m py_compile scripts/peer_utils.py scripts/update-peers.py scripts/validate_templates.py
python3 scripts/validate_templates.py
PYTHONOPTIMIZE=1 python3 scripts/validate_templates.py
python3 -m unittest discover -s tests -p 'test_*.py'

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

for network in mainnet testnet; do
  expected_chain_id="$(tr -d '[:space:]' < "$network/chain-id.txt")"
  for role in producer backup-producer vote-relay api ship; do
    instance="$network-$role"
    output="$temporary/$network-$role.ini"
    scripts/render-config.sh "$network" "$role" "$instance" "$output" >/dev/null
    grep -q "^# $expected_chain_id$" "$output"
    if grep -q '^chain-id[[:space:]]*=' "$output"; then
      echo "ERROR: unsupported chain-id option in $output" >&2
      exit 1
    fi
    if [[ "$role" == producer || "$role" == backup-producer ]]; then
      grep -q "^finalizers-dir = /var/lib/telos/finalizers/$instance$" "$output"
    fi
  done
done

echo "all validations passed"
