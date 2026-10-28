"""test_dump_ingest — the single dump ingest point, and the lint that keeps it single.

Pins the three things the 48 hand-rolled copies kept getting wrong:
  * ``concolic_seeds`` is never rewritten (it is the RUNTIME's dict);
  * the length rename is idempotent and total, so a PRE-rename dump and a
    POST-rename dump normalise to the SAME text -- which is what keeps path
    signatures comparable across a mixed corpus;
  * a half-converted dump is REPORTED rather than silently used.

See reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md.
"""

import json
import os
import re
import tempfile
import unittest

from concolic_engine import dump_ingest as di


def _old_dump():
    """A dump as the runtimes wrote them BEFORE 2026-09-14."""
    return {
        "symbolic_vars": [{"name": "len(rows)", "sort": "Int", "low": 0},
                          {"name": "SYM_RESULT_find_1_ok", "sort": "Bool"}],
        "events": [{"type": "path_condition", "expr": "(len(rows) != 0)"},
                   {"type": "symbolic_call", "result_name": "SYM_RESULT_find_1",
                    "note": "SELECT * FROM posts"}],
        "concrete_values": {"len(rows)": 3},
        "symbolic_results": [{"name": "SYM_RESULT_find_1"}],
        "concolic_seeds": {"len(rows)": 3, "SYM_RESULT_find_1_ok": True},
    }


def _new_dump():
    """The same run, as the runtimes write it AFTER the rename."""
    d = _old_dump()
    d["symbolic_vars"][0]["name"] = "SYM_LEN_rows"
    d["events"][0]["expr"] = "(SYM_LEN_rows != 0)"
    d["concrete_values"] = {"SYM_LEN_rows": 3}
    d["concolic_seeds"] = {"SYM_LEN_rows": 3, "SYM_RESULT_find_1_ok": True}
    return d


class TestLengthRename(unittest.TestCase):
    def test_renames_every_field_a_name_can_appear_in(self):
        d = _old_dump()
        di.fix_len_names(d)
        self.assertEqual(d["symbolic_vars"][0]["name"], "SYM_LEN_rows")
        self.assertEqual(d["events"][0]["expr"], "(SYM_LEN_rows != 0)")
        self.assertEqual(list(d["concrete_values"]), ["SYM_LEN_rows"])

    def test_is_idempotent(self):
        d = _old_dump()
        once = json.dumps(di.fix_len_names(d), sort_keys=True)
        twice = json.dumps(di.fix_len_names(d), sort_keys=True)
        self.assertEqual(once, twice)

    def test_is_a_noop_on_a_dump_from_the_current_runtimes(self):
        d = _new_dump()
        before = json.dumps(d, sort_keys=True)
        di.fix_len_names(d)
        self.assertEqual(json.dumps(d, sort_keys=True), before)

    def test_old_and_new_dumps_normalise_to_the_same_text(self):
        # THE mixed-corpus invariant. Coverage matches paths by string-comparing
        # `expr`; if these diverged, one program path would split into two
        # signatures and the execution tree would silently double.
        old, new = _old_dump(), _new_dump()
        di.normalize(old)
        di.normalize(new)
        self.assertEqual([v["name"] for v in old["symbolic_vars"]],
                         [v["name"] for v in new["symbolic_vars"]])
        self.assertEqual([e.get("expr") for e in old["events"]],
                         [e.get("expr") for e in new["events"]])

    def test_mutates_in_place_rather_than_allocating_a_second_dump(self):
        d = _old_dump()
        self.assertIs(di.fix_len_names(d), d)

    def test_returns_the_same_object_normalize_was_given(self):
        d = _old_dump()
        di.normalize(d)
        self.assertEqual(d["symbolic_vars"][0]["name"], "SYM_LEN_rows")


