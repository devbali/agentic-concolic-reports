# NIGHT PLAN — 2026-09-08, user asleep, full autonomy granted

GOAL: notifications_index to the project standard, then people_stream, then
posts_show. "Standard" = README: engine `complete: true` (0 FAIL /
0 NOT-TESTABLE) + audit sweep + adversary round with zero wins + multiset
matrix green, ALL ON ONE CORPUS. Extraction is the last step, not a checkpoint.

## Running now
`_c7_drive.sh` under systemd user unit `c7drive` (lingering enabled).
Resumable: stages recorded in `_c7_drive_state`; re-running resumes.
Status line: `_c7_drive_status`. Full log: `_c7_drive.log`.

## Stage sequence
1. DEMAND LOOP (<=6 rounds, MMC=40): coverage pass -> missing count ->
   `_demand_root.py` -> 7 DSE variants -> repeat.
   Exit conditions, each recorded distinctly:
     - missing == 0            -> proceed to stage 2
     - missing unchanged x2    -> STAGNATED, needs a model decision, STOP
     - a round adds no dumps   -> STALLED, demand cannot reach it, STOP
2. FULL ENGINE (completion gate ON, no SKIP_COMPLETION) -> `complete: true`
3. AUDITS `_c7_audits.sh`
4. (then, needing judgement) coordinator sweep -> adversary round -> multiset
   matrix -> extraction

## Decision rules while the user sleeps
- MMC is a SEEDING-THROUGHPUT knob for demand rounds, NOT correctness. Do not
  raise it back to 300. The final pass is unaffected: a truly covered clique
  returns UNSAT immediately and never reaches the cap.
- Do NOT run base rounds. They added ZERO coverage and doubled checker cost
  (_C7R1_BASE_ROUND_FINDING.md). `run_dse.rb:378` seen_paths is launch-local,
  so "new path #N" is NOT evidence of corpus growth.
- If a coverage pass exceeds ~2h, that is the known blowup: the 18 C7A1 dumps
  added 3 NESTED decision vars (to_ary_1_row_target_mentions_container_*)
  that join every clique and multiply its space 8-64x. Those are the class
  PAUSED_C7 lists as "STAY DEPENDENT — never declare". Report, do not fix.
- STAGNATION is a model decision -> escalate to the user with the analysis
  ready. Do not invent an assumption tier; Rule T3 = propose, not ship.
- Adversary round is a sub-agent task per RUNBOOK -> flag to the user.

## After notifications closes
people_stream, then posts_show. BOTH ARE BLOCKED until their private
`concolic_targets.rb` is re-synced from the repaired shared file — theirs are
dated 2026-09-03 and carry NONE of the P-1 write / P-2 exists? / P-9 pluck /
P-10 owner_id repairs (see each batch's `_PREFLIGHT_20260907.md`). Those four
families produced 8 of the 10 adversary wins on people_show. Preserve each
batch's documented descents; adjudicate posts_show's unique
`ActiveRecord::Base#to_param` target rather than inheriting it.
