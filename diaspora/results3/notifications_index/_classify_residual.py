#!/usr/bin/env python3
"""Classify residual (blocking) witnesses of a coverage_summary by the KIND of
variable their demanded cube constrains.

The §10.5 split, re-derived here as ONE instrument so a baseline number and a
post-drive number are produced by the same code rather than quoted from a
report. Reads `node_constraint` (the cube), not `concrete_values` (which is a
whole model and names variables the cube does not constrain).

usage: _classify_residual.py <coverage_summary.json> [more.json ...]
env:   DUMP_IDENT=<path>   also write every identity var name + count there
"""
import json, os, re, sys, collections

# The variable occurrences inside a node_constraint string.
VAR = re.compile(r'\bSYM_[A-Za-z0-9_]+')

# IDENTITY families (§10.5). A cube that constrains one of these constrains a
# value the MOCKS DERIVE, not one any seed key feeds.
IDENT_SUFFIX = ('_person_id', '_row_id', '_guid', '_diaspora_handle', '__prior')
IDENT_RE = re.compile(r'(' + '|'.join(re.escape(s) for s in IDENT_SUFFIX) + r')$')

def kind(v):
    # SYM_LEN_X constrains len(X); the underlying X is what the seeder varies,
    # so map it back before asking whether X is an identity column.
    base = v[len('SYM_LEN_'):] if v.startswith('SYM_LEN_') else v
    if IDENT_RE.search(base):
        for s in IDENT_SUFFIX:
            if base.endswith(s):
                return 'identity', s
    if base.endswith('_row_type'):
        return 'row_type', '_row_type'
    return 'seeded', None

def classify(path):
    d = json.load(open(path))
    miss = [m for m in d['missing'] if m.get('missing_branch') == 'combination']
    tot = len(d['missing'])
    n_id = n_seed = n_rt = 0
    fam = collections.Counter()
    names = collections.Counter()
    for m in miss:
        vs = set(VAR.findall(m.get('node_constraint') or ''))
        has_id = False; has_rt = False
        for v in vs:
            k, s = kind(v)
            if k == 'identity':
                has_id = True; fam[s] += 1; names[v] += 1
            elif k == 'row_type':
                has_rt = True
        if has_id:
            n_id += 1
        elif has_rt:
            n_rt += 1
        else:
            n_seed += 1
    return dict(path=path, total_missing=tot, combination=len(miss),
                seeded_only=n_seed, identity=n_id, row_type=n_rt,
                fam=dict(fam), names=names,
                tree_missing=len(d.get('tree_missing') or []),
                demand_sets=d.get('demand_sets'))

if __name__ == '__main__':
    allnames = collections.Counter()
    for p in sys.argv[1:]:
        r = classify(p)
        allnames.update(r['names'])
        c = r['combination'] or 1
        print(f"\n=== {r['path']}")
        print(f"  missing={r['total_missing']}  combination={r['combination']}  "
              f"demand_sets={r['demand_sets']}  tree_missing={r['tree_missing']}")
        print(f"  seeded-only        {r['seeded_only']:6d}  {100*r['seeded_only']/c:5.1f} %")
        print(f"  ALSO identity      {r['identity']:6d}  {100*r['identity']/c:5.1f} %")
        print(f"  derived row_type   {r['row_type']:6d}  {100*r['row_type']/c:5.1f} %")
        print(f"  identity families: " + ", ".join(f"{k}={v}" for k, v in
              sorted(r['fam'].items(), key=lambda kv: -kv[1])))
    out = os.environ.get('DUMP_IDENT')
    if out:
        with open(out, 'w') as f:
            json.dump(allnames.most_common(), f, indent=1)
        print(f"\nidentity var names -> {out} ({len(allnames)} distinct)")
