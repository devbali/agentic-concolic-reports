#!/usr/bin/env python3
"""cost.py — what each endpoint's cloud attempts used: VMs, time, tokens, money.

THE DATA EXISTED AND NOTHING JOINED IT. Three files each held a third of the
answer and none of them is keyed by endpoint:

    entrypoints/sweep_out_*/workers.jsonl        one APPEND per worker state
                                                change: wall_s, box_hours,
                                                tokens, cost, turns
    entrypoints/sweep_out_*/queue/entries/*.json the BOX: cluster name, the
                                                instance type SkyPilot's
                                                optimizer actually chose,
                                                region, launch/teardown times
    src_new/sweep/console/api.py                the PRICE: SkyPilot's own
                                                catalog, with a small fallback
                                                table for when it cannot load

This joins them on the worker id — `workers.jsonl`'s `worker_id` and a queue
entry's `id` are the same string — and keys the result by endpoint.

WHAT AN ATTEMPT IS, AND WHAT IT IS NOT. An attempt is a cloud box that was
launched FOR an endpoint. It is NOT the provenance of that endpoint's stored
artefacts: 159 of the 161 endpoints in `endpoints/` were produced by the local
verification round, and a cloud attempt on the same endpoint may have been
torn down without producing anything. `attempts_that_produced_a_stored_run` is
recorded separately and is the only field that connects the two.

MONEY IS NEVER INFERRED FROM ABSENCE. `workers.jsonl` carries a `cloud_usd`
field and it is 0.0 on every record ever written, because nothing computed it
while the sweep ran; a 0 there means "not computed", not "free". This tool
computes it from `box_hours × the hourly rate for the instance type that ran`,
records which price source answered, and leaves it **null** when no source
could — the §11.2.1 reading, and the same rule the console's price column
already follows ("Unknown — reported as unknown, never as zero").

    tools/cost.py                 print the rollup
    tools/cost.py --endpoint EP   print one endpoint's attempts
    tools/cost.py --json          the whole join, as JSON

`build_store.py` imports `records()` and writes each endpoint's record to
`endpoints/<ep>/cloud.json` plus a summary into its `stats.json`, so a rebuild
reproduces this rather than deleting it.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import typing as t
from pathlib import Path

ROOT = Path("/home/dev/project")
LAB = Path(__file__).resolve().parent.parent
#: SkyPilot lives in its own venv, so the catalog reader needs to be told
#: which interpreter can `import sky`. The console reads the same variable.
SKY_PYTHON = str(ROOT / "venvs/sky/bin/python")


# ---------------------------------------------------------------------------
# the three inputs
# ---------------------------------------------------------------------------

def _latest_worker_rows(lab: Path) -> t.Dict[str, dict]:
    """The LAST record per worker id. `workers.jsonl` is append-only and a
    worker is re-emitted on every state change, so the last line is its
    current state and every earlier one is history."""
    out: t.Dict[str, dict] = {}
    for f in sorted(lab.glob("entrypoints/sweep_out_*/workers.jsonl")):
        run = f.parent.name
        for line in f.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            wid = d.get("worker_id")
            if not wid:
                continue
            d["_sweep_run"] = run
            out[wid] = d
    return out


def _box_records(lab: Path) -> t.Dict[str, dict]:
    """`{worker id: the box the queue recorded for it}`. Only entries that got
    a box: a queued entry that never launched has none, and that is the honest
    reading — no VM, so no VM cost."""
    out: t.Dict[str, dict] = {}
    for f in sorted(lab.glob("entrypoints/sweep_out_*/queue/entries/*.json")):
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        box = d.get("box")
        if not isinstance(box, dict):
            continue
        wid = d.get("id")
        if not wid:
            continue
        box = dict(box)
        box["_queue_state"] = d.get("state")
        box["_last_error"] = d.get("last_error") or ""
        box["_attempt"] = d.get("attempt")
        out[wid] = box
    return out


class Pricer:
    """Hourly USD for an instance type in a region, and WHICH source said so.

    Asks SkyPilot's own catalog through the console's reader, then the
    console's fallback table, then gives up — and `source_for` names which, so
    a figure can never be mistaken for a better-sourced one than it is.
    """

    def __init__(self) -> None:
        self._cat = None
        self._fallback: t.Mapping[str, float] = {}
        self._fallback_as_of = ""
        self.catalog_source = ""
        self.catalog_error = ""
        self._cache: t.Dict[t.Tuple[str, str], t.Tuple[t.Optional[float], str]] = {}
        sys.path.insert(0, str(ROOT / "src_new"))
        os.environ.setdefault("SWEEP_SKY_PYTHON", SKY_PYTHON)
        try:
            from sweep.console import api as console_api
            self._cat = console_api._Catalog()
            self._fallback = console_api._FALLBACK_USD_PER_HOUR
            self._fallback_as_of = console_api._FALLBACK_AS_OF
        except Exception as exc:                        # noqa: BLE001
            self.catalog_error = f"{type(exc).__name__}: {exc}"

    def rate(self, instance_type: str, region: str, cloud: str = "gcp"
             ) -> t.Tuple[t.Optional[float], str]:
        if not instance_type:
            return None, "no instance type recorded for this box"
        key = (instance_type, region)
        if key in self._cache:
            return self._cache[key]
        got: t.Tuple[t.Optional[float], str] = (None, "")
        if self._cat is not None and region:
            try:
                rates = self._cat.rates([instance_type], region, cloud)
                if instance_type in rates:
                    self.catalog_source = self._cat.source or self.catalog_source
                    got = (float(rates[instance_type]),
                           self._cat.source or "skypilot catalog")
            except Exception as exc:                    # noqa: BLE001
                self.catalog_error = self.catalog_error or f"{type(exc).__name__}: {exc}"
            if not self.catalog_error and self._cat.error:
                self.catalog_error = self._cat.error
        if got[0] is None and instance_type in self._fallback:
            got = (float(self._fallback[instance_type]),
                   f"console fallback table, as of {self._fallback_as_of}")
        if got[0] is None:
            got = (None, f"no price source knows {instance_type}"
                         + (f" in {region}" if region else ""))
        self._cache[key] = got
        return got


# ---------------------------------------------------------------------------
# the join
# ---------------------------------------------------------------------------

def _infra_parts(infra: str) -> t.Tuple[str, str]:
    """`"gcp/us-central1"` -> `("gcp", "us-central1")`."""
    cloud, _, region = (infra or "").partition("/")
    return cloud or "", region or ""


#: Backends that bill by the hour. A local box costs machine time on a host
#: somebody already pays for — not $0 of cloud, simply not cloud. Same rule as
#: the console's `_CLOUD_BACKENDS`.
CLOUD_BACKENDS = frozenset({"skypilot"})


def attempts(lab: Path = LAB, pricer: t.Optional[Pricer] = None
             ) -> t.Dict[str, t.List[dict]]:
    """`{endpoint: [attempt, …]}`, one attempt per cloud worker."""
    pricer = pricer or Pricer()
    workers = _latest_worker_rows(lab)
    boxes = _box_records(lab)
    out: t.Dict[str, t.List[dict]] = {}
    for wid, w in sorted(workers.items()):
        ep = w.get("endpoint") or ""
        if not ep:
            continue
        box = boxes.get(wid) or {}
        handle = (box.get("handle") or {})
        plan = (handle.get("plan") or {})
        itype = str(plan.get("instance_type") or "")
        cloud, region = _infra_parts(str(handle.get("infra") or ""))
        backend = str(box.get("backend") or w.get("execution_backend") or "")
        hours = float(w.get("box_hours") or 0.0)
        rate, rate_source = (None, "")
        usd: t.Optional[float] = None
        if backend in CLOUD_BACKENDS:
            rate, rate_source = pricer.rate(itype, region, cloud or "gcp")
            if rate is not None:
                usd = round(rate * hours, 6)
        else:
            rate_source = (f"backend {backend or 'unknown'} does not bill by "
                           "the cloud hour")
        # `cost` IS AN ENVELOPE, NOT A NUMBER: the sweep records
        # `{"usd": …, "provenance": "derived", "price_table_as_of": …,
        # "margin": …}` — a DERIVED figure from the client-side price table,
        # which `entrypoints/PRICES.md` measured as understating real
        # OpenRouter billing by 24 %. The provenance travels with the number so
        # a derived figure is never read as billing.
        cost = w.get("cost")
        if isinstance(cost, dict):
            api_usd = cost.get("usd")
            api_prov = cost.get("provenance") or "unstated"
            api_as_of = cost.get("price_table_as_of")
            api_margin = cost.get("margin")
        else:
            api_usd = cost if isinstance(cost, (int, float)) else None
            api_prov = "a bare number with no provenance" if api_usd is not None else "not recorded"
            api_as_of = api_margin = None
        tokens = dict(w.get("tokens") or {})
        a = {
            "worker_id": wid,
            "sweep_run": w.get("_sweep_run"),
            "kind": w.get("kind"),
            "attempt": w.get("attempt"),
            "state": w.get("state"),
            "exit_reason": w.get("exit_reason") or "",
            "queue_state": box.get("_queue_state"),
            "last_error": box.get("_last_error") or "",
            "agent": {"backend": w.get("agent_backend"),
                      "model": w.get("model")},
            "vm": {
                "backend": backend or None,
                "cluster_name": handle.get("cluster_name"),
                "instance_type": itype or None,
                "cloud": cloud or None,
                "region": region or None,
                "box_class": w.get("box_class"),
                "cpu_requested": (box.get("spec") or {}).get("cpu"),
                "memory_mb_requested": (box.get("spec") or {}).get("memory_mb"),
                "max_wall_s": (box.get("spec") or {}).get("max_wall_s"),
            },
            "time": {"queued_s": w.get("queued_s"), "wall_s": w.get("wall_s"),
                     "box_hours": hours},
            "tokens": tokens,
            "tokens_total": sum(int(v or 0) for v in tokens.values()),
            "work": {"turns": w.get("turns"), "tool_calls": w.get("tool_calls"),
                     "permission_denials": w.get("permission_denials"),
                     "interjections_sent": w.get("interjections_sent"),
                     "interjections_answered": w.get("interjections_answered")},
            "money": {
                "api_usd": api_usd,
                "api_usd_provenance": api_prov,
                "api_price_table_as_of": api_as_of,
                "api_margin": api_margin,
                "cloud_usd": usd,
                "cloud_rate_usd_per_hour": rate,
                "cloud_rate_source": rate_source,
                "cloud_usd_in_workers_jsonl": w.get("cloud_usd"),
            },
        }
        out.setdefault(ep, []).append(a)
    return out


def _stored_run_ids(lab: Path, endpoint: str) -> t.Set[str]:
    """The run ids `endpoints/<ep>/cloud/` actually ships. A stored cloud run
    id embeds its worker id, which is how an attempt is matched to an artefact
    without trusting either side's naming."""
    out = set()
    d = lab / "endpoints" / endpoint / "cloud"
    if d.is_dir():
        out = {p.name for p in d.iterdir() if p.is_dir()}
    return out


