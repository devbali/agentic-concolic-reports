#!/usr/bin/env python3
"""Per-request statement MULTIPLICITY, real vs corpus — counts, not sets.
comments_index adaptation of conversations_index/_multiset_counts.py.

    python3 _multiset_counts.py <batch> [--per-file] [--runs run.json ...]

Coverage is a claim about DECISIONS; this is the claim about STATEMENTS.
Every checker names the evidence it read (DISCIPLINE §15, 2026-09-01); an
unrecognised argument is an ERROR, never a silent fallback.  `--per-file`
judges every run file on its own AND combined, scanning the corpus once.

--- what differs from the conversations version, and why (all measured) ---

1. REQUEST SPLITTING.  conversations opened every request with the Devise
   `users` read.  comments#index is `before_action :authenticate_user!,
   except: :index`, so an ANONYMOUS request never touches Devise and has no
   such opener.  The opener set is therefore DERIVED FROM THE CORPUS, not
   hand-written: a corpus dump IS one request, so the shapes that can open a
   request are exactly the first-note shapes over all dumps, restricted to
   those that occur ONLY in first position.  Measured on the cycle-9/10
   corpus (20 879 dumps): exactly three (users 11352/11352, posts-by-id
   6093/6093, posts-by-guid 3420/3420), so splitting cannot cut a request.

2. LAYOUT CLASS -> AUTH CLASS.  comments#index renders NO layout on either
   renderable format: `format.json { render json: ... }` and
   `format.mobile { render layout: false, ... }` (comments_controller.rb:52-53
   — the APP's own code, not a rig pin), so the conversations layout axis is
   constant here.  The axis that does carry statement structure is ANON vs
   AUTH (the Devise fetch, the share_visibilities join and the
   `people.owner_id` read exist only when signed in).  Classified by a
   POSITIVE marker on both sides (A7-8): the principal fetch shape.

3. FORMAT AXIS: measured to carry no per-REQUEST statement information.
   json and mobile have IDENTICAL note-shape SETS in the corpus; the only
   shapes whose maxima differ are per-ROW shapes (excluded from both
   directions anyway).  The script RE-MEASURES that at run time and prints a
   FORMAT-AXIS line; a per-request shape that ever differs between the two is
   reported as RED, because then this merge would hide an over-emission.

4. Presence (UNDER) is judged GLOBALLY; multiplicity (OVER) like-with-like,
   and a class with no ground-truth request is SKIPPED (A7-8).
"""
import glob, json, os, re, sys
from collections import Counter, defaultdict

