#!/bin/bash

INSTALL_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. $INSTALL_ROOT/node_config

LOG_NAME="$(basename $INSTALL_ROOT)"
nohup $NODEOS_BIN --disable-replay-opts --data-dir $INSTALL_ROOT/data --config-dir $INSTALL_ROOT "$@" >> "/var/log/nodeos/$LOG_NAME.log" 2>&1 &
PID="$!"
echo "nodeos started with pid $PID"
echo $PID > $INSTALL_ROOT/nodeos.pid
taskset -cp $CPU $PID && schedtool -B $PID
