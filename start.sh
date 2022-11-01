#!/bin/bash

INSTALL_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $INSTALL_ROOT/node_config

LOG_NAME="$(basename $INSTALL_ROOT)"
if [[ "$LOCALIZE_LOG" == "true" ]]; then
  LOG_PATH="$INSTALL_ROOT/nodeos.log"
else
  LOG_PATH="/var/log/nodeos/$LOG_NAME.log"
fi

if [[ "$DATA_DIR" != "" ]]; then
  DATA_DIR_PATH=$DATA_DIR
else
  DATA_DIR_PATH=$INSTALL_ROOT/data
fi

nohup $NODEOS_BIN --disable-replay-opts --data-dir $DATA_DIR_PATH --config-dir $INSTALL_ROOT "$@" >> "$LOG_PATH" 2>&1 &
PID="$!"
echo "nodeos started with pid $PID"
echo $PID > $INSTALL_ROOT/nodeos.pid

if [[ "$PIN_CPU" == "true" ]]; then
  command -v taskset >/dev/null 2>&1 && taskset -cp $CPU $PID && echo "taskset called..."
  command -v schedtool >/dev/null 2>&1 && schedtool -B $PID && echo "schedtool called..."
fi
