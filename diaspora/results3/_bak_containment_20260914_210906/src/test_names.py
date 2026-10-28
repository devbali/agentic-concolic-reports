"""Tests for `concolic_engine.names` — loud lookups across the name boundary.

Each REGRESSION test reproduces a failure this project actually paid for
(2026-09-13/14): a cross-boundary lookup that missed on spelling, returned a
falsy value, and had that falsy value read as a meaningful negative.
"""
import re
import unittest

from concolic_engine.names import (
    NameSpace, WrongSpelling, AmbiguousSpelling,
    to_checker, to_runtime, same_variable, len_spellings,
    is_checker_len, is_runtime_len, normalize,
)
from concolic_engine.assumptions import renamer


RT = "len(SYM_RESULT_ActiveRecord__Relation_records_2_rows)"
CK = "SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_2_rows"
ORD = "SYM_RESULT_ActiveRecord__Relation_records_2"
CANON = "SYM_RESULT_ActiveRecord__Relation_records_mentions_66022a8b"
AMAP = {ORD: CANON}


class TestLengthSpelling(unittest.TestCase):
    def test_round_trip_both_ways(self):
        self.assertEqual(to_checker(RT), CK)
        self.assertEqual(to_runtime(CK), RT)
        self.assertEqual(to_runtime(to_checker(RT)), RT)
        self.assertEqual(to_checker(to_runtime(CK)), CK)

    def test_idempotent(self):
        self.assertEqual(to_checker(to_checker(RT)), to_checker(RT))
        self.assertEqual(to_runtime(to_runtime(CK)), to_runtime(CK))
        # and each is a no-op on the other side's own spelling
        self.assertEqual(to_checker(CK), CK)
        self.assertEqual(to_runtime(RT), RT)

    def test_non_length_names_untouched(self):
        for n in ("SYM_RESULT_Foo_bar_1", "x", "", None):
            self.assertEqual(to_checker(n), n)
            self.assertEqual(to_runtime(n), n)

    def test_works_inside_expressions(self):
        self.assertEqual(to_checker("(len(a_rows) > 0)"), "(SYM_LEN_a_rows > 0)")
        self.assertEqual(to_runtime("(SYM_LEN_a_rows > 0)"), "(len(a_rows) > 0)")

    def test_predicates_and_helpers(self):
        self.assertTrue(is_runtime_len(RT))
        self.assertFalse(is_checker_len(RT))
        self.assertTrue(is_checker_len(CK))
        self.assertTrue(same_variable(RT, CK))
        self.assertFalse(same_variable(RT, "len(other_rows)"))
        self.assertEqual(normalize(RT), CK)
        self.assertEqual(sorted(len_spellings(RT)), sorted([RT, CK]))
        self.assertEqual(len_spellings("plain"), ["plain"])


class TestLoudLookup(unittest.TestCase):
    def test_hit_is_a_plain_lookup(self):
        ns = NameSpace({CK: 3}, name="index lens")
        self.assertEqual(ns.get(CK), 3)
        self.assertTrue(ns.has(CK))
        self.assertIn(CK, ns)

    def test_wrong_spelling_raises_and_names_both_forms(self):
        ns = NameSpace({CK: 3}, name="index lens")
        with self.assertRaises(WrongSpelling) as cm:
            ns.get(RT)
        msg = str(cm.exception)
        self.assertIn(RT, msg)          # the spelling that was asked for
        self.assertIn(CK, msg)          # the spelling the table actually has
        self.assertIn("index lens", msg)
        self.assertEqual(cm.exception.key, RT)
        self.assertEqual(cm.exception.found, [CK])

    def test_wrong_spelling_raises_in_the_other_direction_too(self):
        ns = NameSpace({RT: 3})
        with self.assertRaises(WrongSpelling):
            ns.get(CK)

    def test_GENUINE_ABSENCE_DOES_NOT_RAISE(self):
        """The load-bearing property: a real miss stays a normal negative."""
        ns = NameSpace({CK: 3}, name="index lens")
        self.assertIsNone(ns.get("SYM_LEN_something_else_rows"))
        self.assertIsNone(ns.get("len(something_else_rows)"))
        self.assertEqual(ns.get("len(nope_rows)", -1), -1)
        self.assertFalse(ns.has("SYM_LEN_nope_rows"))
        self.assertNotIn("SYM_LEN_nope_rows", ns)

    def test_empty_table_never_raises(self):
        ns = NameSpace({})
        self.assertIsNone(ns.get(RT))
        self.assertIsNone(ns.get(CK))

    def test_falsy_stored_value_is_returned_not_confused_with_absence(self):
        ns = NameSpace({CK: 0})
        self.assertEqual(ns.get(CK), 0)
        self.assertTrue(ns.has(CK))
        with self.assertRaises(WrongSpelling):
            ns.get(RT)

    def test_require_distinguishes_the_two_failures(self):
        ns = NameSpace({CK: 3}, name="lens")
        with self.assertRaises(WrongSpelling):
            ns.require(RT)
        with self.assertRaises(KeyError) as cm:
            ns.require("SYM_LEN_absent_rows")
        self.assertIn("genuine absence", str(cm.exception))

    def test_resolve_is_the_forgiving_variant(self):
        ns = NameSpace({CK: 3})
        self.assertEqual(ns.resolve(RT), 3)
        self.assertEqual(ns.resolve(CK), 3)
        self.assertIsNone(ns.resolve("SYM_LEN_absent_rows"))


