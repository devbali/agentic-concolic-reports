# conversations_index — `ConversationsController#index`

**Status: CLOSED** (post-auth scope, DISCIPLINE §15) — adversary round 7 scored
zero wins with entrypoint-frame proof; the engine reports `complete: true`; the
full closing set is green.

---

## 1. Scope

The entrypoint is the **POST-AUTH action with a SYMBOLIC principal** (Bali
decision, 2026-08-31). The authentication stages — the principal SELECT by
session key or remember-token, and the trackable / lastseenable / rememberable
/ lockable decisions and writes — run **above** the entrypoint and are not part
of this corpus. A locked, deleted or bad-cookie principal never reaches the
action, so those arms are outside this endpoint's domain.

**The endpoint's complete policy is**

    reports/diaspora/results3/queries_from_runs/conversations_index.sql
      UNION
    reports/diaspora/results3/_auth_boundary/BOUNDARY_POLICY.md  (§2, statement shapes)

The union is stated in the SQL file's own header. What the endpoint keeps: the
symbolic principal fetch (SELECT + rep + `persisted` / `profile_not_found` /
`language_available` / username pin), every parameter-domain arm, the content
reps, the real layout and gon reads, will_paginate, and the write the action
itself performs (`set_read`).

## 2. Closing metrics (cycle 23b, 2026-09-01 03:07)

| metric | value |
|---|---|
| engine verdict | `OVERALL_COMPLETE=True; COMPLETION=True` |
| coverage_complete / completion.complete | True / True |
| completion.blocking | `[]` |
| corpus | 18,623 dumps (10 variants: html/json/mobile/js/xml × plain/withcid) |
| tree nodes (distinct PC exprs) | 105 |
| total path conditions | 747,915 |
| missing branches | **0** (truncated False, solver_lost 0, unevaluable `[]`) |
| assumption probes | **5,877 PASS / 0 FAIL / 0 NOT-TESTABLE** |
| shims | **15 PASS / 23 PROTOCOL / 0 NO-TEST** |
| completion-config audits | format_coverage, note_fidelity, pinned_text_query, empty_relation_emission, noteless_call, cardinality_consistency — all green |
| eight SQL-consumer audits + hardening lint | all `EXIT=0` (identity_symbolicity, statement_note_lint, bind_resolution, pc_visibility, skipped_pcs `--patched variant_d`, empty_relation, noteless_call, cardinality) |
| lint with runs | `EXIT=0`, H4/H5/H6 clean |
| crash census | pass — every terminal class is an application terminal |
| boundary declaration | pass — every boundary family declared |
| multiset matrix (7 entries, runs passed explicitly) | **0 RED**: batch runs ×3 and adversary7 runs ×3 individually, plus all-together (38 real requests) |
| GATE dry run | 18,623 dumps, 105 exprs, **0 undocumented** |
| gate columns | persisted, unread, subject, author_id, person_id, conversation_id, id |
| pin ledger | guid, text, language, name, username |

Terminal classes in the corpus (all application terminals, none rig crashes):
`ActionView::Template::Error` 4,899 (the `.js` `no_contacts` NameError, C-8),
`ActionController::UnknownFormat` 715 (the undeclared-format family),
`ArgumentError` 57 (will_paginate `Integer("abc")`, C-7),
`I18n::InvalidLocale` 12 (M-5), `ActiveModel::RangeError` 11 (C-18).

Generation cost: base exploration 27 min (10 variants), coverage 116 → 1 → 0
in three ~3-minute passes, report 83.5 s at 765 MB peak RSS.

## 3. Wins ledger

**Verified in this endpoint's model and corpus** (each found by an adversary
round against a model that lacked it, each re-verified by real run in round 7):