class TestSeedsAreNeverRewritten(unittest.TestCase):
    """The defect that produced the half-converted seed dicts."""

    def test_old_spelling_seeds_survive_normalisation_untouched(self):
        d = _old_dump()
        di.normalize(d)
        self.assertEqual(d["concolic_seeds"],
                         {"len(rows)": 3, "SYM_RESULT_find_1_ok": True},
                         "seeds belong to the runtime and must not be renamed")

    def test_raw_seeds_are_preserved_for_seeds_as_written(self):
        d = _old_dump()
        di.normalize(d)
        self.assertEqual(d[di.RAW_SEEDS_KEY], {"len(rows)": 3,
                                               "SYM_RESULT_find_1_ok": True})

    def test_raw_seeds_key_matches_the_assumption_checkers(self):
        # A dump normalised here must satisfy `seeds_as_written`.
        self.assertEqual(di.RAW_SEEDS_KEY, "_raw_concolic_seeds")

    def test_a_rewritten_seed_dict_is_reported(self):
        d = _old_dump()
        raw = dict(d["concolic_seeds"])
        d["concolic_seeds"] = {"SYM_LEN_rows": 3}      # what a copy did wrongly
        with self.assertRaises(di.MixedSpelling) as cm:
            di.check_invariants(d, raw, where="unit")
        self.assertIn("REWRITTEN", str(cm.exception))

    def test_a_half_converted_seed_dict_is_reported(self):
        d = _old_dump()
        d["concolic_seeds"] = {"len(rows)": 3, "SYM_LEN_rows": 3}
        with self.assertRaises(di.MixedSpelling) as cm:
            di.check_invariants(d, d["concolic_seeds"], where="unit")
        self.assertIn("both length spellings", str(cm.exception))

    def test_a_clean_dump_passes_the_invariants(self):
        for d in (_old_dump(), _new_dump()):
            di.normalize(d)          # strict=True by default: must not raise


class TestOrdinalCanonicalIsSeparate(unittest.TestCase):
    """The essential boundary. It must keep working, and must stay OFF the
    seed dict."""

    def _aliases(self):
        from concolic_engine.assumptions import AliasAssumption
        return [AliasAssumption(result_pattern=r"SYM_RESULT_find_\d+",
                                key="statement")]

    def test_no_aliases_means_no_map_and_no_change(self):
        d = _old_dump()
        self.assertEqual(di.canonicalize_ordinals(d, ()), {})

    def test_canonicalisation_leaves_seeds_ordinal_named(self):
        d = _old_dump()
        di.normalize(d, self._aliases())
        self.assertIn("SYM_RESULT_find_1_ok", d["concolic_seeds"],
                      "seeds must stay in the runtime's ordinal spelling")

    def test_both_boundaries_compose_without_touching_seeds(self):
        d = _old_dump()
        before = dict(d["concolic_seeds"])
        di.normalize(d, self._aliases())
        self.assertEqual(d["concolic_seeds"], before)


class TestLoad(unittest.TestCase):
    def test_load_normalises_from_disk(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "dump_x.json")
            with open(p, "w") as fh:
                json.dump(_old_dump(), fh)
            d, amap = di.load(p)
            self.assertEqual(d["symbolic_vars"][0]["name"], "SYM_LEN_rows")
            self.assertEqual(d["concolic_seeds"]["len(rows)"], 3)
            self.assertEqual(amap, {})


class TestRuntimesMintTheSolverLegalSpelling(unittest.TestCase):
    """Guards the rename at its source, in both runtimes."""

    IDENT = re.compile(r"\A[A-Za-z_][A-Za-z0-9_]*\Z")

    def test_python_runtime(self):
        from py_runtime.base import len_var_name
        self.assertEqual(len_var_name("rows"), "SYM_LEN_rows")
        self.assertIsNone(len_var_name(None))
        self.assertRegex(len_var_name("rows"), self.IDENT)

    def test_python_list_and_dict_agree(self):
        from py_runtime.list_ import SymbolicList
        from py_runtime.dict_ import SymbolicDict
        self.assertEqual(SymbolicList([1], name="L").symbolic_len.name, "SYM_LEN_L")
        self.assertEqual(SymbolicDict({"a": 1}, name="D")._len_sym.name, "SYM_LEN_D")

    def test_ruby_runtime_mints_the_same_spelling(self):
        # The two runtimes must not drift -- the Ruby one produces the corpora.
        src = open(os.path.join(os.path.dirname(__file__),
                                "ruby_runtime", "base.rb")).read()
        self.assertIn('LEN_PREFIX = "SYM_LEN_"', src)
        self.assertIn("def self.len_var_name", src)

    def test_no_runtime_still_mints_the_old_spelling(self):
        here = os.path.dirname(__file__)
        offenders = []
        for sub, pat in (("ruby_runtime", 'len(#{'), ("py_runtime", 'f"len({')):
            d = os.path.join(here, sub)
            for fn in sorted(os.listdir(d)):
                if fn.endswith((".rb", ".py")) and pat in open(os.path.join(d, fn)).read():
                    offenders.append(os.path.join(sub, fn))
        self.assertEqual(offenders, [],
                         "these still mint a non-identifier length name")


