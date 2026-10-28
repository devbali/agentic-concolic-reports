#!/usr/bin/env python3
"""apply_pipeline_round2.py — harness repairs for the SECOND e2e sweep.

Staged separately from round 1 so the first sweep's 161 results stay
homogeneous.  Three changes, each with its reason:

P-1  run_complete over EVERY accepted dump, not just the highest-reach one.
     The shakedown deliberately passed a single dump so that a `complete:
     true` would be visible as a defect.  That made every verdict
     `coverage_complete: false` by construction, which answers nothing about
     the endpoint.  With MAX_RUNS raised, endpoints now carry up to a dozen
     dumps and the real question — is the explored tree complete — can be
     asked.  The one-dump guard is kept for endpoints that really do have
     one dump.

P-2  build_policy over EVERY accepted dump, and DEGRADE rather than fail when
     the builder refuses one.  `diaspora_federation_h_card_hcard` is refused
     wholesale today because its richest dump carries a `Contains(…)` path
     condition outside §7.2's sub-language; the endpoint's other dumps build
     fine.  Refusing the endpoint hides the eight policies that would have
     built.  Each refusal is recorded with the dump it came from and the
     builder's own message, and the endpoint is still marked as carrying a
     representability defect.

P-5  a per-endpoint NOTE CENSUS: how many accesses carry a statement, a
     write, prose, or NO note at all — the brief's "a statement in a note
     that is wrong or missing", decided with the domain's own classifier.

P-4  measure how many atoms are lost purely to the note-envelope
     misclassification (findings/SRC_NEW_DEFECTS.md S-6), without touching
     src_new and without changing any artifact.

P-3  record the SQL/render acceptance signals per endpoint (unsupported and
     unrendered atoms, dropped conditions) as explicit findings rather than
     counts buried in `render`.
"""
from __future__ import annotations
import shutil, sys

PIPE = "/home/dev/project/reports/autolab/e2e/tools/pipeline.py"

OLD_RC = "        summary = run_complete([best_run], config=cfg)"
NEW_RC = '''        # P-1: EVERY accepted dump, not just the highest-reach one.
        all_runs = [r for (_f, r, _rec) in runs]
        summary = run_complete(all_runs, config=cfg)'''

OLD_ONE = '''        if (summary.get("coverage_complete") is True
                and res["completion"]["path_conditions_in_chosen_dump"] > 0
                and summary.get("total_runs", 0) < 2):'''
NEW_ONE = '''        if (summary.get("coverage_complete") is True
                and res["completion"]["path_conditions_in_chosen_dump"] > 0
                and summary.get("total_runs", 0) < 2):'''

OLD_BP = '''        cert = Certificate(app=f"autolab/shakedown/{endpoint_id}")
        policy = build_policy([best_run], entrypoint=entrypoint, certificate=cert)
        res["policy"] = {"atoms_unmerged": len(policy.atoms),
                         "signatures": len(policy.signatures or {})}'''
NEW_BP = '''        cert = Certificate(app=f"autolab/e2e/{endpoint_id}")
        # P-2: build over EVERY accepted dump; when the builder refuses one,
        # record WHICH dump and WHY and rebuild from the rest, rather than
        # losing the endpoint's whole policy to one unrepresentable term.
        usable = [(f, r) for (f, r, _rec) in runs]
        refused = []
        policy = None
        while usable and policy is None:
            try:
                policy = build_policy([r for (_f, r) in usable],
                                      entrypoint=entrypoint, certificate=cert)
            except Exception as be:
                msg = str(be).replace("\\n", " ")
                hit = None
                for (f, _r) in usable:
                    lbl = os.path.basename(f)[len("dump_"):-len(".json")]
                    if lbl and lbl in msg:
                        hit = (f, _r)
                        break
                if hit is None:
                    raise
                refused.append({"dump": os.path.basename(hit[0]),
                                "type": type(be).__name__, "message": msg[:600]})
                usable = [t for t in usable if t[0] != hit[0]]
                policy = None
        if policy is None:
            raise RuntimeError(
                "every accepted dump was refused by build_policy: "
                + "; ".join(r["message"][:200] for r in refused))
        res["policy"] = {"atoms_unmerged": len(policy.atoms),
                         "signatures": len(policy.signatures or {}),
                         "built_from_dumps": len(usable),
                         "refused_dumps": refused}
        if refused:
            res["failures"].append(
                {"stage": "build_policy", "type": "DumpNotRepresentable",
                 "message": "; ".join(f"{r['dump']}: {r['message'][:220]}"
                                      for r in refused)})'''

OLD_RENDER = '''            res["render"] = {"views": len(r.views),
                             "unsupported_atoms": len(r.unsupported),
                             "unrendered_atoms": len(r.unrendered),
                             "dropped_conditions": len(r.dropped_conditions),
                             "sql_lines": len(sql.splitlines())}'''