class TestOrdinalCanonical(unittest.TestCase):
    def test_ordinal_canonical_pair_handled_like_the_len_pair(self):
        ns = NameSpace({CANON: "v"}, name="alias table", alias_map=AMAP)
        self.assertEqual(ns.get(CANON), "v")
        with self.assertRaises(WrongSpelling) as cm:
            ns.get(ORD)
        self.assertIn(ORD, str(cm.exception))
        self.assertIn(CANON, str(cm.exception))

    def test_reverse_direction(self):
        ns = NameSpace({ORD: "v"}, alias_map=AMAP)
        with self.assertRaises(WrongSpelling):
            ns.get(CANON)

    def test_many_to_one_alias_map(self):
        ord2 = "SYM_RESULT_ActiveRecord__Relation_records_7"
        amap = {ORD: CANON, ord2: CANON}
        ns = NameSpace({ORD: 1}, alias_map=amap)
        # the canonical is backed by two ordinals; one of them IS present
        with self.assertRaises(WrongSpelling):
            ns.get(CANON)
        self.assertEqual(ns.resolve(CANON), 1)
        # ord2 is a sibling of ORD through the shared canonical
        with self.assertRaises(WrongSpelling):
            ns.get(ord2)

    def test_CROSS_PRODUCT_len_times_ordinal(self):
        """The real index shape: keys are SYM_LEN_<canonical>_rows, the
        constructor asks with len(<ordinal>_rows)."""
        ns = NameSpace({"SYM_LEN_%s_rows" % CANON: True},
                       name="idx lens", alias_map=AMAP)
        with self.assertRaises(WrongSpelling) as cm:
            ns.get("len(%s_rows)" % ORD)
        self.assertIn("SYM_LEN_%s_rows" % CANON, str(cm.exception))
        self.assertTrue(ns.resolve("len(%s_rows)" % ORD))
        # ...and a length of a DIFFERENT statement is still a normal negative
        self.assertIsNone(ns.get("len(SYM_RESULT_Other_thing_1_rows)"))

    def test_to_canonical_is_idempotent_and_agrees_with_assumptions_renamer(self):
        ns = NameSpace({}, alias_map={"records_1": "records_a1b2c3d4",
                                      "records_11": "records_e5f6a7b8"})
        rn = renamer({"records_1": "records_a1b2c3d4",
                      "records_11": "records_e5f6a7b8"})
        for s in ("records_1", "records_11", "len(records_1_rows)",
                  "(records_11 == records_1)", "nothing"):
            self.assertEqual(ns.to_canonical(s), rn(s), s)
            self.assertEqual(ns.to_canonical(ns.to_canonical(s)),
                             ns.to_canonical(s), s)

    def test_no_alias_map_means_no_ordinal_siblings(self):
        ns = NameSpace({CANON: 1})
        self.assertIsNone(ns.get(ORD))      # cannot know they are related


