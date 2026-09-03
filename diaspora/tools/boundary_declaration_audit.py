#!/usr/bin/env python3
"""BOUNDARY DECLARATION AUDIT — is every boundary family actually declared?

    python3 boundary_declaration_audit.py <batch_dir> [<batch_dir> ...]

The shared target boundary (docs/TARGET_FUNCTIONS.md) names the ActiveRecord
families every batch must intercept. A batch can silently fail to declare one
— and then that family issues NOTHING into the corpus, so no note is wrong,
no statement is mismatched, and every judge stays green.

That is how `Calculations#sum` went missing on conversations_index
(2026-08-29): the action never calls it, the LAYOUT does, and a pin that
suppressed layout rendering hid both the statements AND the fact that the
target was never declared. A pin over a rendering path can suppress a whole
target family's declaration, which no statement-level check can see.

This compares each batch's `declare_target` calls against the boundary list
and reports families that are absent. Absence is not automatically a defect —
an endpoint may genuinely never reach `delete_all` — but it must be a stated
pin with a ledger entry, not an oversight.

EXERCISE CENSUS (added 2026-09-01, notifications_index C7). Declaration is not
exercise. On notifications `sum` IS declared and was invoked **0 times in
879 248 symbolic_call events**, because a `layout(false)` pin removed its only
call site — so this audit passed, correctly, and was blind to the very class
its docstring describes. The census below counts, per declared method, how many
times the corpus actually invoked it, and REVIEWS the ones at zero.

A zero is NOT a verdict: an endpoint may legitimately never call a family, and
saying otherwise would demand statements the app never issues. It is a question
— "is this family unreachable here, or is something suppressing its call site?"
— and only the code answers it. The exit status is unchanged by the census.
"""
import glob
import json
import os
import re
import sys

# the ActiveRecord query boundary, per docs/TARGET_FUNCTIONS.md
BOUNDARY = {
    "finders": ["find", "find_by", "find_by!", "first", "last", "take", "take!", "first!", "last!"],
    "existence": ["exists?", "any?", "none?", "one?", "many?", "empty?"],
    "materialization": ["to_a", "to_ary", "records", "size", "load_target"],
    "calculations": ["count", "sum", "pluck", "ids", "average", "minimum", "maximum", "calculate"],
    "batches": ["find_each", "find_in_batches", "in_batches"],
    "writes": ["save", "save!", "update", "update!", "update_attribute", "touch",
               "destroy", "destroy!", "update_all", "delete_all", "destroy_all"],
    "raw": ["find_by_sql", "count_by_sql"],
}
DECL_RE = re.compile(r"declare_target\(\s*([A-Za-z_:][\w:.\[\]()]*)\s*,\s*:([a-z_0-9?!]+)")
LIST_RE = re.compile(r"%i\[([^\]]*)\]")
# a family may be declared through a hash literal driven into declare_target,
# e.g. `{ exists?: [fm, false], any?: [rel, true], … }.each { |m, (mod, seed)| … }`
HASH_KEY_RE = re.compile(r"^\s*([a-z_0-9]+[?!]?):\s*\[", re.M)


def declared_in(batch):
    found = set()
    for path in glob.glob(os.path.join(batch, "*.rb")):
        try:
            src = open(path).read()
        except Exception:
            continue
        for _owner, meth in DECL_RE.findall(src):
            found.add(meth)
        # `%i[find take! first!].each { |m| interceptor.declare_target(mod, m, …) }`
        for chunk in LIST_RE.findall(src):
            for tok in chunk.split():
                found.add(tok.strip())
        if "declare_target" in src:
            for key in HASH_KEY_RE.findall(src):
                found.add(key)
    return found


def exercised_in(batch):
    """method -> number of symbolic_call events invoking it, over the WHOLE corpus.

    Counts `symbolic_call` ONLY: a `call` trace event carries a target too but is
    not an invocation of the declared boundary in the sense this audit means
    (DISCIPLINE §14, the event-type census gotcha).
    """
    counts = {}
    files = glob.glob(os.path.join(batch, "dump_*.json"))
    for path in files:
        try:
            d = json.load(open(path))
        except Exception:
            continue
        for ev in d.get("events") or []:
            if ev.get("type") != "symbolic_call":
                continue
            tgt = str(ev.get("target") or "")
            meth = tgt.rsplit(".", 1)[-1].rsplit("#", 1)[-1]
            counts[meth] = counts.get(meth, 0) + 1
    return counts, len(files)


def main():
    batches = sys.argv[1:]
    if not batches:
        sys.exit(__doc__)
    red = 0
    per_batch = {}
    for batch in batches:
        found = declared_in(batch)
        print(f"== {os.path.basename(batch.rstrip('/'))}: {len(found)} distinct target methods declared ==")
        for family, meths in BOUNDARY.items():
            missing = [m for m in meths if m not in found]
            if missing:
                print(f"   {family:<16} MISSING: {' '.join(missing)}")
                red += len(missing)
            else:
                print(f"   {family:<16} complete")
        ex, ndumps = exercised_in(batch)
        per_batch[os.path.basename(batch.rstrip('/'))] = (ex, ndumps, set(found))
        if ndumps:
            zero = sorted(m for m in found
                          if any(m in meths for meths in BOUNDARY.values()) and not ex.get(m))
            live = sorted(((ex[m], m) for m in ex if any(m in M for M in BOUNDARY.values())),
                          reverse=True)
            print(f"   -- exercise census over {ndumps} dumps (symbolic_call events only) --")
            for n, m in live[:8]:
                print(f"      {n:9d}  {m}")
            if zero:
                print(f"      REVIEW: declared but invoked 0 times: {' '.join(zero)}")
                print("              not a verdict — is the family unreachable here, or is a")
                print("              pin removing its call site? only the code answers that.")
            else:
                print("      every declared boundary method is invoked at least once")
        else:
            print("   -- exercise census SKIPPED: no dump_*.json in this batch --")
        print()
    # CROSS-BATCH CONTRAST — the sharpest form of this question. "Zero here" is
    # weak (no endpoint calls `delete_all`); "zero here but thousands next door"
    # is the shape of a suppressed call site, which is how notifications' `sum`
    # was found (0 there, 18 306 on conversations, same declared boundary).
    live = {b: e for b, (e, n, _f) in per_batch.items() if n}
    if len(live) > 1:
        print("== cross-batch contrast: invoked elsewhere, never here ==")
        allm = set()
        for e in live.values():
            allm |= {m for m in e if any(m in M for M in BOUNDARY.values())}
        for b, e in live.items():
            gaps = []
            for m in sorted(allm):
                if e.get(m):
                    continue
                others = [(bb, ee[m]) for bb, ee in live.items() if ee.get(m)]
                if others:
                    gaps.append((m, others))
            if gaps:
                print(f"   {b}:")
                for m, others in gaps:
                    where = ", ".join(f"{bb} {n}" for bb, n in sorted(others, key=lambda x: -x[1])[:3])
                    print(f"      {m:<16} 0 here | {where}")
            else:
                print(f"   {b}: nothing invoked elsewhere is missing here")
        print("   REVIEW ONLY — endpoints differ legitimately; ask the code, not this table.\n")
    if red:
        print(f"RESULT: {red} boundary method(s) undeclared across {len(batches)} batch(es) — "
              "each must be a stated pin with a ledger entry, not an oversight "
              "(an undeclared family issues NOTHING and every judge stays green).")
        sys.exit(1)
    print("RESULT: pass — every boundary family is declared in every batch.")
    sys.exit(0)


if __name__ == "__main__":
    main()
