#!/usr/bin/env python3
"""C17 — RESOLVE A RE-MINTED LIST LENGTH TO THE KEY THE RUNTIME ACTUALLY READS.

THE DEFECT (measured by `_c17_seedkey_probe.py`, 600 bases):

  * every `len(X)` whose mint calls `ConcolicTargets.seed_for` honours its
    seed — 2 150 / 2 150 = 100.0 %;
  * the LOADED-TARGET EARLY RETURN in `targets.rb` (the CollectionProxy
    `records`/`load_target` mock, the branch whose note begins
    "preloaded association #<assoc>: answered from the loaded target")
    re-mints an ALREADY DECIDED length under an OWNER-DERIVED name
    (`IterableSymbolicList.new(tgt.length, name: "#{ob}_#{assoc}_row_rows")`)
    and never consults a seed. 366 such keys were written into base seeds;
    233 of them (63.7 %) came back with a value different from the seed.

So `..._row_target_photos_row_rows` IS a symbolic list length and IS a
seedable DIMENSION — but not AT THAT NAME. The name is the second of two
names for one fact; the first name (`len(SYM_RESULT_..._CollectionProxy_
records_N_rows)`, the mock's seed-consulting mint) is where the runtime reads.

THE RESOLUTION, from the base dump alone and exactly (607/607 unique on the
600-base sample, and in 607/607 the upstream's VALUE equals the re-mint's):
  owner base  <- the re-mint's own name, minus "_<assoc>_row_rows"
  upstream    <- the unique materialize-mock length var whose note is
                 `SELECT "<table-of-assoc>".* ...` AND whose note binds
                 `$$(<owner base>_<col>)`.

usage as a library:  from _c17_seedkey_fix import remint_map, fix_seeds
usage as a test:     python3 -u _c17_seedkey_fix.py [dump.json ...]
"""
import json, os, re, sys

REMINT_NOTE = "preloaded association #"
BIND = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")
SEL  = re.compile(r'^SELECT\s+"([a-z_]+)"\.\*')
MATERIALIZE = (
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_load_target_",
    "len(SYM_RESULT_ActiveRecord__Relation_records_",
    "len(SYM_RESULT_ActiveRecord__Relation_to_a_",
    "len(SYM_RESULT_ActiveRecord__Relation_to_ary_",
)
# association name -> table it materializes. Only associations that actually
# reach the early return on this endpoint need an entry; the identity fallback
# (table == association name) covers every one but `followed_tags`.
ASSOC_TABLE = {"followed_tags": "tags"}


def _table_for(assoc):
    return ASSOC_TABLE.get(assoc, assoc)


def remint_map(dump):
    """{re-minted runtime seed key -> (upstream runtime seed key, value)}.

    A key absent from the result is not a re-mint (its own mint reads a seed).
    A key present with upstream None could not be resolved on this base.
    """
    svs = {}
    for sv in dump.get("symbolic_vars") or ():
        n = sv.get("name")
        if n:
            svs[n] = (sv.get("value"), sv.get("note") or "")
    cands = []
    for n, (v, nt) in svs.items():
        if not n.startswith(MATERIALIZE):
            continue
        m = SEL.match(nt)
        cands.append((n, v, m.group(1) if m else None, set(BIND.findall(nt))))
    out = {}
    for n, (v, nt) in svs.items():
        if not nt.startswith(REMINT_NOTE):
            continue
        assoc = nt[len(REMINT_NOTE):].split(":")[0].strip()
        base = n[4:-1] if n.startswith("len(") and n.endswith(")") else n
        suffix = "_%s_row_rows" % assoc
        if not base.endswith(suffix):
            out[n] = (None, v)
            continue
        ob = base[:-len(suffix)]
        tab = _table_for(assoc)
        hit = [c for c in cands if c[2] == tab and any(b.startswith(ob + "_") for b in c[3])]
        out[n] = ((hit[0][0] if len(hit) == 1 else None), v)
    return out


def fix_seeds(seeds, dump, keep_inert=True):
    """Rewrite a seed dict so a demand on a re-minted length lands on the key
    the runtime reads. Returns (new_seeds, [(remint, upstream, value)])."""
    rm = remint_map(dump)
    new = dict(seeds)
    moved = []
    for k, want in list(seeds.items()):
        up = rm.get(k, (None, None))[0]
        if up is None:
            continue
        new[up] = want
        if not keep_inert:
            new.pop(k, None)
        moved.append((k, up, want))
    return new, moved


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    paths = sys.argv[1:] or [os.path.join(here, "dump_html_typed_dse5288_DV100530htmt.json")]
    bad = 0
    for p in paths:
        d = json.load(open(p))
        seeds = d.get("concolic_seeds") or {}
        svs = {sv["name"]: sv.get("value") for sv in (d.get("symbolic_vars") or ()) if sv.get("name")}
        rm = remint_map(d)
        print("== %s" % os.path.basename(p))
        for k, (up, v) in sorted(rm.items()):
            s = seeds.get(k, "<not seeded>")
            inert = (up is not None and k in seeds and svs.get(k) != s)
            print("   re-mint  %s" % k)
            print("      minted %-4r  seed at this key %-6r  %s"
                  % (v, s, "INERT (seed ignored)" if inert else "seed matched by chance/unseeded"))
            print("      upstream %s  = %r" % (up, svs.get(up)))
            if up is None:
                bad += 1
            elif svs.get(up) != v:
                print("      *** upstream value != re-mint value")
                bad += 1
        new, moved = fix_seeds(seeds, d)
        print("   fix_seeds would move %d demands: %s" % (len(moved), [(m[1], m[2]) for m in moved]))
    print("C17-SEEDKEY-FIX-SELFTEST-%s" % ("FAIL" if bad else "OK"))
