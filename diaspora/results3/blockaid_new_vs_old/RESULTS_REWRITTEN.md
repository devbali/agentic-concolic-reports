# Blockaid new-vs-old completeness (WAY2) with REWRITTEN views — 2026-09-01 21:15 UTC

Method: copy NEW policy files to `results3/queries_from_runs/_rewritten/`, replace
every `_SYM_RESULT_[A-Za-z0-9_]+` with `_MY_UID` (the only declared constant),
re-probe, then run WAY2 per-query against candidate subsets (rewritten views
whose tables are a superset of the query's tables, cap 12, ranked by column
overlap), 120s timeout, 3 threads.

## Usability after rewrite
- comments_index: 79/79 usable (was 26/79)
- conversations_index: 48/58 usable (was 8/58); remaining 10 rejected structurally:
  6 aggregate-in-select, 3 unsupported-as-checked, 1 unsupported-as-subsumer.

The full-set run with all rewritten views OOM-killed the checker (rc=-9, 79-view
formula too big for 8GB) — hence per-query candidate subsets instead.

## Verbal semantics (important)
- covered-by-subset (True)  => covered by full rewritten policy (sound).
- NOT-against-subset (False) => INCONCLUSIVE for the full policy (weaker formula).
- CONTROL: comments OLD#20 (`posts WHERE public=TRUE`) and OLD#22
  (`users WHERE id=_MY_UID`) were proven COVERED in every full-set run (15/60/120s)
  yet come back False against the 12-view subset -> demonstrates subset-False
  does NOT imply a policy gap.
- SKIP = no usable view reads the query's tables (structural).

## comments_index (OLD=23)
0 covered / 6 False (subset-only) / 15 timeout / 2 skip
- False: OLD#16,17,18 (comments/posts reads), OLD#20,21,22 (control cases —
  #20/#22 known covered full-set)
- skip: OLD#1, #9 no-superset
- All 15 timeouts are big multi-join queries (people/profiles/mentions/posts).
- Verdict vs full policy: still "nothing proven missing" (controls show subset
  False is not a gap); 21/23 undecidable by z3 at any tested configuration.

## conversations_index (OLD=16)
4 covered / 4 False (subset-only) / 5 timeout / 3 skip
- True: OLD#5 (contacts+profiles+people join), #10 (aspects), #13 (services),
  #15 (users) — matches full-set covered set. Sound positives.
- False: OLD#4 (messages), #9 (profiles), #11 (contacts receiving), #12 (people
  owner). CONTROL: #12 was COVERED in the full-set 60s run -> subset-False
  unreliable as gap evidence (again).
- SKIP: OLD#7/#8 (roles — NO rewritten view reads `roles`; consistent with the
  full-set PROVEN NOT covered), OLD#14 (notifications — no usable rewritten view
  reads `notifications`; the full-set 60s run PROVED #14 NOT covered).
- Timeouts: #0-3 (big joins), #6 (conversation_visibilities).

## Bottom-line completeness verdict (unchanged by rewrite)
- comments: 2 covered (posts public, users id) at full-set; nothing proven
  missing; rest unprovable (z3 wall at 15/60/120s, full-set or subsets).
- conversations: 5 proven missing at full-set 60s: conversation_visibilities
  read (#6), roles admin (#7), roles admin/mod (#8), profiles select (#9),
  notifications unread (#14). Rewritten-runed evidence agrees: roles and
  notifications are unreachable by any usable view.
- The rewrite unlocked full usability but did not change any full-set verdict;
  subset False verdicts are unreliable negatives (control-proven).

Files: run_way2_rewritten_subsets.log, {comments,conversations}_index_way2_rewritten_subsets.json,
_rewritten/*.sql, {comments,conversations}_index_way2_rewritten.json (OOM artifact).