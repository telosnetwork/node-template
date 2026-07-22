#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for command_name in nodeos cleos spring-util timeout; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: required command is missing: $command_name" >&2
    exit 1
  fi
done

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

k1_output="$(cleos create key --to-console)"
k1_private="$(printf '%s\n' "$k1_output" | sed -n 's/^Private key: //p')"
k1_public="$(printf '%s\n' "$k1_output" | sed -n 's/^Public key: //p')"

bls_file="$temporary/bls.txt"
spring-util bls create key --file "$bls_file" >/dev/null
bls_private="$(sed -n 's/^Private key: //p' "$bls_file")"
bls_public="$(sed -n 's/^Public key: //p' "$bls_file")"

replace_placeholders() {
  local config=$1
  local finalizers_dir=$2
  local protocol_features_dir=$3
  sed -i \
    -e 's|<PRIVATE_PRODUCER_IP>|127.0.0.1|g' \
    -e 's|<PRIVATE_BACKUP_IP>|127.0.0.1|g' \
    -e 's|<PRIVATE_RELAY_A>|127.0.0.1|g' \
    -e 's|<PRIVATE_RELAY_B>|127.0.0.1|g' \
    -e 's|<BP_ACCOUNT>|eosio|g' \
    -e "s|<PUB_K1_BLOCK_KEY>|$k1_public|g" \
    -e "s|<PVT_K1_BLOCK_KEY>|$k1_private|g" \
    -e "s|<PUB_BLS_FINALIZER_KEY>|$bls_public|g" \
    -e "s|<PVT_BLS_FINALIZER_KEY>|$bls_private|g" \
    -e "s|<PUB_BLS_BACKUP_KEY>|$bls_public|g" \
    -e "s|<PVT_BLS_BACKUP_KEY>|$bls_private|g" \
    -e "s|/var/lib/telos/finalizers/[^[:space:]]*|$finalizers_dir|g" \
    -e "s|/var/lib/telos/[^[:space:]]*/protocol_features|$protocol_features_dir|g" \
    -e 's|chain-state-db-size-mb = 32768|chain-state-db-size-mb = 1024|g' \
    "$config"

  if grep -Eq '<[A-Z0-9_]+>|@[A-Z0-9_]+@' "$config"; then
    echo "ERROR: unresolved placeholder in $config" >&2
    exit 1
  fi
}

smoke_one() {
  local network=$1
  local role=$2
  local instance="$network-$role"
  local config_dir="$temporary/config-$instance"
  local data_dir="$temporary/data-$instance"
  local protocol_features_dir="$temporary/protocol-features-$instance"
  local log="$temporary/$instance.log"
  mkdir -p "$config_dir" "$data_dir" "$temporary/finalizers-$instance" "$protocol_features_dir"

  "$ROOT/scripts/render-config.sh" \
    "$network" "$role" "$instance" "$config_dir/config.ini" >/dev/null
  replace_placeholders \
    "$config_dir/config.ini" \
    "$temporary/finalizers-$instance" \
    "$protocol_features_dir"
  cp "$ROOT/logging.json" "$config_dir/logging.json"

  set +e
  timeout --kill-after=5s --signal=INT 5s nodeos \
    --config-dir "$config_dir" \
    --data-dir "$data_dir" \
    --genesis-json "$ROOT/$network/genesis.json" \
    >"$log" 2>&1
  exit_code=$?
  set -e

  if [[ $exit_code -ne 0 && $exit_code -ne 124 && $exit_code -ne 130 ]]; then
    echo "ERROR: nodeos smoke failed for $network/$role (exit $exit_code)" >&2
    cat "$log" >&2
    exit 1
  fi
  if ! grep -Eq 'Blockchain started|nodeos using configuration file' "$log"; then
    echo "ERROR: nodeos did not finish parsing $network/$role" >&2
    cat "$log" >&2
    exit 1
  fi
  echo "nodeos accepted $network/$role"
}

for network in mainnet testnet; do
  for role in producer backup-producer vote-relay api ship; do
    smoke_one "$network" "$role"
  done
done
