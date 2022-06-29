#!/bin/bash

INSTALL_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $INSTALL_ROOT/node_config

LOG_NAME="$(basename $INSTALL_ROOT)"
if [[ "$LOCALIZE_LOG" == "true" ]]; then
  LOG_PATH="$INSTALL_ROOT/$LOG_NAME.log"
else
  LOG_PATH="/var/log/nodeos/$LOG_NAME.log"
fi

nohup $NODEOS_BIN --disable-replay-opts --data-dir $INSTALL_ROOT/data --config-dir $INSTALL_ROOT "$@" >> "$LOG_PATH" 2>&1 &
PID="$!"
echo "nodeos started with pid $PID"
echo $PID > $INSTALL_ROOT/nodeos.pid
command -v taskset >/dev/null 2>&1 && taskset -cp $CPU $PID && echo "taskset called..."
command -v schedtool >/dev/null 2>&1 && schedtool -B $PID && echo "schedtool called..."
