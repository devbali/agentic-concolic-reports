#!/usr/bin/env python3
"""Check diaspora's app.json against the app's own schema.rb.

The E12 refactor moved the reconstruction constants (principal/identity
tables and columns, pinned values, symbol-name shapes, inflections) OUT of
`src/queries_from_runs` and INTO this config. Nothing in `src/` can notice a
typo in them any more — a misspelt identity column would silently stop
emitting the principal join. This script is that safety net: everything that
CAN be derived from `schema.rb` is checked against it.

    reports/diaspora/queries_config/validate_app_json.py   # exit 0 = clean

Checked:
  * every table in principal.principal_columns exists, and so does its column;
  * principal.principal_table exists;
  * principal.identity.{table,id_column,guid_column} exist;
  * the identity table has an owner column in principal_columns;
  * every principal.binds.* value compiles as a regex;
  * every FK line in resources/fk.txt names real tables/columns;
  * every principal.identity.ref_fallback_columns name is a real column of at
    least one table;
  * cli.* paths that are set exist on disk.
NOT checkable here (no machine-readable source): the pinned values and the
symbol-name shapes, which are properties of the driver's targets.rb.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")

from queries_from_runs import app_config, schema as schema_mod  # noqa: E402


def main() -> int:
    cfg = app_config.load(os.path.join(HERE, "app.json"))
    sch = schema_mod.load_schema(cfg.schema_rb)
    bad = []

    def col(t, c, what):
        if t not in sch:
            bad.append(f"{what}: table {t!r} not in schema.rb")
        elif c not in sch[t]:
            bad.append(f"{what}: {t}.{c} not in schema.rb")

    prin = cfg.principal
    if prin.principal_table not in sch:
        bad.append(f"principal.principal_table {prin.principal_table!r} not in schema.rb")
    for t, c in prin.principal_columns.items():
        col(t, c, "principal.principal_columns")

    ident = prin.identity
    if ident is None:
        bad.append("principal.identity is absent — no identity join will be emitted")
    else:
        col(ident.table, ident.id_column, "principal.identity.id_column")
        if ident.guid_column:
            col(ident.table, ident.guid_column, "principal.identity.guid_column")
        if not prin.identity_owner_column():
            bad.append(f"principal.principal_columns has no entry for the identity "
                       f"table {ident.table!r}: the identity join cannot be emitted")
        else:
            col(ident.table, prin.identity_owner_column(), "identity owner column")
        for c in ident.ref_fallback_columns:
            if not any(c in cols for cols in sch.values()):
                bad.append(f"identity.ref_fallback_columns: {c!r} is no table's column")

    for name in ("uid", "request_param", "identity_id", "identity_prefix",
                 "non_principal_identity_name", "non_principal_identity_note"):
        pat = getattr(prin.binds, name)
        if pat is None:
            bad.append(f"principal.binds.{name} is unset")
            continue
        try:
            re.compile(pat)
        except re.error as e:
            bad.append(f"principal.binds.{name} is not a regex: {e}")

    n_fk = 0
    for line in open(cfg.fk_txt):
        line = line.strip().rstrip(";")
        if not line or line.startswith("--"):
            continue
        m = re.match(r"(\w+)\.(\w+):(\w+)\.(\w+)$", line)
        if not m:
            bad.append(f"fk.txt: unparseable line {line!r}")
            continue
        n_fk += 1
        col(m.group(1), m.group(2), "fk.txt from")
        col(m.group(3), m.group(4), "fk.txt to")

    for key, path in sorted(cfg.cli.items()):
        if path and not os.path.exists(path):
            bad.append(f"cli.{key} does not exist: {path}")

    for b in bad:
        print("FAIL:", b)
    print(f"checked {len(sch)} tables, {len(prin.principal_columns)} principal "
          f"columns, {n_fk} FK lines against {os.path.basename(cfg.schema_rb)}")
    if bad:
        return 1
    print("OK: app.json agrees with the app's schema.rb")
    return 0


if __name__ == "__main__":
    sys.exit(main())