def _sum(vals: t.Iterable[t.Optional[float]]) -> t.Tuple[float, int]:
    """`(total of what is known, how many were unknown)` — an unknown is
    counted, never silently treated as zero."""
    tot, unknown = 0.0, 0
    for v in vals:
        if v is None:
            unknown += 1
        else:
            tot += float(v)
    return round(tot, 6), unknown


def record_for(endpoint: str, eps: t.Mapping[str, t.List[dict]],
               lab: Path = LAB) -> dict:
    """One endpoint's cloud record, as `endpoints/<ep>/cloud.json`."""
    rows = eps.get(endpoint) or []
    stored = _stored_run_ids(lab, endpoint)
    produced = [a for a in rows
                if any(a["worker_id"].lower() in s.lower() for s in stored)]
    api_usd, api_unknown = _sum(a["money"]["api_usd"] for a in rows)
    cloud_usd, cloud_unknown = _sum(a["money"]["cloud_usd"] for a in rows)
    return {
        "endpoint": endpoint,
        "attempts": len(rows),
        "attempts_that_produced_a_stored_run": len(produced),
        "attempts_still_marked_running": sum(
            1 for a in rows if a["state"] == "running"),
        "vm": {
            "distinct_clusters": sorted({a["vm"]["cluster_name"] for a in rows
                                         if a["vm"]["cluster_name"]}),
            "instance_types": sorted({a["vm"]["instance_type"] for a in rows
                                      if a["vm"]["instance_type"]}),
            "regions": sorted({a["vm"]["region"] for a in rows
                               if a["vm"]["region"]}),
            "box_hours": round(sum(a["time"]["box_hours"] for a in rows), 6),
        },
        "tokens_total": sum(a["tokens_total"] for a in rows),
        "turns_total": sum(int(a["work"]["turns"] or 0) for a in rows),
        "money": {
            "api_usd": api_usd,
            "api_usd_unknown_for": api_unknown,
            "cloud_usd": cloud_usd,
            "cloud_usd_unknown_for": cloud_unknown,
        },
        "reading_this_file": (
            "An attempt is a cloud box launched FOR this endpoint, not the "
            "provenance of its stored artefacts — "
            "`attempts_that_produced_a_stored_run` is the only field that "
            "connects the two, and it is 0 for every endpoint whose policy "
            "came from the local round. A null money figure is NOT COMPUTED, "
            "never free; `*_unknown_for` counts the attempts it could not be "
            "computed for. `box_hours` sums only what a terminal worker "
            "record reported, so an attempt torn down before it reported "
            "contributes 0 hours and is still counted in `attempts`."),
        "attempt_detail": rows,
    }


