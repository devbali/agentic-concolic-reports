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

    # A7-5 (2026-09-01): LIKE-WITH-LIKE. A request's statement multiplicity
    # depends on which LAYOUT it renders, so a real request may only be
    # compared with corpus dumps of the same layout class. Classified by the
    # SAME data-driven marker function on both sides (never by filename, so an
    # early-terminating html dump is not compared against full-layout runs):
    #   mobile — the mobile drawer's `tag_followings` read
    #   html   — layout reads (roles / aspects / notifications / services)
    #   plain  — no layout reads at all (json, xml, and the js 500 path)
    # Without this, A2's four html requests were compared against the corpus
    # max over ALL ten variants: MOBILE's roles x2 (admin + moderator, real and
    # correct — concrete_run_mobile request 3) read as html over-emission.
    # A7-8 (2026-09-01, coordinator RED): classify by POSITIVE BRANCH MARKERS,
    # never by "did the layout reads happen". A request that terminates inside
    # the render (A3's absent-profile 500: 7 statements, no layout reads yet)
    # is still an html request; the old marker filed it as `plain`, the corpus
    # dumps carrying the same statement render the layout and are `html`, and
    # the judge reported the `contacts.mutual.empty?` probe as MISSING
    # (corpus max x0) when the corpus in fact emits it 1,326x per 4,000 dumps.
    # The probe itself is a positive html marker: it lives INSIDE the
    # `format.html` block (C-8 — the one read `.js` does not perform).
    HTML_PROBE = ("select @ as one from contacts where contacts.user_id = @ "
                  "and contacts.sharing = @ and contacts.receiving = @ limit @")
    def klass(keys):
        ks = " ".join(keys)
        if "tag_followings" in ks: return "mobile"
        if re.search(r"\broles\b|\baspects\b|\bnotifications\b|\bservices\b", ks): return "html"
        if HTML_PROBE in keys: return "html"
        return "plain"

    def read_requests(paths):
        out = []
        for rp in paths:
            try: data = json.load(open(rp))
            except Exception: continue
            for sc in data:
                cur = None
                for st in sc.get("statements") or []:
                    sql = st["sql"] if isinstance(st, dict) else st
                    if not is_stmt(sql): continue
                    sh = shape(sql)
                    if sh.startswith("select users.* from users where users.id = @ order by"):
                        if cur: out.append((os.path.basename(rp), cur))
                        cur = Counter()
                    if cur is None: cur = Counter()
                    cur[sh] += 1
                if cur: out.append((os.path.basename(rp), cur))
        return out

    real_reqs = [c for _src, c in read_requests(runs)]
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
    # A7-4 (2026-09-01): the per-row test is TRANSITIVE through the mint graph.
    # A note is per-row if it binds a `$$(..._row…)` var DIRECTLY, or if it binds
    # a var whose owning rep was minted by a call whose own note is per-row.
    # Evidence: `Conversation#last_author` is `Person.includes(:profile).find_by(
    # id: <row>.author_id)` — the finder's note binds `..._records_1_row_author_id`
    # (per-row, already classified), its result rep is `find_by_N`, and the
    # `:profile` PRELOAD note binds `find_by_N_id`, so the no-LIMIT
    # `SELECT profiles.* … person_id = ?` read is issued ONCE PER LISTED ROW
    # (real: x11 on a 12-conversation request) while the sampled model renders
    # one representative (corpus: exactly 1 in every dump that has it,
    # distribution {1: …}). Classified by the graph, not by a blanket `find_by`
    # exemption: a preload of a PER-REQUEST finder (e.g. the principal's own
    # person) never reaches a `_row` bind and stays judged. Measured over the
    # whole corpus: 11,561 occurrences of that shape, 100% per-row-transitive.
    ROW_RE = re.compile(r"\$\$\([A-Za-z0-9_]*_row(_[A-Za-z0-9_]*)?\)")
    BIND_RE = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")
    per_row = set()
    for p in glob.glob(os.path.join(batch, "dump_*.json")):
        try: d = json.load(open(p))
        except Exception: continue
        evs = [e for e in (d.get("events") or []) if e.get("type") == "symbolic_call"]
        by_res = {e.get("result_name"): e for e in evs if e.get("result_name")}
        memo = {}
        def is_per_row(note, depth=0):
            if not note or depth > 6: return False
            if note in memo: return memo[note]
            memo[note] = False  # cycle guard
            if ROW_RE.search(note):
                memo[note] = True; return True
            for v in BIND_RE.findall(note):
                parts = v.split("_")
                for k in range(len(parts), 1, -1):
                    cand = "_".join(parts[:k])
                    if cand in by_res and cand != v:
                        if is_per_row(by_res[cand].get("note") or "", depth + 1):
                            memo[note] = True; return True
                        break
            return False
        for e in evs:
            n = e.get("note") or ""
            if is_stmt(n) and is_per_row(n):
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
    # UNDER-emission is judged against the PASSED runs only (strict: every real
    # request handed to the judge must be reproduced). OVER-emission is a claim
    # about the APP ("we assert a statement the app never issues"), so it is
    # refuted by ANY real request that does issue it: it is judged against the
    # union of the passed runs and the batch's own concrete ground truth, in
    # the SAME layout class, and the corroborating file is named in the output.
    ground = read_requests(runs)
    batch_runs = [r for r in glob.glob(os.path.join(batch, "concrete_run*.json"))
                  if os.path.basename(r) not in {os.path.basename(x) for x in runs}]
    ground += read_requests(batch_runs)
    if batch_runs:
        print("   over-emission corroborated against: "
              + ", ".join(sorted({os.path.basename(r) for r in [*runs, *batch_runs]})))

    real_max = defaultdict(int)                      # (klass, shape) -> max, PASSED runs
    ground_max = defaultdict(int); ground_src = {}   # (klass, shape) -> max + witness
    corp_max = defaultdict(int)
    for c in real_reqs:
        kl = klass(c.keys())
        for k, v in c.items(): real_max[(kl, k)] = max(real_max[(kl, k)], v)
    for src, c in ground:
        kl = klass(c.keys())
        for k, v in c.items():
            if v > ground_max[(kl, k)]:
                ground_max[(kl, k)] = v; ground_src[(kl, k)] = src
    corp_by_class = defaultdict(list)
    corp_global = defaultdict(int)
    for name, c in corpus:
        kl = klass(c.keys()); corp_by_class[kl].append((name, c))
        for k, v in c.items():
            corp_max[(kl, k)] = max(corp_max[(kl, k)], v)
            corp_global[k] = max(corp_global[k], v)
    # A7-8: UNDER-emission asks "can the corpus produce this multiplicity AT
    # ALL" — a question about the corpus, not about a layout — so it is judged
    # GLOBALLY. Only OVER-emission (a claim about what the app never issues)
    # needs like-with-like scoping, and it is skipped for a class with no
    # ground-truth request rather than inventing a verdict from a class gap.
    real_global = defaultdict(int)
    for c in real_reqs:
        for k, v in c.items(): real_global[k] = max(real_global[k], v)
    print(f"== multiset_counts: {len(real_reqs)} real requests, {len(corpus)} dumps ==")
    print("   layout classes — real: "
          + ", ".join(f"{k}x{v}" for k, v in sorted(Counter(klass(c.keys()) for c in real_reqs).items()))
          + " | corpus: " + ", ".join(f"{k}x{len(v)}" for k, v in sorted(corp_by_class.items())))
    bad = 0; limit = 0
    for k in sorted(real_global):
        key = (None, k)
        real_max, corp_max_g = real_global, corp_global
        if corp_global.get(k, 0) < real_global[k]:
            kl = "any"
            if k in per_row:
                limit += 1; print(f"  LIMIT  [{kl}] real x{real_global[k]} corpus max x{corp_global.get(k,0)}  (per-row shape: one-representative under-count, known limit)  {k[:80]}")
            elif renderer(k):
                limit += 1; print(f"  KNOWN  [{kl}] real x{real_global[k]} corpus max x{corp_global.get(k,0)}  (declared renderer re-read: {renderer(k)['reason'][:90]})  {k[:60]}")
            else:
                bad += 1; print(f"  UNDER  [{kl}] real x{real_global[k]} corpus max x{corp_global.get(k,0)}  {k[:110]}")
    over = 0
    ground_classes = {kl for kl, _k in ground_max}
    for key in sorted(corp_max):
        kl, k = key
        if kl not in ground_classes:
            continue  # no comparable ground truth for this layout class
        g = ground_max.get(key, 0)
        if g and corp_max[key] > g and k in per_row:
            # A7-7: SYMMETRY. A per-row shape's multiplicity is a function of
            # the number of LISTED ROWS — the corpus's sampled representatives
            # on one side, the fixtures' row count on the other — so comparing
            # maxima across differently-sized universes is meaningless in BOTH
            # directions. It is already excluded from UNDER (one-representative
            # limit); excluding it from OVER is the same fact. Evidence: this
            # batch's 2-conversation mobile fixtures cap real at x4 while the
            # adversary's 12-conversation mobile request issues x24 of the same
            # shape. Not a blanket waiver: the shape must be REAL (some ground
            # -truth request issues it), and a per-REQUEST shape asserted more
            # often than the app issues it is still RED below.
            limit += 1
            print(f"  ROWSCALE [{kl}] corpus x{corp_max[key]} > this ground truth's x{g} "
                  f"(per-row shape: multiplicity scales with row count, not judged)  {k[:70]}")
        elif g and corp_max[key] > g:
            over += 1; print(f"  OVER   [{kl}] corpus x{corp_max[key]} real max x{g}  {k[:110]}")
        elif g and corp_max[key] > real_max.get(key, 0):
            print(f"  ok     [{kl}] corpus x{corp_max[key]} > this run's x{real_max.get(key,0)}, "
                  f"but real x{g} in {ground_src.get(key)}  {k[:70]}")
    exact = sum(1 for c in real_reqs if any(cc == c for _n, cc in corpus))
    print(f"\ncount-exact real requests reproduced by some dump: {exact}/{len(real_reqs)}")
    print(f"RESULT: {'pass' if not bad and not over else 'RED'} — per-request shapes under-emitted {bad}, over-emitted {over}; per-row shapes at the one-representative limit {limit} (known, not judged)")
    sys.exit(1 if bad or over else 0)

if __name__ == "__main__":
    main()
