# Blockaid new-vs-old extraction comparison — results (2026-09-01)

Method: blockaid coverage mode via `src/queries_from_runs/subsume/check_subsumed.sh`
(z3 4.8.12, diaspora schema + PK/FK/deps from the harness resources).
Direction that matters (completeness): **NEW extracted policy as views, OLD
extracted policy as queries** — covered[i] = old query i is answerable from
the new policy.

## Structural finding: most NEW views are unusable by blockaid

The new extraction (`results3/queries_from_runs/*.sql`) carries unresolved
`_SYM_RESULT_*` symbolic binds in most statements; blockaid rejects those as
unrecognized constants at probe time, so they are quarantined:

| endpoint | NEW views | usable | rejected |
|---|---|---|---|
| comments_index | 79 | 26 | 53 (unrecognized `_SYM_RESULT_*` const) |
| conversations_index | 58 | 8 | 50 (40 unrecognized const, 6 aggregate-in-select, 3 unsupported-as-checked, 1 unsupported-as-subsumer) |

## NEW covers OLD (completeness)

### comments_index (OLD = 23 queries)
| timeout | covered | NOT covered | undecided |
|---|---|---|---|
| 15 s | 2 | 0 | 21 |
| 60 s | 2 | 0 | 21 |
| 120 s | 2 | 0 | 21 |

Covered: `SELECT * FROM posts WHERE public = TRUE`, `SELECT * FROM users WHERE id = _MY_UID`.
The 21 undecided are large multi-join queries (people/profiles/mentions/comments/
posts with 8-10 relations); z3+MBQI cannot decide them at ANY of 15/60/120 s,
neither full-set nor single-view formulas. **Nothing is proven missing.**

### conversations_index (OLD = 16 queries)
| timeout | covered | NOT covered | undecided |
|---|---|---|---|
| 15 s | 5 | 4 | 7 |
| 60 s | 5 | 5 | 6 |

Covered (5): contacts+people join read, `aspects WHERE user_id=_MY_UID`,
`people WHERE owner_id=_MY_UID`, `services WHERE user_id=_MY_UID`,
`users WHERE id=_MY_UID`.

NOT covered — proven missing from the new extraction (5):
1. conversation_visibilities SELECT (conversation-reader visibility)
2. `SELECT 1 FROM people, roles WHERE roles.name='admin' AND people.owner_id=_MY_UID`
3. `... roles.name IN ('admin','moderator') ...`
4. profiles SELECT (id, diaspora_handle, first_name, ...)
5. `SELECT * FROM notifications WHERE recipient_id=_MY_UID AND unread=TRUE`

Undecided (6): profiles/people/messages/contacts reads with joins — z3 wall.

## Errors taxonomy

In the completeness direction, every "error" is `timeout/inconclusive`
(solver proved neither coverage nor a counterexample within the cap). No parse
failures, no crashes, no formula errors. In the reverse direction (OLD covers
NEW), errors additionally include the `_SYM_RESULT_*` probe rejections on the
NEW queries (structural, not semantic).

## Notes

- Per-view subsets were tried for comments (26 single-view runs): same wall,
  killed after confirming no additional decisions. Longer timeouts don't help
  comments (identical 2/0/21 at 15/60/120 s) — the heavy queries are beyond
  this z3 setup, not marginal.
- Longer timeout DID help conversations (4 -> 5 proven misses at 60 s).
- Machine: 8 GB RAM, 4 cores, no swap. java checker ~1-2.5 GB; 3 solver
  threads is the safe concurrency (8 threads OOM-killed the pairwise batch).