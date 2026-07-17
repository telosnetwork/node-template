#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=node_config
source "$INSTALL_ROOT/node_config"

CONFIG_DIR_PATH="${CONFIG_DIR:-$INSTALL_ROOT}"
DATA_DIR_PATH="${DATA_DIR:-$INSTALL_ROOT/data}"
PID_FILE="$INSTALL_ROOT/nodeos.pid"
CONFIG_FILE="$CONFIG_DIR_PATH/config.ini"
LOCK_DIR="$INSTALL_ROOT/.nodeos-start.lock"

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

umask 027
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: another start is in progress (or stale lock: $LOCK_DIR)" >&2
  exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

if [[ ! -x "$NODEOS_BIN" ]]; then
  echo "ERROR: nodeos is not executable at $NODEOS_BIN" >&2
  exit 1
fi

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "ERROR: config file is not readable: $CONFIG_FILE" >&2
  exit 1
fi

if grep -Eq '<[A-Z0-9_]+>|@[A-Z0-9_]+@' "$CONFIG_FILE"; then
  echo "ERROR: $CONFIG_FILE still contains template placeholders" >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*enable-stale-production[[:space:]]*=' "$CONFIG_FILE" \
    && [[ "$ALLOW_STALE_PRODUCTION" != "true" ]]; then
  echo "ERROR: enable-stale-production is refused for production networks" >&2
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  existing_pid="$(sed -n '1p' "$PID_FILE" | tr -d '[:space:]')"
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && process_is_live "$existing_pid"; then
    echo "ERROR: nodeos already appears to be running with pid $existing_pid" >&2
    exit 1
  fi
  rm -f "$PID_FILE"
fi

extra_args=("$@")
for ((index = 0; index < ${#extra_args[@]}; index++)); do
  arg=${extra_args[index]}
  case "$arg" in
    -e|--enable-stale-production|--enable-stale-production=*)
      if [[ "$ALLOW_STALE_PRODUCTION" != "true" ]]; then
        echo "ERROR: --enable-stale-production is refused for production networks" >&2
        exit 1
      fi
      ;;
    --snapshot|--genesis-json|--truncate-at-block|--terminate-at-block|--extract-genesis-json)
      index=$((index + 1))
      if ((index >= ${#extra_args[@]})); then
        echo "ERROR: $arg requires a value" >&2
        exit 2
      fi
      ;;
    --snapshot=*|--genesis-json=*|--truncate-at-block=*|--terminate-at-block=*|--extract-genesis-json=*)
      ;;
    --replay-blockchain|--hard-replay-blockchain|--delete-all-blocks|--fix-reversible-blocks|--force-all-checks|--disable-replay-opts|--print-genesis-json)
      ;;
    *)
      echo "ERROR: unsupported command-line override: $arg; use the reviewed config.ini" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$DATA_DIR_PATH"
LOG_NAME="$(basename "$INSTALL_ROOT")"
if [[ "$LOCALIZE_LOG" == "true" ]]; then
  LOG_PATH="$INSTALL_ROOT/nodeos.log"
else
  mkdir -p "$LOG_DIR"
  LOG_PATH="$LOG_DIR/$LOG_NAME.log"
fi

command=(
  "$NODEOS_BIN"
  --data-dir "$DATA_DIR_PATH"
  --config-dir "$CONFIG_DIR_PATH"
)
if ((${#extra_args[@]})); then
  command+=("${extra_args[@]}")
fi

nohup "${command[@]}" >> "$LOG_PATH" 2>&1 &
pid=$!

sleep 1
if ! process_is_live "$pid"; then
  echo "ERROR: nodeos exited during startup; inspect $LOG_PATH" >&2
  exit 1
fi

if [[ -r "/proc/$pid/stat" ]]; then
  process_start="$(awk '{print $22}' "/proc/$pid/stat")"
else
  process_start="$(ps -p "$pid" -o lstart= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
resolved_nodeos="$(realpath "$NODEOS_BIN" 2>/dev/null || printf '%s' "$NODEOS_BIN")"
resolved_config="$(realpath "$CONFIG_DIR_PATH" 2>/dev/null || printf '%s' "$CONFIG_DIR_PATH")"
printf '%s\n%s\n%s\n%s\n' \
  "$pid" "$process_start" "$resolved_nodeos" "$resolved_config" > "$PID_FILE"

echo "nodeos started with pid $pid; log: $LOG_PATH"
