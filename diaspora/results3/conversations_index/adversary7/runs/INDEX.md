# adversary7 runs — scenario lists (POST-AUTH §15 scope, hook-less warden)

Each `*.json` is the concrete_run_probe output for one manifest process: per-scenario
`target_calls` (depth-0) + `statements` (the real SQL, in order). `*.judge.txt` holds
mock_note_check + note_fidelity_audit + _multiset_counts for that run.

- `A1_reverify_interactions.json` — 17 requests: re-verification of C-5,6,7,8,12,13,15,18,M-5
  + fresh format×cid×page interactions. mock_note_check EXIT=0, note_fidelity EXACT (30 SELECTs).
- `A2_multiplicity_participants.json` — 4 requests, 12-conversation universe (self-only /
  5-party / empty / unread mix). mock_note_check/note_fidelity EXACT; _multiset_counts RED
  (the last_author no-LIMIT profiles preload, real x11 vs corpus x1 — see ADVERSARY_REPORT_7.md).
- `A3_absent_profile.json` — 2 requests, absent-profile principal (person present, no profiles
  row). json empty (no novel shape); html crashes on a federation network fetch (not a DB stmt).
