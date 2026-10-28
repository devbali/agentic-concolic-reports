#!/usr/bin/env python3
"""P16 / §79 — the CORPUS TRIPWIRE for the render-ordinal identity claim.

Claim under test (the ledger entry added 2026-09-12):

    SYM_RESULT_Anonymous_process_2 == SYM_RESULT_Anonymous_process_3

`Anonymous.process` is the wall mock of
Diaspora::MessageRenderer::Processor.process at message_renderer.rb:264. The
claim is that ordinals of THAT ONE STATEMENT are one fact whenever both are
compared, because the mock is a deterministic function of its arguments and
the two sites receive the same arguments.

This scans the WHOLE dump directory (not a sample, not the pruned list — an
argument difference is not part of an outcome profile, so pruning could hide
one) and measures, per run:

  * the ordinals of Anonymous.process seen, their file/lineno/args/result;
  * which ordinals are DECIDED (a path condition over them) and how;
  * the joint outcome of the _2 / _3 decisions;
  * whether the two calls got equal args, in every run that has both calls
    and separately in every run that DECIDES both;
  * determinism of the mock: same args -> same result, per (file, lineno).

Writes `_p16_render_scan.json` (aggregate) and `_p16_render_bases.jsonl`
(one row per run that decides both, for the active probe to pick bases from).
"""
import json, os, re, sys, glob, hashlib, collections
from multiprocessing import Pool

B = os.path.dirname(os.path.abspath(__file__))
ORD = re.compile(r"SYM_RESULT_Anonymous_process_(\d+)")
PCRE = re.compile(r"^\(SYM_RESULT_Anonymous_process_(\d+) == ''\)$")


def one(path):
    try:
        d = json.load(open(path))
    except Exception as e:
        return ("ERR", path, str(e)[:80])
    calls = {}          # ordinal -> (file, lineno, args_digest, args, result)
    for ev in d.get("events") or ():
        if ev.get("type") != "symbolic_call":
            continue
        if ev.get("target") != "Anonymous.process":
            continue
        m = ORD.fullmatch(str(ev.get("result_name") or ""))
        if not m:
            continue
        a = json.dumps(ev.get("args"), sort_keys=True, default=str)
        calls[m.group(1)] = (str(ev.get("file")), ev.get("lineno"),
                             hashlib.blake2b(a.encode(), digest_size=8).hexdigest(),
                             str(ev.get("result_value")))
    dec = {}            # ordinal -> set of taken values
    other = collections.Counter()
    for ev in d.get("events") or ():
        if ev.get("type") != "path_condition":
            continue
        e = str(ev.get("expr") or "")
        if "Anonymous_process" not in e:
            continue
        m = PCRE.match(e)
        if m:
            dec.setdefault(m.group(1), set()).add(bool(ev.get("taken")))
        else:
            other[e] += 1
    return ("OK", os.path.basename(path), calls, {k: sorted(v) for k, v in dec.items()},
            dict(other), d.get("concolic_seeds") or {})


def main():
    paths = sorted(glob.glob(os.path.join(B, "dump_*.json")))
    print(f"scanning {len(paths)} dumps", flush=True)
    agg = {
        "dumps": 0, "errors": [], "dumps_with_process_call": 0,
        "ordinals_seen": collections.Counter(),
        "linenos": collections.Counter(),
        "joint_23": collections.Counter(),      # (out2, out3) over DECIDED
        "decided_sets": collections.Counter(),
        "args_equal_when_both_called": collections.Counter(),
        "args_equal_when_both_decided": collections.Counter(),
        "other_render_exprs": collections.Counter(),
        "det_violations": [],                   # same (file,lineno,args) -> 2 results
        "argdiff_pairs_when_both_decided": [],
    }
    det = {}   # (file, lineno, argdig) -> result
    bases = open(os.path.join(B, "_p16_render_bases.jsonl"), "w")
    nb = 0
    with Pool(4) as pool:
        for i, r in enumerate(pool.imap_unordered(one, paths, chunksize=200)):
            if r[0] == "ERR":
                agg["errors"].append(r[1:]); continue
            _, name, calls, dec, other, seeds = r
            agg["dumps"] += 1
            if calls:
                agg["dumps_with_process_call"] += 1
            for o, (f, ln, ad, res) in calls.items():
                agg["ordinals_seen"][o] += 1
                agg["linenos"][f"{os.path.basename(f)}:{ln}"] += 1
                k = (f, ln, ad)
                if k in det and det[k] != res:
                    if len(agg["det_violations"]) < 20:
                        agg["det_violations"].append(
                            {"dump": name, "ord": o, "file": f, "lineno": ln,
                             "res_a": det[k][:60], "res_b": res[:60]})
                else:
                    det[k] = res
            for e, c in other.items():
                agg["other_render_exprs"][e] += c
            agg["decided_sets"][",".join(sorted(dec))] += 1
            d2, d3 = dec.get("2"), dec.get("3")
            def side(x):
                if x is None: return None
                return "BOTH" if len(x) > 1 else x[0]
            agg["joint_23"][f"{side(d2)}|{side(d3)}"] += 1
            if "2" in calls and "3" in calls:
                eq = calls["2"][2] == calls["3"][2]
                agg["args_equal_when_both_called"][eq] += 1
                if d2 is not None and d3 is not None:
                    agg["args_equal_when_both_decided"][eq] += 1
                    if not eq and len(agg["argdiff_pairs_when_both_decided"]) < 20:
                        agg["argdiff_pairs_when_both_decided"].append(
                            {"dump": name, "a2": calls["2"], "a3": calls["3"]})
            if d2 is not None and d3 is not None and nb < 4000:
                nb += 1
                bases.write(json.dumps({"dump": name, "out2": side(d2), "out3": side(d3),
                                        "eq_args": calls.get("2", (None,)*4)[2] ==
                                                   calls.get("3", (None,)*4)[2],
                                        "nseeds": len(seeds)}) + "\n")
            if (i + 1) % 20000 == 0:
                print(f"  {i+1}/{len(paths)}", flush=True)
    bases.close()
    for k in ("ordinals_seen", "linenos", "joint_23", "decided_sets",
              "other_render_exprs"):
        agg[k] = dict(agg[k].most_common(40))
    for k in ("args_equal_when_both_called", "args_equal_when_both_decided"):
        agg[k] = {str(a): b for a, b in agg[k].items()}
    agg["distinct_arg_digests_at_264"] = len({a for (f, ln, a) in det if ln == 264})
    json.dump(agg, open(os.path.join(B, "_p16_render_scan.json"), "w"), indent=1)
    print(json.dumps(agg, indent=1)[:4000])
    print(f"P16-SCAN-DONE dumps={agg['dumps']} bases={nb}")


if __name__ == "__main__":
    main()
