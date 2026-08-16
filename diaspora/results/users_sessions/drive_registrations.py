#!/usr/bin/env python3
"""Supervisor for the crash-isolated registrations#create DSE.

registrations#create aborts the JVM from native FFI code (SIGSEGV inside
JRuby's string marshalling), which `rescue Exception` cannot catch. This driver
runs run_registrations_isolated.rb in a child process; that child keeps all
worklist state in WORK_DIR/state.json and fsyncs it after every execution.

When the child dies, the driver reads WORK_DIR/current_seed.json — the seed set
that was in flight — marks exactly that one seed poisoned (with the child's exit
signal and log tail), and restarts. The search therefore continues past a crash
instead of stopping at it, and every poisoned seed is recorded rather than
silently skipped.

Usage:
    python3 reports/diaspora/results/users_sessions/drive_registrations.py [--max-restarts N]

Env passthrough: EP_NAME, OUT_DIR, MAX_RUNS, PROC_MAX_RUNS.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = os.path.join(HERE, "run_registrations_isolated.rb")
SLOT = "/home/dev/.claude/jobs/ac135b2a/tmp/concolic-slot"
FALLBACK = "/home/dev/project/scripts/diaspora-concolic"


def load(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work-dir", default=os.path.join(HERE, ".registrations_work"))
    ap.add_argument("--max-restarts", type=int, default=60)
    ap.add_argument("--fresh", action="store_true", help="discard existing state")
    args = ap.parse_args()

    work = args.work_dir
    if args.fresh and os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(work, exist_ok=True)

    launcher = SLOT if os.path.exists(SLOT) else FALLBACK
    env = dict(os.environ, WORK_DIR=work)
    state_path = os.path.join(work, "state.json")
    current_path = os.path.join(work, "current_seed.json")
    logdir = os.path.join(work, "logs")
    os.makedirs(logdir, exist_ok=True)

    crashes = []
    for attempt in range(1, args.max_restarts + 1):
        logpath = os.path.join(logdir, "boot%03d.log" % attempt)
        t0 = time.time()
        with open(logpath, "w") as log:
            rc = subprocess.call([launcher, RUNNER], env=env,
                                 stdout=log, stderr=subprocess.STDOUT)
        dt = time.time() - t0
        st = load(state_path, {}) or {}
        print("boot %-3d rc=%-4d %6.1fs  runs=%-4s written=%-4s stack=%-4s poisoned=%-3s"
              % (attempt, rc, dt, st.get("runs"), st.get("written"),
                 len(st.get("stack", [])), len(st.get("poisoned", []))), flush=True)

        if rc == 0:
            if st.get("worklist_exhausted"):
                print("DRAINED after %d boot(s)" % attempt)
            else:
                print("stopped: %s" % st.get("stop_reason"))
            break

        # Child died. Attribute the crash to the in-flight seed set.
        cur = load(current_path)
        if cur is None:
            print("  child died with no in-flight seed (rc=%d) — aborting" % rc)
            with open(logpath) as f:
                print("  log tail:", f.read()[-600:])
            break

        tail = ""
        try:
            with open(logpath) as f:
                tail = f.read()[-400:]
        except Exception:
            pass
        # Recompute the seed key exactly as the Ruby side does: MD5 of the
        # JSON of the seed hash sorted by key.
        import hashlib
        seed = cur["seed"]
        canon = json.dumps(dict(sorted(seed.items())), separators=(",", ":"))
        # Ruby's JSON.generate on a Hash uses {"k":v} with no spaces — match it.
        key = hashlib.md5(canon.encode()).hexdigest()

        st.setdefault("poisoned", []).append({
            "key": key,
            "label": cur.get("label"),
            "seed": seed,
            "exit_code": rc,
            "signal": -rc if rc < 0 else None,
            "log": logpath,
            "log_tail": tail,
        })
        crashes.append(cur.get("label"))
        with open(state_path, "w") as f:
            json.dump(st, f)
        os.remove(current_path)
        print("  POISONED %s (rc=%d) seed=%s" % (cur.get("label"), rc,
                                                 json.dumps(seed)[:120]), flush=True)
    else:
        print("hit --max-restarts=%d" % args.max_restarts)

    st = load(state_path, {}) or {}
    print("\n=== final ===")
    print("runs=%s written=%s drained=%s stop=%s poisoned=%d crashes=%s"
          % (st.get("runs"), st.get("written"), st.get("worklist_exhausted"),
             st.get("stop_reason"), len(st.get("poisoned", [])), crashes))
    print("errors:", json.dumps(st.get("errors", {})))
    print("unflippable:", json.dumps(st.get("unflippable", {})))
    return 0


if __name__ == "__main__":
    sys.exit(main())
