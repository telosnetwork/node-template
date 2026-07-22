#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <mainnet|testnet> <producer|backup-producer|vote-relay|api|ship> <instance> <output-file>" >&2
}

if [[ $# -ne 4 ]]; then
  usage
  exit 2
fi

NETWORK=$1
ROLE=$2
INSTANCE=$3
OUTPUT=$4
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$NETWORK" in
  mainnet|testnet) ;;
  *)
    echo "ERROR: unsupported network: $NETWORK" >&2
    usage
    exit 2
    ;;
esac

if [[ ! "$INSTANCE" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]; then
  echo "ERROR: instance must contain only lowercase letters, digits, and hyphens" >&2
  exit 2
fi
if [[ "$INSTANCE" != "$NETWORK"-* ]]; then
  echo "ERROR: instance must start with '$NETWORK-' to keep runtime paths separated" >&2
  exit 2
fi

case "$ROLE" in
  producer|backup-producer|vote-relay|api|ship) ;;
  *)
    echo "ERROR: unsupported role: $ROLE" >&2
    usage
    exit 2
    ;;
esac

PROFILE="$ROOT/profiles/$ROLE.ini.example"
CHAIN_ID_FILE="$ROOT/$NETWORK/chain-id.txt"
PEERS_FILE="$ROOT/$NETWORK/peers.ini"

if [[ -e "$OUTPUT" ]]; then
  echo "ERROR: refusing to overwrite existing file: $OUTPUT" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT")"
if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "ERROR: output directory does not exist: $OUTPUT_DIR" >&2
  exit 1
fi

chain_id="$(tr -d '[:space:]' < "$CHAIN_ID_FILE")"
if [[ ! "$chain_id" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERROR: invalid chain ID in $CHAIN_ID_FILE" >&2
  exit 1
fi

tmp="$(mktemp "$OUTPUT.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
  printf '# Network: %s\n' "$NETWORK"
  printf '# Expected chain ID (verify with get_info; not a nodeos option):\n'
  printf '# %s\n\n' "$chain_id"
  sed -e "s/@NETWORK@/$NETWORK/g" -e "s/@INSTANCE@/$INSTANCE/g" "$PROFILE"
} > "$tmp"

case "$ROLE" in
  producer|backup-producer)
    ;;
  *)
    {
      printf '\n# Verified public peers for %s. Curate for region and diversity.\n' "$NETWORK"
      cat "$PEERS_FILE"
    } >> "$tmp"
    ;;
esac

chmod 0600 "$tmp"
mv "$tmp" "$OUTPUT"
trap - EXIT

echo "Rendered $NETWORK $ROLE template to $OUTPUT"
echo "Replace every <PLACEHOLDER>, review the role, and keep private keys out of Git."
