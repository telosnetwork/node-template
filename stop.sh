#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=node_config
source "$INSTALL_ROOT/node_config"

PID_FILE="$INSTALL_ROOT/nodeos.pid"
CONFIG_DIR_PATH="${CONFIG_DIR:-$INSTALL_ROOT}"

process_is_live() {
  local candidate_pid=$1
  if ! kill -0 "$candidate_pid" 2>/dev/null; then
    return 1
  fi
  if [[ -r "/proc/$candidate_pid/stat" ]]; then
    local state
    state="$(awk '{print $3}' "/proc/$candidate_pid/stat")"
    [[ "$state" != "Z" && "$state" != "X" ]]
    return
  fi
  return 0
}

if [[ ! -r "$PID_FILE" ]]; then
  echo "No readable pid file at $PID_FILE"
  exit 0
fi

pid="$(sed -n '1p' "$PID_FILE" | tr -d '[:space:]')"
if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
  echo "ERROR: invalid pid in $PID_FILE" >&2
  exit 1
fi

if ! process_is_live "$pid"; then
  rm -f "$PID_FILE"
  echo "Removed stale pid file; process $pid is not running"
  exit 0
fi

recorded_start="$(sed -n '2p' "$PID_FILE")"
recorded_nodeos="$(sed -n '3p' "$PID_FILE")"
recorded_config="$(sed -n '4p' "$PID_FILE")"

if [[ -r "/proc/$pid/stat" ]]; then
  current_start="$(awk '{print $22}' "/proc/$pid/stat")"
else
  current_start="$(ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
if [[ -n "$recorded_start" && "$current_start" != "$recorded_start" ]]; then
  echo "ERROR: pid $pid was reused by another process; refusing to signal it" >&2
  exit 1
fi

resolved_nodeos="$(realpath "$NODEOS_BIN" 2>/dev/null || printf '%s' "$NODEOS_BIN")"
resolved_config="$(realpath "$CONFIG_DIR_PATH" 2>/dev/null || printf '%s' "$CONFIG_DIR_PATH")"
if [[ -n "$recorded_nodeos" && "$recorded_nodeos" != "$resolved_nodeos" ]]; then
  echo "ERROR: pid file was created for a different nodeos binary" >&2
  exit 1
fi
if [[ -n "$recorded_config" && "$recorded_config" != "$resolved_config" ]]; then
  echo "ERROR: pid file was created for a different config directory" >&2
  exit 1
fi

command_line="$(ps -p "$pid" -o args= 2>/dev/null || true)"
if [[ " $command_line " != *" $NODEOS_BIN "* \
    || "$command_line" != *"--config-dir $CONFIG_DIR_PATH"* ]]; then
  echo "ERROR: pid $pid does not identify the configured nodeos process" >&2
  exit 1
fi

echo "Sending SIGINT to nodeos pid $pid"
kill -INT "$pid"

for ((elapsed = 0; elapsed < SHUTDOWN_TIMEOUT; elapsed++)); do
  if ! process_is_live "$pid"; then
    rm -f "$PID_FILE"
    echo "nodeos stopped cleanly"
    exit 0
  fi
  sleep 1
done

echo "ERROR: nodeos did not stop within ${SHUTDOWN_TIMEOUT}s; inspect it manually" >&2
exit 1
