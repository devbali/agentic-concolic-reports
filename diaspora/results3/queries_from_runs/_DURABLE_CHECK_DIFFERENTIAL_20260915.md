# policy_loadability_audit — ground-truth differential (2026-09-15)

DISCIPLINE: a check must DISTINGUISH, not merely pass. Both sides measured on
the same corpus (`results3/conversations_index`) with the same code path.

## FAIL side — the SHIPPED file, `conversations_index.sql`

```
written=58  loadable=11  unloadable=47  18.97%
unresolved binds: 4 distinct, 47 statement occurrences
RESULT: RED
```

It names each bind's cause from the corpus, and got all four right:

| bind | statements | cause it reported |
|---|---:|---|
| `_SYM_RESULT_..._devise_user_first_1_person_id` | 40 | RESOLVER DEFECT — a SELECT was recorded; it should join |
| `_SYM_RESULT_..._Calculations_pluck_2_pluck_author_id` | 3 | RESOLVER DEFECT |
| `_SYM_RESULT_..._Relation_to_a_1_row_conversation_author_id` | 2 | RESOLVER DEFECT |
| `_SYM_RESULT_..._Relation_to_a_2_row_conversation_author_id` | 2 | RESOLVER DEFECT |

— and printed the producing note that proves each, e.g.

```
SELECT "people".* FROM "people" WHERE "people"."owner_id"
  = $$(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_id) LIMIT 1
```

It also separates the one unloadable statement that is NOT a bind problem
(#8, `not supported: relation alias` — `COUNT(*)` over a FROM list carrying a
self-join alias), so the two failure modes are not conflated.

## PASS side — the same corpus re-extracted with the fixed resolver

```
written=41  loadable=41  unloadable=0  100.00%
unresolved binds: 0 distinct, 0 statement occurrences
RESULT: pass
```

## What this establishes

The audit is RED for the defect and green for its repair, on one corpus, with
no change to the audit between the two runs. Its cause classification is the
load-bearing part: a bind whose corpus note is a SELECT is a resolver defect
and must be fixed HERE; a bind whose note is a description, an error or absent
is a BOUNDARY defect that no resolver can fix (Rule T — see
`docs/BOUNDARY_NOTE_GAPS_20260915.md`). On conversations_index all four were
resolver defects, and all four are gone.

Run it on the file about to ship:

```bash
PYTHONPATH=src venvs/queries_from_runs/bin/python \
  src/queries_from_runs/audits/policy_loadability_audit.py \
  reports/diaspora/results3/<endpoint> \
  reports/diaspora/results3/queries_from_runs/<endpoint>.sql
```
