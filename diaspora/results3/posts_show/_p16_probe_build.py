#!/usr/bin/env python3
"""P16 / §79 — build the ACTIVE FALSIFICATION probe for the render-ordinal
identity declaration.

The gate's own alias test cannot run here (see §79: the alias machinery is
note-gated to SQL statements and intervenes with `len(<list>_rows)`), so the
claim is falsified the way the confinement gate's (vi)/(vii) arms falsify
theirs: BY CONSTRUCTION, with real replays.

CLAIM:   SYM_RESULT_Anonymous_process_2 == SYM_RESULT_Anonymous_process_3.
MECHANISM: the mock (targets.rb W7) returns its own `message` argument, so the
   two results differ iff the two calls receive different messages, i.e. iff
   the two ordinals fall on different MessageRenderer instances.  Corpus-wide
   the ordinals of this statement DO carry different messages (grouping
   signatures 1|2,3,4  1,2,3|4  1,4|2,3  1|2,3|4 ...), but 2 and 3 are in the
   SAME group in every one of the 117 715 runs that make both calls.
FALSIFICATION TARGET: a run in which ordinals 2 and 3 receive DIFFERENT
   messages while both `== ''` comparisons are recorded.

The intervention axes are the ones that decide WHICH post text each renderer
carries and how many renderers the run builds: every `*_text_empty`,
`*_text_has_mention` and `*_text` seed key, plus the `assoc_*` post-text keys.
Per base: the full factorial over the `assoc_*` text axes, and a one-at-a-time
flip of every other text axis.  Bases are picked to cover every (variant,
grouping signature, decided set) the pruned corpus shows.
"""
import json, os, re, glob, hashlib, collections, itertools, random
from multiprocessing import Pool

B = os.path.dirname(os.path.abspath(__file__))
LIST = os.path.join(B, "_snapshot_pruned_P15F.txt")
ORD = re.compile(r"SYM_RESULT_Anonymous_process_(\d+)")
PCRE = re.compile(r"^\(SYM_RESULT_Anonymous_process_(\d+) == ''\)$")
VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")


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
    calls = {}
    for ev in d.get("events") or ():
        if ev.get("type") == "symbolic_call" and ev.get("target") == "Anonymous.process":
            m = ORD.fullmatch(str(ev.get("result_name") or ""))
            if m:
                a = json.dumps(ev.get("args"), sort_keys=True, default=str)
                calls[int(m.group(1))] = hashlib.blake2b(a.encode(), digest_size=6).hexdigest()
    if not calls:
        return None
    dec = sorted({int(m.group(1)) for ev in d.get("events") or ()
                  if ev.get("type") == "path_condition"
                  for m in [PCRE.match(str(ev.get("expr") or ""))] if m})
    g = collections.defaultdict(list)
    for o, dg in calls.items():
        g[dg].append(o)
    sig = "|".join(",".join(str(x) for x in sorted(v))
                   for v in sorted(g.values(), key=lambda v: min(v)))
    return (path, variant_of(path), sig, ",".join(map(str, dec)),
            d.get("concolic_seeds") or {})


TEXT_RE = re.compile(r"(_text_empty|_text_has_mention|_text)$|^assoc_.*text")


def main():
    paths = [l.strip() for l in open(LIST) if l.strip()]
    print(f"scanning {len(paths)} pruned profiles for bases", flush=True)
    rows = []
    with Pool(4) as pool:
        for r in pool.imap_unordered(one, paths, chunksize=200):
            if r:
                rows.append(r)
    print(f"  {len(rows)} carry a process call", flush=True)
    buckets = collections.defaultdict(list)
    for p, v, sig, dec, seeds in rows:
        buckets[(v, sig, dec)].append((len(seeds), p, seeds))
    print(f"  {len(buckets)} (variant, grouping, decided) cells")
    PER_CELL = 2
    bases = []
    for k in sorted(buckets):
        for n, p, seeds in sorted(buckets[k], reverse=True)[:PER_CELL]:
            bases.append((k, p, seeds))
    print(f"  {len(bases)} bases chosen")

    out = {v: [] for v in VARIANTS}
    manifest = []
    rng = random.Random(20260912)
    for (v, sig, dec), p, seeds in bases:
        keys = sorted(k for k in seeds if TEXT_RE.search(k))
        assoc = [k for k in keys if k.startswith("assoc_") and isinstance(seeds[k], bool)]
        others = [k for k in keys if k not in assoc and isinstance(seeds[k], bool)]
        cand = []
        # (a) full factorial over the assoc_* text axes
        for combo in itertools.product([False, True], repeat=min(len(assoc), 4)):
            s = dict(seeds)
            for k, val in zip(assoc[:4], combo):
                s[k] = val
            cand.append(("assoc" + "".join("1" if x else "0" for x in combo), s))
        # (b) one-at-a-time flip of every other text axis (capped at 10 per
        # base, chosen deterministically, so the whole probe stays inside one
        # JRuby hour at CONCOLIC_SLOTS=1)
        for k in sorted(others)[:10]:
            s = dict(seeds)
            s[k] = not seeds[k]
            cand.append(("flip:" + k[-40:], s))
        # (c) two random pair-flips over the other axes (a cheap 2-way search)
        for _ in range(4):
            if len(others) >= 2:
                a, b2 = rng.sample(others, 2)
                s = dict(seeds)
                s[a] = not seeds[a]; s[b2] = not seeds[b2]
                cand.append(("pair", s))
        for why, s in cand:
            manifest.append({"variant": v, "index": len(out[v]), "base": os.path.basename(p),
                             "base_sig": sig, "base_decided": dec, "why": why})
            out[v].append(s)
    for v in VARIANTS:
        json.dump(out[v], open(os.path.join(B, f"_p16_seeds_{v}.json"), "w"))
        print(f"  {v}: {len(out[v])} probe seeds")
    json.dump(manifest, open(os.path.join(B, "_p16_probe_manifest.json"), "w"))
    print(f"P16-BUILD-DONE seeds={sum(len(out[v]) for v in VARIANTS)} bases={len(bases)}")


if __name__ == "__main__":
    main()
