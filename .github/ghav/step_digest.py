#!/usr/bin/env python3
"""Record sha256 digests of the regular files a traced step wrote, at the end of the step.

Usage: step_digest.py <step trace dir>. Scans the raw strace files of the step for successful
writes (open with a write flag, rename/link targets, creat) and writes <dir>/digests.json:
{path: sha256 | "absent" | "dir" | "skipped:<reason>"}. Time-bounded; truncation is recorded.
"""
import hashlib
import json
import os
import re
import sys
import time

# With -y, a successful open returns "N</absolute/path>".
WRITE = re.compile(r'^\d+\.\d+ (open|openat|openat2|creat)\((.*)\) = \d+<(/[^>]*)>\s*$')
# rename/link: the destination is the last string argument; its base is the decoded dirfd or the step cwd.
RENAME = re.compile(r'^\d+\.\d+ (?:renameat2?|rename|linkat|link)\((.*)\) = 0\s*$')
STR = re.compile(r'(?:(?:AT_FDCWD|\d+)<(/[^>]*)>, )?"((?:[^"\\]|\\.)*)"')
WFLAGS = ("O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_APPEND")
BUDGET_S = float(os.environ.get("GHAV_DIGEST_BUDGET", "120"))
MAX_BYTES = 256 * 1024 * 1024


def main():
    d = sys.argv[1]
    cwd = open(os.path.join(d, "cwd")).read().strip()
    paths = set()
    for name in os.listdir(d):
        if not name.startswith("t."):
            continue
        with open(os.path.join(d, name), errors="replace") as f:
            for line in f:
                m = WRITE.match(line)
                if m:
                    if m.group(1) == "creat" or any(w in m.group(2) for w in WFLAGS):
                        paths.add(os.path.normpath(m.group(3)))
                    continue
                m = RENAME.match(line)
                if m:
                    strs = STR.findall(m.group(1))
                    if strs:
                        base, p = strs[-1]
                        paths.add(os.path.normpath(p if p.startswith("/") else os.path.join(base or cwd, p)))
    out, t0, truncated = {}, time.time(), False
    for p in sorted(paths):
        if p.startswith(("/proc", "/dev", "/sys")):
            continue
        if time.time() - t0 > BUDGET_S:
            truncated = True
            break
        try:
            if os.path.isdir(p):
                out[p] = "dir"
            elif not os.path.exists(p):
                out[p] = "absent"
            elif os.path.getsize(p) > MAX_BYTES:
                out[p] = "skipped:size"
            else:
                h = hashlib.sha256()
                with open(p, "rb") as f:
                    for chunk in iter(lambda: f.read(1 << 20), b""):
                        h.update(chunk)
                out[p] = h.hexdigest()
        except OSError as e:
            out[p] = f"skipped:{e.__class__.__name__}"
    json.dump({"truncated": truncated, "written_paths": len(paths), "digests": out},
              open(os.path.join(d, "digests.json"), "w"))
    print(f"ghav: {len(out)} digests for {len(paths)} written paths" + (" (truncated)" if truncated else ""))


if __name__ == "__main__":
    main()
