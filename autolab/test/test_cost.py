#!/usr/bin/env python3
"""Tests for tools/cost.py — the attempts -> VM -> price join.

The properties worth pinning are the ones that make a cost figure honest, not
the arithmetic:

  * a `workers.jsonl` worker is re-emitted on every state change, so only its
    LAST record counts;
  * `cost` is an ENVELOPE (`{"usd": …, "provenance": "derived", …}`), and the
    provenance must travel with the number — the price table it comes from was
    measured as understating real billing by 24 %;
  * an unknown price is **null**, never 0. `workers.jsonl`'s own `cloud_usd` is
    0.0 on every record ever written because nothing computed it, which is
    exactly the confusion this must not reproduce;
  * an attempt is a box launched FOR an endpoint, not the provenance of that
    endpoint's stored artefacts.

Fixtures are hand-built lab trees, so no sweep output is needed and no
application is named.
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
import cost as cost_mod  # noqa: E402


def _worker(wid, endpoint, **kw):
    d = {"worker_id": wid, "endpoint": endpoint, "kind": "batch", "attempt": 1,
         "agent_backend": "dsh", "model": "m", "execution_backend": "skypilot",
         "box_class": "sm", "state": "running", "queued_s": 0.0, "wall_s": 0.0,
         "exit_reason": "", "tokens": {"input": 0, "output": 0},
         "cost": None, "box_hours": 0.0, "cloud_usd": 0.0, "turns": 0,
         "tool_calls": 0}
    d.update(kw)
    return d


def _entry(wid, endpoint, instance_type="n2-standard-2",
           infra="gcp/us-central1", backend="skypilot", boxed=True):
    e = {"id": wid, "endpoint": endpoint, "kind": "batch", "attempt": 1,
         "state": "done", "last_error": "", "box": None}
    if boxed:
        e["box"] = {"backend": backend, "state": "running",
                    "spec": {"cls": "sm", "cpu": 2, "memory_mb": 8000,
                             "max_wall_s": 1800},
                    "handle": {"cluster_name": "cl-" + wid,
                               "infra": infra,
                               "plan": {"instance_type": instance_type}}}
    return e


class _Lab:
    """A lab tree with one sweep run, written to a temp dir."""

    def __init__(self, workers, entries, stored_cloud_runs=()):
        self.dir = Path(tempfile.mkdtemp(prefix="autolab_cost_"))
        run = self.dir / "entrypoints" / "sweep_out_test"
        (run / "queue" / "entries").mkdir(parents=True)
        with open(run / "workers.jsonl", "w") as fh:
            for w in workers:
                fh.write(json.dumps(w) + "\n")
        for e in entries:
            (run / "queue" / "entries" / (e["id"] + ".json")).write_text(
                json.dumps(e))
        for ep, rid in stored_cloud_runs:
            (self.dir / "endpoints" / ep / "cloud" / rid).mkdir(parents=True)


class _FixedPricer(cost_mod.Pricer):
    """A pricer that knows one type, so the unknown path is exercised too."""

    def __init__(self, known=("n2-standard-2", 0.1)):
        self._known = known
        self.catalog_source = "a test"
        self.catalog_error = ""

    def rate(self, instance_type, region, cloud="gcp"):
        if instance_type == self._known[0]:
            return self._known[1], "a test"
        if not instance_type:
            return None, "no instance type recorded for this box"
        return None, f"no price source knows {instance_type}"


class TestOnlyTheLastWorkerRecordCounts(unittest.TestCase):

    def test_a_reemitted_worker_is_read_at_its_final_state(self):
        lab = _Lab([_worker("w1", "ep_a"),
                    _worker("w1", "ep_a", state="done", box_hours=2.0,
                            wall_s=7200.0)],
                   [_entry("w1", "ep_a")])
        got = cost_mod.attempts(lab.dir, _FixedPricer())
        self.assertEqual(len(got["ep_a"]), 1)
        a = got["ep_a"][0]
        self.assertEqual(a["state"], "done")
        self.assertEqual(a["time"]["box_hours"], 2.0)
        self.assertAlmostEqual(a["money"]["cloud_usd"], 0.2)


class TestAnUnknownPriceIsNullNotZero(unittest.TestCase):

    def test_an_unpriced_instance_type_gives_null(self):
        lab = _Lab([_worker("w1", "ep_a", state="done", box_hours=3.0)],
                   [_entry("w1", "ep_a", instance_type="z9-enormous-512")])
        a = cost_mod.attempts(lab.dir, _FixedPricer())["ep_a"][0]
        self.assertIsNone(a["money"]["cloud_usd"])
        self.assertIn("z9-enormous-512", a["money"]["cloud_rate_source"])

    def test_a_box_with_no_recorded_instance_type_gives_null(self):
        lab = _Lab([_worker("w1", "ep_a", state="done", box_hours=3.0)],
                   [_entry("w1", "ep_a", boxed=False)])
        a = cost_mod.attempts(lab.dir, _FixedPricer())["ep_a"][0]
        self.assertIsNone(a["money"]["cloud_usd"])

    def test_the_rollup_counts_unknowns_instead_of_summing_them_as_zero(self):
        lab = _Lab([_worker("w1", "ep_a", state="done", box_hours=1.0),
                    _worker("w2", "ep_a", state="done", box_hours=1.0)],
                   [_entry("w1", "ep_a"),
                    _entry("w2", "ep_a", instance_type="z9-enormous-512")])
        eps = cost_mod.attempts(lab.dir, _FixedPricer())
        r = cost_mod.record_for("ep_a", eps, lab.dir)
        self.assertAlmostEqual(r["money"]["cloud_usd"], 0.1)
        self.assertEqual(r["money"]["cloud_usd_unknown_for"], 1)

    def test_the_sweeps_own_zero_is_carried_separately(self):
        """`workers.jsonl`'s `cloud_usd` is 0.0 everywhere because nothing
        computed it. It is kept under its own key so the two can never be
        confused."""
        lab = _Lab([_worker("w1", "ep_a", state="done", box_hours=1.0)],
                   [_entry("w1", "ep_a")])
        a = cost_mod.attempts(lab.dir, _FixedPricer())["ep_a"][0]
        self.assertEqual(a["money"]["cloud_usd_in_workers_jsonl"], 0.0)
        self.assertAlmostEqual(a["money"]["cloud_usd"], 0.1)


class TestANonCloudBackendIsNotZeroCloud(unittest.TestCase):

    def test_a_local_box_is_left_out_rather_than_counted_as_free(self):
        lab = _Lab([_worker("w1", "ep_a", state="done", box_hours=1.0,
                            execution_backend="local")],
                   [_entry("w1", "ep_a", backend="local")])
        a = cost_mod.attempts(lab.dir, _FixedPricer())["ep_a"][0]
        self.assertIsNone(a["money"]["cloud_usd"])
        self.assertIn("does not bill by the cloud hour",
                      a["money"]["cloud_rate_source"])


class TestTheApiCostEnvelopeKeepsItsProvenance(unittest.TestCase):

    def test_a_derived_figure_says_so(self):
        lab = _Lab([_worker("w1", "ep_a", state="done",
                            cost={"usd": 1.5, "provenance": "derived",
                                  "price_table_as_of": "2026-09-29",
                                  "margin": 0.15})],
                   [_entry("w1", "ep_a")])
        m = cost_mod.attempts(lab.dir, _FixedPricer())["ep_a"][0]["money"]
        self.assertEqual(m["api_usd"], 1.5)
        self.assertEqual(m["api_usd_provenance"], "derived")
        self.assertEqual(m["api_price_table_as_of"], "2026-09-29")
        self.assertEqual(m["api_margin"], 0.15)

    def test_a_missing_cost_is_null_and_named(self):
        lab = _Lab([_worker("w1", "ep_a", state="done")],
                   [_entry("w1", "ep_a")])
        m = cost_mod.attempts(lab.dir, _FixedPricer())["ep_a"][0]["money"]
        self.assertIsNone(m["api_usd"])
        self.assertEqual(m["api_usd_provenance"], "not recorded")

    def test_a_bare_number_is_flagged_as_having_no_provenance(self):
        lab = _Lab([_worker("w1", "ep_a", state="done", cost=2.0)],
                   [_entry("w1", "ep_a")])
        m = cost_mod.attempts(lab.dir, _FixedPricer())["ep_a"][0]["money"]
        self.assertEqual(m["api_usd"], 2.0)
        self.assertIn("no provenance", m["api_usd_provenance"])


class TestAnAttemptIsNotProvenance(unittest.TestCase):

    def test_an_attempt_with_no_stored_run_is_counted_but_not_credited(self):
        lab = _Lab([_worker("w1", "ep_a", state="done", box_hours=1.0)],
                   [_entry("w1", "ep_a")])
        eps = cost_mod.attempts(lab.dir, _FixedPricer())
        r = cost_mod.record_for("ep_a", eps, lab.dir)
        self.assertEqual(r["attempts"], 1)
        self.assertEqual(r["attempts_that_produced_a_stored_run"], 0)

    def test_a_stored_run_naming_the_worker_is_credited(self):
        lab = _Lab([_worker("w1", "ep_a", state="done", box_hours=1.0)],
                   [_entry("w1", "ep_a")],
                   stored_cloud_runs=[("ep_a", "sweep_out.box.w1-abcdef")])
        eps = cost_mod.attempts(lab.dir, _FixedPricer())
        r = cost_mod.record_for("ep_a", eps, lab.dir)
        self.assertEqual(r["attempts_that_produced_a_stored_run"], 1)

    def test_a_torn_down_attempt_contributes_no_hours_but_is_counted(self):
        lab = _Lab([_worker("w1", "ep_a"),          # still "running"
                    _worker("w2", "ep_a", state="done", box_hours=0.5)],
                   [_entry("w1", "ep_a"), _entry("w2", "ep_a")])
        eps = cost_mod.attempts(lab.dir, _FixedPricer())
        r = cost_mod.record_for("ep_a", eps, lab.dir)
        self.assertEqual(r["attempts"], 2)
        self.assertEqual(r["attempts_still_marked_running"], 1)
        self.assertEqual(r["vm"]["box_hours"], 0.5)


if __name__ == "__main__":
    unittest.main()
