#!/usr/bin/env python3
"""Backfill `concolic_scenario` into corpus dumps that predate run_dse.rb
recording it (2026-09-19, completion-gate build).

`assumption_checker._index_row` reads a dump's scenario from
`concolic_scenario.name`, and `_run_chunk` keeps only probe dumps whose
scenario matches the chunk's. A corpus without the key indexes every dump as
scenario `None`, so each probe replays all nine scenarios and none of its
dumps match. run_dse.rb now writes the key natively; this script adds it to
dumps written before that change.

The value is DERIVED FROM THE FILENAME, which the runner itself composed as
`dump_<scenario>_<nnnn><suffix>.json` — no guessing: the scenario name is
matched against the runner's own SCENARIOS list, longest first (so
`anon_mobile_presenter` is never read as `anon_mobile`), and a file that
matches none is left untouched and reported.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCEN = ["anon_handle", "anon_json", "anon_mobile", "anon_mobile_presenter",
        "auth_self_html", "auth_other_html", "auth_json", "auth_mobile",
        "anon_remote_401"]
# longest first: anon_mobile_presenter must win over anon_mobile
SCEN_BY_LEN = sorted(SCEN, key=len, reverse=True)
FMT = {"anon_json": "json", "auth_json": "json",
       "anon_mobile": "mobile", "anon_mobile_presenter": "mobile",
       "auth_mobile": "mobile"}
SIGNED = {"auth_self_html", "auth_other_html", "auth_json", "auth_mobile"}


def main() -> int:
    added = skipped = present = 0
    unmatched = []
    for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
        base = os.path.basename(p)[len("dump_"):]
        scen = next((s for s in SCEN_BY_LEN if base.startswith(s + "_")), None)
        if scen is None:
            unmatched.append(base)
            continue
        try:
            with open(p) as fh:
                d = json.load(fh)
        except Exception as e:  # noqa: BLE001
            unmatched.append(f"{base}: {type(e).__name__}")
            continue
        if isinstance(d.get("concolic_scenario"), dict) and d["concolic_scenario"].get("name"):
            present += 1
            continue
        d["concolic_scenario"] = {"name": scen,
                                  "format": FMT.get(scen, ""),
                                  "signed_in": scen in SIGNED}
        tmp = p + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(d, fh, indent=2)
        os.replace(tmp, p)
        added += 1
    print(f"concolic_scenario: added={added} already_present={present} skipped={skipped}")
    if unmatched:
        print(f"UNMATCHED ({len(unmatched)}): {unmatched[:10]}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
