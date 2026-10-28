#!/usr/bin/env python3
"""Per-request statement MULTIPLICITY, real vs corpus — counts, not sets.

    python3 _multiset_counts.py <batch> [--runs concrete_run.json ...]

For every real request (a scenario's statements, split per request by the
Devise `users` read that opens each) build Counter(shape); for every corpus
dump build Counter(note shape). Report, per shape: the real max multiplicity,
the corpus max, and whether any dump reproduces each real request's Counter
EXACTLY (count-exact, not set-exact). Ignores BEGIN/COMMIT.
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict

def shape(sql):
    s = re.sub(r"[`\"]", "", str(sql)); s = re.sub(r"\$\$\([^)]*\)|\?|\b\d+\b", "@", s)
    s = re.sub(r"'[^']*'", "@", s); s = re.sub(r"\b(true|false)\b", "@", s, flags=re.I)
    return re.sub(r"\s+", " ", s).strip().lower()

def is_stmt(s):
    u = str(s).lstrip().upper()
    return u.startswith(("SELECT", "UPDATE", "INSERT", "DELETE"))

def main():
    batch = sys.argv[1].rstrip("/")
    # A positionally-passed run file was SILENTLY IGNORED before 2026-09-01:
    # the judge re-read only the batch's own concrete runs and printed a green
    # verdict about evidence it had never seen (coordinator false-pass on the
    # adversary R7 runs). Accept positional run files; say what is judged.
    pos = [a for a in sys.argv[2:] if a.endswith(".json")]
    if "--runs" in sys.argv:
        runs = sys.argv[sys.argv.index("--runs") + 1:]
    elif pos:
        runs = pos
    else:
        runs = glob.glob(os.path.join(batch, "concrete_run*.json"))
    print("   judging runs: " + ", ".join(os.path.basename(r) for r in runs))
    real_reqs = []
    for rp in runs:
        for sc in json.load(open(rp)):
            cur = None
            for st in sc.get("statements") or []:
                sql = st["sql"] if isinstance(st, dict) else st
                if not is_stmt(sql): continue
                sh = shape(sql)
                if sh.startswith("select users.* from users where users.id = @ order by"):
                    if cur: real_reqs.append(cur)
                    cur = Counter()
                if cur is None: cur = Counter()
                cur[sh] += 1
            if cur: real_reqs.append(cur)
    corpus = []
    for p in glob.glob(os.path.join(batch, "dump_*.json")):
        try: d = json.load(open(p))
        except Exception: continue
        c = Counter(shape(e["note"]) for e in d.get("events") or [] if e.get("type") == "symbolic_call" and is_stmt(e.get("note") or ""))
        if c: corpus.append((os.path.basename(p), c))
    # DISCIPLINE (coordinator, round 4): the count check is scoped to PER-REQUEST
    # shapes. A shape minted from a SampledList ROW (its corpus note binds a
    # `_row_` variable) is rendered once per listed row by the app and once per
    # representative by the model — the shared runtime's designed
    # one-representative under-count (the policy is a SET of shapes). Those are
    # reported as the known limit, never as RED. Data-driven: no hand list.
    per_row = set()
    for p in glob.glob(os.path.join(batch, "dump_*.json")):
        try: d = json.load(open(p))
        except Exception: continue
        for e in d.get("events") or []:
            n = e.get("note") or ""
            if e.get("type") == "symbolic_call" and is_stmt(n) and re.search(r"\$\$\([A-Za-z0-9_]*_row(_[A-Za-z0-9_]*)?\)", n):
                per_row.add(shape(n))
    # Declared RENDERER re-reads (completion_config.json `multiset_renderer_re_reads`:
    # [{"match": <shape substring>, "reason": ...}]) — R4-NM-3: on the `.js`
    # 500 path the exception RENDERER re-inspects the unloaded relation and
    # re-issues its read (x4 measured); that multiplicity is decided by the
    # exception machinery, not by the app's own code. Extra occurrences of a
    # declared shape are reported as KNOWN with the reason printed, never RED.
    declared = []
    try:
        cfg = json.load(open(os.path.join(batch, "completion_config.json")))
        declared = cfg.get("multiset_renderer_re_reads") or []
    except Exception:
        declared = []
    def renderer(k):
        return next((d for d in declared if d.get("match") and d["match"] in k), None)
    real_max = defaultdict(int); corp_max = defaultdict(int)
    for c in real_reqs:
        for k, v in c.items(): real_max[k] = max(real_max[k], v)
    for _, c in corpus:
        for k, v in c.items(): corp_max[k] = max(corp_max[k], v)
    print(f"== multiset_counts: {len(real_reqs)} real requests, {len(corpus)} dumps ==")
    bad = 0; limit = 0
    for k in sorted(real_max):
        if corp_max.get(k, 0) < real_max[k]:
            if k in per_row:
                limit += 1; print(f"  LIMIT  real x{real_max[k]} corpus max x{corp_max.get(k,0)}  (per-row shape: one-representative under-count, known limit)  {k[:80]}")
            elif renderer(k):
                limit += 1; print(f"  KNOWN  real x{real_max[k]} corpus max x{corp_max.get(k,0)}  (declared renderer re-read: {renderer(k)['reason'][:90]})  {k[:60]}")
            else:
                bad += 1; print(f"  UNDER  real x{real_max[k]} corpus max x{corp_max.get(k,0)}  {k[:110]}")
    over = 0
    for k in sorted(corp_max):
        if k in real_max and corp_max[k] > real_max[k]:
            over += 1; print(f"  OVER   corpus x{corp_max[k]} real max x{real_max[k]}  {k[:110]}")
    exact = sum(1 for c in real_reqs if any(cc == c for _, cc in corpus))
    print(f"\ncount-exact real requests reproduced by some dump: {exact}/{len(real_reqs)}")
    print(f"RESULT: {'pass' if not bad and not over else 'RED'} — per-request shapes under-emitted {bad}, over-emitted {over}; per-row shapes at the one-representative limit {limit} (known, not judged)")
    sys.exit(1 if bad or over else 0)

if __name__ == "__main__":
    main()
