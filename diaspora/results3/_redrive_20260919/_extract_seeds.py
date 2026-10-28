#!/usr/bin/env python3
"""Extract per-variant `concolic_seeds` from an endpoint's existing dump corpus.

Writes one JSON array of seed dicts per variant, suitable for that endpoint's
runner via EXTRA_SEEDS_JSON + SEEDS_ONLY=1 + VARIANT(S)=<variant>.

Faithfulness: seeds come from the corpus itself, grouped by the scenario/variant
that produced them. Nothing is re-selected or synthesised.

Usage: _extract_seeds.py <endpoint_dir> <out_dir> <endpoint_name> [--jobs N]
"""
import json
import os
import re
import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor


def read_one(path):
    try:
        with open(path, "rb") as fh:
            d = json.load(fh)
    except Exception as e:  # noqa: BLE001
        return ("__ERROR__", os.path.basename(path), f"{type(e).__name__}: {e}")
    scen = d.get("concolic_scenario") or {}
    variant = scen.get("name")
    if variant is None:
        # No recorded scenario (people_stream). Derive it from the label.
        # comments/conversations/notifications: "<variant>_dse####<suffix>"
        # people_stream:                        "<scenario>####<suffix>"
        lbl = (d.get("label") or os.path.basename(path)).replace("dump_", "")
        if "_dse" in lbl:
            variant = lbl.split("_dse")[0]
        else:
            m = re.match(r"^([a-z][a-z_]*?)\d{3,}", lbl)
            variant = m.group(1) if m else lbl
    seeds = d.get("concolic_seeds")
    return (variant, os.path.basename(path), seeds)


def main():
    endpoint_dir, out_dir, name = sys.argv[1], sys.argv[2], sys.argv[3]
    jobs = 16
    if "--jobs" in sys.argv:
        jobs = int(sys.argv[sys.argv.index("--jobs") + 1])

    files = [
        os.path.join(endpoint_dir, f)
        for f in os.listdir(endpoint_dir)
        if f.startswith("dump_") and f.endswith(".json")
    ]
    files.sort()
    print(f"{name}: {len(files)} dumps", flush=True)

    by_variant = defaultdict(list)
    no_seeds = 0
    errors = []
    with ProcessPoolExecutor(max_workers=jobs) as ex:
        for i, (variant, base, seeds) in enumerate(
            ex.map(read_one, files, chunksize=64)
        ):
            if variant == "__ERROR__":
                errors.append((base, seeds))
                continue
            if seeds is None:
                no_seeds += 1
                continue
            by_variant[variant].append(seeds)
            if (i + 1) % 25000 == 0:
                print(f"  ...{i+1}/{len(files)}", flush=True)

    os.makedirs(out_dir, exist_ok=True)
    manifest = {
        "endpoint": name,
        "source_dir": endpoint_dir,
        "total_dumps": len(files),
        "dumps_without_concolic_seeds": no_seeds,
        "read_errors": len(errors),
        "variants": {},
    }
    for variant, seedlist in sorted(by_variant.items()):
        p = os.path.join(out_dir, f"{name}__{variant}.json")
        with open(p, "w") as fh:
            json.dump(seedlist, fh)
        # distinctness check (seeds are dicts; compare canonical JSON)
        distinct = len({json.dumps(s, sort_keys=True) for s in seedlist})
        manifest["variants"][variant] = {
            "seeds": len(seedlist),
            "distinct_seeds": distinct,
            "file": p,
        }
        print(
            f"  {variant}: {len(seedlist)} seeds ({distinct} distinct) -> {p}",
            flush=True,
        )

    mp = os.path.join(out_dir, f"{name}__MANIFEST.json")
    with open(mp, "w") as fh:
        json.dump(manifest, fh, indent=2)
    print(f"  no_seeds={no_seeds} errors={len(errors)} manifest={mp}", flush=True)
    if errors:
        for b, e in errors[:10]:
            print(f"    ERR {b}: {e}", flush=True)


if __name__ == "__main__":
    main()
