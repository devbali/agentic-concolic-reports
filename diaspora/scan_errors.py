#!/usr/bin/env python3
import json, os, glob, collections

ROOT = os.path.expanduser("~/project/reports/diaspora/results")
DUMPS = "dump_*.json"

def main():
    batches = sorted([d for d in os.listdir(ROOT) if os.path.isdir(os.path.join(ROOT,d))])
    grand = collections.Counter()
    per_batch = {}
    error_detail = collections.defaultdict(list)  # (batch,ep) -> detail
    for b in batches:
        bdir = os.path.join(ROOT, b)
        epc = collections.Counter()
        for ep in sorted(os.listdir(bdir)):
            epdir = os.path.join(bdir, ep)
            if not os.path.isdir(epdir):
                continue
            dumps = sorted(glob.glob(os.path.join(epdir, DUMPS)))
            # take the newest dump (highest r index)
            if not dumps:
                continue
            newest = dumps[-1]
            try:
                data = json.load(open(newest))
            except Exception as e:
                epc["JSON_ERROR"] += 1
                grand["JSON_ERROR"] += 1
                continue
            err = data.get("error")
            if err is None:
                etype = "NONE"
            else:
                etype = err.get("type", "UNKNOWN")
                if etype == "NoMethodError":
                    msg = str(err.get("message",""))
                    # try to tag the method
                    tb = err.get("traceback") or []
                    frame = ""
                    for line in tb:
                        if " " in line and "." in line:
                            frame = line
                            break
                    error_detail[(b,ep)].append((etype, msg[:90], frame[:90]))
            epc[etype] += 1
            grand[etype] += 1
        per_batch[b] = epc
    print("===== GRAND TOTAL (newest dump per entrypoint) =====")
    for k,v in grand.most_common():
        print(f"  {k}: {v}")
    print()
    print("===== PER BATCH =====")
    for b in batches:
        c = per_batch.get(b, collections.Counter())
        if not c: continue
        eps = sum(c.values())
        print(f"{b}: {eps} eps, " + ", ".join(f"{k}={v}" for k,v in c.most_common()))
    print()
    print("===== NoMethodError DETAIL =====")
    for (b,ep),l in sorted(error_detail.items()):
        for etype,msg,frame in l:
            print(f"{b}/{ep} :: {msg} :: {frame}")

if __name__ == "__main__":
    main()
