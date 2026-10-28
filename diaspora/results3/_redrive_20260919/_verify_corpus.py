#!/usr/bin/env python3
"""Branching-safety verification: the re-driven corpus must explore EXACTLY the
same paths as the original, differing only in recorded SQL notes.

Checks, per variant:
  * dump count
  * 1:1 seed -> dump (every original seed replayed exactly once)
  * the MULTISET of path-condition signatures is identical
  * per-seed PC identity (same conditions, same polarity, same order)

Usage: _verify_corpus.py <orig_dir> <fresh_dir>
"""
import hashlib
import json
import os
import re
import sys
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor


def pcs_sig(d):
    parts = []
    for ev in d.get("events", []) or []:
        if ev.get("kind") == "path_condition" or "taken" in ev:
            parts.append(f"{ev.get('expr')}:{ev.get('taken')}")
    return hashlib.md5("||".join(parts).encode()).hexdigest(), len(parts)


def summarise(path):
    try:
        d = json.load(open(path, "rb"))
    except Exception as e:  # noqa: BLE001
        return None, os.path.basename(path), f"{type(e).__name__}", 0, None
    scen = d.get("concolic_scenario") or {}
    variant = scen.get("name")
    if not variant:
        # people_stream records no scenario; derive it from the label, and
        # strip the per-drive LABEL_SUFFIX so orig and fresh group together.
        lbl = (d.get("label") or os.path.basename(path)).replace("dump_", "")
        if "_dse" in lbl:
            variant = lbl.split("_dse")[0]
        else:
            m = re.match(r"^([a-z][a-z_]*?)\d{3,}", lbl)
            variant = m.group(1) if m else lbl
    seedkey = hashlib.md5(
        json.dumps(d.get("concolic_seeds"), sort_keys=True).encode()
    ).hexdigest()
    sig, n = pcs_sig(d)
    err = (d.get("error") or {}).get("type")
    return variant, seedkey, sig, n, err


def scan(d):
    files = [
        os.path.join(d, f)
        for f in os.listdir(d)
        if f.startswith("dump_") and f.endswith(".json")
    ]
    files.sort()
    by_variant = defaultdict(lambda: {"seeds": Counter(), "sigs": Counter(),
                                      "pc": Counter(), "err": Counter(),
                                      "seed2sig": {}})
    with ProcessPoolExecutor(max_workers=16) as ex:
        for variant, seedkey, sig, n, err in ex.map(summarise, files, chunksize=64):
            if variant is None:
                by_variant["__READ_ERROR__"]["err"][sig] += 1
                continue
            b = by_variant[variant]
            b["seeds"][seedkey] += 1
            b["sigs"][sig] += 1
            b["pc"][n] += 1
            b["err"][err or "-none-"] += 1
            b["seed2sig"][seedkey] = (sig, n)
    return len(files), by_variant


def main():
    orig, fresh = sys.argv[1], sys.argv[2]
    no, bo = scan(orig)
    nf, bf = scan(fresh)
    print(f"orig  {orig}: {no} dumps, variants={sorted(bo)}")
    print(f"fresh {fresh}: {nf} dumps, variants={sorted(bf)}")
    print()

    ok = True
    for v in sorted(set(bo) | set(bf)):
        o, f = bo.get(v), bf.get(v)
        if o is None or f is None:
            print(f"[{v}] MISSING on one side (orig={o is not None} fresh={f is not None})")
            ok = False
            continue
        so, sf = set(o["seed2sig"]), set(f["seed2sig"])
        dup_f = sum(c - 1 for c in f["seeds"].values() if c > 1)
        sig_same = o["sigs"] == f["sigs"]
        pc_same = o["pc"] == f["pc"]
        shared = so & sf
        per_seed_mismatch = sum(
            1 for k in shared if o["seed2sig"][k] != f["seed2sig"][k]
        )
        print(f"[{v}]")
        print(f"  dumps      orig={sum(o['seeds'].values())} fresh={sum(f['seeds'].values())}")
        print(f"  distinct seeds orig={len(so)} fresh={len(sf)} "
              f"(missing={len(so-sf)} extra={len(sf-so)} dup_in_fresh={dup_f})")
        print(f"  PC-signature multiset identical : {sig_same}")
        print(f"  PC-count     multiset identical : {pc_same}")
        print(f"  per-seed PC mismatches          : {per_seed_mismatch}/{len(shared)}")
        seeds_same = o["seeds"] == f["seeds"]
        print(f"  seed MULTISET identical         : {seeds_same}"
              f" (orig has {sum(c-1 for c in o['seeds'].values() if c>1)} dup seeds)")
        if o["err"] != f["err"]:
            print(f"  ERROR PROFILE DIFFERS: orig={dict(o['err'])} fresh={dict(f['err'])}")
            ok = False
        else:
            print(f"  error profile identical        : {dict(o['err'])}")
        # NOTE: duplicate seeds are legitimate in some corpora (e.g.
        # conversations_index html_plain: 2659 dumps / 2657 distinct seeds), so
        # the criterion is that the seed MULTISET matches the original, not
        # that it is duplicate-free.
        if not (sig_same and pc_same and per_seed_mismatch == 0
                and not (so - sf) and seeds_same):
            ok = False
        print()

    print("VERDICT:", "BRANCHING IDENTICAL" if ok else "DIFFERENCES FOUND — STOP")


if __name__ == "__main__":
    main()
