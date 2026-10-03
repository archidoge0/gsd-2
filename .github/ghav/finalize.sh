#!/usr/bin/env bash
# GHAV trace finalizer: run as the first `if: always()` step after the traced steps.
# Records the processes that are still alive under each step's strace, stops them as the runner
# would at job end, and waits for every strace to flush and exit.
set -u
root="${GHAV_TRACE_DIR:-$HOME/ghav-trace}"
for d in "$root"/*/; do
  spid="$(cat "$d/strace.pid" 2>/dev/null)" || continue
  kill -0 "$spid" 2>/dev/null || continue
  ps -o pid=,ppid=,etimes=,args= -s "$spid" | awk -v s="$spid" '$1 != s' > "$d/survivors-at-job-end.txt"
  echo "$(basename "$d"): $(wc -l < "$d/survivors-at-job-end.txt") survivor(s)"
  for p in $(ps -o pid= -s "$spid"); do [ "$p" != "$spid" ] && kill -TERM "$p" 2>/dev/null; done
done
sleep 5
for d in "$root"/*/; do
  spid="$(cat "$d/strace.pid" 2>/dev/null)" || continue
  for p in $(ps -o pid= -s "$spid" 2>/dev/null); do [ "$p" != "$spid" ] && kill -KILL "$p" 2>/dev/null; done
  for _ in $(seq 30); do kill -0 "$spid" 2>/dev/null || break; sleep 1; done
  kill -0 "$spid" 2>/dev/null && kill -INT "$spid" 2>/dev/null
done
exit 0
