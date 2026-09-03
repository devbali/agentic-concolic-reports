# RESULT.md — variant_e (round 3, thin, coordinator-run)

One lever: joint seeds for SYM_NOTE_TYPE_PROFILE in {4,5,6,7} (mirroring
variant_d's types 0-3 dicts). Run: SEEDS_ONLY, flock + systemd-run
MemoryMax=2500M, 11 runs, 0 errors, worklist drained
(_dse_joint47.log).

FINDING — LEVER REFUTED, with dump evidence: 0/7 seeded dumps co-record
`(assoc_target_text_has_mention == True) AND (assoc_target_persisted ==
...)` for types 4-7, because those types' polymorphic targets are
Mention/Person rows — the `assoc_target_text_has_mention` variable is a
Post-target attribute and structurally cannot mint there. Consistent with
the coverage checker never naming those combos in missing[]. No
extraction/diff rerun performed: the corpus differs from variant_d's only
by 11 conjunction-free dumps, so the query set and diff numbers are
variant_d's (verified premise: extraction is deterministic over dumps).

Experiment consequence: convergence — see ../ROUNDS.md round 3 and
../../MOCK_TEST_RECIPE.md.