def records(lab: Path = LAB) -> t.Tuple[t.Dict[str, dict], dict]:
    """`({endpoint: record}, provenance)` for every endpoint with an attempt."""
    pricer = Pricer()
    eps = attempts(lab, pricer)
    out = {ep: record_for(ep, eps, lab) for ep in sorted(eps)}
    prov = {
        "price_source": pricer.catalog_source or "fallback table only",
        "price_source_error": pricer.catalog_error,
        "inputs": ["entrypoints/sweep_out_*/workers.jsonl",
                   "entrypoints/sweep_out_*/queue/entries/*.json",
                   "src_new/sweep/console/api.py (price catalog + fallback)"],
    }
    return out, prov


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    recs, prov = records()
    if args.json:
        json.dump({"provenance": prov, "endpoints": recs}, sys.stdout, indent=1)
        print()
        return 0
    if args.endpoint:
        r = recs.get(args.endpoint)
        if r is None:
            print(f"no cloud attempt recorded for {args.endpoint}")
            return 1
        print(json.dumps(r, indent=1))
        return 0

    api, api_unk = _sum(r["money"]["api_usd"] for r in recs.values())
    cld, cld_unk = _sum(r["money"]["cloud_usd"] for r in recs.values())
    hours = round(sum(r["vm"]["box_hours"] for r in recs.values()), 4)
    atts = sum(r["attempts"] for r in recs.values())
    print(f"== cloud attempts: {atts} across {len(recs)} endpoints ==")
    print(f"   price source : {prov['price_source']}")
    if prov["price_source_error"]:
        print(f"   price error  : {prov['price_source_error']}")
    print(f"   box hours    : {hours}")
    print(f"   cloud USD    : {cld}   (not computable for "
          f"{sum(r['money']['cloud_usd_unknown_for'] for r in recs.values())}"
          f" attempts)")
    print(f"   api USD      : {api}   (not recorded for "
          f"{sum(r['money']['api_usd_unknown_for'] for r in recs.values())}"
          f" attempts)")
    print(f"   tokens       : {sum(r['tokens_total'] for r in recs.values())}")
    produced = sum(r["attempts_that_produced_a_stored_run"]
                   for r in recs.values())
    print(f"   attempts whose artefacts are in endpoints/: {produced}")
    print()
    print(f"{'endpoint':<42} {'att':>4} {'hrs':>7} {'cloud$':>8} "
          f"{'api$':>8} {'tokens':>9}  instance types")
    for ep, r in sorted(recs.items(),
                        key=lambda kv: -kv[1]["vm"]["box_hours"]):
        print(f"{ep:<42} {r['attempts']:>4} {r['vm']['box_hours']:>7.3f} "
              f"{r['money']['cloud_usd']:>8.4f} "
              f"{r['money']['api_usd']:>8.4f} {r['tokens_total']:>9} "
              f" {','.join(r['vm']['instance_types']) or '-'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
