#!/bin/bash
# go.sh <outname> <run.mjs args...> : detached build run; watch <outname>/status.log
cd /home/tomas/.claude/jobs/d3b140b3/tmp/bench
name=$1; shift

mkdir -p /tmp/dd-bench-d3b140b3; setsid nohup node run.mjs "/tmp/dd-bench-d3b140b3/$name" "$@" > "$name.out" 2>&1 < /dev/null &
echo "started $name pid $!"
