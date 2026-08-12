#!/usr/bin/env python3
import json, os, glob, sys

ROOT = os.path.expanduser("~/project/reports/diaspora/results")
FILTER = sys.argv[1] if len(sys.argv)>1 else "NoMethodError"

def main():
    for b in sorted(os.listdir(ROOT)):
        bdir = os.path.join(ROOT, b)
        if not os.path.isdir(bdir): continue
        for ep in sorted(os.listdir(bdir)):
            epdir = os.path.join(bdir, ep)
            if not os.path.isdir(epdir): continue
            dumps = sorted(glob.glob(os.path.join(epdir, "dump_*.json")))
            if not dumps: continue
            data = json.load(open(dumps[-1]))
            err = data.get("error")
            if err is None: continue
            if err.get("type") != FILTER: continue
            tb = err.get("traceback") or ""
            if isinstance(tb, str):
                lines = [l for l in tb.split("\n") if l.strip()]
            else:
                lines = list(tb)
            print(f"##### {b}/{ep}")
            print("  MSG:", str(err.get("message",""))[:200])
            for line in lines[-8:]:
                print("   ", line[:170])
            print()

if __name__ == "__main__":
    main()