| win | what it is |
|---|---|
| C-5 | a write follows the record's DIRTY STATE: the SET list is derived, not asserted (`set_read`'s `unread` write) |
| C-6 | `conversation_id` may be an Array → `IN (?, ?)`, not a scalar equality |
| C-7 | an invalid page (`?page=abc`) is a real terminal: will_paginate's `Integer(value)` raises before the action's reads |
| C-8 | `.js` is not templateless — it renders `index.haml` in full and 500s at the `no_contacts` NameError, and `.js?conversation_id=` performs the endpoint's WRITE first; the four undeclared formats (`xml/atom/csv/text`) are their own arm |
| C-12 | the REAL layout renders (asset resolvers emptied): `include_gon`, `_header`, `_drawer`, `_footer` and their reads belong to the request |
| C-13 | a has_many proxy read twice LOADS ONCE (`loaded?` dispatch) — the second read issues no statement |
| C-15 | `?conversation_id[]` reaches the action as `[]`, truthy, and AR renders `AND 1=0` — a third arm of the cid domain |
| C-18 | an out-of-range scalar cid raises `ActiveModel::RangeError` while the binds are cast — after three statements, with the conversations SELECT recorded |
| M-5 | `users.language` unavailable ⇒ `set_locale` raises `I18n::InvalidLocale` and the request issues EXACTLY ONE statement |

**Reclassified to the shared auth-boundary artifact** (found here, verified
here, and preserved with their evidence in `_auth_boundary/`): **C-10**
(lastseenable's `last_seen` write), **C-11** (a locked principal: logout +
`forget_me!` + 401), **C-14** (a remember-cookie login is an AUTHENTICATION
event → trackable's UPDATE), **C-16** (a write's SET-list ORDER is a two-phase
rule — first save in first-write order with `updated_at` last, later saves in
schema order), **C-17** (`last_sign_in_ip == current_sign_in_ip` is a fact of
its own, never derived from the timestamp equality). With them go R6-NM-1/2/3/5
(cookie age arms, the future-cookie remember write, the deleted principal, the
IP-spoof raise).

## 4. Known limits (recorded, not judged)

