#!/usr/bin/env python3
"""P16 / §79 part 2 — do ANY two calls of Anonymous.process@264 in ONE run
ever receive DIFFERENT arguments? (§78.9 said 433/1500 sampled runs had
"different args"; this measures it over the whole corpus, per ordinal pair.)"""
import json, os, re, glob, hashlib, collections
from multiprocessing import Pool
B = os.path.dirname(os.path.abspath(__file__))
ORD = re.compile(r"SYM_RESULT_Anonymous_process_(\d+)")

def one(path):
    try:
        d = json.load(open(path))
    except Exception:
        return None
    calls = {}
    for ev in d.get("events") or ():
        if ev.get("type") == "symbolic_call" and ev.get("target") == "Anonymous.process":
            m = ORD.fullmatch(str(ev.get("result_name") or ""))
            if m:
                a = json.dumps(ev.get("args"), sort_keys=True, default=str)
                calls[int(m.group(1))] = (hashlib.blake2b(a.encode(), digest_size=8).hexdigest(),
                                          str(ev.get("args", {}).get("message"))[:60])
    if not calls:
        return ("none",)
    digs = {v[0] for v in calls.values()}
    return ("ok", len(calls), len(digs), tuple(sorted(calls)),
            sorted({v[1] for v in calls.values()})[0], os.path.basename(path) if len(digs) > 1 else "")

def main():
    paths = sorted(glob.glob(os.path.join(B, "dump_*.json")))
    c_ndist = collections.Counter(); c_ords = collections.Counter()
    msgs = collections.Counter(); split = []
    n = 0
    with Pool(4) as pool:
        for r in pool.imap_unordered(one, paths, chunksize=200):
            if not r or r[0] != "ok":
                continue
            n += 1
            c_ndist[(r[1], r[2])] += 1
            c_ords[r[3]] += 1
            msgs[r[4]] += 1
            if r[2] > 1 and len(split) < 20:
                split.append(r[5])
    out = {"runs_with_calls": n,
           "(#calls,#distinct_args)": {str(k): v for k, v in c_ndist.most_common()},
           "ordinal_sets": {str(k): v for k, v in c_ords.most_common(10)},
           "messages": dict(msgs.most_common(10)),
           "runs_with_two_different_args": split}
    json.dump(out, open(os.path.join(B, "_p16_render_scan2.json"), "w"), indent=1)
    print(json.dumps(out, indent=1)[:3000])
    print("P16-SCAN2-DONE")

if __name__ == "__main__":
    main()
