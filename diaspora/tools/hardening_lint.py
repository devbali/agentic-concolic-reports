#!/usr/bin/env python3
"""HARDENING LINT — the adversary's past wins, as a deterministic pre-check.

    PYTHONPATH=src python3 hardening_lint.py <batch_dir> [--runs concrete_run.json ...] [--sample N]

Every check below is one row of `ADVERSARY_WINS.md`'s "cross-endpoint
patterns": a class of gap a real run already caught on some endpoint.
Running this on a NEW batch (or after a repair) costs seconds and spends no
JRuby, so the adversary's ~20-minute rounds are spent on NEW ground instead
of re-finding the same class a fourth time.

It reads dumps (sampled) and, optionally, concrete runs. It never proves
completeness — it only refuses the known ways of being incomplete.

H1 formats        every renderable format of the action is a corpus scenario
H2 link text      text rendered through MessageRenderer must have a
                  link-bearing decision (the `Post.exists?` family, 3/3 hits)
H3 opaque notes   a target mock whose note is not SQL, over a body that can
                  reach SQL, swallows the calls below it (N-1)
H4 list length    every collection length must vary across the corpus
                  (0 / 1 / many), else empty and multi-row states are blind
H5 pinned enums   a *_type / type column that takes exactly one value
                  corpus-wide is a pinned subclass family (N-2)
H6 over-emission  notes never issued by any concrete run inflate the policy
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict

WALLS = ("render", "head", "redirect_to", "url_for", "gon", "fetch_and_save",
         "default_render", "_set_rendered_content_type", "devise_mapping",
         "assert_is_devise_resource!", "validate", "status=", "push")
LINK_RE = re.compile(r"diaspora://", re.I)



# INSTR-7 class (2026-08-30): a data access is any DML, not just a SELECT —
# `update_attribute` delegates to `save`, whose note is the `UPDATE`.
_DML = ("SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "REPLACE")
def _is_dml(sql):
    return str(sql or "").lstrip().upper().startswith(_DML)

def _shape(sql):
    """quoting/whitespace/literal-insensitive shape of a statement."""
    s = re.sub(r"[`\"]", "", str(sql))
    s = re.sub(r"\$\$\([^)]*\)|\?|\b\d+\b", "@", s)
    s = re.sub(r"'[^']*'", "@", s)
    # `to_sql` INLINES booleans while the wire protocol BINDS them, so a note
    # over a boolean scope condition (`contacts.sharing = true`,
    # `posts.public = true`) could never match its own real run — the one
    # inlined type with no normalization rule (conversations_index,
    # 2026-08-29: 2 unmatched shapes → 0, no collisions).
    s = re.sub(r"\b(true|false)\b", "@", s)
    return re.sub(r"\s+", " ", s).strip().lower()


def load(batch, sample):
    files = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
    if sample and len(files) > sample:
        step = len(files) / float(sample)
        files = [files[int(i * step)] for i in range(sample)]
    for f in files:
        try:
            yield json.load(open(f))
        except Exception:
            continue


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    batch = args[0].rstrip("/")
    sample = int(args[args.index("--sample") + 1]) if "--sample" in args else 1200
    if args.count("--runs") > 1:
        # the repeated form `--runs a --runs b` silently kept only the FIRST
        # list and produced twelve convincing false findings (comments_index
        # 2026-08-29); refuse it instead of guessing.
        sys.exit("hardening_lint: pass ONE --runs followed by every run file "
                 "(`--runs a.json b.json …`); the repeated `--runs` form is "
                 "ambiguous and was silently dropping files.")
    runs = []
    if "--runs" in args:
        for a in args[args.index("--runs") + 1:]:
            if a.startswith("--"):
                break
            runs.append(a)

    scenarios = set()
    seeds_seen = defaultdict(set)          # var -> {values}
    len_polarity = defaultdict(set)        # list var -> {True, False} recorded
    nested_sql = defaultdict(lambda: [0, 0])   # target -> [calls, calls with nested SQL]
    notes_by_target = defaultdict(set)
    call_targets = set()
    text_vals = set()
    type_vals = defaultdict(set)           # column -> {literals}
    n = 0
    for d in load(batch, sample):
        n += 1
        # a target's note may live on the RESULT VAR rather than on the event
        # (the interceptor takes it from `#concolic_note` of the returned
        # value) — the fold and mock_note_check read both, so this lint must
        # too, or every such target looks "opaque" (2026-08-28: comments_index
        # `exists?` carried its `SELECT 1 AS one …` note on the var).
        var_note = {str(sv.get("name")): str(sv.get("note") or "")
                    for sv in (d.get("symbolic_vars") or [])}
        scenarios.add((d.get("concolic_scenario") or {}).get("name"))
        for ev in d.get("events") or []:
            if ev.get("type") == "path_condition":
                m = re.match(r"\((?:len\(|SYM_LEN_)([A-Za-z0-9_]+)\)?\s*(?:!=|>|==)", str(ev.get("expr", "")))
                if m:
                    len_polarity[m.group(1)].add(bool(ev.get("taken")))
        for k, v in (d.get("concolic_seeds") or {}).items():
            if isinstance(v, (str, int, bool, float)):
                seeds_seen[k].add(v)
            if isinstance(v, str) and len(v) > 8:
                text_vals.add(v[:120])
        # A target's own event is pushed AFTER its lambda returns, so any
        # SELECT it caused from inside appears immediately BEFORE it
        # (conversations_index 2026-08-29: `Base#save` emits the belongs_to
        # validation SELECTs as nested `load_intermediate` events — 4 660 of
        # 4 660 calls — so it is not opaque even though its own note is an
        # UPDATE).
        evs = [e for e in (d.get("events") or []) if e.get("type") == "symbolic_call"]
        for i, e in enumerate(evs):
            t0 = str(e.get("target") or "").replace("#", ".")
            nested_sql[t0][0] += 1
            prev = evs[i - 1] if i else None
            pnote = str((prev or {}).get("note") or "")
            if prev is not None and _is_dml(pnote):
                nested_sql[t0][1] += 1
        for ev in d.get("events") or []:
            if ev.get("type") != "symbolic_call":
                continue
            t = str(ev.get("target") or "").replace("#", ".")
            call_targets.add(t)
            note = str(ev.get("note") or "")
            if not note.strip():
                rn = str(ev.get("result_name") or "")
                # the outcome var carries a suffix: `…_exists__1` -> `…_exists__1_exists`
                note = var_note.get(rn) or next(
                    (v for k, v in var_note.items() if k.startswith(rn) and v.strip()), "")
            note = re.sub(r"\s+", " ", note)
            notes_by_target[t].add(note)
            for col, lit in re.findall(r'[`"]?(\w*type)[`"]?\s*(?:=|IN)\s*\(?\s*\'([^\']*)\'', note, re.I):
                type_vals[col.lower()].add(lit)

    print(f"== hardening_lint: {n} dumps sampled from {os.path.basename(batch)}; "
          f"{len(call_targets)} targets, {len(scenarios)} scenarios ==\n")
    red = 0

    # H1 — formats
    print("-- H1 formats (corpus scenarios) --")
    print(f"   scenarios: {sorted(x for x in scenarios if x)}")
    has_mobile = any("mobile" in (s or "") for s in scenarios)
    print(f"   {'ok' if has_mobile else 'CHECK'}: mobile variant "
          f"{'present' if has_mobile else 'ABSENT — if the controller has a *.mobile.haml view or mobile-fu applies, this is a blind format (M-2)'}")
    red += 0 if has_mobile else 1
    print()

    # H2 — link-bearing text
    print("-- H2 link-bearing text (the Post.exists? family) --")
    any_link = any(LINK_RE.search(v) for v in text_vals)
    exists_target = any("exists" in t for t in call_targets)
    one_as_one = any("1 AS one" in nt for ns in notes_by_target.values() for nt in ns)
    print(f"   seeded text values carrying 'diaspora://': {'yes' if any_link else 'NO'}")
    print(f"   an exists?-family target in the corpus: {'yes' if exists_target else 'NO'}")
    print(f"   any existence-probe note (`1 AS one`): {'yes' if one_as_one else 'NO'}")
    if not (any_link or one_as_one):
        red += 1
        print("   CHECK: if any rendered text reaches Diaspora::MessageRenderer, the link "
              "branch is foreclosed — hit on 3/3 endpoints (C-4, M-1, N-1)")
    print()

    # H3 — opaque notes over SQL-reaching targets
    print("-- H3 opaque notes (a target mock that can swallow nested SQL) --")
    opaque = []
    for t, ns in sorted(notes_by_target.items()):
        if any(_is_dml(nt) for nt in ns):
            continue
        if any(w.lower() in t.lower() for w in WALLS):
            continue
        # a note may DECLARE itself a wall — the target name need not contain
        # a wall word (`Anonymous.new` = the federation Discovery constructor)
        if any(re.search(r"\bWALL\b", nt) for nt in ns):
            continue
        # a target that emits SQL through NESTED events is not opaque
        calls, with_sql = nested_sql.get(t, [0, 0])
        if calls and with_sql >= 0.5 * calls:
            continue
        opaque.append((t, sorted(ns)[0][:60] if ns else ""))
    for t, ex in opaque[:12]:
        print(f"   CHECK {t:<62} note={ex!r}")
    if opaque:
        red += 1
        print(f"   {len(opaque)} target(s) with no SQL note and not a documented wall — each must be "
              "proven unable to reach a target (N-1: MessageRenderer#title swallowed Post.exists?)")
    else:
        print("   ok: every non-wall target carries SQL notes")
    print()

    # H4 — collection lengths. The real question is whether the length
    # DECISION is explored both ways, which lives in the recorded PCs; the
    # seed dict only shows the side that needed a seed (2026-08-28: this
    # flagged three healthy dimensions on comments_index).
    print("-- H4 collection lengths (0 / 1 / many) --")
    lens = {k: v for k, v in seeds_seen.items() if k.startswith("len(")}
    # A batch may DECLARE a length whose polarity is fixed by WHAT THE LIST
    # IS, not by exploration — completion_config.json `h4_by_construction:
    # [{"match": "<substring of the len var>", "reason": "..."}]` (conversations
    # 2026-08-29: a will_paginate BeyondPageList has 0 rows by definition, so
    # `size > 0` can only be False). The reason is printed so it stays
    # auditable; an entry that matches nothing is itself reported.
    byc = []
    try:
        cfgp = os.path.join(batch, "completion_config.json")
        if os.path.exists(cfgp):
            byc = json.load(open(cfgp)).get("h4_by_construction") or []
    except Exception:
        byc = []
    one_sided_all = sorted(k for k, pol in len_polarity.items() if len(pol) < 2)
    one_sided, declared = [], []
    for k in one_sided_all:
        hit = next((e for e in byc if e.get("match") and e["match"] in k), None)
        (declared if hit else one_sided).append((k, hit))
    one_sided = [k for k, _ in one_sided]
    print(f"   {len(len_polarity)} len(...) decisions recorded as PCs; "
          f"{len(one_sided_all)} appear with ONE polarity only, {len(declared)} declared by construction")
    for k, e in declared:
        print(f"   declared {k}: {e.get('reason','(no reason given)')}")
    for e in byc:
        if not any(e.get("match") and e["match"] in k for k in len_polarity):
            print(f"   CHECK h4_by_construction entry {e.get('match')!r} matches no recorded length — stale declaration")
            one_sided.append(e.get("match"))
    for k in one_sided[:8]:
        print(f"   CHECK {k}: only {sorted(len_polarity.get(k, {None}))[0]} recorded — the other side is unexplored")
    if one_sided or not len_polarity:
        red += 1
        print("   a frozen length hides empty-state branches, interior indexes and "
              "`count > 0 with zero rows` (notifications N/A-1, conversations near-misses)")
    print()

    # H5 — pinned enums. A batch may declare pins in completion_config.json
    # (`pc_pin_ledger`), which Rule G requires to be disjoint from the gate
    # list; a declared pin is an answered CHECK, not an open one.
    pinned = set()
    try:
        cfgp = os.path.join(batch, "completion_config.json")
        if os.path.exists(cfgp):
            pinned = {str(x).lower() for x in (json.load(open(cfgp)).get("pc_pin_ledger") or [])}
    except Exception:
        pinned = set()
    print("-- H5 pinned type columns --")
    for col, vals in sorted(type_vals.items()):
        declared = col in pinned or any(col.endswith(p) or p.endswith(col) for p in pinned)
        mark = "ok   " if (len(vals) > 1 or declared) else "CHECK"
        if len(vals) < 2 and not declared:
            red += 1
        elif len(vals) < 2:
            print(f"   (pin declared in pc_pin_ledger)", end=" ")
        print(f"   {mark} {col}: {sorted(vals)[:8]}{' …' if len(vals) > 8 else ''}")
    if not type_vals:
        print("   (no type-column literals in notes)")
    print()

    # H6 — over-emission. Without --runs there is nothing to compare against,
    # and a SKIPPED check must say so: silence reads as a pass (2026-08-29).
    if not runs:
        print("-- H6 over-emission: SKIPPED (no --runs given; pass the batch's "
              "concrete runs AND every adversary round's run files) --\n")
    if runs:
        real = set()
        for rp in runs:
            loaded = json.load(open(rp))
            if not isinstance(loaded, list) or any(not isinstance(sc, dict) for sc in loaded):
                # a judge/stats file beside the runs (conversations R5
                # `_corpus_scan.json`, 2026-08-30) is not a run: say so
                # rather than crash or silently skip.
                print(f"   note: {rp} is not a run file (scenario list of dicts) — ignored")
                continue
            for sc in loaded:
                for st in sc.get("statements") or []:
                    # keep the FULL statement: the shape comparison below
                    # normalizes it, and truncating here meant any statement
                    # longer than the cut could never match (comments_index
                    # 2026-08-29 — a 69-char principal read reported as
                    # over-emission although every real run issues it).
                    real.add(re.sub(r"\s+", " ", st["sql"]))
        # A batch may DECLARE a note family as answered in
        # completion_config.json — `h6_answered: [{"match": "<substring>",
        # "reason": "..."}]` — the same mechanism as H5's pin ledger. Use it
        # only where the shape is genuinely unreachable by a real run (the
        # JFFI-abort path) or is a scope constant the fidelity judge already
        # scores EXACT; the reason is printed, so it stays auditable.
        answered = []
        try:
            cfgp = os.path.join(batch, "completion_config.json")
            if os.path.exists(cfgp):
                answered = json.load(open(cfgp)).get("h6_answered") or []
        except Exception:
            answered = []
        print("-- H6 over-emission (note families no concrete run issued) --")
        unissued = []
        for t, ns in sorted(notes_by_target.items()):
            for nt in ns:
                if not _is_dml(nt):
                    continue
                # identifier quoting alone made a 30-char prefix compare
                # report false over-emission (conversations_index
                # 2026-08-29); compare normalized shape instead.
                head = nt[:60]
                if not any(_shape(nt) == _shape(r) for r in real):
                    unissued.append((t, head))
        ok_rows, open_rows = [], []
        for t, h in unissued:
            hit = next((a for a in answered
                        if str(a.get("match", "")) and str(a.get("match")) in f"{t} {h}"), None)
            (ok_rows if hit else open_rows).append((t, h, hit))
        for t, h, hit in ok_rows[:6]:
            print(f"   answered {t}: {str(hit.get('reason'))[:70]}")
        for t, h, _ in open_rows[:10]:
            print(f"   CHECK {t}: {h}")
        unissued = [(t, h) for t, h, hit in open_rows]
        print(f"   {len(unissued)} note shape(s) never issued by the {len(runs)} concrete run(s) "
              "— over-emission inflates the policy" if unissued else "   ok")
        if unissued:
            red += 1
        print()

    print(f"RESULT: {red} hardening check(s) need an answer "
          "(each is a class a real run already caught on some endpoint)."
          if red else "RESULT: all hardening checks clean.")
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
