#!/usr/bin/env python3
"""P29 / §88 — the ACTIVE FALSIFICATION probe for RENDER_TEXT_SOURCE.

CLAIM:  (SYM_RESULT_Anonymous_process_3 == '')  ==  (<act finder>_text_empty == True)
        for the one act-family finder that resolved the post in that run.
FALSIFICATION TARGET: a run that RECORDS both decisions with DIFFERENT values.

Same shape as §79.3(b): bases chosen to cover every (variant, act finder,
decided set) cell the pruned corpus shows, richest seed dict first; the
interventions are the axes that decide what text each renderer carries — the
act finder's own `_text_empty` / `_text` / `_text_has_mention`, the full
factorial over the `assoc_*` text axes, a one-at-a-time flip of every other
text axis, and random pair-flips (a cheap 2-way search for a decoupling).
"""
import json, os, re, collections, itertools, random
from multiprocessing import Pool

B = os.path.dirname(os.path.abspath(__file__))
LIST = os.path.join(B, "_snapshot_pruned_P26F2.txt")
VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")
ACT = ("SYM_RESULT_ActiveRecord__Relation_evilq_act_vis_1",
       "SYM_RESULT_ActiveRecord__Relation_evilq_act_author_1",
       "SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1",
       "SYM_RESULT_ActiveRecord__Relation_findpublic_act_1")
P3 = "(SYM_RESULT_Anonymous_process_3 == '')"
TEXT_RE = re.compile(r"(_text_empty|_text_has_mention|_text)$|^assoc_.*text")


def variant_of(name):
    for v in VARIANTS:
        if os.path.basename(name).startswith("dump_" + v):
            return v
    return "?"


def one(path):
    try:
        d = json.load(open(path))
    except Exception:
        return None
    dec = {}
    for ev in d.get("events") or ():
        if ev.get("type") != "path_condition":
            continue
        e = str(ev.get("expr") or "")
        if e == P3:
            dec.setdefault("p3", set()).add(bool(ev.get("taken")))
        for a in ACT:
            if e == "(%s_text_empty == True)" % a:
                dec.setdefault(a, set()).add(bool(ev.get("taken")))
    if "p3" not in dec:
        return None
    acts = [a for a in ACT if a in dec]
    if not acts:
        return None
    return (path, variant_of(path), acts[0],
            "%s/%s" % (sorted(dec["p3"]), sorted(dec[acts[0]])),
            d.get("concolic_seeds") or {})


def main():
    paths = [l.strip() for l in open(LIST) if l.strip()]
    print("scanning %d pruned profiles for bases that MINT THE PAIR" % len(paths), flush=True)
    rows = []
    with Pool(int(os.environ.get("W", "3"))) as pool:
        for r in pool.imap_unordered(one, paths, chunksize=200):
            if r:
                rows.append(r)
    print("  %d profiles record the render decision AND an act _text_empty" % len(rows))
    buckets = collections.defaultdict(list)
    for p, v, act, outc, seeds in rows:
        buckets[(v, act, outc)].append((len(seeds), p, seeds))
    print("  %d (variant, act finder, outcome) cells" % len(buckets))
    for k in sorted(buckets):
        print("     %-10s %-58s %-16s  %d" % (k[0], k[1][-52:], k[2], len(buckets[k])))
    PER_CELL = int(os.environ.get("PER_CELL", "3"))
    bases = []
    for k in sorted(buckets):
        for n, p, seeds in sorted(buckets[k], reverse=True)[:PER_CELL]:
            bases.append((k, p, seeds))
    print("  %d bases chosen" % len(bases))

    out = {v: [] for v in VARIANTS}
    manifest = []
    rng = random.Random(20260913)
    for (v, act, outc), p, seeds in bases:
        keys = sorted(k for k in seeds if TEXT_RE.search(k))
        boolkeys = [k for k in keys if isinstance(seeds[k], bool)]
        assoc = [k for k in boolkeys if k.startswith("assoc_")]
        own = [k for k in boolkeys if k.startswith(act)]
        others = [k for k in boolkeys if k not in assoc and k not in own]
        cand = []
        # (a) the act finder's OWN text axes, full factorial (the antecedent)
        for combo in itertools.product([False, True], repeat=min(len(own), 2)):
            s = dict(seeds)
            for k, val in zip(sorted(own)[:2], combo):
                s[k] = val
            cand.append(("own" + "".join("1" if x else "0" for x in combo), s))
        # (b) act finder's text_empty crossed with the assoc_* text axes —
        #     the most plausible decoupling (a renderer fed a DIFFERENT text)
        te = act + "_text_empty"
        for combo in itertools.product([False, True], repeat=min(len(assoc), 3)):
            for tv in (True, False):
                s = dict(seeds)
                for k, val in zip(sorted(assoc)[:3], combo):
                    s[k] = val
                if te in s:
                    s[te] = tv
                cand.append(("cross%s:%s" % ("".join("1" if x else "0" for x in combo), tv), s))
        # (c) one-at-a-time flip of every other text axis, with the antecedent
        #     held at each of its two values
        for k in sorted(others)[:8]:
            for tv in (True, False):
                s = dict(seeds)
                s[k] = not seeds[k]
                if te in s:
                    s[te] = tv
                cand.append(("flip:%s:%s" % (k[-36:], tv), s))
        # (d) random pair-flips
        for _ in range(4):
            if len(others) >= 2:
                a, b2 = rng.sample(others, 2)
                s = dict(seeds)
                s[a] = not seeds[a]; s[b2] = not seeds[b2]
                cand.append(("pair", s))
        for why, s in cand:
            manifest.append({"variant": v, "index": len(out[v]),
                             "base": os.path.basename(p), "act": act,
                             "base_outcome": outc, "why": why})
            out[v].append(s)
    for v in VARIANTS:
        json.dump(out[v], open(os.path.join(B, "_p29_seeds_%s.json" % v), "w"))
        print("  %s: %d probe seeds" % (v, len(out[v])))
    json.dump(manifest, open(os.path.join(B, "_p29_probe_manifest.json"), "w"))
    print("P29-BUILD-DONE seeds=%d bases=%d"
          % (sum(len(out[v]) for v in VARIANTS), len(bases)))


if __name__ == "__main__":
    main()