class TestNoHandRolledCopies(unittest.TestCase):
    """THE LINT. Documentation did not stop the copies; a red test does.

    The rule this enforces is the one the RUNBOOK states and that four agents
    broke in one night: there is ONE ingest, and it is `dump_ingest`. A new
    `def fix_len_names` / `def canonicalize_ordinals` anywhere else is a
    defect, not a convenience -- 48 copies with 15 distinct behaviours is how
    a batch came to disagree with its own docstring.

    EXISTING copies are grandfathered by an explicit, shrinking allowlist:
    they sit in live campaign directories that must not be edited mid-flight.
    The point of the count is that it can only go DOWN.
    """

    ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "reports"))
    PATTERN = re.compile(r"^def (fix_len_names|canonicalize_ordinals)\b", re.M)
    #: Measured 2026-09-14, before any batch was converted. Lower this as
    #: batches adopt `dump_ingest`; never raise it.
    BUDGET = 60

    def _copies(self):
        # Dedupe by REAL path: reports/ carries symlinked directories, and a
        # copy reached through two paths is still one copy.
        seen, hits = set(), []
        for dirpath, dirnames, filenames in os.walk(self.ROOT):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if not fn.endswith(".py"):
                    continue
                p = os.path.realpath(os.path.join(dirpath, fn))
                if p in seen:
                    continue
                seen.add(p)
                try:
                    with open(p, encoding="utf-8", errors="replace") as fh:
                        body = fh.read()
                except OSError:
                    continue
                hits.extend([p] * len(self.PATTERN.findall(body)))
        return hits

    @unittest.skipUnless(os.path.isdir(ROOT), "reports/ not present")
    def test_the_number_of_hand_rolled_copies_never_grows(self):
        copies = self._copies()
        self.assertLessEqual(
            len(copies), self.BUDGET,
            "a new hand-rolled dump rename appeared (%d > %d). Import "
            "concolic_engine.dump_ingest instead; see "
            "reports/diaspora/docs/NAME_BOUNDARY_PLAN_20260914.md.\n%s"
            % (len(copies), self.BUDGET,
               "\n".join(sorted(set(copies))[:10])))

    #: Frozen reference trees. `results2/` and `results/` are read-only
    #: records of closed experiments -- their dumps are already written and
    #: their code is never run again, so they keep the old spelling.
    FROZEN = ("/results2/", "/results/")
    #: `_bak_*` files are point-in-time snapshots kept as a record and never
    #: executed; they are expected to preserve the code as it was.
    SNAPSHOT_PREFIX = "_bak_"

    @unittest.skipUnless(os.path.isdir(ROOT), "reports/ not present")
    def test_no_live_batch_mints_a_hand_built_length_name(self):
        """The gap this lint was written for.

        Fixing the runtimes is not enough: a batch's wall mocks can mint a
        length variable THEMSELVES, bypassing `len_var_name` entirely --
        `symint("len(#{vn})", ...)`. Two such sites were found in
        notifications_index/targets.rb on 2026-09-14, after the runtime fix
        looked complete. A hand-built name is a legal Z3 symbol and an
        ILLEGAL Python identifier, so it silently reintroduces the dialect
        (and `solver.py` reads the resulting declaration as UNSAT, i.e. as
        "infeasible"). Mint through `SymbolicVar.len_var_name`."""
        mint = re.compile(r"""(symint|symstr|symbool|register_var)\s*\(\s*["']len\(""")
        offenders = []
        for dirpath, dirnames, filenames in os.walk(self.ROOT):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if not fn.endswith(".rb"):
                    continue
                p = os.path.realpath(os.path.join(dirpath, fn))
                if any(f in p for f in self.FROZEN):
                    continue
                if os.path.basename(p).startswith(self.SNAPSHOT_PREFIX):
                    continue
                try:
                    body = open(p, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                if mint.search(body):
                    offenders.append(p)
        self.assertEqual(sorted(set(offenders)), [],
                         "these mint a length var by hand instead of via "
                         "SymbolicVar.len_var_name")

    @unittest.skipUnless(os.path.isdir(ROOT), "reports/ not present")
    def test_src_itself_defines_the_rename_exactly_once(self):
        src_root = os.path.dirname(__file__)
        defs = []
        for dirpath, dirnames, filenames in os.walk(src_root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith(".py") and not fn.startswith("test_"):
                    p = os.path.join(dirpath, fn)
                    if self.PATTERN.search(open(p, encoding="utf-8",
                                                errors="replace").read()):
                        defs.append(p)
        self.assertEqual([os.path.basename(p) for p in defs], ["dump_ingest.py"])


if __name__ == "__main__":
    unittest.main()