_DML = ("SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "REPLACE")
PRINCIPAL = "select users.* from users where users.id = @ order by users.id asc limit @"
_INLIST_RE = re.compile(r"\bin \(@(?:, @)+\)")
ROW_RE = re.compile(r"\$\$\([A-Za-z0-9_]*_row(_[A-Za-z0-9_]*)?\)")
BIND_RE = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")


def is_stmt(s):
    return str(s or "").lstrip().upper().startswith(_DML)


def shape(sql):
    s = re.sub(r"[`\"]", "", str(sql)); s = re.sub(r"\$\$\([^)]*\)|\?|\b\d+\b", "@", s)
    s = re.sub(r"'[^']*'", "@", s); s = re.sub(r"\b(true|false)\b", "@", s, flags=re.I)
    return re.sub(r"\s+", " ", s).strip().lower()


def in_norm(sh):
    """Arity-insensitive form of a shape's IN-lists.

    The project's OWN statement currency does not distinguish `IN` arity:
    note_fidelity_audit compares the predicate set {(column, '=' | 'IN')}
    (tools/note_fidelity_audit.py:48-60), so `people.id IN (?, ?)` and
    `people.id IN (?, ?, ?)` are one shape to the fidelity judge and one
    predicate in the extracted policy.  Used ONLY to decide whether a shape
    belongs to a per-ROW family already present in the corpus; the arity is
    still printed (IN-ARITY census), never erased, because it is the visible
    face of the 0/1/many list abstraction: the corpus's SampledList carries at
    most two representative rows, so its bulk preloads bind at most two
    distinct keys while a fixture with three distinct authors binds three.
    Same fact as the ROWSCALE lines, same direction, and it stays reported."""
    return _INLIST_RE.sub("in (@...)", sh)


def arity(sh):
    m = _INLIST_RE.search(sh)
    return sh.count(", @", m.start()) + 1 if m else 0


def _run_shapes(rp):
    out = set()
    try: data = json.load(open(rp))
    except Exception: return out
    if isinstance(data, dict): data = data.get("scenarios") or []
    for sc in data:
        if not isinstance(sc, dict): continue
        for st in sc.get("statements") or []:
            sql = st["sql"] if isinstance(st, dict) else st
            if is_stmt(sql): out.add(shape(sql))
    return out


def klass(keys):
    return "auth" if PRINCIPAL in keys else "anon"


def load_corpus(batch):
    corpus, first_shapes, shape_total, per_row = [], Counter(), Counter(), set()
    action_first = Counter()
    for p in sorted(glob.glob(os.path.join(batch, "dump_*.json"))):
        try: d = json.load(open(p))
        except Exception: continue
        evs = [e for e in (d.get("events") or []) if e.get("type") == "symbolic_call"]
        dml = [str(e.get("note") or "") for e in evs if is_stmt(e.get("note"))]
        if not dml: continue
        first_shapes[shape(dml[0])] += 1
        # the ACTION opener: the FIRST `posts` read of the request.
        # comments#index's first data access is `post_service.find!(post_id)`
        # (comment_service.rb:24 -> PostService#find! -> EvilQuery), so every
        # request opens with a read of `posts` whichever arm it takes.  Taken
        # from the corpus rather than hand-written, and admitted below only if
        # the shape occurs EXACTLY ONCE per request corpus-wide, so splitting
        # on it cannot cut a request in half.  This is what makes the split
        # correct for a rig that memoizes the principal across requests (the
        # pre-INSTR-1 warden memo of adversary rounds 2-7 emits the users read
        # once for several requests).
        _p = [shape(n) for n in dml if re.search(r"\bfrom posts\b", shape(n))]
        if _p: action_first[_p[0]] += 1
        for n in dml: shape_total[shape(n)] += 1
        corpus.append((os.path.basename(p), Counter(shape(n) for n in dml),
                       (d.get("concolic_scenario") or {}).get("name") or "?"))
        by_res = {e.get("result_name"): e for e in evs if e.get("result_name")}
        memo = {}

        def is_per_row(note, depth=0):
            if not note or depth > 6: return False
            if note in memo: return memo[note]
            memo[note] = False
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

        for n in dml:
            if is_per_row(n): per_row.add(shape(n))
    openers = {s for s, c in first_shapes.items() if c == shape_total.get(s, 0)}
    action_openers = {s for s, c in action_first.items() if c == shape_total.get(s, 0)}
    return corpus, openers, action_openers, first_shapes, action_first, per_row


def read_requests(paths, openers, action_openers, stats=None):
    """Split a run file's statements into REQUESTS.

    Two rules, both derived from the corpus (a dump IS one request):
      * a statement whose recorded frame (`under`) is null was not issued
        under any target frame — it is scenario-body / fixture traffic, not
        part of a request.  Dropped, and counted in `stats` so the drop is
        reported, never silent.  (Measured over all 57 evidence files: 25
        such statements, every one an adversary fixture INSERT/UPDATE/DELETE
        or a hand-written probe query in the scenario body; the batch's own
        concrete runs contain none.)
      * a request starts at the principal fetch, or at an ACTION opener (the
        post finder) when the current request already has one — so a rig that
        memoizes the principal across requests (the pre-INSTR-1 warden memo
        in adversary rounds 2-7) is still split correctly."""
    out = []
    for rp in paths:
        try: data = json.load(open(rp))
        except Exception: continue
        if isinstance(data, dict): data = data.get("scenarios") or []
        for sc in data:
            if not isinstance(sc, dict): continue
            # An `under: null` statement was issued OUTSIDE any target frame,
            # i.e. by the scenario body. It is not a request statement — and
            # neither is what FOLLOWS it until the next request opener: the
            # body's own `User.find(uid)` (unframed) is immediately followed
            # by that fresh User's `people.owner_id` association load, which
            # IS framed but is still the body's call. Measured on
            # adversary8/H03: three such probe pairs at the end of the
            # scenario were being charged to the preceding request, which read
            # `people.owner_id` x3 where every real request reads it once.
            # Dropping only PRE-first-opener statements (the cycle-10 rule)
            # could not see them because they come after the last request.
            # This batch's OWN concrete runs contain zero unframed statements,
            # so the rule never touches them; both counts are printed.
            shs = []; in_body = False
            for st in sc.get("statements") or []:
                framed = True
                if isinstance(st, dict):
                    sql = st["sql"]; framed = st.get("under") is not None
                else:
                    sql = st
                if not is_stmt(sql): continue
                if not framed:
                    if stats is not None: stats["unframed"] += 1
                    in_body = True
                    continue
                sh0 = shape(sql)
                if sh0 == PRINCIPAL or sh0 in action_openers:
                    in_body = False          # a new request begins
                if in_body:
                    if stats is not None: stats["body_tail"] += 1
                    continue
                shs.append(sh0)
            # A request BEGINS at its action opener.  Statements before the
            # scenario's FIRST action opener are scenario-body setup and
            # inspection, not request statements: an adversary body that
            # queries the fixture through ActiveRecord (`post.comments.to_a`,
            # `Comment.find`, `Post.find_by`, a `pluck`, a `count`) gets a
            # target frame like any other AR call, so `under` alone cannot
            # separate it — its POSITION can.  A scenario that never reaches
            # an action opener (a pure probe scenario, e.g. adversary6 E06)
            # contributes no request at all.  Both are counted and reported.
            k = next((i for i, sh in enumerate(shs) if sh in action_openers), None)
            if k is None:
                if stats is not None:
                    stats["no_action_scenarios"] += 1
                    stats["pre_action"] += len(shs)
                continue
            # keep the principal fetch of the FIRST request: on this endpoint
            # `authenticate_user!` is `except: :index`, so the principal is
            # fetched lazily by `set_locale`/`user_signed_in?` and is followed
            # by `user.person` (people.owner_id) and the gender `profiles` read
            # BEFORE the action's post finder — measured distance 3, not 1, in
            # 9 of the 25 auth scenarios.  Rewinding only one statement dropped
            # the principal read and misclassified those requests as anonymous.
            prin = [i for i, sh in enumerate(shs[:k]) if sh == PRINCIPAL]
            if prin:
                k = prin[-1]
            if stats is not None: stats["pre_action"] += k
            cur = None; has_action = False
            for sh in shs[k:]:
                if sh == PRINCIPAL or (sh in action_openers and has_action):
                    if cur: out.append((os.path.basename(rp), cur))
                    cur = Counter(); has_action = False
                if cur is None: cur = Counter()
                if sh in action_openers: has_action = True
                cur[sh] += 1
            if cur: out.append((os.path.basename(rp), cur))
    return out


def judge(batch, runs, corpus, openers, action_openers, per_row, fdiff_req, ood):
    print("   judging runs: " + ", ".join(os.path.basename(r) for r in runs))
    per_row_norm = {in_norm(s) for s in per_row}
    stats = Counter()
    # A declared OUT-OF-DOMAIN post finder still OPENS a request — the split is
    # about request structure, the verdict about the entrypoint's input domain.
    # Without this the array-`post_id` requests of A04 merge into the preceding
    # request and its comments read reads as x2 (a phantom under-emission).
    def _ood_shapes(shapes):
        return {sh for sh in shapes
                if any(o.get("match") and o["match"] in sh for o in ood)}
    split_openers = set(action_openers) | _ood_shapes(
        {k for _n, c, _s in corpus for k in c} |
        {sh for rp in runs for sh in _run_shapes(rp)})
    real_reqs = [c for _s, c in read_requests(runs, openers, split_openers, stats)]
    if stats["unframed"] or stats["pre_action"] or stats["no_action_scenarios"] or stats["body_tail"]:
        print(f"   dropped {stats['unframed']} unframed statement(s) (`under: null` — scenario-body "
              f"traffic), {stats['body_tail']} framed statement(s) issued after one with no opener "
              f"between (the body's own AR calls), and {stats['pre_action']} framed statement(s) "
              f"before a scenario's first action opener; {stats['no_action_scenarios']} scenario(s) "
              f"never reached the action")
    ground = read_requests(runs, openers, split_openers)
    batch_runs = [r for r in sorted(glob.glob(os.path.join(batch, "concrete_run*.json")))
                  if os.path.basename(r) not in {os.path.basename(x) for x in runs}]
    ground += read_requests(batch_runs, openers, split_openers)
    if batch_runs:
        print("   over-emission corroborated against: "
              + ", ".join(sorted({os.path.basename(r) for r in [*runs, *batch_runs]})))
    if not real_reqs:
        print("   SKIP — no real request parsed from these files")
        return 0
    real_global = defaultdict(int); corp_global = defaultdict(int)
    real_max = defaultdict(int); ground_max = defaultdict(int); ground_src = {}
    corp_max = defaultdict(int); corp_by_class = Counter()
    for c in real_reqs:
        kl = klass(c.keys())
        for k, v in c.items():
            real_global[k] = max(real_global[k], v)
            real_max[(kl, k)] = max(real_max[(kl, k)], v)
    for src, c in ground:
        kl = klass(c.keys())
        for k, v in c.items():
            if v > ground_max[(kl, k)]:
                ground_max[(kl, k)] = v; ground_src[(kl, k)] = src
    for _n, c, _s in corpus:
        kl = klass(c.keys()); corp_by_class[kl] += 1
        for k, v in c.items():
            corp_global[k] = max(corp_global[k], v)
            corp_max[(kl, k)] = max(corp_max[(kl, k)], v)
    def out_of_domain(k):
        return next((o for o in ood if o.get("match") and o["match"] in k), None)
    print(f"== multiset_counts: {len(real_reqs)} real requests, {len(corpus)} dumps ==")
    print("   auth classes — real: "
          + ", ".join(f"{k}x{v}" for k, v in sorted(Counter(klass(c.keys()) for c in real_reqs).items()))
          + " | corpus: " + ", ".join(f"{k}x{v}" for k, v in sorted(corp_by_class.items())))
    bad = limit = over = 0
    for k in sorted(real_global):
        if corp_global.get(k, 0) < real_global[k]:
            if k in per_row:
                limit += 1
                print(f"  LIMIT  real x{real_global[k]} corpus max x{corp_global.get(k,0)}  "
                      f"(per-row shape: one-representative under-count, known limit)  {k[:80]}")
            elif in_norm(k) != k and in_norm(k) in per_row_norm:
                limit += 1
                print(f"  LIMIT  real x{real_global[k]} corpus max x{corp_global.get(k,0)}  "
                      f"(per-row family, wider IN-list than the corpus's representatives; same "
                      f"predicate {{col, IN}} as the corpus shape)  {k[:80]}")
            elif out_of_domain(k):
                limit += 1
                print(f"  OUT-OF-DOMAIN  real x{real_global[k]} corpus max x{corp_global.get(k,0)}  "
                      f"({out_of_domain(k)['reason'][:110]})  {k[:70]}")
            else:
                bad += 1
                print(f"  UNDER  real x{real_global[k]} corpus max x{corp_global.get(k,0)}  {k[:110]}")
    ground_classes = {kl for kl, _k in ground_max}
    for key in sorted(corp_max):
        kl, k = key
        if kl not in ground_classes: continue
        g = ground_max.get(key, 0)
        if g and corp_max[key] > g and (k in per_row or in_norm(k) in per_row_norm):
            limit += 1
            print(f"  ROWSCALE [{kl}] corpus x{corp_max[key]} > ground x{g} "
                  f"(per-row: multiplicity scales with row count, not judged)  {k[:70]}")
        elif g and corp_max[key] > g:
            over += 1
            print(f"  OVER   [{kl}] corpus x{corp_max[key]} real max x{g}  {k[:110]}")
        elif g and corp_max[key] > real_max.get(key, 0):
            print(f"  ok     [{kl}] corpus x{corp_max[key]} > this run's x{real_max.get(key,0)}, "
                  f"but real x{g} in {ground_src.get(key)}  {k[:70]}")
    ar_real, ar_corp = {}, {}
    for c in real_reqs:
        for k in c:
            if in_norm(k) != k: ar_real[in_norm(k)] = max(ar_real.get(in_norm(k), 0), arity(k))
    for _n, c, _s in corpus:
        for k in c:
            if in_norm(k) != k: ar_corp[in_norm(k)] = max(ar_corp.get(in_norm(k), 0), arity(k))
    if ar_real or ar_corp:
        print("   IN-ARITY census (0/1/many list abstraction; the corpus's SampledList "
              "carries at most 2 representative rows):")
        for n in sorted(set(ar_real) | set(ar_corp)):
            print(f"     real max IN({ar_real.get(n,0)})  corpus max IN({ar_corp.get(n,0)})  {n[:80]}")
    exact = sum(1 for c in real_reqs if any(cc == c for _n, cc, _s in corpus))
    red = bool(bad or over or fdiff_req)
    print(f"count-exact real requests reproduced by some dump: {exact}/{len(real_reqs)}")
    print(f"RESULT: {'RED' if red else 'pass'} — per-request shapes under-emitted {bad}, "
          f"over-emitted {over}; per-row shapes at the one-representative limit {limit} "
          f"(known, not judged); format-split needed for {len(fdiff_req)} per-request shape(s)")
    return 1 if red else 0


def main():
    argv = sys.argv[1:]
    if not argv: sys.exit(__doc__)
    batch = argv[0].rstrip("/")
    rest = [a for a in argv[1:]]
    per_file = "--per-file" in rest
    rest = [a for a in rest if a != "--per-file"]
    if "--runs" in rest:
        i = rest.index("--runs")
        bad_args = [a for a in rest[:i] if not a.endswith(".json")]
        runs = rest[i + 1:]
    else:
        runs = [a for a in rest if a.endswith(".json")]
        bad_args = [a for a in rest if not a.endswith(".json")]
    if bad_args:
        sys.exit(f"ERROR: unrecognised argument(s) {bad_args} — a checker never falls back silently.")
    if not runs:
        runs = sorted(glob.glob(os.path.join(batch, "concrete_run*.json")))
    missing = [r for r in runs if not os.path.exists(r)]
    if missing:
        sys.exit(f"ERROR: run file(s) not found: {missing}")
    corpus, openers, action_openers, first_shapes, action_first, per_row = load_corpus(batch)
    print(f"   request openers derived from corpus (first-note shapes occurring ONLY first): {len(openers)}")
    for s in sorted(openers): print(f"     opener  x{first_shapes[s]:<7d} {s[:92]}")
    for s in sorted(set(first_shapes) - openers):
        print(f"     NOT-AN-OPENER (also occurs mid-request; not used to split) {s[:80]}")
    print(f"   action openers (first note after the optional principal fetch): {len(action_openers)}")
    for s in sorted(action_openers): print(f"     action  x{action_first[s]:<7d} {s[:92]}")
    for s in sorted(set(action_first) - action_openers):
        print(f"     NOT-AN-ACTION-OPENER (also occurs later in a request) {s[:70]}")
    fm = defaultdict(lambda: defaultdict(int))
    for _n, c, scen in corpus:
        f = "mobile" if "mobile" in scen else "json"
        for s, v in c.items(): fm[f][s] = max(fm[f][s], v)
    per_row_norm = {in_norm(s) for s in per_row}
    fdiff = [s for s in set(fm["json"]) | set(fm["mobile"])
             if fm["json"].get(s, 0) != fm["mobile"].get(s, 0)]
    fdiff_req = [s for s in fdiff if s not in per_row and in_norm(s) not in per_row_norm]
    print(f"   FORMAT AXIS: {len(fdiff)} shape(s) differ json vs mobile, "
          f"{len(fdiff_req)} of them per-REQUEST")
    for s in sorted(fdiff_req):
        print(f"     FORMAT-SPLIT NEEDED (per-request shape, json x{fm['json'].get(s,0)} "
              f"mobile x{fm['mobile'].get(s,0)}): {s[:80]}")
    try:
        ood = json.load(open(os.path.join(batch, "completion_config.json"))).get(
            "multiset_out_of_domain") or []
    except Exception:
        ood = []
    rc = 0
    groups = ([(os.path.basename(r), [r]) for r in runs] if per_file else [])
    groups.append((f"COMBINED ({len(runs)} file(s))", runs))
    for label, rs in groups:
        print("\n" + "=" * 72 + f"\n  SCOPE: {label}")
        rc |= judge(batch, rs, corpus, openers, action_openers, per_row, fdiff_req, ood)
    sys.exit(1 if rc else 0)


if __name__ == "__main__":
    main()
