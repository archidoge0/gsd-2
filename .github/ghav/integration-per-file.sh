#!/usr/bin/env bash
# Trace `npm run test:integration` one test file at a time, so that a file that
# hangs under ptrace cannot block the others. Each file gets its own trace
# directory (integration-NNN); manifest.tsv maps directories to files and
# records the traced exit code, and the untraced exit code when the traced run
# timed out.
set -u
root="${GHAV_TRACE_DIR:-$HOME/ghav-trace}"
mkdir -p "$root"
export PATH="$PWD/node_modules/.bin:$PATH"
prefix=(node --import ./src/resources/extensions/gsd/tests/resolve-ts.mjs --experimental-strip-types --test)
opts=(-f -ff -qq -ttt -y -s 4096 -e trace=%file,%process,getdents64,getdents,fchdir)
manifest="$root/integration-manifest.tsv"
printf 'dir\tfile\ttraced_exit\tseconds\tuntraced_exit\n' > "$manifest"
n=0
fail=0
for f in src/tests/integration/*.test.ts src/resources/extensions/gsd/tests/integration/*.test.ts \
         src/resources/extensions/async-jobs/*.test.ts src/resources/extensions/browser-tools/tests/*.test.mjs; do
  n=$((n + 1))
  d=$(printf '%s/integration-%03d' "$root" "$n")
  mkdir -p "$d"
  printf '%s\n' "$PWD" > "$d/cwd"
  date +%s.%N > "$d/start"
  t0=$(date +%s)
  timeout -k 10 300 strace --seccomp-bpf "${opts[@]}" -o "$d/t" "${prefix[@]}" "$f" > "$d/out.log" 2>&1
  rc=$?
  t1=$(date +%s)
  urc=-
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
    timeout -k 10 300 "${prefix[@]}" "$f" > "$d/untraced.log" 2>&1
    urc=$?
  fi
  printf 'integration-%03d\t%s\t%s\t%s\t%s\n' "$n" "$f" "$rc" "$((t1 - t0))" "$urc" >> "$manifest"
  echo "[$n] $f traced=$rc ($((t1 - t0))s) untraced=$urc"
  [ "$rc" = 0 ] || fail=1
done
exit $fail