1. **Per-row one-representative under-count.** A shape issued once per listed
   row is issued once per REPRESENTATIVE by the sampled-content model (the
   shared runtime's designed limit; the policy is a SET of shapes). Detected
   structurally, not by hand: a note is per-row if it binds a `$$(…_row…)` var
   or, transitively through the dump's own mint graph, a var whose owning rep
   was minted by a per-row call (A7-4). Example: `Conversation#last_author` is
   `Person.includes(:profile).find_by(id: <row>.author_id)`, so its `:profile`
   preload (`SELECT profiles.* … person_id = ?`, no LIMIT) fires once per row —
   real ×11 on a 12-conversation request, corpus exactly 1. The multiplicity of
   such a shape scales with row count, so it is excluded from BOTH the
   under- and the over-emission verdicts (A7-7).
2. **One declared renderer re-read.** On the `.js` 500 path the exception
   renderer re-inspects the unloaded relation and re-issues its paginated read
   (×4 measured, ×1 in the corpus). That multiplicity is the exception
   machinery's, not the app's; declared in `completion_config.json`
   (`multiset_renderer_re_reads`) with its reason.
3. **`_rows_beyond` H4 declaration.** The page beyond the last has 0 rows by
   definition, so will_paginate's `size > 0` conjunct has one realizable
   outcome; the paginated list's own length var carries 0/1/many in both
   polarities.

## 5. Cycle history — the classes that generalize

**Instrument fidelity before model claims (A3-1…A3-5).** Two rig defects
invalidated a round of evidence before any model question could be asked: the
concrete rig resolved the principal ONCE PER PROCESS (so every request after
the first under-reported the Devise `users` read), and the probe dropped
query-cached statements while the AR query cache was never cleared between
requests. Both were fixed (per-request warden object; `CompletionChecker.new_request!`),
every affected claim was re-derived, and M-5's one-statement multiset was
re-established on the fixed rig. The rule: a measurement is worthless until the
instrument that produced it has been tested on a case whose answer is known.

**A model that cannot dispatch cannot be judged (A3-9…A3-11, A4-3).** Saying
`loaded?` truthfully — a proxy read twice loads once — exposed three defects at
once and forced a full regeneration; making the will_paginate model dispatch
did the same. Each time the corpus had been internally consistent and wrong.
The GATE_TABLE pre-flight over the WHOLE corpus (every distinct PC expr must be
documented or the run aborts) is what turned these from silent drift into loud,
early aborts — it fired again in round 7 (A7-1, A7-2).

**The seeder is a first-class component (A3-12, A3-13, A5-6, A6-12).** Round
after round, "coverage stopped closing" was the seeder, not the model: five
scripts that knew only six variants; a base chosen without regard to what it
recorded; a model overlay that wrote Z3's artifact values (`""`, `0`) over the
route that reached the decision; and a var-vs-var handler that only understood
integers, which made every demanded STRING equality unreachable by
construction. Each was diagnosed by replaying single roots and diffing PC
sequences against a donor, never by adding rounds.

**Independence claims are hypotheses; the engine refutes them (A4-8, A6-8,
A6-13).** Three withdrawal rounds followed the same shape: a declared
"disjoint reps" pair turned out to be jointly load-bearing (page × list;
request-parameter × principal; and finally the boundary family itself). The
counter-move that matters is scoping the withdrawal by the RULE, not by the
symptom: withdrawing every SYM_PARAM pair produced a 61-minute combinatorial
pass, while the rep-key-scoped rule kept the demand and the runtime.
`_boundary_family` was later found to be keyed on a substring instead of the
rep key, which manufactured a transitively-unobservable demand of 1,180
combinations — removed by making membership follow `_rep_key` (A6-13).

**Silent compute is a failure mode of its own (A6-11).** Raising the per-clique
cap to list a full demand in one pass turned out to bound Z3's enumeration, not
just the listing: one pass burned 15h32m at 100% CPU with no output, invisible
to watchers that only looked for verdict lines. The repair was three-part — cap
restored and the demand paged through ROUNDS, in-process heartbeats every 10
minutes (phase, elapsed, solver calls, RSS), and a wall-clock watcher that
fires on log-mtime staleness regardless of what the process prints.

**Unobservability is sometimes three-way (A6-14).** A cookie login on a
not-remembered principal passes only through the future-dated arm; otherwise it
401s above the action. So `remembered=False ∧ cookie_future=False` cannot
co-occur with ANY post-terminal decision, while each PAIR is co-observed —
something pairwise independence cannot express. The engine's exemption tool for
that is a SymbolicConstraintAssumption, and it was made corpus-DERIVED: emitted
only while the closed cell is empty, withdrawing itself on one counter-example.

**Scope is a modelling decision, and it pays (A7-0…A7-3).** Moving the auth
stages above the entrypoint replaced a 1,422-combination boundary demand with a
105-node action model that closed in three passes. Nothing was discarded: the
boundary's statements, decisions, constraint and 26 real requests became the
shared artifact the other five endpoints union in. Two GATE aborts during
bring-up were repaired at cause, not by widening a regex — a fallback decision
name documented with its closing polarity (A7-1), and a principal double-fetch
whose not_found arm was recognised as a boundary 401 and removed from the
endpoint (A7-2).

**A judge is code, and code is checked like code (A7-4…A7-8).** The final RED
sequence was entirely in the checking instrument: a per-row classifier that
could not see a transitive per-collection read; an over-emission verdict
computed across differently-scoped variants; a genuine GROUND-TRUTH GAP (no js
request with a populated inbox) closed by adding real evidence rather than an
exemption; an asymmetry that judged per-row shapes leniently in one direction
and strictly in the other; and finally a layout classifier that filed an
early-terminating html request as `plain` and reported a statement present
6,120 times as MISSING. Every one was diagnosed by census against the corpus
before touching anything — and one of them was a defect I had introduced one
round earlier while fixing another.

## 6. Process note

Cycle 23 ended RED and was not reported until the coordinator asked. The rule
(DISCIPLINE §14) is that a chain's verdict is read from the chain's own tail at
the moment it ends and reported immediately, RED or green — never waited for as
a notification.

## 7. Extracted policy (`queries_from_runs`)

`reports/diaspora/results3/queries_from_runs/conversations_index.sql` —
**58 views**, from 383,090 raw queries over 18,623/18,623 dumps loaded
(95 distinct after dedup, 37 dropped by the subsumption prune,
`subsume_ran=True`, no subsume errors). Run under `flock
/tmp/concolic-heavy.lock` in its own unit (`MemoryMax=5G`), 7 min CPU, with the
streaming per-dump dedup driver `_extract_conversations_index_streaming.py`
(ported verbatim from the posts_show driver; `src/` untouched).

Shape of the output: 18 `people.*` views, 14 `profiles.*`, 3 `messages.*`, and
one each of `conversation_visibilities.*`, `conversations.*`, `users.*`,
`aspects.*`, `services.*`, `tags.*` — the action's own reads plus the real
layout's (gon presenter, mobile drawer). 47 `-- NOTE` lines carry per-view
provenance; 2,226 `unscoped` flags were raised pre-dedup.

**Placeholders kept** (unresolved symbolic binds, emitted as `_VAR` and
annotated in the file): the principal's `person_id`, the two
`conversation_id` params, the plucked `author_id`, and two conversation
`author_id`s.

**Extraction-time skips — one kind, 21,037 occurrences, stated in full:**
every one is `unparseable note on …Calculations_count…: SELECT COUNT(*) FROM
(SELECT DISTINCT "conversation_visibilities"."id" FROM
"conversation_visibilities" LEFT OUTER JOIN …)` — will_paginate's
`total_entries` COUNT over a derived table. The transformer parses
single-block SELECTs into views and does not fold a COUNT over a subquery.
This costs the policy no row visibility: the query returns a CARDINALITY, and
the rows it counts are exactly those of the paginated read, which IS in the
file as the `conversation_visibilities.*` view (same `person_id = _principal`
predicate and the same join to `conversations`). Recorded here rather than
waived: if a consumer ever needs cardinality-channel coverage, this is the one
shape to add.

The `skipped_pc_shapes` counters (685,372 occurrences over 40 shapes, led by
the sampled lists' length tests and the count/exists probes) are the fold's
normal PC-side skips, not query losses.

---

*Full derivations: `AGENT_RUN.md` (A3-1…A7-8). Boundary artifact:
`../_auth_boundary/BOUNDARY_POLICY.md`. Extracted policy:
`../queries_from_runs/conversations_index.sql`.*

## Post-closure correction (2026-09-01) — one check was vacuous here

While reconciling comments_index, the coordinator found that
`cardinality_consistency_audit`, counted among this endpoint's closing checks,
judged **zero** events on this corpus. Its rule's subject is a BULK loader
reading a list's own rows; conversations has none — its `load_intermediate`
calls key on a single finder result, and its list rows are read one statement
per row (`messages.conversation_id = <row_id>`), a shape the audit excludes by
design because `=` is correct there.

**This retracts nothing.** The absence is faithful to the application: the
count-based multiplicity matrix (0 under / 0 over) and `note_fidelity_audit`
(EXACT on every endpoint statement) independently confirm the real endpoint
issues those per-row statements and no bulk preload over a list. Engine
completeness, the assumption gate, the other audits, and adversary round 7's
zero wins are untouched.

**What it does change** is the honest count of what closed this endpoint: ten
checks with evidence here, not eleven. The audit now prints its population and
reports `pass but VACUOUS` at zero, so this is visible in its own output rather
than only in this note.


## Second post-closure note (2026-09-01) — what the multiset verdict means

Adversary round 9 on comments_index found (M-18) that every rig in this project
dispatches outside `ActionDispatch::Executor`, so ActiveRecord's query cache —
installed as an executor hook — never engages. A real Rack request to this app
serves some repeated statements from that cache; our harness issues all of them.
Both sides of this endpoint's count matrix (corpus AND the concrete-run ground
truth) were measured that way.

**Checked here rather than assumed:** this corpus issues **6 757** repeated
identical reads (same SQL, same bind variables, same request) and **0** of them
are modelled as returning a different row count on the second issue. So the
corpus never fabricates a state query caching would forbid; it over-states how
much traffic reaches the database.

**Nothing in the extracted policy changes.** Caching removes duplicate
statements, it never introduces a shape, so the 58 views and the access they
describe stand. What is weaker than it sounded is the matrix sentence: "0 under
/ 0 over" means the corpus reproduces what OUR HARNESS records, not that it
reproduces production statement counts. Read it as a claim about shape presence
and about internal consistency, not about database traffic.
