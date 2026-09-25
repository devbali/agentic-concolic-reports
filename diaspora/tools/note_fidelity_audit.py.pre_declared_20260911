#!/usr/bin/env python3
"""NOTE FIDELITY AUDIT — projection-level pass over every target function's
notes against REAL statements (Bali directive 2026-08-26: "a pass about
all the target functions and the sql queries we put in notes ... we are
doing a lot of *s while the actual traces do specific columns; the adverse
agent should feed into the notes").

    python3 note_fidelity_audit.py <batch_dir> <concrete_run.json>... [--aliases a.json]

LEFT:  real statements from concrete runs (the batch's own scenarios AND
       the adversary's runs — every `*.json` you pass), each tagged with the
       target frame it was issued under.
RIGHT: the corpus notes per target (symbolic_call events).

mock_note_check answers "is there a note of this SHAPE"; this audit is
stricter and asks, per real statement, whether the note is FAITHFUL in its
projection — the part the policy inherits:
  EXACT          same tables, same predicate columns, same projection kind
                 and columns
  STAR-OVER      real statement projects NAMED columns; the note says `t.*`
                 (the policy over-approximates: allows every column)
  AGG-COLLAPSE   real is COUNT/SUM/… but the note is `t.*` (or vice versa)
                 — an aggregate is not a row read
  PRED-DIFF      projection faithful, predicate columns differ
  MISSING        no note for this target (or its aliases) with these tables
Also reports, per target, how many of its corpus notes are wildcard
notes at all. Exit 1 on STAR-OVER / AGG-COLLAPSE / MISSING.
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from statement_diff import normalize  # same dir (tools/)  # noqa: E402

_AGG = re.compile(r"\b(COUNT|SUM|AVG|MIN|MAX)\s*\(", re.I)
# Rule T4 requires the note to match the real statement in projection,
# PREDICATE SHAPE and ORDERING. The shape normalizer wildcards literals and
# binds, which also erased `=` vs `IN`, `LIMIT` and `ORDER BY` — so a
# single-row read noted as a bulk `IN (…)`, or a note missing the real
# `LIMIT 1`/ordering, scored EXACT (comments_index adversary round 4,
# 2026-08-28). These compare those three explicitly.
_LIMIT_RE = re.compile(r"\bLIMIT\b", re.I)
_ORDER_RE = re.compile(r"\bORDER\s+BY\s+(.+?)(?:\s+LIMIT\b|\s*\)?\s*$)", re.I | re.S)
_IN_RE = re.compile(r"([`\"]?\w+[`\"]?\.[`\"]?\w+[`\"]?)\s*(=|IN)\s*", re.I)



# INSTR-7 (conversations adversary R4, 2026-08-30): both judges compared
# SELECTs only, so a run with four `UPDATE "users"` scored green. A data
# access is any DML statement; transaction control and pragmas are not.
_DML = ("SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "REPLACE")
def _is_dml(sql):
    return str(sql or "").lstrip().upper().startswith(_DML)

def pred_ops(sql):
    """{(column, '=' | 'IN')} — a single-row read and a bulk read are not
    the same access, even when their tables and columns coincide."""
    return {(c.strip('`"').lower(), op.upper()) for c, op in _IN_RE.findall(sql)}


def order_key(sql):
    m = _ORDER_RE.search(sql)
    return re.sub(r"\s+", " ", m.group(1)).strip().lower() if m else ""


def has_limit(sql):
    return bool(_LIMIT_RE.search(sql))


def projection(sql):
    """('star'|'agg'|'cols'|'mixed', {table.col,...})"""
    m = re.search(r"\ASELECT\s+(DISTINCT\s+)?(.*?)\s+FROM\b", sql.strip(), re.I | re.S)
    sel = m.group(2) if m else ""
    cols = {f"{t.lower()}.{c.lower()}" for t, c in re.findall(r'[`"]?(\w+)[`"]?\.[`"]?(\w+)[`"]?', sel)}
    has_star = bool(re.search(r'(\.\s*\*|^\s*\*|,\s*\*)', sel)) or sel.strip() == "*"
    has_agg = bool(_AGG.search(sel))
    if has_agg:
        return "agg", cols
    if has_star and cols:
        return "mixed", cols
    if has_star:
        return "star", set()
    return "cols", cols


def classify(real, note):
    nr, nn = normalize(real), normalize(note)
    if nr["tables"] != nn["tables"]:
        return None
    rk, rc = projection(real)
    nk, nc = projection(note)
    if rk == "agg" and nk != "agg" or nk == "agg" and rk != "agg":
        return "AGG-COLLAPSE"
    if rk in ("cols", "mixed") and nk == "star":
        return "STAR-OVER"
    if rk == "cols" and nk == "cols" and not (nc >= rc):
        return "PROJ-DIFF"
    if pred_ops(real) != pred_ops(note):
        return "PRED-OP-DIFF"      # `=` vs `IN`: single-row vs bulk access
    if has_limit(real) != has_limit(note):
        return "LIMIT-DIFF"
    if order_key(real) != order_key(note):
        return "ORDER-DIFF"
    if nr["predicates"] != nn["predicates"]:
        return "PRED-DIFF"
    return "EXACT"


RANK = {"EXACT": 0, "ORDER-DIFF": 1, "LIMIT-DIFF": 2, "PRED-DIFF": 3,
        "PRED-OP-DIFF": 4, "PROJ-DIFF": 5, "STAR-OVER": 6, "AGG-COLLAPSE": 7}


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    batch = args[0]
    aliases = json.load(open(args[args.index("--aliases") + 1])) if "--aliases" in args else {}
    runs = [a for a in args[1:] if a.endswith(".json") and not a.startswith("--") and os.path.exists(a)]
    if "--aliases" in args:
        runs = [r for r in runs if r != args[args.index("--aliases") + 1]]

    notes = defaultdict(set)
    for f in glob.glob(os.path.join(batch, "dump_*.json")):
        for ev in json.load(open(f)).get("events") or []:
            if ev.get("type") == "symbolic_call" and ev.get("result_name"):
                n = str(ev.get("note") or "")
                if _is_dml(n):
                    notes[str(ev.get("target") or "").replace("#", ".")].add(re.sub(r"\s+", " ", n))

    real = defaultdict(lambda: defaultdict(set))   # target -> sql -> {scenario}
    for rp in runs:
        for sc in json.load(open(rp)):
            for st in sc.get("statements") or []:
                if _is_dml(st["sql"]):
                    fr = (st.get("under") or "(outside any target frame)").replace("#", ".")
                    real[fr][re.sub(r"\s+", " ", st["sql"])].add(f"{os.path.basename(rp)}:{sc.get('name')}")

    print(f"== note_fidelity_audit: {len(runs)} run file(s), {sum(len(v) for v in real.values())} distinct real SELECTs "
          f"under {len(real)} frames; {len(notes)} targets carry notes ==\n")
    print("-- wildcard notes per target (corpus) --")
    for t in sorted(notes):
        kinds = defaultdict(int)
        for n in notes[t]:
            kinds[projection(n)[0]] += 1
        print(f"   {t:<70} notes={len(notes[t]):<4} " + " ".join(f"{k}={v}" for k, v in sorted(kinds.items())))
    print()

    red = 0
    findings = defaultdict(list)
    for tgt in sorted(real):
        if tgt == "(outside any target frame)":
            continue
        # the alias map is bidirectional in practice: a real frame may be
        # reported under the alias, or the note may be recorded under it
        # (conversations_index 2026-08-29: 108 false PRED-OP-DIFF events on a
        # note byte-identical to the real statement).
        rev = [k for k, v in aliases.items() if tgt in (v or [])]
        pool = set()
        for n in [tgt] + list(aliases.get(tgt, [])) + rev:
            pool |= notes.get(n, set())
        for sql, scen in sorted(real[tgt].items()):
            best, best_note = None, None
            for note in pool:
                c = classify(sql, note)
                if c is not None and (best is None or RANK[c] < RANK[best]):
                    best, best_note = c, note
            if best is None:
                # any note anywhere with these tables? (frame nesting)
                for t2, ns in notes.items():
                    for note in ns:
                        c = classify(sql, note)
                        if c is not None and (best is None or RANK[c] < RANK[best.rstrip("*")]):
                            best, best_note = c + "*", note
            verdict = best or "MISSING"
            findings[verdict.rstrip("*")].append((tgt, sql, best_note, sorted(scen)[:3]))
            if verdict.rstrip("*") in ("STAR-OVER", "AGG-COLLAPSE", "MISSING", "PROJ-DIFF",
                                       "PRED-OP-DIFF", "LIMIT-DIFF", "ORDER-DIFF"):
                red += 1

    for v in ("MISSING", "STAR-OVER", "AGG-COLLAPSE", "PROJ-DIFF", "PRED-OP-DIFF",
              "LIMIT-DIFF", "ORDER-DIFF", "PRED-DIFF", "EXACT"):
        items = findings.get(v, [])
        print(f"-- {v}: {len(items)} --")
        if v == "EXACT":
            continue
        for tgt, sql, note, scen in items[:12]:
            print(f"   {tgt}  [{', '.join(scen)}]")
            print(f"      real: {sql[:150]}")
            if note:
                print(f"      note: {note[:150]}")
        print()
    print("RESULT: " + (f"RED — {red} real statement(s) whose note is unfaithful in projection or missing."
                        if red else "every real statement has a projection-faithful note."))
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
