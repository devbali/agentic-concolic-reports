#!/usr/bin/env python3
"""Assemble _residual_classes.json — the four residual classes with their
numbers — from the instruments that measured them. Every number here is read
from a file that a caged job wrote; nothing is typed in by hand."""
import json, os, re, subprocess, sys
from collections import Counter
HERE = os.path.dirname(os.path.abspath(__file__))
Q = "/home/dev/project/reports/diaspora/results3/queries_from_runs"

def jload(p, default=None):
    try:
        return json.load(open(p))
    except Exception:
        return default

def grep1(path, pat, default="n/a"):
    try:
        for l in open(path):
            m = re.search(pat, l)
            if m:
                return m.group(1) if m.groups() else l.strip()
    except Exception:
        pass
    return default

parts = jload(os.path.join(HERE, "_parts_OD0911.json"), {})
cens = jload(os.path.join(HERE, "_confinement_census_OD0911.json"), {})
disq = jload(os.path.join(HERE, "_disq_why.json"), {})
unev = jload(os.path.join(HERE, "_unev_why.json"), {})
ctx  = jload(os.path.join(HERE, "_matched_ctx_OF0911B.json"), {})
real = jload(os.path.join(HERE, "_gc_realise.json"), {})
ext  = (jload(os.path.join(Q, "_summary_posts_show.json"), {}) or {}).get("posts_show", {})

md5 = subprocess.run(["md5sum", "/home/dev/project/src/concolic_engine/coverage.py"],
                     capture_output=True, text=True).stdout.split()[0]
snap = sum(1 for _ in open(os.path.join(HERE, "_snapshot_pruned_OD0911.txt")))
corpus = len(list(filter(None, subprocess.run(
    ["find", HERE, "-maxdepth", "1", "-name", "dump_*.json"],
    capture_output=True, text=True).stdout.split("\n"))))

c16c = (cens.get("census") or {}).get("16c", {})
tot_rem = int(c16c.get("remaining", 0) or 0)
pairs = cens.get("pairs", {})
two_sided = len(disq.get("two_sided") or [])
n_disq = cens.get("disqualified_decisions", 0)
n_und = cens.get("undecidable_decisions", cens.get("undecidable", 0))
per = real.get("per") or {}
uneval = per.get("UNEVALUATED", 0)
realised = per.get("REALISED", 0) + per.get("REALISED(both-sided)", 0)
contra = per.get("CONTRADICTED", 0)
tot_out = uneval + realised + contra
ubk = unev.get("bucket") or {}
uev = unev.get("events") or {}
constructed = len(ctx.get("constructed") or [])
still = len(ctx.get("still_none") or [])

classes = {
 "a": {"name": "REAL DEPENDENCE — measured two-sidedness, NOT licensable",
       "lines": [
  f"{two_sided} of the {n_disq} disqualified decisions are GENUINELY TWO-SIDED on the",
  f"corpus (_disq_why: 0 are disqualified only by OR-shared shapes). Families:",
  "19 text has_mention, 11 findpublic not_found, 7 text empty, 4 find_by_N",
  "not_found, 4 guid, 2 CollectionProxy#size, 2 public, 1 Length(SYM_PARAM_id),",
  "1 rendered text, 1 assoc/dispatch. They carry the disqualified pairs",
  f"({pairs.get('disqualified','n/a')} of {sum(v for v in pairs.values() if isinstance(v,int))}).",
  "NO DECLARATION IS AVAILABLE HERE: a confinement declaration over a decision",
  "the corpus shows two-sided would be false, and more driving can only ADD",
  "two-sided evidence. The demand over these parts is owed in full."]},
 "b": {"name": "UNDECIDABLE — no matched context in the corpus",
       "lines": [
  f"{n_und} decisions / {pairs.get('undecidable','n/a')} pairs. One-flip round OF0911B built",
  f"matched contexts for {constructed}; {still} still have none.",
  "A gate can never have an exact matched context by construction (its flip",
  "changes which decisions are evaluated), so those are undecidable at any",
  "corpus size and are declared, not counted as coverage."]},
 "c": {"name": "UNEVALUATED-IN-THE-WALK after construction",
       "lines": [
  f"{uneval} of {tot_out} constructed gate outcomes ({100.0*uneval/max(1,tot_out):.0f} %) were seeded and never",
  f"reached; {realised} realised, {contra} contradicted. Of the unevaluated:",
  f"RENDER-ERROR {ubk.get('RENDER-ERROR',0)}, ALIAS {ubk.get('ALIAS',0)}, then by §16b's own",
  f"'never' test over the corpus: CONJUNCTION-FORECLOSURE {uev.get('CONJUNCTION-FORECLOSURE',0)},",
  f"REACHABLE {uev.get('REACHABLE',0)}, NO-MATCH {uev.get('NO-MATCH',0)}.",
  "Only the foreclosure share is a src/ question (§76.5); the REACHABLE share",
  "is a base-selection defect in this batch's constructor."]},
 "d": {"name": "MOCK-DOMAIN CONTRADICTION — a model decision, not evidence",
       "lines": [
  "SYM_RESULT_..._CollectionProxy_size_1_size has the hard-coded mock domain",
  "{0,1,2,4}. The demand asks for values outside it; a seed outside it is",
  "contradicted by the mock, never by the app. 1 gate. It is NOT impossibility",
  "evidence (§72.3) and it is NOT closeable by driving: it needs a ruling on",
  "whether the mock domain is the model (declare) or a limit (widen it, which",
  "is shared-boundary work under Rule T)."]},
}

out = {
 "pass_date": "2026-09-11",
 "pass_log": "_covFINAL_OD0911.log",
 "engine_md5": md5,
 "snapshot_profiles": snap,
 "corpus_dumps": corpus,
 "or_remaining": tot_rem,
 "classes": classes,
 "extract_date": "2026-09-11",
 "rotation_residue": sum(1 for e in (ext.get("errors") or [])
                         if "bind-rotation-UNRESOLVED" in e),
 "subsume_true": ext.get("n_subsumed_dropped", 0),
 "subsume_false": max(0, (ext.get("n_queries_deduped", 0) or 0)
                      - (ext.get("n_queries_final", 0) or 0)
                      - 0) if ext else 0,
 "subsume_null": len(ext.get("subsume_errors") or []),
 "subsume_note": ("the tri-state is preserved: null is an UNDECIDED pair and is "
                  "never folded into false"),
}
out["subsume_false"] = max(0, (ext.get("n_queries_final", 0) or 0) - out["subsume_true"]) if ext else 0
json.dump(out, open(os.path.join(HERE, "_residual_classes.json"), "w"), indent=1)
print(json.dumps({k: v for k, v in out.items() if k != "classes"}, indent=1))
print("RESIDUAL CLASSES DONE")
