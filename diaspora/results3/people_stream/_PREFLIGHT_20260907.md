# PREFLIGHT — people_stream (coordinator, 2026-09-07, before any run)

## BLOCKER: this batch's private `concolic_targets.rb` predates the boundary repair

`people_stream/concolic_targets.rb` is dated **2026-09-03 18:32** (the Gate-1b boundary
fix). The shared declaration `reports/diaspora/concolic_targets.rb` was
revised **2026-09-04 19:27** by the people_show R1 repair (commit 8776bf3),
which fixed FOUR sanctioned boundary families:

  P-1 write · P-2 exists? · P-9 pluck · P-10 owner_id direction

Marker census (`P-1|P-2|P-9|P-10|"write target"`):

| file | markers |
|---|---|
| shared `concolic_targets.rb` | P-1, P-2, P-9, P-10, "write target" |
| `people_show/concolic_targets.rb` | P-1, P-2, P-9, "write target" |
| **`people_stream/concolic_targets.rb`** | **none** |

Those four families produced **8 of the 10 adversary wins** on people_show.
Running this endpoint on the current copy would start it from a boundary
already known to be defective — DISCIPLINE §8 Rule T (a boundary defect voids
every endpoint and forces a from-scratch regeneration). **Re-sync from the
repaired shared file BEFORE the first run**, preserving this batch's
documented descents.

## Descents to PRESERVE across the re-sync (verified against the runner header)

Common to every batch (deliberate, documented):
- `ActionController::ImplicitRender#default_render` — Section Z/Y2 removed
- `calc, :pluck` — batch-local override lives in `targets.rb`
- `Post.singleton_class, :blocked_people` — DESCENDED

people_stream-specific:
- `Stream::Base, :attach_user_likes` — DESCENDED (recovers the viewer-likes
  query results2 documented as swallowed)
- `Stream::Base, :post_ids` — DESCENDED

## Nothing else outstanding
The runner is a results3 discipline-clean port; no other divergence from the
shared declaration was found.
