#!/usr/bin/env python3
"""POLICY COVERAGE — which tables and table.columns a policy file mentions.

    policy_coverage.py <base.sql> <new.sql> [<base.sql> <new.sql> ...]

A differential for "nothing was lost": for each pair it prints the tables and
``table.column`` references present in the BASE file and missing from the NEW
one (and the other way round). Aliases are resolved to their real table, so
``posts0.public`` counts as ``posts.public``.

This is a PROXY, not a policy comparison: it says which of the schema a file
still speaks about, which is the cheap way to notice that a rewrite dropped a
relation or a column reference outright. It says nothing about whether the
statements mean the same thing.
"""
import sys

import sqlglot
from sqlglot import exp


def statements(path):
    body = "".join(
        l for l in open(path, encoding="utf-8", errors="replace")
        if not l.lstrip().startswith("--")
    )
    return [s.strip() for s in body.split(";") if s.strip()]


def coverage(path):
    tables, cols, bad = set(), set(), 0
    for sql in statements(path):
        try:
            ast = sqlglot.parse_one(sql, read="mysql")
        except Exception:
            bad += 1
            continue
        alias = {}
        for t in ast.find_all(exp.Table):
            tables.add(t.name)
            alias[t.alias_or_name] = t.name
        for c in ast.find_all(exp.Column):
            if c.name.startswith("_"):
                continue
            t = alias.get(c.table, c.table)
            cols.add(f"{t}.{c.name}" if t else c.name)
    return tables, cols, bad


def main():
    args = sys.argv[1:]
    if len(args) < 2 or len(args) % 2:
        sys.exit(__doc__)
    for i in range(0, len(args), 2):
        base, new = args[i], args[i + 1]
        bt, bc, bb = coverage(base)
        nt, nc, nb = coverage(new)
        print(f"== {base.split('/')[-1]}  ->  {new.split('/')[-1]}")
        print(f"   tables  base={len(bt):3d} new={len(nt):3d} "
              f"lost={len(bt - nt):2d} gained={len(nt - bt):2d}"
              + (f"   LOST: {sorted(bt - nt)}" if bt - nt else ""))
        print(f"   columns base={len(bc):3d} new={len(nc):3d} "
              f"lost={len(bc - nc):2d} gained={len(nc - bc):2d}"
              + (f"   LOST: {sorted(bc - nc)}" if bc - nc else ""))
        if bb or nb:
            print(f"   [unparseable statements: base={bb} new={nb}]")


if __name__ == "__main__":
    main()
