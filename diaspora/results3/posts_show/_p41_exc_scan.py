#!/usr/bin/env python3
"""P41 — FULL-CORPUS exception-note census for the B-4 boundary defect.

Same detector as `src/queries_from_runs/audits/exception_note_audit.py`
(imported, not re-typed), run over EVERY dump instead of a 150-dump sample,
with 8 workers.  Adds what the audit does not carry and the blast-radius
question needs:

  * per-dump totals, so the RATE is a distribution and not one number
  * the MODEL CLASS the failed note names (`sql_for` writes
    "<klass> query (render_relation_sql failed: ...)"), so we can say WHICH
    statements were lost
  * the SUBJECT split: event `target`/`result_name` vs symbolic-var `name`,
    and the set of RESULT NAMES involved -- these are what decision
    expressions are spelled from, so this is the join to the demand structure
  * a control: notes that are legitimate SELECT statements, counted, so the
    rate has a denominator.

Read-only.  Verdict line: `P41-EXC-SCAN-DONE`.
"""
import json, os, sys, collections, multiprocessing as mp
B = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src/queries_from_runs/audits")
from exception_note_audit import _PATTERNS, notes_of      # the SHIPPED detector

LIST = os.environ.get("DUMPLIST")
WORKERS = int(os.environ.get("WORKERS", "8"))

def scan(fn):
    p = os.path.join(B, fn)
    try:
        d = json.load(open(p))
    except Exception:
        return None
    exc_subj = collections.Counter()
    exc_kind = collections.Counter()
    klass = collections.Counter()
    res_names = set()
    var_names = set()
    n_notes = n_sql = n_exc = 0
    for src, subject, note in notes_of(d):
        n_notes += 1
        if note.strip().upper().startswith(("SELECT", "WITH")):
            n_sql += 1
            continue
        for kind, pat in _PATTERNS:
            if pat.search(note):
                n_exc += 1
                exc_kind[kind] += 1
                exc_subj[f"{src}:{subject}"] += 1
                if " query (render_relation_sql failed" in note:
                    klass[note.split(" query (", 1)[0][:60]] += 1
                else:
                    klass["<other-shape>"] += 1
                (res_names if src == "event" else var_names).add(subject)
                break
    return (n_notes, n_sql, n_exc, exc_kind, exc_subj, klass, res_names, var_names)

def main():
    files = [l.strip() for l in open(LIST) if l.strip()]
    tot = collections.Counter()
    exc_kind = collections.Counter(); exc_subj = collections.Counter()
    klass = collections.Counter(); res_names = set(); var_names = set()
    perdump = collections.Counter()
    dumps_hit = 0; scanned = 0; unparsed = 0
    with mp.Pool(WORKERS) as pool:
        for i, r in enumerate(pool.imap_unordered(scan, files, chunksize=64)):
            if r is None:
                unparsed += 1; continue
            scanned += 1
            n_notes, n_sql, n_exc, ek, es, kl, rn, vn = r
            tot["notes"] += n_notes; tot["sql_notes"] += n_sql; tot["exc_notes"] += n_exc
            exc_kind.update(ek); exc_subj.update(es); klass.update(kl)
            res_names |= rn; var_names |= vn
            perdump[n_exc] += 1
            if n_exc: dumps_hit += 1
            if (i + 1) % 20000 == 0:
                print(f"  [{i+1}/{len(files)}] exc={tot['exc_notes']} hit_dumps={dumps_hit}", flush=True)
    print("\n=== FULL-CORPUS EXCEPTION-NOTE CENSUS ===")
    print(f"  dumps scanned      {scanned}   unparseable {unparsed}   listed {len(files)}")
    print(f"  notes total        {tot['notes']}")
    print(f"  notes that are SQL {tot['sql_notes']}  ({100.0*tot['sql_notes']/max(1,tot['notes']):.2f} %)")
    print(f"  notes that CAPTURED AN EXCEPTION {tot['exc_notes']}  "
          f"({100.0*tot['exc_notes']/max(1,tot['notes']):.2f} % of all notes)")
    print(f"  dumps with >=1 such note {dumps_hit} of {scanned} "
          f"({100.0*dumps_hit/max(1,scanned):.2f} %)")
    print(f"  mean per affected dump   {tot['exc_notes']/max(1,dumps_hit):.1f}")
    print(f"\n  by detector pattern: {dict(exc_kind)}")
    print(f"\n  MODEL CLASS whose statement was lost (top 25):")
    for k, v in klass.most_common(25):
        print(f"    {v:>9}  {k}")
    print(f"\n  distinct EVENT subjects affected: {len(res_names)}")
    print(f"  distinct VAR subjects affected:   {len(var_names)}")
    print(f"\n  top subjects (top 30):")
    for k, v in exc_subj.most_common(30):
        print(f"    {v:>9}  {k}")
    hist = sorted(perdump.items())
    print(f"\n  per-dump exception-note histogram (count -> dumps): "
          f"{dict(hist[:12])} ... max {hist[-1][0]}")
    json.dump({"scanned": scanned, "unparsed": unparsed,
               "notes": tot["notes"], "sql_notes": tot["sql_notes"],
               "exc_notes": tot["exc_notes"], "dumps_hit": dumps_hit,
               "by_pattern": dict(exc_kind),
               "by_class": dict(klass),
               "event_subjects": sorted(res_names),
               "var_subjects": sorted(var_names),
               "top_subjects": dict(exc_subj.most_common(200)),
               "per_dump_hist": {str(k): v for k, v in hist}},
              open(f"{B}/_p41_exc_scan.json", "w"), indent=1)
    print("\nP41-EXC-SCAN-DONE")

if __name__ == "__main__":
    main()
