# PREFLIGHT — posts_show (coordinator, 2026-09-07, before any run)

## BLOCKER: this batch's private `concolic_targets.rb` predates the boundary repair

`posts_show/concolic_targets.rb` is dated **2026-09-03 18:32** (the Gate-1b boundary
fix). The shared declaration `reports/diaspora/concolic_targets.rb` was
revised **2026-09-04 19:27** by the people_show R1 repair (commit 8776bf3),
which fixed FOUR sanctioned boundary families:

  P-1 write · P-2 exists? · P-9 pluck · P-10 owner_id direction

Marker census (`P-1|P-2|P-9|P-10|"write target"`):

| file | markers |
|---|---|
| shared `concolic_targets.rb` | P-1, P-2, P-9, P-10, "write target" |
| `people_show/concolic_targets.rb` | P-1, P-2, P-9, "write target" |
| **`posts_show/concolic_targets.rb`** | **none** |

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

posts_show-specific:
- `Diaspora::Mentionable.singleton_class, :people_from_string` — DESCENDED
- `PostPresenter, :build_mentioned_people_json` — DESCENDED
- `PostService, :mark_user_notifications` — DESCENDED. NOTE: this is the path
  that issues the notification `UPDATE`. Descending it is only sound now that
  the shared boundary declares the P-1 write target — another reason the
  re-sync must happen before the first run.

## SECOND ITEM TO ADJUDICATE: a target this batch alone declares

`ActiveRecord::Base, :to_param` is declared HERE and in NO other batch and NOT
in the shared file. Under Rule T that is a divergence to resolve, not to
inherit: if it is policy-bearing it belongs in the shared declaration for every
endpoint; if it is a wall mock it belongs in this batch's `targets.rb`. Decide
before the run — do not carry it silently through the re-sync.

## Also note
This runner is a **results2-era port** (its header predates the results3
rebuild), unlike people_stream's. Expect more drift than the target census
alone shows; read the header against the current shared declaration before the
first launch.