class TestKeysFor(unittest.TestCase):
    def test_returns_every_backing_ordinal(self):
        ord2 = "SYM_RESULT_ActiveRecord__Relation_records_7"
        ns = NameSpace({ORD + "_row_text": 1, ord2 + "_row_text": 2, "junk": 3},
                       alias_map={ORD: CANON, ord2: CANON})
        self.assertEqual(sorted(ns.keys_for(CANON + "_row_text")),
                         sorted([ORD + "_row_text", ord2 + "_row_text"]))

    def test_includes_the_key_itself_when_present(self):
        ns = NameSpace({CK: 1, RT: 1})
        self.assertEqual(ns.keys_for(CK), [CK, RT])

    def test_genuine_absence_is_the_only_empty_answer(self):
        ns = NameSpace({CK: 1}, alias_map=AMAP)
        self.assertEqual(ns.keys_for("SYM_LEN_never_minted_rows"), [])
        self.assertEqual(ns.keys_for(RT), [CK])


class TestTableHygiene(unittest.TestCase):
    def test_normalized_rekeys_both_spellings(self):
        # normal form is checker spelling AND canonical ordinals, so the
        # runtime/ordinal key RT lands under the canonical checker name.
        n = NameSpace({RT: 3, CANON: "x"}, alias_map=AMAP).normalized()
        self.assertEqual(n["SYM_LEN_%s_rows" % CANON], 3)
        self.assertEqual(n[CANON], "x")
        # without an alias map only the length spelling is normalized
        self.assertEqual(NameSpace({RT: 3}).normalized()[CK], 3)

    def test_ambiguous_table_is_reported(self):
        ns = NameSpace({RT: 3, CK: 4}, name="mixed", strict_ambiguity=True)
        with self.assertRaises(AmbiguousSpelling):
            ns.get(CK)
        # same value under both spellings is not ambiguous, just redundant
        NameSpace({RT: 3, CK: 3}, strict_ambiguity=True).get(CK)

    def test_ambiguity_is_off_by_default(self):
        self.assertEqual(NameSpace({RT: 3, CK: 4}).get(CK), 4)

    def test_audit_reports_which_names_would_miss(self):
        ns = NameSpace({CK: 1}, name="lens")
        bad = ns.audit([CK, RT, "SYM_LEN_absent_rows"])
        self.assertEqual(bad, {RT: [CK]})


class TestRegressionsFromRealFailures(unittest.TestCase):
    """The four failures of 2026-09-13/14, each as the lookup that produced it."""

    def test_seeder_dropped_every_SYM_LEN_value(self):
        # FAILURE 1: seeder read a checker-side demand against runtime-side
        # seeds and dropped 18.5-31% of values as "no seed needed".
        seeds = NameSpace({RT: 0}, name="concolic_seeds")
        with self.assertRaises(WrongSpelling):
            seeds.get(CK)

    def test_gate_probe_did_not_match_its_own_dump(self):
        # FAILURE 2: the batch canonicalisation hook renamed len(X)->SYM_LEN_X
        # inside a loaded dump's recorded seeds, so a probe written in the
        # runtime spelling never matched its own launch -> 40x slower path.
        on_disk = {RT: 0}
        after_hook = {CK: 0}
        self.assertNotEqual(on_disk, after_hook)      # the silent mismatch
        self.assertEqual(NameSpace(after_hook, name="dump seeds").resolve(RT), 0)
        with self.assertRaises(WrongSpelling):
            NameSpace(after_hook, name="dump seeds").get(RT)

    def test_class_A_pins_looked_unachievable(self):
        # FAILURE 3: class-A analysis called 3,746 cubes unachievable because
        # the pin names were not put through canonicalize_ordinals+fix_len_names.
        idx = NameSpace({"SYM_LEN_%s_rows" % CANON: True},
                        name="index lens", alias_map=AMAP)
        with self.assertRaises(WrongSpelling):
            idx.get("len(%s_rows)" % ORD)

    def test_class_D_unminted_test(self):
        # FAILURE 4: the constructor's "unminted" test consulted the index's
        # length table and dropped a variable the corpus mints in 68% of runs.
        LIDX = NameSpace({CK: 0}, name="index lens (LIDX)")
        with self.assertRaises(WrongSpelling):
            LIDX.get(RT)                       # would have been "unminted"
        # and the genuinely-unminted variable still reports unminted, quietly
        self.assertIsNone(LIDX.get("SYM_LEN_truly_never_minted_rows"))


if __name__ == "__main__":
    unittest.main()
