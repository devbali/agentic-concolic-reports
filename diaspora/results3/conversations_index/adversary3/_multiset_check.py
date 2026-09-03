#!/usr/bin/env python3
"""Per-request STATEMENT-MULTISET differential (adversary round 3).

The judges (`mock_note_check`, `note_fidelity_audit`) ask "does SOME corpus
note have this SHAPE".  This asks the completion question instead: is the
MULTISET of statements this real request issued a multiset the corpus
contains?  A real request whose multiset no corpus dump carries is a state
the corpus does not model, even when every one of its statements has a note.

    python3 _multiset_check.py <batch> <run.json> [<run.json> ...] [--sample N]
"""
import collections
import glob
import json
import os
import re
import sys

SKIP = re.compile(r"^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)", re.I)


def shape(sql):
    s = re.sub(r"[`\"]", "", str(sql))
    s = re.sub(r"\$\$\([^)]*\)|\?|\b\d+\b", "@", s)
    s = re.sub(r"'[^']*'", "@", s)
    s = re.sub(r"\b(true|false)\b", "@", s)
    s = re.sub(r"\(\s*@\s*(,\s*@\s*)+\)", "(@)", s)      # IN (@, @) -> IN (@)
    return re.sub(r"\s+", " ", s).strip().lower()


LABEL = [('from users', 'users'), ('people.owner_id', 'people.owner_id'),
         ('select contacts.id', 'contacts_pluck'), ('@ as one from contacts', 'contacts_exists'),
         ('subquery_for_count', 'vis_count'), ('t0_r0', 'vis_rows'),
         ('count(*) from messages', 'msg_count'), ('messages.author_id from messages', 'msg_pluck'),
         ('from messages where', 'msg_rows'),
         ('count(*) from people inner join', 'part_count'),
         ('from people inner join conversation_visibilities', 'part_rows'),
         ('from conversations inner join', 'conv_lookup'),
         ('@ as one from posts', 'post_exists'),
         ('unread > @', 'cv_first_unread'),
         ('update conversation_visibilities', 'UPDATE cv'),
         ('from conversation_visibilities where', 'cv_find'),
         ('from people where people.id', 'people.id'),
         ('from profiles where profiles.person_id = @ limit', 'profiles LIMIT'),
         ('from profiles where profiles.person_id = @', 'profiles preload')]


def label(sh):
    if ' in (' in sh:
        base = sh.replace(' in (@)', ' = @')
        for pat, name in LABEL:
            if pat in base:
                return name + ' [IN]'
    for pat, name in LABEL:
        if pat in sh:
            return name
    return sh[:48]


def corpus_multisets(batch, sample):
    files = sorted(glob.glob(os.path.join(batch, "dump_*.json")))
    if sample and len(files) > sample:
        step = len(files) / float(sample)
        files = [files[int(i * step)] for i in range(sample)]
    seen = collections.Counter()
    shapes = collections.Counter()
    for f in files:
        try:
            d = json.load(open(f))
        except Exception:
            continue
        ms = collections.Counter()
        for ev in d.get("events", []):
            if ev.get("type") != "symbolic_call":
                continue
            n = (ev.get("note") or "").strip()
            if not n or SKIP.match(n):
                continue
            if not re.match(r"^(SELECT|UPDATE|INSERT|DELETE)", n, re.I):
                continue
            sh = shape(n)
            shapes[label(sh)] += 1
            ms[label(sh)] += 1
        seen[tuple(sorted(ms.items()))] += 1
    return seen, shapes, len(files)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sample = 0
    for a in sys.argv[1:]:
        if a.startswith("--sample"):
            sample = int(a.split("=", 1)[1])
    batch, runs = args[0], args[1:]
    corpus, cshapes, nfiles = corpus_multisets(batch, sample)
    print(f"== corpus: {nfiles} dumps, {len(corpus)} distinct statement multisets, "
          f"{len(cshapes)} distinct statement shapes ==\n")
    corpus_labels = set(cshapes)
    for rp in runs:
        print(f"---- {os.path.basename(rp)} ----")
        for sc in json.load(open(rp)):
            ms = collections.Counter()
            for st in sc.get("statements") or []:
                if SKIP.match(st["sql"].strip()):
                    continue
                ms[label(shape(st["sql"]))] += 1
            key = tuple(sorted(ms.items()))
            exact = corpus.get(key, 0)
            novel = sorted(k for k in ms if k not in corpus_labels)
            # is there a corpus dump whose multiset CONTAINS this one?
            superset = 0
            for ck, cv in corpus.items():
                cm = dict(ck)
                if all(cm.get(k, 0) >= v for k, v in ms.items()):
                    superset += cv
            # SET level: multiplicity aside, does any corpus dump have this
            # exact SET of statement shapes (the D1 multiset under-count is a
            # separate, already-declared limit)?
            sset = frozenset(ms)
            set_exact = sum(v for k, v in corpus.items() if frozenset(dict(k)) == sset)
            set_super = sum(v for k, v in corpus.items() if sset <= frozenset(dict(k)))
            verdict = ("EXACT" if exact else
                       ("COVERED-BY-SUPERSET" if superset else "NO-CORPUS-COUNTERPART"))
            sverdict = ("SET-EXACT" if set_exact else
                        ("SET-SUBSET-OF" if set_super else "SET-NOVEL"))
            print(f"  {sc['name']:34s} {verdict:22s} {sverdict:14s} exact={exact:5d} "
                  f"superset={superset:6d} set_exact={set_exact:6d} set_super={set_super:6d}"
                  f"{'  NOVEL-SHAPES=' + ','.join(novel) if novel else ''}")
            print(f"      {dict(ms)}")
        print()


main()
