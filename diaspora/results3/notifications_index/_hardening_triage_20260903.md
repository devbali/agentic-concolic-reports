# Hardening-lint triage — notifications_index C7 corpus (coordinator, 2026-09-03)

Ran `hardening_lint.py notifications_index --sample 400` on the regenerated
C7 corpus (4 938 dumps). Result: **2 flags, both triaged below.** Nothing here
blocks the account-gated resume; both feed step 2 (demand rounds).

## H3 — opaque notes: `CollectionProxy#records/#load_target` — FALSE POSITIVE (design)

Flag: note `"preloaded association #actors: answered from the loaded targ…"`
is not SQL.

Triage: this note fires ONLY on the already-loaded path
(`targets.rb` §5b-CP, `a0.loaded?` true). On that path Rails issues NO
statement (`collection_association.rb` `load_target` returns early when
`loaded?`), so a SQL note would be a lie. The mock returns the real loaded
rows (same length variable + representative the preloader already recorded)
instead of swallowing, and the actual statements (the join-table fetch via
`ConcolicThroughLoadProbe.load_intermediate`, the people `IN` read via
`emit_includes_preloads`) are emitted as their own noted events. The
non-loaded path of the same mock carries real SQL (`ct.sql_for`). H3's
"documented wall" escape hatch doesn't match this target (no WALL word), so
the lint flags it — expected behavior of the check, not a model defect.

Answer for the report: document this target as a declared no-statement
wall in the batch notes (the lint's `WALL`-word escape hatch, or its
nested-SQL evidence, would clear it); no code change.

## H4 — collection length polarity: `CollectionProxy_records_4_rows` — REAL, feed step 2

Flag: `SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_4_rows`
recorded with only `False` polarity in the sample (len `== 0` seen; `> 1`
essentially absent).

Triage: this flags a length dimension whose EMPTY state is observed but
whose non-empty state is not — "empty-state branches, interior indexes and
`count > 0 with zero rows`" are blind. Give the demand rounds a seed that
makes the `records_4` collection non-empty (which collection is it? map
`records_4` to its association before seeding — likely one of the six
content dimensions). Also note `records_3`/`records_2` show healthy
two-polarity (34/34 in the same sample), so this is per-dimension, not a
systemic miss.

## Not flagged (worth stating in the report)

- H1: all 7 render scenarios present, mobile variant included — the layout
  un-pin held in the regenerated corpus.
- H2: link-bearing text not seeded, but an exists?-family target and
  `1 AS one` probes are present — no MessageRenderer foreclose.
- H5: all type columns pinned correctly (mentions_container_type, taggable_type, type).
- H6: skipped (no `--runs`); the final closing pass runs it with the
  concrete runs, as always.