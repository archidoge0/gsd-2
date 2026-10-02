#!/usr/bin/env bash
# GHAV tracing shell: runs one GitHub Actions `run` step under strace.
# Used as `shell: bash <this file> {0}`.
#
# `strace -f` exits only when every traced descendant has exited, so a step that
# leaves a background process running would block here although GitHub would
# continue. We therefore wait for the step script itself, record the processes
# that are still alive (they outlive the step and are part of its effect), and
# then detach strace so that they keep running untraced, as they would on GitHub.
# Plain ptrace (no --seccomp-bpf): a seccomp-filtered process would get ENOSYS
# from filtered syscalls after the tracer detaches.
set -u
script="$1"
root="${GHAV_TRACE_DIR:-$HOME/ghav-trace}"
dir="$root/${GHAV_STEP:-${GITHUB_ACTION:-step}}"
mkdir -p "$dir"
printf '%s\n' "$PWD" > "$dir/cwd"
date +%s.%N > "$dir/start"
status="$dir/status"
rm -f "$status"
opts=(-f -ff -qq -ttt -y -s 4096 -e trace=%file,%process,getdents64,getdents,fchdir -o "$dir/t")
strace "${opts[@]}" bash -c 'bash --noprofile --norc -eo pipefail "$1"; echo $? > "$2"' _ "$script" "$status" &
spid=$!
while [ ! -s "$status" ] && kill -0 "$spid" 2>/dev/null; do sleep 1; done
if kill -0 "$spid" 2>/dev/null; then
  date +%s.%N > "$dir/detached-at"
  ps -eo pid,ppid,pgid,etimes,args --forest > "$dir/survivors.txt"
  kill -INT "$spid"
fi
wait "$spid" 2>/dev/null
exit "$(cat "$status" 2>/dev/null || echo 1)"
