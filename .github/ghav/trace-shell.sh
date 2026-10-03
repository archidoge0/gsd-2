#!/usr/bin/env bash
# GHAV tracing shell v5: runs one GitHub Actions `run` step under strace.
# Used as `shell: bash <this file> {0}`.
#
# - strace runs unprivileged with --seccomp-bpf: plain ptrace slowed tests enough to time out.
# - strace runs in its own session with its output in a file, so it never holds the step's pipes.
#   The step's output is streamed from that file.
# - The wrapper returns when the step script itself ends. It does not detach strace (detaching a
#   seccomp-filtered process makes its filtered syscalls fail with ENOSYS). Processes that outlive
#   the step stay traced into this step's directory, so their effects are charged to the step that
#   started them. finalize.sh stops them at job end, as the runner would.
set -u
script="$1"
here="$(cd "$(dirname "$0")" && pwd)"
root="${GHAV_TRACE_DIR:-$HOME/ghav-trace}"
dir="$root/${GHAV_STEP:-${GITHUB_ACTION:-step}}"
mkdir -p "$dir"
printf '%s\n' "$PWD" > "$dir/cwd"
env -0 > "$dir/env0"
date +%s.%N > "$dir/start"
status="$dir/status"
log="$dir/output.log"
rm -f "$status"
: > "$log"
opts=(--seccomp-bpf -f -ff -qq -ttt -y -s 4096 -e verbose=execve
      -e trace=%file,%process,%network,getdents64,getdents,fchdir -o "$dir/t")
setsid strace "${opts[@]}" bash -c 'bash --noprofile --norc -eo pipefail "$1"; echo $? > "$2"' \
  _ "$script" "$status" < /dev/null > "$log" 2>&1 &
spid=$!
echo "$spid" > "$dir/strace.pid"
tail -n +1 -F "$log" 2>/dev/null &
tpid=$!
while [ ! -s "$status" ] && kill -0 "$spid" 2>/dev/null; do sleep 1; done
date +%s.%N > "$dir/end"
sleep 1
kill "$tpid" 2>/dev/null
wait "$tpid" 2>/dev/null
# Processes of this step that are still alive (strace itself excluded).
ps -o pid=,ppid=,etimes=,args= -s "$spid" 2>/dev/null | awk -v s="$spid" '$1 != s' > "$dir/survivors-at-step-end.txt"
if [ -s "$dir/survivors-at-step-end.txt" ]; then
  echo "::notice title=ghav trace::$(wc -l < "$dir/survivors-at-step-end.txt") process(es) outlive step ${GHAV_STEP:-}; still traced"
fi
python3 "$here/step_digest.py" "$dir" || echo "ghav: step_digest failed"
exit "$(cat "$status" 2>/dev/null || echo 1)"
