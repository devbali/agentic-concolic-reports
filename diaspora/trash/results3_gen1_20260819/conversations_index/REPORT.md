# results3/conversations_index — discipline-clean rebuild (2026-08-18)

(Fifth results3 endpoint. The completion pass finished its assumptions
rebuild and checker run at 21:46 on 2026-08-18 and was killed — again by
the OOM problem this box has had all day — before this REPORT could be
written. Saved 2026-08-19 from the on-disk state: `coverage_summary.json`,
`coverage_assumptions.py`'s docstring ledger (the pass's own write-up),
and the four exploration summaries. Nothing here is new analysis; it is
the record of what that pass did and proved.)

## Verdict — honest stop

`coverage_complete: false, truncated: true, solver_lost: 0,
unevaluable_exprs: [], tree_nodes: 38, missing (cap-4 sample): 144,
total_runs: 3,009, PCs: 69,494, assumptions: 62 declared / 60 used,
0 unparseable dumps, dump_errors: {ActionView::Template::Error: 125}`.

The residual is the `count_1`-keyed family left FULLY CONNECTED on
purpose: the corpus itself proves that cutting it would be unsound (see
"ordinal instability", below). Every sampled missing combo is a
5–31-conjunct demand (mean 18.6) crossing the sidebar-collection
families (`to_a_2`/`records_1`/`size_2`/`pluck_1_*`) with the
right-column and guard families — the same combinatorial-demand shape
posts_show reported as its honest stop. Single-flip DSE exhausted its
worklist on three of four scenarios (below); forcing `complete` would be
false.

## Corpus (2026-08-18, one `run_dse.rb` invocation per scenario, all four
variants dump into this directory)

| scenario     | dumps (=distinct paths) | runs   | PCs    | stop                  |
|--------------|-------------------------|--------|--------|-----------------------|
| html_plain   | 392                     | (summary lost — overwritten by json_withcid's; see note) | ~5,470 | — |
| html_withcid | 2,521                   | 12,000 | 63,336 | MAX_RUNS cap          |
| json_plain   | 8                       | 45     | 26     | worklist exhausted    |
| json_withcid | 88                      | 10,935 | 662    | worklist exhausted    |

Note: `exploration_summary.json` and `exploration_summary.json_withcid.json`
are byte-identical (both json_withcid); html_plain's per-scenario summary
was lost to the same-name overwrite. Its 392 dumps and ~5,470 PCs
(= 69,494 − 63,336 − 662 − 26) are intact and are what the checker used.

## The three findings of the completion pass (full arguments + empirical
counts in `coverage_assumptions.py`'s docstring — the authoritative copy)

1. **Shared-counter ordinal instability blocks the obvious family cut.**
   `to_a`/`records`/`count`/`size` share one per-(class,method) counter
   across the whole request, so `to_a_2` means the sidebar materialize in
   most runs but `conversation.messages.to_a` (a DIFFERENT call site) in
   runs where the sidebar list is empty — proven by direct counterexample
   (`dump_html_withcid_dse10127.json`). An assumption keying on `count_1`
   as guard would silently exempt combos other runs genuinely produce, so
   NO count_1-keyed cut was declared; that residual is the 144 missing.
   (Same root cause as the known prefix-relative var-naming bug in
   `call_interceptor.rb`.)

2. **posts_show's Tier 6 ("length gates its own row attribute") does NOT
   port.** This endpoint's `to_a`/`records` mock builds the representative
   row unconditionally, before the length seed is decided — and the corpus
   shows the co-occurrence for real (e.g. `len(records_2_rows)==False`
   with `records_2_row_text_has_mention` in 672/3,009 dumps). No such
   assumption declared here.

3. **Crash attribution (`dump_errors: 125`).** 120/125 are
   `_conversation.haml:35 — undefined method 'message' for nil`: a
   MOCK-FIDELITY gap, not an app bug — `messages.present?` (`records_2`)
   and `messages.last` (`last_1`) are two independently seeded mocks for
   the SAME real relation, so DSE produced "present yet last==nil", a
   state no consistent database can produce. The other 5 are
   `No route matches ... id=>nil` from `convidx_conv_lookup_1` returning
   nil at the partial's first use of `conversation`; the Tier 2 CONVIDX
   gate proves (matching the dumps: no PCs recorded past that point) these
   foreclose everything later in the partial.

## Assumption tiers (62 declared, 60 used; every NEW pairing verified
0/3,009 empirical violations AND argued from the real guarding code)

- **Tier 0** — scenario variant exclusivity (html/json × with/without
  `conversation_id`), auto-derived from observed (expr, variant) SETS —
  no reliance on ordinal meaning.
- **Tier 1** — the prior pass's 7 assumptions kept verbatim (A×B/A×C/A×D
  on `conversations_controller.rb:13-24` + `conversation.rb:31-38`;
  P1×P2/P1×P3/P2×P3 on `person.rb:254-255`), extended to the
  render-descent exprs the mock-surface discipline newly exposed: A also
  forecloses `to_a_1`, the `convidx_conv_lookup_1_id == first_1_id`
  compare, and the A-gated right column (`count_3`/`records_3`/`to_a_3`);
  B also forecloses `to_a_1`.
- **Tier 2** (new) — `convidx_conv_lookup_1_not_found` gates everything
  `_conversation.haml` reads off the conversation object.
- **Tier 3** (new) — `last_1` not_found-gates-attribute (the classic
  found-vs-attribute pairing on a dedicated, stable ordinal).

Trustworthy ordinals (`to_a_1`, `convidx_conv_lookup_1`, `first_1`,
`first_2`, `find_by_1`, `last_1`) are each either a dedicated per-target
counter or structurally the temporally-first call on their shared counter
— verified empirically, 0 violations.

## What the discipline bought (vs results2)

The render family no-ops are gone, so `index.haml` → `_conversation.haml`
/ `_show.haml` / `_messages.haml` / `_message.html.haml` execute for
real, opening the whole second generation of collection exprs
(`count_N`/`records_N`/`to_a_N`/`size_N`/`SYM_LEN_*`) and their SQL.
Extraction gate: **20 distinct queries** recorded (results2: 6) —
sidebar visibilities list, per-conversation participants/messages/author
lookups, unread count/pluck family, and the withcid conversation +
first-unread + set_read chain, with `$$()` binds. (Subsumption prune and
the blockaid diff vs the reference's 16 did not run in the killed
session — its leaked `JAVA_TOOL_OPTIONS=-Xmx1200m` crashed the checker
JVM on every endpoint; re-run 2026-08-19, see
`../queries_from_runs/_summary.json` and `../queries_from_runs/diff/`.)