NEW_RENDER = '''            res["render"] = {"views": len(r.views),
                             "unsupported_atoms": len(r.unsupported),
                             "unrendered_atoms": len(r.unrendered),
                             "dropped_conditions": len(r.dropped_conditions),
                             "sql_lines": len(sql.splitlines()),
                             "unsupported_detail": [str(x)[:200] for x in r.unsupported][:10],
                             "unrendered_detail": [str(x)[:200] for x in r.unrendered][:10],
                             "dropped_detail": [str(x)[:200] for x in r.dropped_conditions][:10]}
            # P-3: a dropped condition or an unrendered atom is a LOSS in the
            # rendered view, not a neutral count. Recorded as a finding.
            # P-5: A NOTE CENSUS, per endpoint.
            # The brief asks for "any statement in a note that is wrong,
            # missing, or fabricated relative to what the code would really
            # issue". Two of those three are mechanically decidable from the
            # policy: a note that is ABSENT on an access (the call reached the
            # store and said nothing about it) and a note that is PROSE where
            # a statement belongs. The classifier used is the domain's own, so
            # this cannot disagree with what the renderer thinks a note is.
            # `refs` completeness is already enforced upstream by
            # `validate_provenance` (a dangling bind or a dead ref refuses the
            # dump), so it is not re-checked here.
            try:
                from domains.ruby_rails_sql.render import classify_note as _cn
                from concolic.model import note as _nm
                census = {"select": 0, "write": 0, "nonquery": 0,
                          "prose": 0, "absent": 0}
                prose_examples, absent_targets = [], []
                for a in (normed.atoms or ()):
                    acc = getattr(a, "access", None)
                    if acc is None:
                        continue
                    raw_note = getattr(acc, "note", None)
                    kind = _cn(raw_note)
                    if kind == "prose":
                        # re-ask with the envelope unwrapped, so S-6 does not
                        # masquerade as a prose note
                        kind = _cn(_nm.resolved(raw_note))
                    census[kind] = census.get(kind, 0) + 1
                    if kind == "prose" and len(prose_examples) < 5:
                        prose_examples.append(
                            {"target": getattr(acc, "target", None),
                             "note": str(raw_note)[:200]})
                    if kind == "absent" and len(absent_targets) < 10:
                        absent_targets.append(getattr(acc, "target", None))
                res["notes"] = {"census": census,
                                "prose_on_an_access": prose_examples,
                                "access_with_no_note": absent_targets}
                if census["absent"]:
                    res["failures"].append(
                        {"stage": "notes", "type": "AccessWithNoStatementNote",
                         "message": f"{census['absent']} access event(s) carry no "
                                    "statement note, so nothing in the corpus says "
                                    "that call reached the store: "
                                    + ", ".join(str(t) for t in absent_targets[:5])})
                if census["prose"]:
                    res["failures"].append(
                        {"stage": "notes", "type": "ProseNoteOnAnAccess",
                         "message": f"{census['prose']} access event(s) carry PROSE "
                                    "where a statement belongs: "
                                    + "; ".join(f"{e['target']}: {e['note'][:80]}"
                                               for e in prose_examples)})
            except Exception as _e:
                res["notes"] = {"probe_failed": str(_e)}

            # P-4: QUANTIFY S-6 without touching src_new.
            # `domains/ruby_rails_sql/render.py:classify_note` takes the
            # FIRST TOKEN of the raw note, and §4.1.1c's note is a JSON
            # envelope, so every structured note classifies as `prose` and no
            # atom is renderable. Proof:
            #   classify_note('SELECT ...')                      -> select
            #   classify_note('{"refs": {...}, "text": "SELECT"}') -> prose
            #   classify_note(note.parse(<that>).text)            -> select
            # This re-asks the SAME classifier with the payload unwrapped by
            # the sanctioned reader, so the number below is exactly "how many
            # atoms this endpoint loses to that one line".  It renders
            # nothing and changes no artifact.
            try:
                from concolic.model import note as _note_mod
                from domains.ruby_rails_sql.render import classify_note
                recovered = 0
                for a in (normed.atoms or ()):
                    acc = getattr(a, "access", None)
                    raw_note = getattr(acc, "note", None) if acc is not None else None
                    if raw_note is None:
                        continue
                    if classify_note(raw_note) == "select":
                        continue
                    if classify_note(_note_mod.resolved(raw_note)) == "select":
                        recovered += 1
                res["render"]["atoms_lost_to_note_envelope"] = recovered
            except Exception as _e:
                res["render"]["atoms_lost_to_note_envelope"] = f"probe failed: {_e}"
            if r.unrendered or r.dropped_conditions:
                res["failures"].append(
                    {"stage": "render_sql", "type": "RenderIncomplete",
                     "message": f"{len(r.unrendered)} atom(s) did not render and "
                                f"{len(r.dropped_conditions)} condition(s) were "
                                "dropped from the rendered SQL"})'''


def main():
    apply = "--apply" in sys.argv
    s = open(PIPE).read()
    edits = [(OLD_RC, NEW_RC), (OLD_BP, NEW_BP), (OLD_RENDER, NEW_RENDER)]
    for old, new in edits:
        n = s.count(old)
        if n != 1:
            print(f"!! anchor x{n}: {old[:70]!r}")
            return 1
        s = s.replace(old, new)
    if apply:
        shutil.copy(PIPE, PIPE + ".bak_round1")
        open(PIPE, "w").write(s)
        print("pipeline.py patched (backup at pipeline.py.bak_round1)")
    else:
        print("all 3 anchors unique; would patch pipeline.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
