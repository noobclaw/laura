#!/bin/sh
# usage: tools/shots.sh name "query" [W H] [extra shot.py args]  -> /tmp/webshots/wip/name.png
mkdir -p /tmp/webshots/wip
n=$1; q=$2; w=${3:-1280}; h=${4:-720}; shift; shift; [ $# -gt 0 ] && shift; [ $# -gt 0 ] && shift
timeout 300 python3 "$(dirname "$0")/shot.py" /tmp/webshots/wip/$n.png "$q" $w $h "$@" 2>&1 | grep -v "GPU stall\|PCFSoft"
