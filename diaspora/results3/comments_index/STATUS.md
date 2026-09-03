# comments_index — reference-free status (2026-08-25)

> **SUPERSEDED as a state description (2026-08-28).** Everything below is the
> gen-5 snapshot of 2026-08-25 and is kept as history. The live state is
> `AGENT_RUN.md` (cycle 5) and `coverage_summary.json`: `complete: true`,
> 0 missing / 46 PC nodes, 8 243 dumps, assumptions 1 095/1 095 PASS, shims
> 19 PASS / 11 PROTOCOL, note check green, six SQL-consumer audits green
> (including `empty_relation_emission_audit`). Three adversary rounds have
> been answered; round 3's wins M-3 and M-4 are closed with real runs
> (`concrete_manifest_r3.rb`).

**First endpoint run with NO reference policy on the machine** (removed
this session; recoverable via
`git -C ruby_examples/dse-apps checkout -- policies/extracted/diaspora/per-endpoint/`).
Completion is judged by the checker suite alone (RUNBOOK).

## Corpus
- anon round: 257 runs / 46 paths; auth round (NEW this pass — the old
  runner was anonymous-only): 642 runs / 122 paths. `errors={}` both.
- Runner ports this pass: AUTH scenario + `symbolic_user_ci`,
  SEEDS_ONLY/EXTRA_SEEDS_JSON/LABEL_SUFFIX replay knobs, seeds recorded
  into dumps (`concolic_seeds` was empty before — assumption probes need it).

## Extracted policy: 15 views (`../queries_from_runs/comments_index.sql`)
Public families (comments/people/profiles via `posts.public = TRUE`),
signed-in families (via `posts.author.owner_id = _MY_UID` and via
`share_visibilities.user_id = _MY_UID`), posts fetch (param-free by
design; fetch precedes authorization), mention-lookup pair.

## Gates
- Phase 3 fold audits: GREEN (junk list = 4 documented walls; the
  `Length(SYM_PARAM_post_id) < 16` guid-vs-id dispatch classified
  by-design — a param-shape constraint, not a column predicate).
- MOCK CHECKER: 4/4 (name_from_attrs shim 100% coverage; mention-lookup,
  post-fetch, comments-relation note shapes match real SQL).
- ASSUMPTION CHECKER: 3/3 foreclosures verified (not-found → 404,
  non-public → NonPublic, mention-free → no lookup), each diverging AND
  labeled under a controlled flip.
- CONCRETE CHECKER (anon scenario): GREEN at target level — real sqlite
  fixtures, real dispatch, comments rendered in real JSON; every
  concretely-invoked target function present in the corpus (aliases file
  declares the mention_lookup_* ≡ find_by naming equivalence).

## Repairs made (violations found by the checkers, all fixed this pass)
1. mention_lookup aliases dropped their WHERE (violation-6 pattern; the
   shared kwargs fix doesn't reach batch-local aliases + module-prepend
   doesn't propagate on this Ruby) → thread-local stash prepended to
   Person.singleton_class.
2. `render_arg_value` double-quoted string literals → SQL parsed them as
   identifiers (`people`.`concolic_mention@example.org` as a COLUMN in
   the folded view) → single-quote fix, both batch copies.
3. Runner: seeds not recorded in dumps; no replay knobs; anon-only.

## Open items (checker-found, next pass)
1. **persisted-pin divergence** (concrete checker analysis): persisted
   comments concretely resolve mentions via the `mentions` TABLE;
   symbolic reps are pinned new_record so the corpus only explored
   `people_from_string`. Port notifications' persisted-decision pattern
   to comment reps; then the mentions-association families join the
   policy. A statement-level concrete diff (statement_log during the
   concrete run) will gate this.
2. **auth concrete scenario** (share_visibilities fixtures) not yet run.
3. **ordinal-fragile assumption expr**: comment-mention-free assumption
   valid only against anon ordinals (checker-found dead knob in auth
   context; snapshot_scenario pinned to anon in the manifest). Repair:
   call-site-stable naming for the comments-list materialize.
4. Mention handle renders as a concrete literal (symbolic identity spent
   in the text regex scan) — policy view is handle-specific rather than
   parameterized.

## 2026-08-26 — cycle 2: `complete: true`; reference 23/23 covered, 0 rejected
Two rejected independences withdrawn by the sub-agent; auth worklist exhausted
(7 717 runs). Engine complete reference-free. Reference diff 14/0/9 under the
standard subset sweep, **23/0/0** once the sweep includes the `users`
principal-join table (`diff_ci_c2w`). See EXPERIMENT_REPORT.md "Cycle 2".
