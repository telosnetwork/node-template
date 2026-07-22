#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary="$(mktemp -d)"

cleanup() {
  if [[ -r "$temporary/nodeos.pid" ]]; then
    pid="$(sed -n '1p' "$temporary/nodeos.pid")"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      kill -INT "$pid" 2>/dev/null || true
    fi
  fi
  rm -rf "$temporary"
}
trap cleanup EXIT

cp "$ROOT/start.sh" "$ROOT/stop.sh" "$temporary/"

cat > "$temporary/fake-nodeos" <<'SCRIPT'
#!/usr/bin/env python3
import signal
import time

signal.signal(signal.SIGINT, lambda _signum, _frame: raise_exit())
signal.signal(signal.SIGTERM, lambda _signum, _frame: raise_exit())


def raise_exit():
    raise SystemExit(0)


while True:
    time.sleep(1)
SCRIPT
chmod +x "$temporary/fake-nodeos"

cat > "$temporary/node_config" <<EOF
NODEOS_BIN="$temporary/fake-nodeos"
CONFIG_DIR="$temporary"
DATA_DIR="$temporary/data"
LOCALIZE_LOG=true
LOG_DIR="$temporary/logs"
SHUTDOWN_TIMEOUT=5
ALLOW_STALE_PRODUCTION=false
EOF

printf '%s\n' 'enable-stale-production = yes' > "$temporary/config.ini"
if "$temporary/start.sh" >"$temporary/stale.out" 2>&1; then
  echo "ERROR: runner accepted enable-stale-production = yes" >&2
  exit 1
fi
grep -q 'enable-stale-production is refused' "$temporary/stale.out"

printf '%s\n' '# safe fake config' > "$temporary/config.ini"
if "$temporary/start.sh" -e >"$temporary/short.out" 2>&1; then
  echo "ERROR: runner accepted -e" >&2
  exit 1
fi
grep -q -- '--enable-stale-production is refused' "$temporary/short.out"

printf '%s\n' 'enable-stale-production = yes' > "$temporary/unsafe.ini"
if "$temporary/start.sh" --config unsafe.ini >"$temporary/config-override.out" 2>&1; then
  echo "ERROR: runner accepted --config override" >&2
  exit 1
fi
grep -q 'unsupported command-line override' "$temporary/config-override.out"

"$temporary/start.sh" >/dev/null
[[ "$(wc -l < "$temporary/nodeos.pid" | tr -d '[:space:]')" == "4" ]]

if "$temporary/start.sh" >"$temporary/duplicate.out" 2>&1; then
  echo "ERROR: runner accepted a duplicate start" >&2
  exit 1
fi
grep -q 'already appears to be running' "$temporary/duplicate.out"

"$temporary/stop.sh" >/dev/null
[[ ! -e "$temporary/nodeos.pid" ]]

echo "runner lifecycle tests passed"
