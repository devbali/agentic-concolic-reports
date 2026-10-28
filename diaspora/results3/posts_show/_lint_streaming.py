#!/usr/bin/env python3
"""statement_note_lint, STREAMED — identical verdict, O(1) memory.

WHY (2026-09-11). The shipped lint was killed at 5.9 GB on this endpoint's
129 606-dump directory. The cause is one line:

    all_events = []                      # statement_note_lint.py:~52
    for f in files:
        d = json.load(open(f))
        for ev in d.get("events") or []:
            ...
            all_events.append(ev)        # EVERY symbolic_call event of EVERY dump

It retains every symbolic_call event dict of the whole corpus so that pass 2 can
classify them AFTER pass 1 has learned `noted_targets`. Only the small
`noted_targets` SET is actually needed between the passes.

AND CHUNKING IT WOULD BE UNSOUND. `noted_targets` is CORPUS-GLOBAL -- the lint's
own rule is "only a target with ZERO noted events ANYWHERE is a wall". Split the
directory in two and a target noted only in chunk B is reported as JUNK in chunk
A. Pruning is unsound too: `_note_invariance.py` measured 63 of 15 542 outcome
profiles carrying MORE THAN ONE note set, so the pruned list is not a faithful
input for a note-level audit.

So neither of the two cheap inputs is sound; the sound fix is to stream. This
reproduces the shipped logic EXACTLY -- same regexes, same branch order, same
bucket keys, same red rule, same exit code -- in two streaming passes over the
same file list, holding only `noted_targets` and the counters.
"""
import glob, json, os, re, sys
from collections import defaultdict

JUNK_RE = re.compile(r"WHERE unavailable|render_relation_sql failed|query \(")
FINDER_RE = re.compile(r"find_by|exists\?|FinderMethods\.find\b")
PLUCK_RE = re.compile(r"\b(pluck|pick)\b")
AGG_RE = re.compile(r"Calculations\.(count|sum|average|minimum|maximum)")
STAR_RE = re.compile(r'^SELECT "[^"]+"\.\*')


def main():
    batch = sys.argv[1]
    lst = os.environ.get("DUMP_LIST")
    if lst:
        files = [l.strip() for l in open(lst) if l.strip()]
        files = [f if os.path.isabs(f) else os.path.join(batch, f) for f in files]
    else:
        files = glob.glob(os.path.join(batch, "dump_*.json"))
    if not files:
        sys.exit(f"no dumps for {batch}")

    # ---- pass 1: the ONLY cross-dump state the verdict needs ---------------
    noted_targets = set()
    for i, f in enumerate(files):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        for ev in d.get("events") or []:
            if ev.get("type") == "symbolic_call" and ev.get("result_name") is not None \
                    and ev.get("note"):
                noted_targets.add(str(ev.get("target") or ""))
        del d
        if i % 20000 == 0:
            print(f"  [pass1 {i}/{len(files)}] noted_targets={len(noted_targets)}",
                  flush=True)
    print(f"pass 1 done: {len(noted_targets)} targets carry a real note somewhere",
          flush=True)

    # ---- pass 2: classify, retaining only the counters ---------------------
    buckets = {k: defaultdict(int) for k in ("junk", "no_where", "star_pluck", "star_agg")}
    ok = 0
    for i, f in enumerate(files):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        for ev in d.get("events") or []:
            if ev.get("type") != "symbolic_call" or ev.get("result_name") is None:
                continue
            note = str(ev.get("note") or "")
            target = str(ev.get("target") or "")
            key = f"{target} | {note[:90]}"
            if (not note and target not in noted_targets) or (note and JUNK_RE.search(note)):
                buckets["junk"][key] += 1
            elif not note:
                ok += 1
            elif FINDER_RE.search(target) and note.startswith("SELECT") and " WHERE " not in note:
                buckets["no_where"][key] += 1
            elif PLUCK_RE.search(target) and STAR_RE.match(note):
                buckets["star_pluck"][key] += 1
            elif AGG_RE.search(target) and STAR_RE.match(note):
                buckets["star_agg"][key] += 1
            else:
                ok += 1
        del d
        if i % 20000 == 0:
            print(f"  [pass2 {i}/{len(files)}]", flush=True)

    def dump(title, h):
        print(f"-- {title}: {sum(h.values())} events, {len(h)} distinct --")
        for k, c in sorted(h.items(), key=lambda kv: -kv[1])[:20]:
            print(f"  {c:8d}  {k}")
        print()

    print(f"== statement_note_lint (STREAMED): {len(files)} dumps, {ok} clean notes ==\n")
    dump("NO-WHERE finder notes (Class S, red)", buckets["no_where"])
    dump("STAR-PLUCK notes (Class S, red)", buckets["star_pluck"])
    dump("STAR-AGGREGATE notes (warn — broader than real COUNT/SUM statement)", buckets["star_agg"])
    dump("JUNK notes (warn — verify each is a documented wall)", buckets["junk"])
    red = bool(buckets["no_where"]) or bool(buckets["star_pluck"])
    print("RESULT: RED findings above." if red else "RESULT: no red-level note findings.")
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
