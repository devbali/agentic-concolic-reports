#!/usr/bin/env python3
"""P16 / §79 — the ACTIVE PROBE's verdict.

Reads every dump the P16P drive wrote and answers, per probe run:
  * did the run make both call 2 and call 3 of Anonymous.process@264?
  * did they receive DIFFERENT messages?          <- the split we hunt
  * were both `(... == '')` decisions recorded?
  * did they DISAGREE?                            <- the refutation

VERDICT
  REFUTED : >=1 run decides both and they disagree.
  PASS    : the search ran, the interventions took (probe runs land on outcome
            profiles / grouping signatures the bases did not have), and no run
            splits the pair.
  NOT-TESTABLE : the interventions never took (a dead knob) — never a PASS.
"""
import json, os, re, glob, hashlib, collections
from multiprocessing import Pool

B = os.path.dirname(os.path.abspath(__file__))
ORD = re.compile(r"SYM_RESULT_Anonymous_process_(\d+)")
PCRE = re.compile(r"^\(SYM_RESULT_Anonymous_process_(\d+) == ''\)$")


def one(path):
    try:
        d = json.load(open(path))
    except Exception as e:
        return ("ERR", os.path.basename(path), str(e)[:60])
    calls, msgs = {}, {}
    for ev in d.get("events") or ():
        if ev.get("type") == "symbolic_call" and ev.get("target") == "Anonymous.process":
            m = ORD.fullmatch(str(ev.get("result_name") or ""))
            if m:
                a = json.dumps(ev.get("args"), sort_keys=True, default=str)
                calls[int(m.group(1))] = hashlib.blake2b(a.encode(), digest_size=6).hexdigest()
                msgs[int(m.group(1))] = str(ev.get("args", {}).get("message"))[:40]
    dec = {}
    for ev in d.get("events") or ():
        if ev.get("type") == "path_condition":
            m = PCRE.match(str(ev.get("expr") or ""))
            if m:
                dec.setdefault(int(m.group(1)), set()).add(bool(ev.get("taken")))
    g = collections.defaultdict(list)
    for o, dg in calls.items():
        g[dg].append(o)
    sig = "|".join(",".join(str(x) for x in sorted(v))
                   for v in sorted(g.values(), key=lambda v: min(v)))
    prof = hashlib.blake2b(";".join(sorted(
        f"{ev.get('expr')}:{int(bool(ev.get('taken')))}"
        for ev in d.get("events") or () if ev.get("type") == "path_condition"
    )).encode(), digest_size=8).hexdigest()
    return ("OK", os.path.basename(path), sig,
            {k: sorted(v) for k, v in dec.items()},
            calls.get(2), calls.get(3), msgs.get(2), msgs.get(3), prof)


def main():
    paths = sorted(glob.glob(os.path.join(B, "dump_*P16P*.json")))
    print(f"{len(paths)} probe dumps", flush=True)
    sigs = collections.Counter(); decs = collections.Counter()
    joint = collections.Counter(); profs = set()
    split_called, split_decided = [], []
    both_called = 0
    err = []
    with Pool(4) as pool:
        for r in pool.imap_unordered(one, paths, chunksize=100):
            if r[0] == "ERR":
                err.append(r[1:]); continue
            _, name, sig, dec, c2, c3, m2, m3, prof = r
            sigs[sig] += 1
            decs[",".join(str(x) for x in sorted(dec))] += 1
            profs.add(prof)
            if c2 is not None and c3 is not None:
                both_called += 1
                if c2 != c3:
                    split_called.append({"dump": name, "sig": sig, "m2": m2, "m3": m3})
            if 2 in dec and 3 in dec:
                def s(x):
                    return "BOTH" if len(x) > 1 else x[0]
                joint[f"{s(dec[2])}|{s(dec[3])}"] += 1
                if c2 != c3:
                    split_decided.append({"dump": name, "sig": sig, "m2": m2, "m3": m3,
                                          "dec": {str(k): v for k, v in dec.items()}})
                elif s(dec[2]) != s(dec[3]):
                    split_decided.append({"dump": name, "sig": sig, "OUTCOMES_DIFFER": True,
                                          "dec": {str(k): v for k, v in dec.items()}})
    # did the interventions take? compare against the bases' own signatures
    base_sigs = set()
    try:
        prev = json.load(open(os.path.join(B, "_p16_render_scan3.json")))
        base_sigs = set(prev["grouping_signature"])
    except Exception:
        pass
    out = {
        "probe_dumps": len(paths), "errors": err[:5],
        "distinct_outcome_profiles_produced": len(profs),
        "grouping_signatures": dict(sigs.most_common(20)),
        "new_grouping_signatures": sorted(set(sigs) - base_sigs),
        "decided_sets": dict(decs.most_common(10)),
        "joint_23_outcomes": dict(joint),
        "runs_with_both_calls": both_called,
        "runs_where_2_and_3_GOT_DIFFERENT_MESSAGES": len(split_called),
        "examples_split_called": split_called[:10],
        "runs_where_BOTH_DECIDED_AND_SPLIT": len(split_decided),
        "examples_split_decided": split_decided[:10],
    }
    refuted = len(split_decided) > 0
    took = (len(profs) > 1)
    out["verdict"] = ("REFUTED" if refuted else ("PASS" if took else "NOT-TESTABLE"))
    json.dump(out, open(os.path.join(B, "_p16_probe_explain.json"), "w"), indent=1)
    print(json.dumps(out, indent=1)[:4000])
    print(f"P16-PROBE-VERDICT {out['verdict']}")


if __name__ == "__main__":
    main()
