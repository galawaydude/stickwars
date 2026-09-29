#!/bin/bash
# Headless dev harness driver. Usage:
#   ./dev.sh start            launch STICKTOP.app in --dev mode (no window, no menu icon)
#   ./dev.sh "fake" "play" "step 120" "snap lines"   run commands, print results
#   ./dev.sh stop
set -euo pipefail
PIDFILE=/tmp/sticktop-dev.pid
OUT=/tmp/sticktop-out.txt
case "${1:-}" in
start)
    [ -f $PIDFILE ] && kill -USR2 "$(cat $PIDFILE)" 2>/dev/null && sleep 0.5 || true
    rm -f $OUT
    "$(dirname "$0")/STICKTOP.app/Contents/MacOS/STICKTOP" --dev ${DEV_ARGS:-} >/tmp/sticktop-dev.log 2>&1 &
    echo $! > $PIDFILE
    for _ in $(seq 50); do grep -q READY $OUT 2>/dev/null && break; sleep 0.1; done
    cat $OUT ;;
stop)
    kill -USR2 "$(cat $PIDFILE)" 2>/dev/null || true; rm -f $PIDFILE ;;
*)
    printf '%s\n' "$@" > /tmp/sticktop-cmd.txt
    rm -f $OUT
    kill -USR1 "$(cat $PIDFILE)"
    for _ in $(seq 600); do grep -q '^DONE' $OUT 2>/dev/null && break; sleep 0.05; done
    cat $OUT ;;
esac
