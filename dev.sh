#!/bin/bash
# Headless dev harness driver. Usage:
#   ./dev.sh start            launch STICKWARS.app in --dev mode (no window, no menu icon)
#   ./dev.sh "fake" "play" "step 120" "snap lines"   run commands, print results
#   ./dev.sh stop
set -euo pipefail
PIDFILE=/tmp/stickwars-dev.pid
OUT=/tmp/stickwars-out.txt
case "${1:-}" in
start)
    [ -f $PIDFILE ] && kill -USR2 "$(cat $PIDFILE)" 2>/dev/null && sleep 0.5 || true
    rm -f $OUT
    "$(dirname "$0")/STICKWARS.app/Contents/MacOS/STICKWARS" --dev ${DEV_ARGS:-} >/tmp/stickwars-dev.log 2>&1 &
    echo $! > $PIDFILE
    for _ in $(seq 50); do grep -q READY $OUT 2>/dev/null && break; sleep 0.1; done
    cat $OUT ;;
stop)
    kill -USR2 "$(cat $PIDFILE)" 2>/dev/null || true; rm -f $PIDFILE ;;
*)
    printf '%s\n' "$@" > /tmp/stickwars-cmd.txt
    rm -f $OUT
    kill -USR1 "$(cat $PIDFILE)"
    for _ in $(seq 12000); do grep -q '^DONE' $OUT 2>/dev/null && break; sleep 0.05; done
    cat $OUT ;;
esac
