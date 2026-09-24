# The Discipline — consolidated (2026-08-21)

This supersedes the working notes in `DISCIPLINE_TESTS.md` (kept as history).
It exists because the discipline has now been violated **four times after we
built a verification suite for it**, and each time the suite passed while the
discipline failed. This document states what every violation actually was,
why the checks structurally could not catch it, and the minimal
discipline + checks that close the class — not the instance.

---

## 1. Were they all discipline violations? Yes — and all of only two kinds

Every extraction gap in this project, before and after the test suite, is one
of exactly two classes:

**Class S — swallowed or mis-shaped statements.** A mock returns a value at a
point where real execution would issue one or more SQL statements, and the
emitted notes do not match the real statements — either missing entirely
(swallowed) or wrong in projection/join shape (mis-shaped).

**Class B — blinded branches.** A data-dependent conditional in real code
executes, but no path condition is recorded for it — because a value that
should be symbolic is concrete (a pin, an unregistered variable, a compare
that never fires on our mocked structures). The branch is not "unexplored";
it is *invisible*: DSE cannot flip what was never recorded.

The complete history:

| # | When found | Violation | Class | Found by |
|---|-----------|-----------|-------|----------|
| 0a | gen2 | `persisted?` returned concrete → `1=0` scopes unlabeled in every run | B | user reading the SQL |
| 0b | gen2 | `_SYM_RESULT_..._find_by` placeholders not rendered as producer joins | S (shape) | user reading the SQL |
| 1 | gen4 | `has_many :through` load: real path issues the join-table fetch; mock emitted one note | S | reference diff (proven rejection) |
| 2 | gen4 | pins (`text`, Post STI) foreclosed the photos branch family | B | reference diff (tried_unknowns) |
| 3 | gen6 | `.includes(person: :profile)`: real Preloader issues one SELECT per step; ALL materialize mocks swallowed them | S | user pushing on "why aren't all branches hit" + zero-PC scan |
| 4 | gen6 | `pluck("tags.name","taggings.id")`: note rendered the relation's default `SELECT "tags".*`, losing the joined-table column from the view's output set | S (shape) | reference diff residue, diagnosed on user's "why is there still the residue" |
| 5 | gen7 | `assoc_#{name}` var names collide across owners (three `assoc_profile` producers in one run), so the extraction fold attributed the StartedSharing target's profile-tags read to the CONTACTS chain instead of the notifications-target chain — a mis-chained view that provably cannot cover the reference query (both sides project only `(name, taggings.id)`, no ownership column) | S (shape, in fold-space) | determinacy analysis after solver stalemate: `[22,75]` refuted in 48s, every richer combo inconclusive at 900s |
| 6 | gen8 | `relation.find_by(conditions)` notes rendered with NO WHERE at all (806/806 events: bare `SELECT "contacts".* FROM "contacts"`): sql_for's Relation branch never renders args-borne conditions, and the kwargs→positional re-pack is undone at the wrapper boundary (Ruby 2.6 auto-splits the trailing hash back into **kwargs, which the interceptor's param binding drops). `contact_for_person_id`'s `find_by(user_id:, person_id:)` — the link from notification target to contact — was severed in every corpus since the beginning | S (shape) | chasing violation 5's chain: the repaired names exposed that the taggings view was contacts-chained because find_by_1's note had no conditions |
| 7 | gen9 | the STI type pin (`attrs["type"] = "Notifications::..."`, a plain String) silenced the app's own `note.type == "Notifications::StartedSharing"` branch (_notification.haml:5) — no PC, so `notifications.type = '...'` vanished from every downstream view; the correctly-chained taggings view stayed type-unscoped and provably could not determine the type-scoped reference query | B | determinacy analysis of the gen9 stalemate: view and query near-identical except the type predicate |
| 8 | gen10 | `pcs.parse_pc` does not understand `StringVal('…')` — the Ruby runtime's native rendering for EVERY string-compare PC (string.rb z3_str_val) — so every recorded string-equality branch in every corpus was silently dropped into `skipped_pcs` and no string-column predicate ever folded into any view. The violation-7 repair recorded the type PC perfectly; extraction then discarded it | B (in fold-space) | the repaired PC visibly present in dumps but absent from the view; parse_pc probed directly |

Violations 1–4 happened **after** T1/M1–M4/A1–A4/T2 existed and passed.
Not one of the four was first caught by our own suite. Every discovery came
from a *differential* signal: the reference diff, or a human comparing what
real code does against what the corpus contains.

## 2. Why the checks missed them — three structural reasons

**(a) The checks audit presence; the violations are absences.** T1 checks
that a shim's real body issues no SQL. M2 checks coverage of test bodies. M4
checks that a note faithfully renders *the statement it renders*. A1–A4 check
recorded assumptions. All of these inspect artifacts that exist. Class S and
Class B are things that *don't* exist — a note never emitted, a PC never
recorded. No per-artifact check can see an absence. Only comparison against
ground truth can.

**(b) The checks are per-mock; the violations are per-path.** The materialize
mocks passed their probes for every path we knew about. Then a new app path
(`mentioned_people`) routed through the *same mocks* via a *different AR
mechanism* (the Preloader) and the same mock silently under-reported. A mock
is not correct or incorrect in isolation — it is correct *relative to every
call path that reaches it*, and new paths appear whenever exploration opens a
new branch. Unit-shaped checks cannot re-validate per new path; only a
corpus-level differential can.

**(c) After each failure we wrote a test for the instance, not the class.**
T1b was written to check through-association intermediates — the exact
mechanism of violation #1. Violation #3 was the *same class* (statement-set
equivalence) through a *different mechanism* (eager loading), so T1b passed
while the discipline failed. Any check that enumerates mechanisms
(through-loads, preloads, counter caches, …) loses to the next mechanism.
The check must be derived from ground truth so that unknown mechanisms are
covered by construction.

## 3. The discipline — three rules, nothing else

**D1 (evidence equivalence).** A mock may replace *execution*; it must never
replace *evidence*. For any call path, the notes emitted under mocking must
match the statements real execution would issue on that path — as a
multiset, and statement-by-statement in tables, joins, predicates (with
symbolic binds where values are data), and **projection**. "The mock returns
the right value" is not compliance; "the corpus contains the right
statements" is.

**D2 (branch visibility).** Every conditional in reached app code whose
predicate depends on data must either (i) record a PC over a symbolic
operand, or (ii) appear in the pin ledger with a written branch-neutrality
argument and a seeded decision if branch-relevant. A concrete value at a
data-dependent compare with neither is a violation even if the run is
"correct" — invisibility is the harm.

**D3 (assumption independence).** Every foreclosure/exclusivity
assumption carries a directed probe (A2), **verified at the end of each
generation against the final evidence layer** (Bali, 2026-08-25 — an A2
pass is relative to the target/note set it ran under, and ours grows
with every repair; end-of-batch timing makes the verdict contemporaneous
with the extracted policy). A3 (line-diff of the probe pair) is demoted
to an on-demand diagnostic when a probe fails — evidence-level
independence at the final layer is the criterion; execution-level side
effects that touch no PC or target function do not affect the policy.
*(This family has never produced a miss — all post-suite violations were
mock- or fold-side.)*

## 4. The checks — absence-detecting, derived from ground truth

**C1 — statement differential (kills Class S, all mechanisms).**
Run the endpoint end-to-end in *real mode*: concrete fixtures, a real
database, and AR's own instrumentation (`sql.active_record` notifications)
logging every statement actually issued. Run the same scenario in concolic
mode and collect all emitted notes. Normalize both sides (table set + join
set + predicate columns + projection columns; literals wildcarded) and diff:

- real statement with no corresponding note → **FAIL (swallowed)** — this is
  violations 1 and 3, caught before any solver runs;
- corresponding note whose shape differs (projection/joins) → **FAIL
  (mis-shaped)** — this is violations 0b and 4;
- note with no real counterpart → warn (over-emission; usually a seeded
  branch the fixture didn't take — cross-check against the run's PCs).

C1 is per-*path*, not per-mock: any new branch family opened by exploration
gets a new fixture scenario and a fresh differential. It never needs to know
which AR mechanism is involved.

**C2 — branch differential (kills Class B).**
Same real-mode run, with line/branch coverage on app code (JRuby `--debug` +
Coverage — the M2 machinery). Compare against the union of app lines executed
across the concolic corpus, and against recorded PCs:

- app conditional executed in real mode whose line the corpus never reached →
  blind spot (violation 2's photos family);
- app conditional the corpus *does* execute, with no PC referencing any
  symbolic operand and no pin-ledger entry → blind compare (violation 0a's
  `persisted?`; gen5's `diaspora_handle` compare — zero PCs corpus-wide was
  the tell that finally exposed violation 3).

**C3 — external oracle (OPTIONAL — never assumed).**
(Reframed 2026-08-24, Bali: the engine must produce all queries WITHOUT a
reference policy; do not assume one exists.) When a reference policy
happens to be available, a determinacy diff against it is a free extra
detector — and any residue that first surfaces there means **C1/C2 have a
gap**: the repair loop must fix the check as well as the mock, and show
the strengthened check catches the violation on its own. The completion
criterion is C1 + C2 + the corpus/fold audits, never C3. The full
per-check spec with examples: `CHECKS.md`; the runnable suite:
`src/end_to_end_completion_checker/` (language-agnostic auditors +
C1 differ, Python) and `src/ruby_runtime/completion_checker/`
(in-process probes).

**P — the process rule.** When a violation is found, the repair (T3 loop,
unchanged) must end with a differential check that catches the violation's
*class* with the mechanism left unspecified. An instance-shaped test does not
close the loop. This is the rule we broke three times.

## 5. Mapping from the old suite

| Old | Status |
|-----|--------|
| T1 leaf-probe | kept, reframed 2026-08-24 (Bali): the contract is TARGET FUNCTIONS, not SQL — a shim mock's real body must reach zero target functions (naming convention 2026-08-24: SHIM MOCK = replaces pure computation, contributes no evidence; TARGET MOCK = mock of a declared target function, must produce evidence matching the real one) (targets are where the runtime mints evidence; SQL is just the most important target family, asserted separately via statement_log where a DB is wired). Implemented: completion_checker/target_call_probe.rb |
| M2 100% coverage | kept — unit hygiene for probe bodies |
| M4 note fidelity | subsumed by C1 (C1 checks shape against *real* statements, not against what the mock meant to render) |
| T1b, T1c | subsumed by C1, C2 — they were instance-shaped versions of these |
| T2 / A1–A4 | kept unchanged (D3) |
| T3 repair loop | kept, with rule P appended |

## 6. Status (2026-08-21)

- Violation 3 repaired (`emit_includes_preloads`): **gen6 result 70/71
  covered, 0 rejected** — the repair flipped all six profiles-via-mentions
  queries plus two mention-row queries (subset sweep proved most in 2-5s).
- Violation 4's first repair was itself instance-shaped and failed — it
  rewrote the projection from the pluck *arguments*, but ground truth
  (`notifications_index/_probe_tags_sql.rb`, the first concrete C1 probe:
  clean app boot, no mocks, real relation SQL) showed the real statement
  also projects the association scope's `ORDER BY taggings.id` column.
  Exactly the failure mode §2(c) predicts, caught this time by a
  ground-truth differential instead of the next reference-diff residue.
  Second repair (order-column projection) landed in gen7: **70/71 covered,
  0 rejected** — but the taggings query stayed unknown, exposing
  violation 5 (chain mis-attribution from owner-colliding assoc var
  names). Third repair: owner-qualified association base names
  (`assoc_base_name` in concolic_targets.rb) — every association var now
  names its owner chain (`..._row_target_profile_id`), smoke-verified;
  gen8 regenerating with the ctx/saturation seed rounds re-derived from
  the renamed corpus (the old seed files reference pre-rename names).
  Note for C1's design: violation 5 lives in the *fold*, not the mock —
  the statement differential must therefore compare the FOLDED views'
  join chains against real statements, not just the raw per-call notes.
- The gen8 fold repair itself first broke 21 view families (the fold
  registered producers only for `assoc_`-prefixed names) — caught by the
  placeholder count in the same run and fixed by making registration
  note-driven for any var; gen8b restored 70/71.
- Violation 6 (severed find_by conditions) repaired via the thread-local
  capture pattern at the ConcolicKwargsToPositional boundary (where
  values still carry symbolic identity), read back by
  sql_for/class_finder_sql. gen9: chain restored (the taggings view now
  joins taggings→profiles→contacts(recipient,target)→notifications) but
  the query stayed unknown — exposing violation 7.
- Violation 7 (silent type pin) repaired with `TypeLinkedString`: the
  concrete String pin keeps `constantize`/`Hash#key`/`is_a?` behavior,
  but its own `==`/`!=` record the linking PC on the row's `_type` var,
  so the app's genuine type branch folds into downstream views as
  `notifications.type = '...'` (transform.py's atom relevance filter
  scopes it to queries chained through the note row, post-compare).
  Smoke-verified both branch sides; gen10 regenerating.
- Violation 8 (string PCs never folding): repaired with a StringVal
  unwrapper wrapped around pcs.parse_pc — same in-process monkeypatch
  pattern as the assoc fold, src/ untouched, upstreaming flagged.
  Violations 5 and 8 are mirror images: S and B each have a fold-space
  analogue — evidence correctly *recorded* by the runtime can still be
  mis-attributed (5) or discarded (8) at extraction. C1/C2 must
  therefore run against the FOLDED output, not the raw corpus.
- Pattern worth naming: violations 4→8 form a chain — each repair made
  the corpus legible enough to expose the next, strictly deeper defect
  (projection → chain attribution → severed predicates → silenced
  branch → discarded branch evidence). This is what C1/C2 would have
  surfaced in one differential pass instead of five solver-mediated
  iterations.
- One extraction-semantics lesson from closing the loop: run-level PC
  folding OVER-scopes queries that execute on both sides of a branch
  (the actors chain gained `type <>/= 'StartedSharing'` variants and two
  previously-covered reference queries flipped to REJECTED). The sound
  fix is complement elimination at view-build: when both `col = 'x'` and
  `col <> 'x'` variants of an otherwise-identical view exist, their
  union is exactly the unscoped view — merge; a single-variant view
  keeps its predicate (control dependence cannot be ruled out, and for
  the truly branch-gated reads — the StartedSharing contact/tags chain —
  that predicate is precisely what made coverage provable).

## 7. Final score (2026-08-21, gen10c)

**71 / 71 reference queries covered, 0 rejected, 0 tried_unknown.**
The full arc: 1 (results2) → 7 → 15 → 30 → 44 → 60 → 64 (gen4) →
70 (gen6, preload emission) → 70 (gen7-9, three more repairs converging
on the taggings chain) → **71 (gen10c)**. Every one of the last seven
came from a discipline repair, not solver escalation; the solver's role
was verdicts, and its stalemates were themselves the class-B/S detectors
of record until C1/C2 exist.
- C1 and C2 are **specified but not yet implemented** — the reference diff
  (C3) is still doing their job, which is exactly the situation this
  document exists to end. Implementation is the next work item: the real-mode
  harness is the missing piece (fixture DB + `sql.active_record` logging);
  the concolic side of both differentials already exists in the corpus.
- The score these repairs are accountable to: 64/71 covered, 0 rejected,
  7 tried_unknown at gen4-final; gen6 targets the 6 profiles-via-mentions
  (violation 3) and the taggings.id projection (violation 4) — i.e. all 7.


## 8. Rule T (2026-08-27) — the target boundary is shared, and a defect in
## it restarts everything

### T1 — one boundary, many shims
The set of **target functions** (what `declare_target` covers: the
ActiveRecord query boundary, the app-level data-access targets, the
framework walls) is a property of the APPLICATION, not of an endpoint. It
lives once, in `shared/target_boundary.rb`, and every batch requires it.

What stays per batch:
- **shim mocks** (pure leaves: `Person.name_from_attrs`, `image_url`,
  `authenticatable_salt`, …) with their `shim_tests.rb`;
- **call-site-stable aliases** (`ci_vis_first`, `devise_user_first`,
  `convidx_conv_lookup`, …) — naming only, byte-faithful;
- **scenarios / variants**, fixtures, concrete manifests;
- **pins**, each with its ledger entry, and the endpoint's assumptions.

Measured before the split: the five copies of `concolic_targets.rb` were
77% identical (393 of ~508 non-comment lines; 43 of ~50 `declare_target`
lines common to all five). The divergence was accidental, and it cost the
same defect three times — `Post.exists?` on the `diaspora://` link family
(`ADVERSARY_WINS.md` C-4, M-1, N-1).

### T2 — a target-boundary defect voids EVERY endpoint
A defect in a target declaration — a note that misstates what the real call
does, a note that is not SQL over a body that can reach SQL, a pinned
column inside a note, a wrong return kind, a missing target — is a defect
in the shared boundary. When one is found, on any endpoint, by anyone:

1. every endpoint's `complete: true` is **void**, including endpoints whose
   own adversary round was clean;
2. the fix lands in `shared/target_boundary.rb`, never in a batch copy;
3. **every** corpus is regenerated from scratch against the fixed boundary
   (no patching of existing dumps, no partial rounds);
4. all three checks re-run per endpoint: engine (coverage + assumptions +
   shims + note check) → `queries_from_runs/audits` → `tools/hardening_lint.py`
   → adversary;
5. the row in `ADVERSARY_WINS.md` moves to `verified` only after a real run
   on the regenerated corpus.

A shim defect, by contrast, is local: it voids only its own endpoint. The
cost of a from-scratch cycle is hours of machine time and no human
attention; the cost of a wrong boundary is a wrong policy on every endpoint
that shares it.

### T3 — agents may not edit the boundary
A batch agent that believes a target declaration is wrong STOPS and reports
it as blocking, exactly as it would for a `src/` change, and lists every
target-declaration change it needs under a `BOUNDARY CHANGES` heading in
its `AGENT_RUN.md` cycle section (target, old note/return, new note/return,
the real statement that justifies it). Only the coordinator edits
`shared/target_boundary.rb`, and doing so triggers T2.

### T4 — what the boundary must satisfy (harvest list, from real runs)
- a target whose note is a non-SQL string must be **proven** unable to
  reach another target — otherwise it swallows the calls below it
  (`MessageRenderer#title` swallowed `Post.exists?`: N-1; `hardening_lint`
  H3 lists the candidates per batch);
- `FinderMethods#exists?` carries the existence probe
  `SELECT 1 AS one FROM <t> WHERE <col> = $(…) LIMIT 1` — never `SELECT t.*`
  — and the text's link-bearing property is a decision, not a pin;
- no note pins a type column (`type`, `*_type`) to one literal; the type is
  a decision over the real subclass set (N-2);
- projection fidelity: existence probe ⇒ `SELECT 1 AS one … LIMIT 1`;
  aggregate ⇒ `COUNT(*)`/`SUM`; pluck ⇒ its real projection + ORDER;
  preload ⇒ one bulk `IN (…)`, not per-row `= $(…)`; finders carry
  `ORDER BY pk` + `LIMIT 1`;
- return kinds match the real call (row / list / count / bool / nil) — no
  count int for a row list, no nil for a Person-or-raise;
- a collection length is a decision (0 / 1 / many), never a frozen seed.


## 9. Rule S (2026-08-27) — every shim is RUN; there are no waivers

A shim mock stands in for code the concolic run cannot execute. Its claim —
"this body reaches no target function" — is only ever established by
RUNNING the real body and observing it. So:

1. **Every extracted shim must reach verdict PASS**: the real method runs in
   `shim_tests.rb` under the target-call probe with zero target invocations
   AND 100% of its executable lines covered. `WAIVED` is not a passing
   verdict, and neither is a coverage waiver — both are blocking.
2. **If it cannot run as-is, make it runnable with the MINIMAL mocks the
   test needs** — fixture rows, a stubbed collaborator that is itself a
   proven leaf, a provisioned config value, a constructed receiver. Each
   such mock is named and justified in the test, and each is subject to the
   same scrutiny as any other mock: it must not stand over app logic that
   could reach a target, or it has merely moved the problem.
3. **Prose is not evidence.** A reason may accompany a test; it may never
   replace one.
4. **Not everything the extractor lists is a shim over application code.**
   The exclusion is decided at RUNTIME from the real class, never from
   prose: a stub is the runtime's own rep machinery (verdict `PROTOCOL`)
   when the real class does not define the method at all, or defines it
   only through the ActiveRecord / Ruby object protocol — `read_attribute`,
   `attributes`, `persisted?`, `hash`, `inspect`, a plain column reader, the
   runtime's introspection accessors. Anything with a body of its own — an
   app method (`Profile#image_url`, `post_location`), a gem method we stand
   in for (`authenticatable_salt`), a Rails dispatch, an association read —
   is a shim and must be RUN. `PASS` and `PROTOCOL` are the only
   non-blocking verdicts. Where the receiver is a local whose class cannot be
   resolved statically, a batch may state the fact — `{ real_class: "Comment" }`
   — and the runner CHECKS it against the real class (verdict `PROTOCOL` if
   that class defines the method only through the protocol,
   `FAIL-NOT-PROTOCOL` if it has a body of its own). A stated fact that the
   code contradicts is a failure, not a waiver.
5. **A dispatch or naming layer declares what it reaches.** A byte-faithful
   prepend or a `loaded?`-branch dispatcher cannot reach zero targets —
   reaching the declared target IS its job. Its test declares `reaches:` and
   the runner tests EQUALITY: it reaches exactly those targets and nothing
   else, at 100% line coverage, plus (for a prepend) byte-faithfulness of
   the body against the shadowed original. The true claim is tested; the bar
   is not waived.
6. **A measurement limit is answered with a stronger claim, never a waiver.**
   JRuby's Coverage attributes a multi-line literal (a presenter's `as_json`
   hash, an array literal) to its FIRST line and reports 0 for the
   continuation lines, so line coverage understates a body that in fact ran
   completely. The runner therefore accepts a body that is STRAIGHT-LINE —
   no conditional, loop, block-iterator, rescue, ternary or short-circuit
   operator anywhere in its range — when its entry line executed: such a
   body cannot be partially executed. Any branch at all keeps the 100% bar.
   (`CommentPresenter#as_json`, comments_index 2026-08-28: 28.6% reported,
   all six keys demonstrably produced.)
7. **An unmeasurable instrument is replaced, not waived.** ActiveRecord
   builds association and attribute readers with
   `mixin.class_eval <<-CODE, __FILE__, __LINE__+1`, so their
   `source_location` points into the BUILDER TEMPLATE and line coverage is
   structurally 0% for every such method in every batch. For a GENERATED
   method (its source_location line does not contain a `def`), the runner
   drops the coverage bar and observes what is measurable instead: that the
   method actually RAN, via a TracePoint during the fixture. The target
   claim (zero targets, or `reaches:` equality) is unchanged.
   (`k.conversation_visibilities`, conversations_index 2026-08-28.)
8. **A stub over a body that ISSUES A QUERY is not a shim at all** — it is a
   target, and belongs in the shared boundary (Rule T). `ActiveRecord::Base#reload`
   is `self.class.unscoped { find(id) }`: data access, found while applying
   this rule (conversations_index, 2026-08-27).

Why: on the first three endpoints the engine accepted 25/29, 32/33 and
similar waiver ratios, i.e. four shims proven and the rest asserted. A
verdict a batch can grant itself is not a check, and it is exactly the kind
of unverified decision the adversary has repeatedly turned into a finding.


## 10. Rule V (2026-08-28) — a value parsed out of a column is a PARAMETER

The fold binds `$(VAR)` by taking the longest underscore-delimited suffix of
the variable name that is a real column of the producing row. A value that
was *parsed out of* a column — a handle or a guid lifted from a message's
`text` — has no producing column, so that matcher silently binds it to
whatever column its NAME happens to end with, and the extracted view then
asserts a join the application never performs
(`…_row_text_dlink_guid` → `posts.guid = messages.guid`, 3 176 occurrences
in conversations_index; found by comments_index while fixing its own
UNRESOLVABLE binds, 2026-08-28).

So: **mint any value derived from the CONTENT of a column in the
`SYM_PARAM_*` family** (or with no SQL note), so the fold renders a policy
parameter rather than a column bind. Prefer a producer link only where a
real column produces the value.

`bind_resolution_audit` now reports these separately as **DERIVED-MISBOUND**
and fails on them; a green audit that only counted UNRESOLVABLE could not
tell "resolved correctly" from "resolved to whatever column the name ends
with".


## 11. Rule G (2026-08-28) — the gate list and the pin ledger must agree

`pc_visibility_audit --gate <cols>` asserts "the app provably compares these
columns, so each must be PC-visible". When a column becomes a PIN (its state
proved unreachable, or its value fixed with a ledger entry), it must leave
the gate list IN THE SAME CHANGE, and the ledger entry is what licenses the
removal. A pinned column left in the gate list reads as a blind branch
(comments_index 2026-08-28: `persisted` pinned by the D3 fix, still gated,
audit RED); a decision quietly dropped from the gate list without a ledger
entry is how a real branch goes missing. Neither is acceptable: gate list ∪
pin ledger must cover every column the app compares, and the two sets must
be disjoint.


## 12. Instrument notes (2026-08-28 →)

**2026-08-29, from conversations_index's cycle:**
- `[value, sort]` is a DECLARATION form, not any 2-element Array: since the
  0/1/many cardinality rule (B-7) a mock returning two rows was being read
  as a value plus a sort and silently losing the second row. The interceptor
  now requires the second element to name a sort.
- `bind_resolution_audit` used to degrade quietly to a name-level fallback
  without the `queries_from_runs` venv and false-RED every `SYM_PARAM_*`
  bind (14 852 in one run). It now FAILS LOUDLY (exit 2) instead: an audit
  that cannot do its job must say so, never guess. Same class as pointing
  `--patched` at `variant_e`.
- `note_fidelity_audit` did not apply the alias map when SELECTING which
  notes to compare, so a correctly-noted nested finder scored PRED-OP-DIFF
  against a note byte-identical to the real statement (108 events). The map
  is now used in both directions.
- `hardening_lint` H6 compared a 30-character RAW prefix, so identifier
  quoting alone produced a false over-emission CHECK; it now compares
  normalized shapes.
- **A dump count is not a corpus.** conversations_index carried 60 078 dumps
  of which 41 753 were exact duplicates (same variant, path, note multiset,
  seeds and scenario); deduplicating cut the coverage pass from an OOM kill
  at ~1 961 MB to a 673 MB peak. Deduplicate before concluding anything from
  size, and judge a coverage pass by its own `COMPLETE=` verdict — never by
  a summary file a crashed pass never wrote.


- **The projection judge now compares `=` vs `IN`, `LIMIT` and `ORDER BY`.**
  The shape normalizer wildcards literals and binds, which also erased three
  of Rule T4's own requirements: a single-row read noted as a bulk `IN (…)`,
  or a note missing the real `LIMIT 1`/ordering, scored EXACT. New verdicts
  in `tools/note_fidelity_audit.py`: `PRED-OP-DIFF`, `LIMIT-DIFF`,
  `ORDER-DIFF`, all failing. Found by the comments_index adversary, round 4.
- **The `fix_profile` → Discovery JVM abort is diagnosed and is not I/O.**
  `Faraday.default_adapter == :typhoeus` → Ethon → libcurl through JRuby's
  JFFI; `Discovery.new` is innocent (it returns for loopback and even
  domain-less handles), and the JVM dies on the first `HttpClient.get`, with
  `com.kenai.jffi.CallContextCache` as the last JIT events and glibc heap
  corruption in the sibling processes — which is why a nil domain aborts
  identically. Consequence, stated rather than hidden: `reload` (B-1) and
  every `profile_not_found == True` arm are unreachable-by-real-run on all
  three batches, so their corpus modelling is verified by code reading and
  the concolic corpus only.


## 13. Rule D (2026-08-29) — derive what is determined; decide only what is free

Three of the four defects found in the cycle that introduced the
distinct-key preload model were the same mistake: **a quantity the data
already determines was modelled as a free decision.**

- the NESTED preload step's key count is determined by the parents actually
  loaded (a `has_one` is keyed on the parent's primary key, so N parents ⇒
  N distinct keys) — deciding it freely produced `people.id IN (a, b)`
  followed by `profiles.person_id = a`, a pair ActiveRecord cannot emit;
- on a table with a UNIQUE index over the relation's fixed columns
  (`mentions` on `(person_id, container_id, container_type)`) the key count
  IS the row count — deciding it freely asserted `len(rows) > 1` beside a
  single-key read, a state the database rejects with `RecordNotUnique`;
- the same physical row must have ONE variable: binding the outer step to
  `…_row2_author_id` and the nested step to `…_row_author2_id` broke the
  `people.id = comments.author_id` chain for the second row while keeping it
  for the first (pattern §7 again, one fact one variable).

**A BOUND IS NOT A DETERMINATION.** The first misapplication of this rule
came two cycles later: the comments relation's ROW count was derived from
its distinct-AUTHOR count, but `keys <= rows` only bounds it — so the corpus
asserted "one distinct author ⇒ one comment", while ten comments by one
author is trivially real, and `(len(comments) > 1)` vanished from the corpus
entirely (comments_index M-14, 2026-08-29). Derive X from Y only when Y
FIXES X (a primary key, a unique index, the parents actually loaded), never
when Y merely constrains it. Mechanized as the audit's second rule: a list
read in bulk anywhere in the corpus can hold many rows, so its row count
must itself be a recorded decision.

**A WRITE IS CONDITIONAL ON DIRTINESS.** ActiveRecord's partial writes issue
NO statement for an unchanged record — `BEGIN`, the `belongs_to` validation
`SELECT`, `COMMIT`, and no `UPDATE`. A corpus that emits the write on every
`save` asserts a statement the application does not make, and the "no write"
side may have no representation at all (conversations_index C-5,
2026-08-29: the only route to it was a `find_by` returning nil, which a
unique index makes unreachable). Model the changed/unchanged decision.

**AND ONE VARIABLE MUST CARRY ONE FACT, NOT TWO.** The same cycle welded
"the child was not found" to "no nested read happens" on a single variable,
so a partially-loaded list could never hold a nil BESIDE a live row — the
one shape that raises (M-13). Two facts, two variables.

So: before adding a decision, ask what determines the quantity — the loaded
parents, a schema constraint, another decision already recorded. If anything
does, DERIVE it. A free decision over a determined quantity does not add
coverage; it manufactures states the application cannot reach, and every
judge that compares a statement to a note will score them EXACT because the
contradiction is between the run's own decision and its own note.

Mechanized by `queries_from_runs/audits/cardinality_consistency_audit.py`,
which reads a run's cardinality decisions and the key shape of the notes it
emits.

**The rule applies to BULK loaders only** — corrected the same day, on
evidence from conversations_index. A per-owner emitter (`find_target`,
`find_by`, `first`, `count`, `exists?`, `pluck`, `reload`, a row
materialization) issues ONE statement PER ROW, so `= $(row_key)` in a
many-row state is correct: a real five-conversation request issues five
separate `conversation_id = ?` statements and no `IN` at all, and the only
bulk emitter in that corpus scored zero. The first version of the audit
conflated the two and would have demanded exactly the over-emission M-7
forbids; it now flags only a bulk loader emitting a single-key note (and any
`IN` over a single bind, which is always wrong). After the correction:
conversations_index PASSES, comments_index 11 996 events → 25 (the genuine
M-10 nested-step cases), notifications_index 18 670 → 1 068.

**An audit that a batch can refute with evidence is doing its job — and so
is the batch.** The refutation cost one message; chasing it green would have
corrupted a correct corpus.

**Three audits carried false positives that a batch diagnosed for me**
(notifications_index, 2026-08-29 — all three now pass on its unchanged
corpus): `bind_resolution` re-labelled a bind as DERIVED-MISBOUND even when
it had resolved to a REAL column (`photos.status_message_guid`), which would
have pushed the batch to rename the variable and thereby CREATE the Rule V
join; `cardinality_consistency` attributed binds by name prefix, charging a
NESTED list's keys (`…_row_actors_row_id` extends `…_row`) to the outer list,
and counted `type IN ('StatusMessage')` — a literal set — as a bulk key set;
`skipped_pcs` counted `(X != X)` self-compares as dropped, though a tautology
carries no branch and the fold is right to drop it (1 990 of them, produced
by AR's `stale_target?` once Rule D made both sides one fact). It also now
fails distinguishably when run without the venv instead of exiting 1 like a
finding.

**GROUND TRUTH ITSELF CAN UNDER-REPORT — and did, on every batch.** Two rig
bugs deleted statements from the concrete runs that every judge treats as
truth (conversations_index INSTR-1/INSTR-2, 2026-08-29):

- the harness memoised the principal once per PROCESS (`@concrete_user ||=`
  bound to `main`, not to the per-request warden), so every request after
  the first in a manifest lost the Devise `users` read and
  `current_user.person`'s `people.owner_id` read — four requests, ONE
  `users` read, in every concrete run that batch had ever made;
- the shared probe skips `payload[:cached]` statements and nothing cleared
  the AR query cache between requests, so any statement REPEATED by a later
  request vanished. Fixed in `concrete_run_probe.rb`: the cache is cleared
  per scenario, and `CompletionChecker.new_request!` is available for
  manifests that issue several requests in one body. Within-request caching
  is left alone, because a real request caches too.

**Consequence, stated plainly: any earlier conclusion of the form "no
statement can result" may be an artifact of the rig.** Re-derive such claims
on a fixed rig before trusting them — and re-derive them ONE AT A TIME, not
as a class: M-5's one-statement `I18n::InvalidLocale` multiset was
re-measured on the fixed rig and STANDS (`set_locale` raises before
`current_user.person` is touched, so no `people.owner_id` read is issued),
while the invalid-`page` claim from the same batch did NOT (that failure
happens inside the action, after the person has loaded, giving
`{users, people.owner_id}`). A third rig artifact was identified in the same
measurement: the harness's own salt cache issues a `find`-shaped read
(`"id" = ? LIMIT ?`, no ORDER BY, outside any target frame) that is not the
request's — distinguishable because Devise's `serialize_from_session` is a
`first` with `ORDER BY … ASC LIMIT ?`, and because the second request for the
same uid does not repeat it.
A third bug in the same family: fixtures wrote `sharing: 1` where the SQLite
adapter quotes `'t'`, so `Contact.mutual` matched nothing in every concrete
run — `no_contacts` was always true and that partial never rendered.

**`to_sql` inlines booleans; the wire protocol binds them.** H6's shape
normalizer absorbed `?`, digits and quoted strings but left bare
`true`/`false`, so a note over ANY boolean scope condition
(`contacts.sharing = true`, `posts.public = true`) could never match its own
real run — the one inlined type with no rule. Diagnosed by
conversations_index by diffing normalized forms rather than assuming: 2
unmatched shapes → 0 with the rule added, and 23 run statements still map to
23 distinct shapes, so nothing collided. The batch-side alternative — render
booleans as `?` in notes — was offered and correctly NOT taken: it would
have cost a full 31 846-dump regeneration to change how a constant is
DISPLAYED, with no change to the statement described.

**A skipped check reads as a pass.** `hardening_lint`'s H6 does nothing
without `--runs`, and the coordinator's standard sweep never passed it — so
H6 was silently absent from every check run until 2026-08-29. It now
announces the skip, the sweep passes every run file (the batch's concrete
runs AND every adversary round's), and the repeated `--runs a --runs b` form
— which silently kept only the first list and produced twelve convincing
false findings — is refused outright. A batch may declare an answered
over-emission family in `completion_config.json` (`h6_answered`, with a
printed reason), the same auditable mechanism as the pin ledger.
H4 has the same mechanism (`h4_by_construction`, added 2026-08-29) for a
length whose single polarity is fixed by WHAT THE LIST IS rather than by what
was explored — will_paginate's BeyondPageList has 0 rows by definition, so its
`size > 0` can only be False. The reason is printed; an entry that matches no
recorded length is reported as stale. A polarity that is merely unexplored is
never declared — it is seeded.

The same day, `hardening_lint` H3 was sharpened the same way, on evidence
from conversations_index: a target is NOT opaque when (a) one of its notes
declares itself a `WALL` (the target name need not contain a wall word —
`Anonymous.new` is the federation Discovery constructor), or (b) it emits
SQL through NESTED events rather than in its own note (`Base#save` emitted
the `belongs_to` validation SELECTs in 4 660 of 4 660 calls; `to_param`
emitted none in 13 390, so it stays exempt on purity instead). Both signals
were already in the dumps — the check just was not reading them.


## 14. Two failure modes a batch found in the CHECKING system itself (2026-08-29)

**A batch's own prose became an audit's evidence.** `format_coverage_audit`
reported `js TEMPLATELESS … not required` — on the strength of a sentence the
batch had written in its own `run_dse.rb`. Measurement then showed `.js`
renders the full template: 16 statements, 34 with a selected conversation,
including a write. An audit may read a batch's DECLARATION to know what to
check, never to conclude that the check is unnecessary. Silence from an audit
that cannot see a case is not evidence about that case.

**A pin can suppress a TARGET DECLARATION, not just statements.** The shared
boundary lists `count sum`, but `Calculations#sum` was never declared on
conversations_index: the action never calls it, the LAYOUT does, and the
`layout(false)` rig pin hid the rendering path. An undeclared family issues
NOTHING into the corpus — so no note is wrong, no statement mismatches, and
every statement-level judge stays green. Mechanized as
`tools/boundary_declaration_audit.py`, which compares each batch's
`declare_target` calls against the boundary families and requires an absence
to be a stated pin with a ledger entry rather than an oversight. (All three
batches pass it today; it exists so the next omission is caught by a check
rather than by an adversary two weeks later.)

**No judge sees STATEMENT MULTIPLICITY.** On conversations_index the
visibilities `COUNT` was emitted TWICE in every html/mobile dump (2,575 of
2,575 sampled) where every real request issues it once — a guard counts, then
will_paginate's loaded shortcut should not, but the rig's relation never said
`loaded?`. `note_fidelity` and `statement_diff` compare the SET of statement
shapes, so two of the same shape look identical to one. It surfaced only
because the two `.js` variants stopped agreeing with the other eight — a
corpus under two models is not one corpus. Until a per-request multiplicity
check exists, a batch's concrete comparison must compare statement COUNTS per
shape, not just presence. (Recorded 2026-08-29, conversations C13 A3-10.)

**A scenario list copied into consumers goes stale silently.** conversations
C13 added four format scenarios in `run_dse.rb`; five consumers
(`coverage_assumptions.py`, both hand-seeders, `demand_round.py`,
`_dedup_scan.py`) carried a private six-variant tuple. Effects: the seeder
attributed every new-scenario dump to `None` and wrote no seeds (62 of 63
targets never seeded, the chain would have burned all its rounds), and the
assumption builder classed js/xml dumps as one `"unknown"` bucket, so
variant-exclusivity independence assumptions treated four request shapes as
one. Rule: a consumer reads `concolic_scenario.name` from the dump — the field
written for that purpose — never a copied list. Every batch must grep its own
tree for a variant tuple before its next coverage pass. (2026-08-29, A3-12.)

**A solver model is evidence about the CONSTRAINED variables only.** Z3 assigns
every unconstrained variable a default (0). Two batches independently overlaid
the full model onto a seed and foreclosed the very decisions being demanded:
notifications (`_demand_root.py`, list lengths zeroed, 478 → 478 for two
rounds) and conversations (`mk_hand_seeds2.py`, `to_a_1_rows: 0` emptied the
inbox so the target clique was never reached; 27 roots → 0 recordings). Rule:
seed from a real dump that reaches the target's prefix and overlay ONLY the
variables named in the target's exprs. And test a seeder by replaying its roots
alone under `SEEDS_ONLY` — a DSE round hides a dead root behind its expansion.
(2026-08-29, notifications PAUSED.md; conversations A3-13.)

**Both statement judges compared SELECTs only (INSTR-7).** `mock_note_check`
and `note_fidelity_audit` filtered real statements and corpus notes to
`SELECT`, so a real run carrying four `UPDATE "users"` scored EXIT=0 / 18
EXACT. Found by conversations adversary R4 (2026-08-30) alongside C-10: every
rig on every batch built the principal on a stub `Object` rather than a real
`Warden::Proxy`, so Devise's `after_set_user` hooks (`devise_lastseenable`'s
`last_seen` UPDATE on every signed-in request; the lockable logout) never
ran and no corpus contains them. Both judges now treat any DML as a data
access. Rule: a rig's principal is a REAL warden (`Devise.warden_config`),
and a judge that filters by statement kind must say so in its header.

**Multiplicity scope (decided 2026-08-30, conversations cycle 16).** The
count-based multiplicity check compares per-REQUEST shapes — boundary,
layout, badge counts, finders — and must match ground truth exactly. Per-ROW
shapes inside a `SampledList` (one representative row is rendered where the
app renders N) are a known, designed under-count of the shared runtime, not a
batch defect: the policy is a SET of statement shapes and a second identical
row adds no shape. Record the ceiling per endpoint; do not grow the list
model to chase it. `hardening_lint` H3/H6 now treat any DML as a data access
(the INSTR-7 class inside the lint's helper).

**Coverage is a claim about DECISIONS; statements are a separate claim.**
Conversations cycle 21: a repair cast symbolic finder binds through
`value_for_database`; the runtime refused `to_i` on a symbolic value and every
scalar-cid run died with `NotImplementedError` AFTER recording its cid
decision. Coverage read `complete` at 117 nodes while the corpus held no
scalar or `IN (?, ?)` conversations read; only the per-request count check
saw it (real ×1 / corpus ×0). Two rules: (1) a run that crashes in the rig's
own code is a wrong recording, never evidence — `tools/rig_crash_census.py`
runs after every model change and in the coordinator's sweep, and fails on any
rig-class terminal; (2) the count-based multiplicity check is a closing check
in its own right, not a courtesy — a corpus can be complete on decisions and
empty on statements. (2026-08-30, A6-7.)

**A request-level parameter decision is never structurally independent.**
Tier-2 "disjoint reps" independence (decisions on two different reps, neither
gating the other) was refuted four times on conversations by the engine's
flip-both probe: page×list (A4-8), the `'0.0.0.0'` IP arm×first-login (A5-9),
`cid_out_of_range`×`page_beyond` and `via_cookie`×`last_seen_stale` (A6-8).
A `SYM_PARAM_*` arm terminates the request (out-of-range cid after three
statements, an expired cookie after one) or changes the ORDER of a later write
(cookie ∧ stale is C-16's second-save order). Rule (cycle 21d): tier 2 never
pairs two decisions of the BOUNDARY FAMILY — request-level `SYM_PARAM_*` arms
and the principal rep's decisions — with each other; those combinations are
the coverage checker's to demand. A request-level × CONTENT pair (a parameter
arm vs a row/list decision of the render) stays a declared assumption
because the gate's flip-both probe tests each one individually (1,311 on
conversations, all PASS); withdrawing them on the variable's NAME fused the
boundary into the content cliques and enumerated combinations no statement
depends on. A refuted assumption is withdrawn at the class it belongs to,
never re-declared narrower; a class is defined by what the refutations
share, not by a prefix.

## 15. Entrypoint scope ruling (Bali, 2026-08-31)

The ENDPOINT ENTRYPOINT is the controller action POST-AUTHENTICATION, with
the principal symbolic. The authentication stages run above the entrypoint
and are modelled ONCE, app-wide, as the shared auth-boundary policy
(`results3/_auth_boundary/BOUNDARY_POLICY.md`) — their queries (principal
resolution, trackable/lastseenable/rememberable/lockable writes, their
constraint structure) are unioned into every endpoint's final policy at
extraction, never re-derived per endpoint. The adversary attacks the same
post-auth entrypoint with a concrete principal instantiation consistent with
the symbolic declaration; an auth-stage statement is a boundary-policy
finding, not an endpoint win. Rounds 4–6 of conversations paid for this
boundary evidence once; no other endpoint pays again.

§15 addendum (Bali): the adversary's post-verification of every claimed win
must include an ENTRYPOINT CHECK — trace evidence that the novel statement
was issued from inside the declared entrypoint invocation itself (post-auth
action frame, principal concretely instantiated within its symbolic
declaration). The coordinator rejects a win whose writeup lacks that
evidence; statements from above the entrypoint go to the boundary policy.

**A judge that ignores the evidence you hand it prints a green about nothing.**
`_multiset_counts.py` accepted run files only after `--runs`; positional files
were silently dropped and the batch's own concrete runs re-judged instead —
so the coordinator's independent check of the R7 adversary runs returned
"pass" twice while the same judge, invoked correctly, returned RED (1 under,
2 over). Rule: every checker names the evidence it read in its own output
(`judging runs: …`), and an unrecognised argument is an error, never a
silent fallback. (2026-09-01, conversations R7.)

**Presence is a GLOBAL question; multiplicity is a scoped one.** The R7
multiset judge scoped both under- and over-emission by request class (layout
vs plain), so an html request that 500s before the layout reads was filed
`plain`, whose max for the `contacts.mutual` probe is 0 — and the judge
reported a MISSING shape that the corpus carries 6,120 times (once per html
dump, note faithful, decision explored both ways). Rule: "can the corpus
produce this shape at all" is answered against the whole corpus; only
over-emission compares like with like, and a class with no ground-truth
request is SKIPPED, never given a verdict inferred from the gap. Escalate a
red, but demand the census before treating it as a defect — and a rebuttal
with a corpus census outranks a judge's verdict. (2026-09-01, A7-8.)

**A check that tests a DIFFERENT QUANTITY than the one its own rule names.**
`cardinality_consistency_audit` said, in its docstring and again in its RULE 2
comment, that "the predicate follows the KEY set" and that "ten comments by one
author is trivially real" — and then tested `len(rows) > 1`, the ROW count. On
comments_index cycle 10 it scored 13 460 dumps RED for emitting exactly what
ActiveRecord emits, contradicting matrix row T-o (`M-7`), which the same
endpoint had already applied and an adversary had verified. Two lessons, and
the second is the expensive one: (a) when a check and an established rule
disagree, the check is a suspect, not an authority — re-read what it MEASURES,
not what it SAYS; (b) a batch under a red is the worst-placed party to argue
the check is wrong, so it must bring evidence a third party can re-derive.
This one did: an escape census over its own corpus with `unexplained: 0`, which
the coordinator then reproduced from an independent implementation before
touching the shared file. **A red you cannot explain is a defect; a red you can
explain event-for-event is a hypothesis about the checker — and it still needs
someone other than the accused to confirm it.** (2026-09-01, comments C10.)

**When you widen a check, name the seam you opened and hand it to the
adversary.** The fix above makes the audit TRUST a recorded `keys_many`.
Whether that decision was legitimately FREE — rather than determined by a
unique index (M-11/T-r) or by the parents actually loaded (M-10/T-q) — is Rule
D's question, policed by `hardening_lint` H4 per relation. Neither check covers
that class alone, so neither may be closed by citing the other. Every escape
the audit takes is now COUNTED AND PRINTED (11 366 by key-count decision, 2 094
by a sibling's missing parent): an escape that fires silently turns a green
into a statement about nothing. The widening also ships with a synthetic
self-test pinning BOTH directions — `tools/cardinality_audit_selftest.py`,
four dumps: escape fires where AR really emits `=` (key decided one; sibling
parent missing), audit still REDs where it does not (key decided many; no key
decision recorded at all). **A loosened check without a test that still fails
is indistinguishable from a deleted check.**

**A census of a field the rig never writes proves nothing.**
`rig_crash_census` read `dump["error"]`; comments_index's rig records
application terminals in `dump["concolic_terminal"]` and reserves `error` for
unexpected ones. The census printed 20 879 × `<ok>` and a green RESULT over a
field that is empty by construction — the same shape as the `_multiset_counts`
silent-fallback false pass, and it had already been counted as one of the
coordinator's own closing checks. Fixed to read either field and to unroll the
cause chain (`ActionView::Template::Error<-NoMethodError`), it finds 8 terminal
classes on this corpus, all application terminals. Conversations' rig writes
`error`, so ITS census was real and its closure stands — verified rather than
assumed. Rule: **a check that can pass without reading anything must say how
many records it actually examined, and a per-batch field convention is exactly
the kind of thing a shared tool must not hardcode.** (2026-09-01, comments C10.)

**A green must state its POPULATION; a pass over zero is vacuous.**
`cardinality_consistency_audit` passed on conversations_index and was counted
as one of the eleven checks in its closure. It had judged **nothing**: that
corpus contains no bulk loader reading a list's own rows (its `load_intermediate`
calls key on a finder result, and its list rows are read one statement per row,
which the audit deliberately excludes). The absence is faithful to the app —
the multiset matrix and note fidelity confirm the real endpoint issues those
per-row statements — so this retracts no verdict; but "the audit passed" was
never evidence there, and nobody could see that from its output. The audit now
prints the number of (note, list) pairs its rule could speak about and reports
`pass but VACUOUS` at zero. **Extend the habit: every check should say what it
examined, so a green over an empty population is legible as the non-event it
is.** (2026-09-01, coordinator, found while reconciling comments C10.)

**A metric that does not measure what its label says is worse than no metric.**
The first version of that population counter incremented for every note binding
a list's rows, regardless of emitter kind or row-count decision, and reported
**936 546** on the corpus whose true population is **0** — it would have hidden
the very vacuity it was written to expose, behind a large confident number.
Same shape, same day, in the escape accounting: the pre-existing `partial`
escape was reported as firing on 44 385 events, but only **2 262** of those lay
inside the rule's population; the rest were suppressions of pairs the rule never
judges. Both were caught by asking the dull question — *does this number count
the thing its sentence claims?* — against an independent measurement of the same
quantity. **Whenever you add a counter to a checker, derive the same number a
second way before you quote it.** (2026-09-01, coordinator.)

**§12 amendment (2026-09-01, adversary R8 / M-15) — a JVM abort is a property
of a PATH, not of a call site.** §12 recorded that the typhoeus → Ethon →
libcurl FFI call aborts JRuby, and that was generalised into "every path
through `Discovery#fetch_and_save` is unreachable, so every
`profile_not_found == True` arm behind it is unreachable too". That
generalisation is false. Faraday parses the webfinger URL with `URI.parse`
BEFORE the adapter runs, so a fixture `people.diaspora_handle` whose domain is
not a legal URI host (`wraith@ba[d.example`) raises `URI::InvalidURIError` in
pure Ruby and returns a `DiscoveryError`: **31 depth-0 `fix_profile` calls, 31
`fetch_and_save` calls, 0 JVM aborts**, while the same probe with a parseable
URL still aborts. The arms behind that wall are reachable on comments_index
(author tree 19×, mention tree 12×) and must be modelled, not walled.

Rule: **an unreachability argument must name the exact step that stops
execution and show that every input reaches it.** "The library aborts" is not
that argument — a library that validates before it calls out has a pure-Ruby
failure path, and a fixture value is usually enough to take it. Any pin,
waiver or wall resting on an abort is suspect until someone has tried to reach
the code with an input the abort cannot see. This one had survived seven
adversary rounds.

**Validate a new check on a corpus where the property is known to HOLD before
you trust it — and be willing to throw it away.** T-c's unchecked half (a
preload and a `find_target` must share one predicate rather than mint two) got
the obvious formulation: same `(table, column)` in one run ⇒ same bind
variable. It scored 1 137/1 137 on comments_index, where the row is applied —
and flagged **2 225 of 2 497** on conversations_index, where the flags are
false: two reads of `profiles.person_id` for DIFFERENT owners (the principal's
profile via `find_target`, a participant's via the preload) correctly bind
different variables. The rule is about ONE owner read twice; a note carries no
owner identity, so the quantity the check needs is not in the evidence at all.
The check was discarded rather than shipped with an exclusion list — an
exclusion list here would have been a way of hiding that the check cannot
express its own rule. **A checker that is green where the property holds and
red where it does not has to be understood before it is believed; one that
cannot see the quantity its rule is about should not exist.** Better an
acknowledged gap in the table than a check that manufactures work and false
confidence. (2026-09-01, coordinator.)

**§14 addendum — M-18: know what your ground truth is a measurement OF.**
Every rig in this project dispatches through `ActionController::TestCase#process`,
which never runs `ActionDispatch::Executor` — and Rails installs ActiveRecord's
query cache as an executor hook. Same manifest, same fixtures, same request:
plain dispatch **16 statements / 0 cached**; inside
`Rails.application.executor.wrap` **16 / 8 cached**. `ActionDispatch::Executor`
is in this app's middleware stack, so a real Rack request puts 8 of those
statements on the database and our harness puts 16. Every per-request
multiplicity this project has measured — corpus AND concrete-run ground truth —
is therefore a measurement of an unwrapped dispatch, not of production.

**Blast radius, measured rather than assumed (2026-09-01, coordinator).** The
dangerous consequence would be a corpus modelling the same read as returning
DIFFERENT results on its second issue, a state query caching makes impossible.
Comparing notes by EXACT text (same SQL, same bind variables) across both closed
and open corpora: conversations 6 757 repeated reads, comments 32 053 — and
**0 with disagreeing length decisions in either**. So the corpora over-state a
real request's database traffic and never fabricate an impossible state.
Consequences: shape PRESENCE, which is what an access-control policy asserts, is
untouched (caching removes duplicates, it never adds a shape); multiplicity
claims are an upper bound; and a "0 under / 0 over" matrix verdict means the
corpus matches OUR HARNESS, not that it matches production statement counts.
That is a weaker claim than the phrase suggests, and it must be written that way
wherever it is quoted.

**Method note, twice in one day.** Both times this was investigated, the first
measurement was wrong in the SAME way: notes were compared with binds normalised
to `@`, which fuses two different owners' reads into one "repeat" and
manufactured 147 conversations / 840 comments false contradictions. The earlier
T-c check died of the identical fault. **When comparing statements, bind
identity is part of the statement**; normalise only when the question is
explicitly about shape rather than about a specific read. A measurement that
reports a defect should be re-derived a second way before it is escalated —
and a measurement that reports ZERO should be checked for reading a field that
exists at all (the first pass here keyed on `result_var`, which no dump has, and
confidently reported 0 repeats out of 6 000 dumps).

**Dump-schema gotcha: `call` and `symbolic_call` both carry a `target`; only
`symbolic_call` can carry a note.** A census that greps `target` without
filtering on `event["type"]` over-counts a target family by roughly 2× and,
worse, reads the trace events' missing notes as evidence ABOUT THE NOTE
CHANNEL. That is how comments_index cycle 12 produced "4 657 discovery events,
every one with an empty note, therefore `pending_note` is a no-op" — an
invented defect, entered into a limits list, from a census whose population was
the wrong kind of event. Filtered by type the same corpora read: current 0
`symbolic_call` discovery events (4 657 bare `call` traces), archive cycle-11
7 972 `symbolic_call` events **all noted** — the direct refutation.

Two rules, and the second is the one that keeps costing this project time:
- **filter on event type in every census**, and say which type you counted;
- **an invented defect in a limits list is worse than an omitted real one** — a
  later reader chases it, or "fixes" working code on its authority. Withdraw it
  where it was published, and leave the retraction in place of the claim so a
  reader meets the correction rather than the error.

Adjacent, same day, coordinator: a census over `sorted(glob(...))[:8000]` is
biased by FILENAME — comments' dumps sort `dump_anon_*` before `dump_auth_*`,
so an 8 000-dump "sample" of a 26 528-dump corpus was almost purely anonymous
and its zero was a fact about anon scenarios, not about the corpus. **State the
population of every census in the sentence that reports its number.** Five
distinct measurement failures happened in this project on 2026-09-01 — a
counter measuring the wrong quantity, a checker fusing different owners' reads
(twice), a census on the wrong event type, and a sampled census reported as a
total. Every one produced a confident number about a population nobody had
checked.

**§14 — INSTR-9: a second request in the same process under-reports its shapes,
and `executor.wrap` does NOT fix it.** notifications_index C7 (2026-09-01)
measured, with scenario ORDER as the only variable: whichever html scenario runs
FIRST in a process records 27 shapes; whichever runs SECOND records 23 —
wrapped or not. The four "lost" shapes (`aspect_memberships` by contact_id,
`aspects` by id, `blocks`, `tags ⋈ taggings`) are a SCENARIO-ORDER artifact, not
an executor effect. Something is memoized at a level `Rails.application.executor`
does not reset. Same class as INSTR-1, one level up.

**Why this is dangerous rather than merely untidy:** the rig drives requests the
same way the ground-truth probe does, so BOTH can be blind in the same way — and
then they agree, and every judge is green. That is the layout-pin lesson exactly
(*parity between a rig and its own ground truth is a tautology, not evidence*),
reached by a different route.

**Rule: ground truth is ONE REQUEST PER PROCESS**, or the second request's
shapes are silently missing.

**Exposure on the closed endpoints, measured 2026-09-01:**
- **conversations_index is exposed.** Its auth scenario drives **12 requests in
  one process** (4 variants sharing it) and its mobile scenario 3. Later requests
  are NOT subsets — req3 contributes +7 new shapes, req6 +6, req9 +6 — so the
  union (28 shapes) exceeds req1 alone (19), and **9 shapes appear only after
  req1**. Whether any shape is MISSING from that union cannot be settled from the
  recorded data, because each later request is a different variant. The decisive
  test is the one notifications ran: re-drive a scenario one-request-per-process
  and diff the shape set.
- **comments_index is largely isolated:** 37 scenarios, mostly one request each
  (0–1 principal fetches). Only `comments-auth-visibility-chain` (3 requests) and
  the mobile session-switch scenario carry the exposure.

**DECISIVE EVIDENCE (notifications C7, ground truth rebuilt one-request-per-
process, 2026-09-01):** 14 processes, 14 scenarios, 334 statements, **38
distinct shapes in the union** — against the old multi-request ground truth's
249 statements. The contamination is visible per process, and it is severe:

```
auth req0  42 statements / 27 shapes    <- the rich one
     req1  23 / 19
     req2  21 / 15
     req3  11 / 10
```

**The FIRST request of each process is the rich one, and every later request in
that process is progressively poorer.** This is not a subtle bias; a fourth
request records roughly a third of the first's shapes. Any ground truth built
from later requests is measuring an application that has already memoised state
the executor does not reset.

**QUEUED, NOT ASSUMED:** the one-request-per-process re-drive for conversations'
auth and mobile scenarios, to run when the box is free. Until it runs,
conversations' "0 under-emission" verdict carries this caveat — its policy is
extracted from the CORPUS, so a shape both sides missed would be absent from
both without any judge objecting.

**Why the population rule works: it makes a wrong number DETECTABLE.**
notifications C7 (2026-09-01) reported the discovery gap as "new-person branch
17 statements (8 SELECT, 3 INSERT…), existing-person 27" — both RAW totals,
labelled as application counts. The coordinator required the header to state
its exclusion rule (adapter `PRAGMA`/`sqlite_master` introspection is not
application data access, raw counts in the evidence JSON). **To write "4 of 27"
the agent had to compute the split, and computing it exposed the mislabelling.**
Corrected: new-person 17 raw / **13 application** / 4 excluded; existing-person
27 raw / **10 application** / **17 excluded** — the second branch is mostly
introspection, not 8 SELECTs as first reported.

The agent's own summary is the rule in its strongest form: *the requirement to
state a number's population is what made the number wrong-detectable — I would
have shipped the mislabelled counts if the exclusion had been allowed to live
in my head.* This is the sixth measurement failure of the day and the first
caught by the documentation requirement rather than by a re-derivation. **Make
the checker/agent WRITE the population and the exclusion rule into the artifact,
not merely apply them** — a rule applied silently cannot catch the number it
was applied to.

**Independent corroboration, unplanned:** comments_index measured the SAME app
callback on different fixtures and recorded "new-person branch: 17 statements,
13 of them data access" — identical to notifications' corrected split, and both
existing-person branches failed the same way (`owner_xor_pod`:
"Specify an owner or a pod, not both", then ROLLBACK). Two agents, two batches,
two fixture sets, one number. That is the strongest form of confirmation this
project generates, and it only became visible once both were counted the same
way.

## 16. Combination coverage is CO-EVALUATION coverage (decided 2026-09-10)

**Decision record, superseding the combination-coverage decision of
2026-08-18.** What `complete: true` means changed; §16a says what that does to
the closed endpoints.

### The rule

> A combination demand exists **only over decisions that some run evaluated
> together**. The demand universe is the **maximal observed evaluation sets** —
> for each run, the set of decisions its path evaluated; keep the maximal ones.
> For each such set, every Z3-satisfiable outcome assignment must be observed
> in one run's executed path.

An `IndependenceAssumption` **projects** a set: inside a set that holds both
declared-independent expressions the edge is cut and the set is replaced by the
maximal cliques of the induced graph. A declaration over a pair no run
co-evaluates is **inert** — there was never a demand to relax.
`UntrackedPath` still removes the expression from the universe *before* the
sets are formed; `OneSideUntracked` still pins a side *inside* every set that
holds the expression. Neither behaviour changed.

### Why the old rule was wrong

The 2026-08-18 rule started the dependence graph COMPLETE — every pair of
expressions dependent unless declared otherwise — and demanded every
satisfiable assignment of every maximal clique. A complete graph connects
decisions that never share a path, and Bron–Kerbosch over pairwise edges then
manufactures SETS no run walked: A–B, B–C and A–C each observed makes the
triangle {A,B,C} a clique even when no execution ever evaluated all three.
Such a set can never acquire a blocking clause (the engine only blocks on a run
that evaluated the WHOLE set), so every one of its assignments is missing
forever, at any corpus size. On notifications_index, **330 of 1 277 maximal
cliques were evaluated whole by NO run** and the uncovered fraction sat at
~97 % under three different alias keyings — re-keying moved the size of the
target, never the reach of the driving. The tree semantics the checker started
from never demanded those combinations: no tree node evaluates two decisions on
different branches. The complete graph was an artefact of the representation.

### The precondition — and it is REPORTED, not assumed

Co-evaluation demand is sound only over a **complete tree layer**: every
tracked expression observed with every satisfiable outcome. An unexplored
branch outcome may be the very gate that would put two decisions on one path,
so without it "never seen together" is not evidence of "cannot occur
together". `CoverageResult` therefore carries `tree_complete` and
`tree_missing` (`"<expr> :: <side>"` per satisfiable, never-observed side); a
non-empty `tree_missing` **REFUSES the combination claim** — `complete` is
False and the reason is printed in `summary()`.

The precondition is a NAMED consequence, not a second gate: if an outcome is
satisfiable under the shared constraints it extends to a satisfiable assignment
of any set containing it, so an unobserved satisfiable side always also shows
up as a missing combination. The flag exists so a refusal is legible in the
report instead of being left for the reader to infer. Under it, completeness is
a **fixed point**: every gate that would co-locate two decisions has itself
been taken both ways, so any feasible co-evaluation has been realised.

**The honest blind spots** (all pre-existing, but this rule widens what they
hide): an `UntrackedPathAssumption` removes a decision from the universe, so a
co-evaluation that ONLY an untracked decision gates is never demanded — under
the old rule untracking hid a branch, under this one it can also hide a
combination. The same holds for the untracked side of a `OneSideUntracked` and
for an expression the solver cannot parse (`unevaluable_exprs`). **Untrack a
GATE only when its arms are genuinely interchangeable.**

### Mutability

The graph is a function of the corpus and is rebuilt every pass. Under this
rule a new run can ADD demand, by showing two decisions can be evaluated
together. Demand is **monotone**: co-evaluation is an existential over runs, so
once two decisions have been seen together they stay together and no run can
retract a demand. Subset dedup can make a demand set disappear from the
reported list when a later run evaluates a strict superset — that never
weakens the demand, because covering every satisfiable assignment of a superset
implies covering every satisfiable assignment of each subset. A previously
declared independence over a pair that only later co-evaluates starts CUTTING
at that point; it is inert until the corpus produces the pair, and the
assumption gate then has a snapshot to probe it on — an unsound declaration
becomes falsifiable exactly when it starts to matter. W-E still WITHDRAWS a
declared independence on a co-evaluated length pair; nothing about withdrawal
changed.

### Pairwise edges are not sets

Pairwise co-evaluation + clique search reproduces the artefact (the triangle
above). The demand universe is therefore the observed SETS, not the pairs. The
clique search survives only as the projection of a declared independence
INSIDE one observed set, where it can no longer blow up — one run's decisions
bound it.

### §16a — the closed endpoints are NOT voided

`comments_index`, `conversations_index` and `people_show` closed under the
2026-08-18 rule. **Old-complete implies new-complete, and on an old-complete
corpus the two demand universes are IDENTICAL.** The argument, in four steps:

1. Every demand set is a clique of the dependence graph (its adjacency is
   induced from that graph), hence contained in a maximal clique of it.
2. Old-complete means every maximal clique had all its satisfiable assignments
   observed. An assignment is only ever observed by a run that evaluated the
   WHOLE clique, so every maximal clique with at least one satisfiable
   assignment is contained in some run's evaluation set.
3. A maximal clique of the whole graph that is contained in an evaluation set
   is also a maximal clique of that set's induced graph — so every old maximal
   clique IS a demand set, and every other demand set is a subset of one and is
   dropped by the subset dedup.
4. Same sets, same pins, same blocking clauses, same solver ⇒ same verdict.

**Verified, not just argued** (2026-09-10, read-only re-check under the new
engine with each endpoint's UNCHANGED `coverage_assumptions.py`):
comments_index 84 nodes / 85 demand sets / 0 missing / complete / tree_complete;
conversations_index 105 / 83 / 0 / complete / tree_complete; people_show
97 / 239 / 0 / complete / tree_complete. Their `coverage_summary.json` files
were not touched.

The one place where new-complete does NOT follow from old-complete is a
`OneSideUntracked` pin on an expression that some run evaluated APART from a
decision it was cliqued with: the old rule let that pin suppress a branch
demand on a path where the pinned decision was never evaluated at all, and the
new rule demands it. That divergence can only arise when step 2 fails — i.e.
when the corpus was NOT old-complete — so it does not touch a closed endpoint.
It is a strictly-more-correct demand, not a regression.

**And a warning against over-claiming it.** On notifications_index the new rule
moved the uncovered fraction from 97.44 % to 97.15 % — the 330 never-jointly-
evaluated cliques were real but held only 10.9 % of the satisfiable mass and
were overwhelmingly NARROW (191 of width 5). The complete-graph default was an
artefact worth removing, and removing it makes the residual ACTIONABLE (every
remaining assignment is now over a set some run walked, so it is a driving
problem rather than possibly-unreachable), but it was not that endpoint's
blocker. Do not quote this decision as a coverage improvement.

Rule T is therefore NOT triggered by this change: no closed endpoint has to be
re-driven or re-argued. What DOES change for every endpoint is the meaning of a
`complete: true` it earns from now on — it is now conditional on
`tree_complete`, and it no longer includes combinations of decisions that no
execution can make together.

### §16b — the demand is per ASSIGNMENT, not per SET (decided 2026-09-10)

**Decision record, refining §16 the same day.** §16 restricted the demand to
decisions some run evaluated TOGETHER. §16b applies the identical principle one
level down, at the granularity where the tree actually lives — the assignment.
It is **not a new assumption kind**: nothing is declared, no `AssumptionSet`
entry exists, and the relation below is INFERRED from the corpus.

#### The rule

> Decision `g` with outcome `o` **FORECLOSES** decision `d` iff **(a)** some run
> evaluated `g` and `d` together, and **(b)** every run in which `g` took `o`
> left `d` unevaluated.
>
> For a demand set `S` the demanded objects are the **leaves of the pruned
> decision tree** over `S`: members are walked in an order that puts a gate
> before what it forecloses; a member the cube has already foreclosed is not
> part of that cube, and the cube ranges over the rest. A leaf is demanded iff
> it is Z3-satisfiable.

Equivalently: a cube is demanded iff no member is assigned while foreclosed by
another assigned member, and every unassigned member is foreclosed by an
assigned one. The demand is strictly nested:

    foreclosure-aware  ⊆  set-level (§16)  ⊆  complete-graph (2026-08-18).

`IndependenceAssumption` still PROJECTS a set exactly as in §16 (the projection
runs first, foreclosure applies inside each projected set); `UntrackedPath` and
`OneSideUntracked` are untouched. An untracked expression is in no set, so it
can neither foreclose nor be foreclosed — the §16 blind-spot warning gains one
more consequence, and untracking a GATE is now even more clearly a decision
about the demand and not only about a branch.

#### Why — the measurement

Co-evaluation is a fact about the SET; it was never a promise that every
assignment over the set is reachable, and the engine's own docstring said so.
On notifications_index the gap became load bearing. Ground-truth differential
over 68 231 dumps: with `row_target_not_found == true` (5 687 runs) the mean
number of gated decisions evaluated per run is **0.00** — zero runs of 5 687;
with it false (67 045 runs) it is **8.18**. The set-level rule demanded the
cross-product of that gate's outcomes with the decisions it enables, and that
product does not exist in the program: 89.6 % of a 542 784-assignment target
was unreachable by construction, and the driving campaign was correctly halted.

Two independence declarations (classes W-C, W-F) would have approximated the
fix and are **withdrawn on flip-both evidence** — correctly: the pairs ARE
dependent where both outcomes are reachable. Independence was the wrong
instrument. The framework needed "dependent, but this product is infeasible",
and that is derivable from the corpus with nothing declared.

#### Soundness — the SAME precondition, not a new one

If `d` were evaluable under `g=o`, some path would show it. That is the
identical argument §16 already rests on, one level down, and it holds at the
same fixed point. **The minimum-evidence question** — how many runs with `g=o`
make "never evaluated" evidence rather than absence — has the answer **ONE, and
only because of tree completeness**: `tree_complete` says every satisfiable
branch outcome has been explored, so "no `g=o` run reaches `d`" cannot be
explained by `g=o` being undriven. Note the rule carries its own floor: (a)+(b)
force `g` to have been observed BOTH ways, so a foreclosure is never read off a
decision the corpus has driven one way only.

**And the honest edge of that argument, which §16b sharpens and does not
remove.** Tree completeness is a per-DECISION claim; it does not by itself say
that a `g=o` path which reaches `d` has been driven. The full argument is the
§16 fixed point — tree claim AND combination claim together — so what is sound
is the TRUE verdict: when the checker says `complete`, the corpus satisfies both
claims and the demand universe it used is the right one. While it says
INCOMPLETE, a foreclosure can in principle hide a gap that more driving would
expose, exactly as §16's "never seen together" can. **The reported missing list
is therefore a LOWER bound on the remaining work at every intermediate state,
and only the completeness verdict is a claim.** This was already true of §16;
under §16b it is worth writing down, because foreclosure is the mechanism that
turns an unreachable target into a reachable one and the temptation to read the
intermediate number as final is correspondingly larger.

Foreclosures are therefore reported **exactly as conditional as the combination
claim**: `CoverageResult.foreclosures_provisional` is True whenever
`tree_missing` is non-empty, `summary()` prints PROVISIONAL, and the
combination claim is refused as before. **Foreclosure never excuses a branch**:
a satisfiable, never-observed outcome is still `tree_missing`, whatever
forecloses what.

#### Mutability — and the one non-monotonicity, stated

A new run that evaluates `d` under `g=o` **REMOVES** the foreclosure and **ADDS**
demand: (b) is a universal over the corpus, so it can only ever be refuted by a
run that walks what it forbids. That is the opposite direction from set growth,
which adds demand by widening the sets; both push the same way, so demand stays
monotone in the corpus — **with one exception, which is real and is not hidden**:
if `g` had been driven only as `not o`, a run that first takes `g=o` can CREATE
a foreclosure (condition (a) already held) and so RETRACT demand. That can only
happen while `g :: o` stood in `tree_missing`, i.e. while the claim was already
refused. At the fixed point the demand only grows. This is what "provisional"
means, precisely. (`src/test_coevaluation.py::
test_the_one_non_monotonicity_is_confined_to_an_incomplete_tree`.)

#### Coverage is still an OBSERVATION, and a partial run is not free

A leaf `(T, α)` is covered iff some run evaluated every member of `T` with those
outcomes. It need not have evaluated the rest of `S` — by (b) it provably did
not. The converse guard matters just as much: a run whose evaluated members are
a proper subset of `S` contributes a blocking clause **only if every member it
did not evaluate is foreclosed by the outcomes it did** (a "closed" prefix). An
unexplained partial walk blocks NOTHING. That is the conservative direction and
it is where the rule stays honest: it never counts an unproven cover.

#### Rule T — what `complete: true` now means

Demands ⊆ §16 demands ⊆ complete-graph demands, so **old-complete still implies
new-complete** and the §16a argument carries through unchanged: on a corpus that
was complete under the older rule every demand set was fully covered, and
pruning assignments out of a fully covered set leaves it fully covered. Rule T
is **NOT triggered**. Verified read-only under the new engine with each
endpoint's UNCHANGED `coverage_assumptions.py` (2026-09-10, `coverage_summary.json`
files untouched) — see `results3/notifications_index/_FORECLOSURE_SEMANTICS_20260910.md`
§4 for the run.

What a `complete: true` earned from now on asserts is therefore narrower again,
and the narrowing is exactly the artefact: it no longer includes an assignment
in which a decision is taken while the corpus shows that outcome removes it
from the path.

### §16c — CONFINEMENT: disjoint footprints (decided 2026-09-11)

> **SCOPE — how §16c differs from a declared `IndependenceAssumption`, and why
> the two kinds stay SEPARATE (owner ruling, 2026-09-15).**
>
> Both grant the *same licence*: this pair needs no cross product. They were
> examined for a merge on 2026-09-15 and the ruling is **keep them separate**.
> The load-bearing difference is SCOPE — where each claim is valid:
>
> | | declared independence | confinement (§16c) |
> |---|---|---|
> | who makes it | a person, by hand | the checker, derived |
> | evidence | the author's rationale | measured footprints + standing disqualifier |
> | **SCOPE — where valid** | **GLOBAL: every evaluation set holding the pair** | **WITHIN ONE LEAF ONLY** |
> | refuted by | flip-both probe (X11-blind, see below) | flip A / flip B / flip both, criteria (i)-(viii) |
> | falsified continuously? | no — probed once at the gate | YES — counterexample search at load, every pass |
>
> **Why confinement is leaf-local and can never be applied globally.** A
> footprint is measured over MATCHED CONTEXTS — pairs of runs with the SAME
> tree shape, i.e. inside one leaf. Such a measurement says nothing whatever
> about any other leaf. This is why `project_confinement` splits a demand set
> into gates ∪ cliques and applies the relation WITHIN each part, and why a
> decision whose flip changes *which* decisions are evaluated is undecidable
> here and stays fully demanded (that is foreclosure's business, §16b).
>
> **The hazard, in both directions, and it is SILENT either way:**
> - A confinement pair applied GLOBALLY removes edges from evaluation sets the
>   footprint measurement never spoke about — demand shrinks, MISSING drops,
>   `complete` flips true, nothing errors.
> - A declared claim narrowed to WITHIN-LEAF silently changes what its author
>   asserted.
>
> **Do not import confinement's criteria into the declared path.** Criterion
> (iv) ("flipping A leaves B evaluated") is a KIND discriminator — it asks
> *confinement or foreclosure?*, not *is this claim true?*. Declared claims are
> dominated by mutually-exclusive dispatch pairs that FAIL (iv) while being
> TRUE: 27 041 of notifications_index's declarations, 1 115 of posts_show's.
> Applying (iv) to them would withdraw them and re-open four closed endpoints.
> Confinement's evidence is stronger only for the pairs confinement can
> MEASURE; declared claims are mostly pairs it cannot.
>
> **What DOES transfer:** the standing disqualifier search (the counterexample
> scan at load, every pass). It needs no footprint, so it can be extended to
> declared pairs report-only. Filed, not built.
>
> Full analysis, both directions argued, in
> `docs/ASSUMPTION_KIND_UNIFICATION_20260915.md`.

#### Worked examples — one REAL instance of each of the three kinds

All three are verbatim from shipped corpora (trimmed). Read them together: the
point is not what each says but **why each is that kind and not another**.

---

**1. INDEPENDENCE — declared by a person, global scope.**
`people_stream/_assumptions_declared.json`

```
expr_a: (SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found      == True)
expr_b: (SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account == True)
description: "mutually exclusive / foreclosed per app control flow"
agent_notes:  people_controller.rb:140 `raise ActiveRecord::RecordNotFound if
              @person.nil?` fires immediately when the finder's not_found
              boundary decides True -- BEFORE line 141's closed_account? check
              ever runs. Verified: every not_found==True dump has EXACTLY 2 PCs
              (A + the not_found var), nothing else.
```

*Claim:* no cross product — do not demand the four combinations of these two.
*Why declared:* the justification is an argument about **app control flow**
(line 140 raises before line 141 runs). No footprint measurement produces that;
a person read the controller.
*Why it is NOT confinement:* flipping `not_found` to True means
`closed_account` is **never evaluated at all**. There is no matched context —
no pair of runs with the same tree shape differing only in that decision — so
confinement classifies it undecidable and leaves it fully demanded. This
declaration is exactly the mutual-exclusion family that FAILs confinement's
criterion (iv) **while being true**.
*SCOPE — GLOBAL.* This licence applies in **every evaluation set that holds
both expressions**, in every leaf and every scenario, wherever the pair
co-occurs. That is correct FOR THIS CLAIM: the evidence is "line 140 raises
before line 141 runs", a fact about the code that holds no matter which leaf
you are in. The scope follows from the KIND of evidence — a control-flow
argument is leaf-independent, so the licence is too.
*Refuted by:* the flip-both probe. Note its blindness (X11, below).
*Note the honest tell in the notes:* "every not_found==True dump has EXACTLY 2
PCs". That is a corpus check the author ran by hand — the thing the standing
disqualifier would do automatically and continuously.

---

**2. CONFINEMENT — derived by the checker, valid WITHIN A LEAF only.**
`comments_index/_bak_assumptions_declared_20260913_0200.json` (46 of 4 228 rows)

```
expr_a:      (Length(SYM_PARAM_post_id) < 16)
expr_b:      (SYM_RESULT_..._ci_author_first_1_not_found == True)
footprint_a: []                                  <- EMPTY
footprint_b: [ ActionController::Head.head,
               ActiveRecord::FinderMethods.ci_author_first,
               ActiveRecord::FinderMethods.ci_public_first,
               ActiveRecord::Relation.records, ... 9 shapes ]
enabling_b:  { head: "taken", ci_public_first: "taken", ... }
```

*Claim:* same licence — no cross product for this pair.
*Why derived:* nobody wrote this. The checker MEASURED that flipping the
post_id length changes **no statement shape at all** (`footprint_a` is empty),
while the finder's not_found controls nine. Disjoint footprints ⇒ no shape can
require both outcomes ⇒ no cross product.
*Why it is NOT independence:* the evidence is a measurement, not an argument,
and it carries its own falsifier — one run anywhere in the corpus with
`ci_author_first_1_not_found` on its non-enabling side and one of those nine
shapes present DISQUALIFIES the decision, and that search runs at load on every
pass.
*SCOPE — WITHIN ONE LEAF ONLY, and this is the sharp contrast with example 1.*
`footprint_a: []` was measured over MATCHED CONTEXTS — pairs of runs with the
SAME tree shape. It says "in the leaves we measured, post_id's length moved no
shape". It says **nothing whatever** about a leaf the measurement did not
reach, where the length might well move one. So `project_confinement` splits
the demand set into gates ∪ cliques and applies the relation WITHIN each part,
never across. Contrast example 1: that author's evidence was about the source
code and holds everywhere; this evidence is about a measured population and
holds only there. **Same licence, different reach, because different evidence.**
Applying this pair globally would remove edges from evaluation sets the
measurement never spoke about — demand shrinks, MISSING drops, `complete` flips
true, nothing errors.
*Refuted by:* criteria (i)-(viii) — flip A, flip B, flip both.

---

**3. FORECLOSURE — derived, and a different claim entirely.**
`posts_show/_p31_subconj_classes_P35W7.json` (1 008 classes at W=7)

```
conditioning:                                                  (C)
  (..._records_2_row_text_has_mention == True)        -> false
  (..._as_api_response_1_row_guid == '')              -> true
  (..._as_api_response_2_row_guid == '')              -> false
member:                                                        (d)
  (SYM_LEN_..._records_7_rows != 0)
A: 2830
```

*Claim:* NOT "these two do not interact" — **"given C, d never occurs"**. The
three conditioning literals hold together in 2 830 runs (`A=2830`, so C is not
vacuous), and in none of them does the member hold (`B(C,d)=0`).
*What it removes:* specific combinations, not a cross product. Every demanded
cube containing C ∧ d is dropped.
*Why it is NOT confinement:* nothing here is about disjoint footprints. C
changes WHICH decisions are evaluated — row 7 is never rendered, so its length
is never read. That is precisely the case confinement declares undecidable and
hands to foreclosure.
*Refuted by:* a **WITNESS** — build one run exhibiting C ∧ d. Not a
perturbation. This is why a gate test for foreclosure must be a construction
attempt with a mandatory positive control (a constructor that can build nothing
would pass every foreclosure for free).
*SCOPE — NEITHER GLOBAL NOR LEAF-LOCAL: the scope IS the conditioning `C`.*
This is not a pairwise edge and the global/within-leaf axis does not apply to
it. The licence reaches exactly the cubes in which all three conditioning
literals hold — the 2 830 runs' worth of context and no other. Where C does not
hold, nothing is removed and the member is demanded normally. That is why
foreclosure carries its context in the assumption itself, while the other two
carry theirs in the SCOPE of a pair.
*Width:* `W` caps |C|. Here |C|=3 at W=7. Sound at any width — failing to find
a conjunction leaves the demand standing.

#### §16c-X11 — the redundancy question, answered (2026-09-15)

**The question.** X11 ("the flip probe is blind to dependence that REMOVES
reads") was answered for the DERIVED path by building §16c. Was the declared
path therefore covered too — i.e. does the filed symmetric fix catch anything
§16b foreclosure and §16c confinement do not already catch? **No. The ground is
not covered, in either of two independent ways, and the residual class is large
and named.** But the fix AS FILED is the wrong predicate, and the acceptance
test as briefed cannot be met by any sound one.

**(1) §16c structurally cannot cover a DECLARED pair.** A declared
`IndependenceAssumption` cuts the edge `{A,B}` in the projection graph at
`coverage.py:2407-2414`; `demands = maximal_sets(projected)` at `:2428` then
contains no set holding both. `project_confinement` is called at `:2643` with
that ALREADY-PROJECTED `demands`, and its pair loop (`restrict_confinement`,
`:1768-1786`) only ever ranges over members of ONE group. So a declared pair can
never be classified `confined` / `overlapping` / `undecidable` / `disqualified`,
never reaches the tripwire (`:2685`), and can never be withdrawn. Footprints ARE
measured for it — `infer_footprints` runs over `active`, not `demands`
(`:1959-1960`) — but nothing ever compares them. **There is no audit anywhere
in `src/` that cross-checks a declared independence against measured
footprints.** The one accidental leak is the global OR-sharing pass
(`:1990-2016`): a declared-cut pair with a non-benign 2×2 can surface in
`confinement_and_pairs`, labelled "refused OR-sharing licence" rather than
"your declaration is contradicted", while the benign-but-overlapping case is
erased by `or_pairs &= confined_all` at `:2040`.

**(2) §16c was OFF in all four closed endpoints' SHIPPED configuration.**
comments_index `confinement=False` (`_cov_CONFOFF_20260913.log:3`);
notifications_index `CONFINEMENT=0` (`_c30_cov_C30OFF5.log:7`);
conversations_index closed 2026-09-01, ten days before §16c existed;
people_stream ran the default-on code path but serialises no census and ships
zero confinement licences. So even the derived cover is absent where the
declarations live.

**(3) §16b does not cover it either — and the declaration is STRICTLY STRONGER
than foreclosure.** Foreclosure is inferred globally (`:2445`) but APPLIED per
demand set (`restrict_foreclosures`, `:1730-1740`, called at `:2717`), so a
declaration that has already split A from B leaves it nothing to constrain. And
for the foreclosure GENRE itself: where `(A,a0)` forecloses `B`, §16b still
demands the OPEN-arm cubes `A=a1 ∧ B=T` and `A=a1 ∧ B=F`; the declaration drops
those too. `demand(declaration) ⊊ demand(§16b)`. "It is redundant with
foreclosure" is false: it claims more.

**The declared surface that rests on the flip probe alone.** Classified F
(foreclosure-shaped: "on one arm of A, B is never evaluated") vs D
(disjointness-shaped: both co-evaluated in both polarities, disjoint
statements):

| endpoint | declared pairs | F | D | flip-probe PASS | corpus-fact PASS | FAIL |
|---|---|---|---|---|---|---|
| people_stream | 25 | 23 | 2 | 25 | 0 | 0 |
| comments_index | 3 432 | 1 725 | 1 707 | 2 670 | 978 | 0 |
| conversations_index | 5 336 | 1 533 | 3 016 | 3 905 | 1 972 | 0 |
| notifications_index | 27 041 | 1 025 | 26 016 | 1 721 (class reps; 1 712 reused) | 0 | 0 |

~6 600 replay-earned PASSes, **zero FAILs**, on a probe DISCIPLINE itself calls
the wrong instrument.

**The measurement — the declared-pair 2×2 (new, 2026-09-15).** The engine's own
`infer_pair_tables` + `classify_cells` (`coverage.py:1822-1898`) applied to
DECLARED pairs, which nothing does today: per co-evaluated pair, the 2×2 of
target-call SHAPE presence over outcome profiles, each shape classified
benign (OR / A-only / B-only / ALWAYS / NEVER) vs INTERACTION (AND /
NON-MONOTONE). Read-only, no replays, ~60-90 s per endpoint. Tool:
`reports/diaspora/tools/declared_pair_2x2.py`. `KEEP_NOTES=1` is REQUIRED on
conversations_index and notifications_index, whose loaders pop `note`/`args`
(C1 currency, §2 of `CONFINEMENT_PRECISION_20260913.md`): without it
conversations reports 22 shapes and 188 interactions, with it 49 shapes and
875 — the degraded currency merges distinct statements and HIDES interaction.

| endpoint | pairs | inert (never co-eval) | 1 cell | BENIGN | OPEN | **INTERACTION** |
|---|---|---|---|---|---|---|
| people_stream | 25 | 0 | 6 | 0 | 17 | **2** |
| comments_index | 4 182 | 1 512 | 18 | 914 | 1 013 | **725** |
| conversations_index | 6 123 | 2 218 | 239 | 1 528 | 1 263 | **875** |
| notifications_index | 27 041 | — | — | — | — | **NOT MEASURED** |

notifications_index carries the largest exposure (26 016 D-class declarations
on a 138 912-run corpus) and was NOT measured: a live campaign owns that
directory. That gap is the single biggest unknown here.

**Named residual instances.** people_stream's two four-cell pairs are BOTH
interaction, and both shipped inside `OVERALL_COMPLETE=True`:

```
A (SYM_RESULT_PeopleController_diaspora_id__1_result == True)
B (SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found == True)
   gate verdict: PASS "no combination-only access shapes"
                 (_assumption_results.json, snapshot dump_auth_json0209_C12B.json)
   corpus 2x2 : 588 shapes classified AND, 339 benign, all four cells observed
                AND | ActiveRecord::Relation.records | SELECT DISTINCT posts.*
                      FROM "posts" LEFT OUTER JOIN share_visibilities ...
```

All 725 of comments_index's interactions are the `disjoint rep chains` genre —
the genre whose `agent_notes` say in terms *"licensed by the engine's flip-both
access-trace probe"*. That is the residual class, by name.

**Why the flip probe passed them, and why the FILED fix would not have caught
them either.** The defect is not only directional, it is ORIENTATIONAL. From one
base the gate's four replays visit all four cells: base `(on,on)`, flip-A
`(off,on)`, flip-B `(on,off)`, flip-both `(off,off)`. Per shape:

| shape pattern (base, flip-A, flip-B, flip-both) | shipped `novel` | filed fix (iii) | `classify_cells` |
|---|---|---|---|
| AND, base in `(on,on)` — `(1,0,0,0)` | PASS | PASS | **AND → FAIL** |
| AND, base in `(off,off)` — `(0,0,0,1)` | **FAIL** | **FAIL** | **AND → FAIL** |
| pure removal — `(1,1,1,0)` | PASS | **FAIL** | OR → PASS |
| unaffected / A-only / OR-shared | PASS | PASS | benign → PASS |

Two consequences, both load-bearing:

- The SAME physical dependence is FAILed or PASSed by the shipped probe
  depending only on which cell its base sits in. `classify_cells` tries all four
  orientations and is invariant; `novel` and criterion (iii) are not.
- **The filed symmetric fix would manufacture false refutations.** `(1,1,1,0)`
  — the combination loses a shape both single flips keep — is the OR pattern:
  two independent producers, either sufficient. The owner ruled on 2026-09-11
  that OR-sharing is not interaction (`classify_cells` docstring). Adding the
  LOST direction refutes it. **Do not ship the fix as filed.**

**The six posts_show negative controls (§64) — the briefed acceptance test is
unmeetable, and that is the finding.** Measured on `_snapshot_pruned_p5.txt`
(31 054 dumps, 4 644 profiles, `KEEP_NOTES=1`):

| control | corpus 2×2 | what would flip it |
|---|---|---|
| `find_by_1_not_found × find_by_2_not_found` (W-F) | **INTERACTION** (AND: `Person.name`) | orientation-invariant 2×2 |
| `Length(SYM_PARAM_id) < 16 × find_by_1_not_found` (W-C) | **INTERACTION** (AND: `Person.name`) | orientation-invariant 2×2 |
| `find_by_3_not_found × find_by_3_text_empty` (SAME REP) | OPEN — only 2 of 4 cells exist | criterion (iv) only |
| `find_by_3_not_found × find_by_3_text_has_mention` (SAME REP) | OPEN — only 2 of 4 cells exist | criterion (iv) only |
| `len(records_2_rows) != 0 × records_2_row_text_empty` (W-E) | never co-evaluated → **INERT** | nothing; the declaration carries no demand |
| `len(records_2_rows) != 0 × photos_…_row_text_empty` (W-E) | never co-evaluated → **INERT** | nothing; the declaration carries no demand |

2 of 6 flip under a sound predicate. 2 are foreclosure-shaped: only criterion
(iv) ("the partner stays evaluated") sees them, and (iv) must NOT be imported
into the declared path — it is a KIND discriminator, and the owner ruling above
(§16c SCOPE, 2026-09-15) forbids it; applying it would refute ~1 000 posts_show
and ~27 000 notifications_index declarations of the mutual-exclusion family in
one stroke. 2 are never co-evaluated at all, hence INERT under the 2026-09-10
co-evaluation semantics — they predate that rule and are no longer controls.
**"All six must FAIL" is therefore not a valid acceptance test for any sound
independence predicate.** It was a valid test for the confinement gate, where
(iv) is in scope, and DISCIPLINE records that all six FAIL there.

**Verdict and what to build.** X11 is REAL and OPEN on the declared path; it is
not redundant with §16b or §16c. But:

1. **Do not implement the fix as filed** (the LOST direction / criterion (iii)
   alone): it is orientation-dependent and refutes benign OR-sharing.
2. The sound instrument is the **orientation-invariant per-shape 2×2**,
   `classify_cells`, over the gate's own four replays — the engine's existing
   function, with the owner's own OR-sharing semantics, subsuming `novel` in
   every case in the table above.
3. Cheaper and available first with NO gate change and NO probe replays: the
   same 2×2 over the CORPUS, as a REPORT-ONLY `CoverageResult` field naming
   declared pairs the corpus contradicts (the `ASSUMPTION_KIND_UNIFICATION_
   20260915.md` Stage 3 disqualifier). The measurements above are exactly that
   field, computed out of tree. It is non-empty on every endpoint measured.
4. Whether either becomes BLOCKING is an owner call. It is not a small one:
   1 602 measured interactions across three closed endpoints, plus an unmeasured
   notifications_index, all inside shipped `complete: true`.


---

**The one-line discriminator.** Ask what refutes it:

| refuted by | kind |
|---|---|
| an argument about control flow, checked by a person | independence |
| flipping A and watching B's measured footprint | confinement |
| building a run that exhibits the combination | foreclosure |

**Decision record, the third inferred relation after co-evaluation (§16) and
foreclosure (§16b).** The owner's sentence: *"this downstream thing only
happens on one side, so no need to run combinatorially all the other things
with both."* Foreclosure removes assignments the program cannot make;
confinement removes the CROSS PRODUCT over decisions whose downstream effects
are disjoint. Like foreclosure it is INFERRED from the corpus — nothing is
declared, no `AssumptionSet` entry exists. (The gate's derived test is typed
`ConfinementAssumption` because that is what the gate is asked to test, not
where the relation came from.) In one line: non-interference of two
decisions' effects on the access trace.

#### The rule

> The **footprint** of a tracked decision `D` is the set of target-call
> **shapes** (target, note with binds and string literals wildcarded,
> argument shape — `concolic_engine.assumptions.call_shape`, the gate's own
> access-trace currency) whose PRESENCE differs between two runs that MATCH on
> every other evaluated expression — same evaluated set, same outcomes, same
> both-sided set — and differ only in `D`'s outcome. A run that recorded both
> sides of `D` is in none of `D`'s contexts. `D` is **decided** iff at least
> one such matched context exists; otherwise its footprint is **undecidable**,
> which is never read as empty.
>
> **STRICT (owner's refinement, later on 2026-09-11):** a decision is
> **confined** iff it is decided and EVERY shape in its footprint is strictly
> ONE-SIDED across the ENTIRE corpus — the shape is present ⇒ the decision
> took its enabling side; it never appears in a run where the decision took
> the other side, nor in a run that recorded the decision both ways. Runs
> where the decision is UNEVALUATED count neither way: on such a path it has
> no outcome, the shape is enabled by whatever gated it away, and that leaf
> is foreclosure's business, demanded on its own. Strictness is per shape and
> all-or-nothing per decision: one shape reachable on the other arm, through
> anything else, makes the decision NOT confined — the two-sided shape is
> never dropped to keep the rest.
>
> Two decisions are a **confined pair** iff both are confined and their
> footprints are disjoint. Inside a demand set, a confined pair needs each
> outcome observed once (under any compatible prefix), not the cross product.
>
> **GATES ARE MEASURABLE (owner's original case, later on 2026-09-11).** A
> gate can never have an exact matched context — its flip changes WHICH
> decisions are evaluated. So a decision with no exact context is measured
> under the **co-evaluated keying**: a matched context for `D` is two runs
> that agree on every decision evaluated in BOTH (other than `D`) and differ
> only in `D`'s outcome; decisions evaluated in only one of the two — `D`'s
> downstream, foreclosed on the other side — are not matched on: they ARE
> the footprint. A gate's footprint is then the shapes of its downstream,
> strictness applies unchanged (never present with the gate on its other
> side, corpus-wide), and two gates with disjoint downstreams are a confined
> pair. A decision that HAS an exact context keeps that (less confounded)
> measurement; the fallback only ever ADDS decided decisions, which is what
> makes the demand nest in the earlier rule.
>
> **THE DEMAND RULE, composed with foreclosure.** For a demand set `S` with
> its foreclosure relation (gates first): over ALL members the confinement
> graph keeps the edge `{x,y}` unless `(x,y)` is a confined pair. The parts
> are the maximal cliques of that graph, each CLOSED under "a part holding a
> member `d` holds every gate of `S` that forecloses `d`" (transitively);
> each part is judged by §16b on its own (its pruned tree, its gates first);
> the demand over `S` is the union over the parts (subset parts deduplicated).
> Consequences: a confined gate's own downstream stays with it — the closure
> keeps the gate in the downstream's part, and that part's pruned tree
> demands the downstream only under the gate's enabling side (foreclosure);
> two confined gates land in different parts, so the product of their arms is
> not demanded, nor the product of their downstreams where those are confined
> pairs too (confinement); a member confined with nothing keeps every edge and
> holds its part together (the conservative default). posts_show's 24 length
> gates in one set multiply to 2^24 under the earlier rule; under this rule
> each confined gate needs its two arms once.

What strict EXCLUDES, and why that is the conservative choice: under the
weak reading ("toggles in SOME matched context") a shape reachable on `A`'s
other arm via an unrelated `C` still counted as `A`'s, and `A × B` could
collapse although `Z` did not need `A` at all; strict says a shape the other
arm can still issue is not the decision's to control, and demands the product
there. The weak reading survives only as `confinement_strict=False`, so the
nesting can be tested; batches never use it. Note the direction: strict is a
SUBSET relation on PAIRS (strict-confined pairs ⊆ weak-confined pairs) and
therefore a SUPERSET on DEMAND — `weak-confined ⊆ strict-confined ⊆ §16b`;
strict never demands less than weak, never more than §16b.

Implementation (`coverage.py`, `infer_footprints` / `restrict_confinement`,
next to foreclosure): footprints are measured on the alias-applied runs (the
engine's canonical namespace — the posts_show census that read raw dump names
reported 791 "pending" pairs for exactly that mismatch), contexts are matched
on every expression a profile mentions, per profile the union AND the
intersection of its runs' traces are kept so the pairwise definition is exact
(a shape is in the footprint iff present in some run of one arm and absent
from some run of the other). Then, **foreclosure first**: inside each demand
set the members that foreclose something (its gates) stay in every part; the
non-gate members' confinement graph (edge kept unless the pair is confined) is
decomposed into maximal cliques `K_i` and the set `S` becomes the sub-sets
`G ∪ K_i`. New `CoverageResult` fields, all with defaults: `footprints`,
`footprints_undecidable`, `confined_pairs`, `confinement_overlapping`,
`confinement_undecidable_pairs`, `confinement_splits`,
`confinement_provisional`, `confinement_withdrawn`; `summary()` prints one
line. `confinement_to_dict()` hands the confined pairs, with the footprints
they were licensed on, to the gate.

#### Why — X11, and what the flip probe could not see

The independence flip-both probe FAILs only on a NOVEL shape (posts_show
`_COMPLETION_20260910.md` §64): dependence that REMOVES reads — a finder that
does not find, a list with no rows — leaves the combination's trace a subset
of the single flips' and passes. All six of posts_show's negative controls
passed it; 83 of 83 tier-2 candidates passed it. Independence was again the
wrong instrument. What those pairs have, when they have anything, is not
"no interaction at all" but "no shape needs both" — and that is a corpus
MEASUREMENT with a concrete falsifier, not a probe verdict. On the p5
snapshot the census (raw names) found 54 decided / 57 undecidable decisions
and, among 1 733 candidates, 231 disjoint, 44 overlapping (e.g.
`assoc_profile_nsfw` × `assoc_status_message_text_has_mention`, 27 shared
shapes), 667 undecidable — the 44 are real dependence the flip probe passed.

#### Soundness — the claim and its falsifier

Suppose a shape `Z` required both outcomes: `A=x ∧ B=y ⇒ Z`. In any matched
context with `B=y`, flipping `A` toggles `Z`, so `Z ∈ footprint(A)`;
symmetrically `Z ∈ footprint(B)`. Disjointness refutes such a `Z`. Strictness
adds the stronger check the owner asked for — that every footprint shape is
"only possible when the upstream thing is one way" — and its falsifier is a
**COUNTEREXAMPLE SEARCH run at load on every pass**: for every confined
decision and every shape in its footprint, one run anywhere in the corpus
with the decision on its non-enabling side and the shape present DISQUALIFIES
the decision (`confinement_disqualified`: decision, shape, and the two runs
named; `summary()` prints them). One matched context in which a shape outside
`footprint(A)` varies with `A` enlarges the footprint; one shared shape
withdraws the pair.

**Preconditions, CHECKED, never assumed.** (1) Tree completeness — as for
foreclosure; with `tree_missing` non-empty the footprints are PROVISIONAL and
the combination claim is refused. (2) Matched contexts for BOTH members — an
undecidable decision is in no confined pair and stays fully demanded.
(3) A trace layer — a corpus recording no target call has nothing to measure
a footprint on; every decision is undecidable there and the projection is the
identity (this is what keeps the engine's own trace-less fixtures byte-identical).

**Why foreclosure first.** A matched context is by definition two runs with
the same tree shape, so a footprint says nothing about a decision whose flip
changes WHICH decisions are evaluated — that is foreclosure's business (and
such a decision is typically undecidable). Keeping the gates in every part
makes the pruned tree of `G ∪ K_i` the pruned tree of `S` restricted to
`K_i`'s survivors: confinement is applied WITHIN the leaf, exactly where the
matched-context measure is valid. A projection-cap hit keeps the set whole
(conservative, never truncated).

#### The three checks

1. **Engine unit tests** — `src/test_confinement.py` (23): the confined pair
   (demanded cube list before `And(Not a, Not b)` → after empty), the
   jointly-gated shape in both footprints (no collapse), undecidable is not
   empty, both-sided runs excluded, PROVISIONAL on an incomplete tree, gates
   kept in every part, cap keeps the set whole, canonical-namespace keying
   under an `AliasAssumption`, the trace-less identity, the tripwire, and the
   randomized nesting property (60 corpora). The STRICT tests plant
   counterexamples and assert disqualification: a shape reachable via `A` or
   via an unrelated `C` (weak collapsed `A × B`; strict disqualifies both `A`
   and `C`, names the runs, keeps the product); ONE run with `A` off and the
   shape present among a thousand with `A` on; per-shape all-or-nothing (three
   one-sided shapes and one two-sided → not confined, footprint still reports
   all four); a both-sided run showing the shape; an unevaluated run does NOT
   count; and strict ⊆ weak ⊆ §16b on 60 random corpora.
2. **The gate's composition probe** — `ConfinementAssumption` in
   `assumption_checker.py` (`_test_confinement`), tested on fixtures with a
   stub replay (`src/test_confinement_gate.py`, 25): flip A, flip B, flip
   both; PASS iff (i) ΔA ⊆ footprint(A), (ii) ΔB ⊆ footprint(B),
   (iii) `trace(both) == (base − removed_A − removed_B) ∪ added_A ∪ added_B`,
   (iv) each single flip leaves the PARTNER evaluated with its base outcome
   and the double flip records both flipped — (iv) is what sees
   removal-shaped dependence — (v) no footprint shape present in the base
   SURVIVES its decision's flip (strict one-sidedness observed by replay, in
   flip-A/flip-B and in flip-both; a flip that leaves the decision
   unevaluated while the shape is still issued is a ROUTE AROUND it, FAIL),
   and then the ACTIVE search (owner, later on 2026-09-11: "the gate must
   try to falsify the claim by construction" — the independence gate flips
   and replays; a passive corpus scan is not that): (vi) EXHAUSTIVE FLIP
   OVER PROFILES — every distinct outcome profile in the corpus carrying a
   footprint shape is flipped on a representative run and replayed
   (`_exhaustive_flip`), FAIL if the shape is still issued or issued with the
   decision unevaluated; (vii) an ADVERSARIAL CONSTRUCTED ROUTE per footprint
   shape that has other producers — the decision off, every other producer
   on with its foreclosing gates held open, from a base run or a Z3 model
   over the base's declared variables, UNSAT recorded as evidence
   (`_constructed_route`), FAIL if the shape appears. A PASS rests on the
   gate's OWN replays and on nothing already run: a probe budget that
   truncates (vi) (`ACHK_CONF_PROFILES`, default unlimited), a flip that did
   not take, or a route that could not be constructed is NOT-TESTABLE —
   never PASS on partial evidence. Any deviation FAILs; a dead knob is
   NOT-TESTABLE; per-probe isolation and the results file as X10 requires
   (the X10 combined-flip lines are now one shared helper, `_combined_flip`,
   used unchanged by the independence test). The six posts_show negative
   controls, modelled as stub replays, all FAIL on (iv); the 27-shared-shape
   pair FAILs at disjointness and, wrongly licensed, on (i);
   `src/test_confinement_active.py` (7) drives the active probes against stub
   PROGRAMS: (vi) catches a shape a second profile still issues after the
   flip (the single-snapshot probe passes it), (vii) catches the A-or-C route
   no corpus run walked (passive + (vi) pass it), the solver route for an
   unrecorded producer and its UNSAT evidence, a truncated budget and a dead
   flip both NOT-TESTABLE; (e) for a GATE: the constructed probe puts the
   gate on its non-enabling side and another producer on, and reaches the
   downstream shape. The gate-measurable tests: (a) two gates with disjoint
   downstreams in one set — §16b's cube list before, per-gate demand after,
   and the differentiating corpus (an unwalked arm combination the earlier
   rule demands and this one does not); (b) a shape needing both gates on
   is in both footprints, the gates' product becomes a part of its own;
   (c) a downstream shape reachable with the gate off disqualifies the gate;
   (d) the same corpus is undecidable under the exact keying and decided
   under the co-evaluated one; and the nesting confined-gates ⊆ earlier
   strict ⊆ §16b on 60 random corpora. The existing independence flip test is
   untouched; X11's symmetric fix as FILED (add the LOST direction) was
   investigated on 2026-09-15 and **REJECTED as the wrong predicate** — see
   "§16c-X11 — the redundancy question, answered" below. X11 itself is NOT
   answered by §16c and remains OPEN on the declared path.
   **End to end** (`src/test_confinement_e2e.py`, 4, through the REAL
   completion flow with a stub runner subprocess): `CoverageResult.
   assumptions_to_dict()` now appends the inferred pairs (type
   `ConfinementAssumption`, `"inferred": true`, with footprints, enabling
   sides, producers and gates), so every endpoint's `summary["assumptions"]`
   → `completion.attach_to_summary` → `assumption_check` →
   `_assumptions_declared.json` → `assumption_checker.py --declared` →
   `_test_confinement` runs with NO per-endpoint change; a FAIL blocks
   `completion.complete` and `summary.complete`, lists the pair in
   `completion.assumptions.confinement_withdrawn` (fed back next pass as
   `CoverageChecker(withdrawn_pairs=…)`, never licensed again) and marks the
   summary `coverage_numbers_stale`; and — unlike a declared assumption —
   an inferred pair the gate could not verify (NOT-TESTABLE, NOT-COMPARABLE,
   ERROR) is withdrawn and blocks too (`confinement_unverified`).
3. **The corpus tripwire** — two mechanisms. The COUNTEREXAMPLE SEARCH
   above runs at load, every pass, over every run, and disqualifies. And
   `prior_footprints=` on `CoverageChecker`: given the footprints an earlier
   pass licensed pairs on, every pair confined under them that this corpus no
   longer confines (a member disqualified or undecidable now, or a footprint
   enlarged into the other's) is counted and printed as WITHDRAWN. Licensing
   itself always uses the current corpus.

#### Mutability

A footprint is a union over matched contexts: it only grows, so a confined
pair can only be WITHDRAWN by a new run — the same direction as foreclosure.
A decision can also become decided (a first matched context), which can
CREATE a confined pair and retract demand; that is the counterpart of §16b's
one non-monotonicity and is likewise confined to a corpus on which the tree
or a context was still missing.

#### Rule T — what `complete: true` now means

Every sub-set is a subset of its set with the same gates in the same order,
so each of its pruned-tree leaves is the restriction of a leaf of the set,
every satisfiable leaf of the sub-set extends to a satisfiable leaf of the set
(a Z3 model determines every expression), and a run covering the extension
covers the restriction. Hence

    confined-gates (co-evaluated keying, gates confinable)
      ⊆ earlier strict (exact keying, gates protected)
      ⊆ foreclosure-aware (§16b) ⊆ set-level (§16) ⊆ complete-graph
    (and weak-confined ⊆ strict-confined at each keying)

— old-complete still implies new-complete, and a corpus with no confined pair
gets a byte-identical verdict. Verified: the randomized property tests (every
confinement-missing cube is contained in a §16b-missing cube; identical
reports where nothing is confined), the whole pre-existing `src/` suite
unchanged, and a read-only re-run of one shipped endpoint with confinement
off and on (see `results3/_CONFINEMENT_20260911.md`). Rule T is **NOT
triggered**. The endpoints pick the property up at their next pass through
`coverage_report.py`; the exact pricing on a snapshot is
`tools/confinement_census.py`.

#### Honest blind spots

The footprint sees SHAPES (binds and literals wildcarded), so a dependence
that changes a bind but no shape is invisible to it — the same reading the
gate's access trace has always used (§14, `_TRACE_PROJECTION_20260909.md`
§5). An empty DECIDED footprint means the decision changes no shape in any
matched context; it is (vacuously strictly) confined with every other confined
decision. The gate's
criterion (iv) can over-withdraw a genuinely confined pair whose partner is
reachable by two paths (the snapshot's flip removes it, another snapshot's
would not) — the conservative direction, and the reason a FAIL there names
the mechanism rather than the pair.

**NOTE (2026-09-13) — why the gate refutes the inference at 76-85 %, measured;
a note, not a semantics change.** `docs/CONFINEMENT_PRECISION_20260913.md`
classifies all 93 gate FAILs (notifications 78, comments_index 15) from the
probes' own data. The footprint is measured too small for three reasons, and
thin corpus support is NOT one of them — FAILing pairs have MORE matched
contexts than PASSing ones (notifications median 71 vs 39), so no minimum-
support threshold separates them. (1) CURRENCY: notifications_index,
comments_index and conversations_index `coverage_report.py::fix_len_names`
pops `note` and `args` from every event for memory, so `call_shape`
degenerates to the target NAME — 16 and 9 distinct shapes where the gate's
`access_trace` measures 91 and 22 on the same corpus, and the two currencies
the `call_shape` docstring says can never disagree do. posts_show's loader
keeps them and is unaffected. (2) SPAN: on notifications 158 of 159
exactly-keyed decided decisions have shapes they co-occur with that NO matched
context contains (median 31 % of their reach); `infer_footprints` reads
"never observed" as "not the decision's" where the only sound reading is
"unknown", and unknown belongs IN the footprint. (3) THE FALLBACK: 88 of the
93 FAILs have a member decided only by `infer_footprints_coevaluated`; pairs
whose members both have an exact context pass 35/40, pairs with a fallback-only
member pass 64/152. A criterion combining the three (correct currency +
`fp | blind` + no fallback licence) makes ZERO false licences over all 192
probed pairs, at recall 0.21. The note also records what rests on nothing:
notifications 510 of 656 licensed pairs (77.7 %) and posts_show 2 701 of 2 701
(100 %) have never been probed. The three read-only tools are
`tools/_conf_precision_{sample,pairs,span}.py`. §16c's semantics are UNCHANGED
by this note.

**FOLLOW-UP (2026-09-13, later) — C1 measured, C2 and C3 IMPLEMENTED, both
default OFF.** The note above said the `coverage.py` changes were not
implemented; they now are, as two knobs that default to the shipped reading,
so every summary written before today reproduces byte for byte (proved at
endpoint scale: comments_index re-run with its SHIPPED configuration under the
new engine, 18 non-completion keys compared, NONE differing —
`comments_index/_RESTORED_20260913.md` §4.2 — plus 328 `src/` tests, 7 of them
new in `src/test_confinement_span.py`).

* **C1 (currency)** is a batch-driver fix, not an engine one, and is measured
  rather than argued (`tools/_c1_currency_cost.py`,
  `tools/_c1_currency_patch.md`): with `share_run_objects` already
  deduplicating events, keeping `note`/`args` costs comments_index **+2.7 %
  peak RSS (1 413 -> 1 451 MB)** and takes the shape count from 13 to **22 =
  the gate's**. It is landed in `comments_index`; `notifications_index`'s copy
  was NOT edited (its C21 pass was executing that file), and neither was
  `conversations_index`'s. A note DIGEST reproduces the same shape SET at
  +1.3 %, but it is not a currency fix in general: `confinement_to_dict()`
  hands the gate `shape_str` STRINGS, so a hash breaks the handshake, and the
  one safe digest (the note's `call_shape` normal form) loses the bind text
  `apply_aliases` would have rewritten.
* **C2 — `CoverageChecker(confinement_span_union=True)`**, `unobserved=
  "attribute"` on `infer_footprints` / `infer_footprints_coevaluated`,
  `footprint_unobserved=` on `project_confinement`. `fp = m | (reach & ~span)`.
  Monotone: the footprint only grows, so the licensed pairs are a SUBSET and
  Rule T is not triggered.
* **C3 — the knob to use is the EXISTING `confinement_keying="exact"`.** The
  note's own prescription ("a fallback-decided decision gets `fp = reach`") is
  implemented as `confinement_fallback_licence=False`, and MEASURED IT IS
  NEARLY INERT: on comments_index it changes the licensed set by ZERO pairs
  (46 probed: 35 -> 35 with C1, 30 -> 30 with C1+C2), because almost every
  licence there is an OR-SHARING licence (`classify_cells`), which survives a
  bigger footprint. What the note's §5.1 table actually priced is the STRICTER
  reading of the same sentence — a pair with a fallback-only MEMBER is refused
  outright — and that is exactly what `confinement_keying="exact"` already
  does (a decision with no exact context stays UNDECIDABLE, so it enters no
  pair and `infer_pair_tables` never sees it). Verified equivalent on
  comments_index's full corpus: "refuse" and `keying="exact"` license the
  IDENTICAL pair sets (8 under C1+C3, 3 under C1+C2+C3).
* **And the bar was not met by C1+C2 alone.** On comments_index's 46 probed
  pairs C1+C2 still makes **8 false licences** (precision 0.73). Zero false
  licences needs C3 as well. So C1+C2 is a correction worth landing, but it is
  not on its own a defensible confinement layer.

#### §16c round 5 — OR-sharing is not interaction (2026-09-11, measured first)

**The finding that forced it.** Gate-aware confinement on posts_show (GC0911,
31 394 profiles): §16b 5.21e13 → §16c 7.77e10 remaining, sets 1 901 → 6 494,
6 365 wide sets still holding all of it. The census categories said where:
**overlapping 0, disqualified 2 416** — under STRICT an OR-shared shape does
not overlap, it disqualifies (present with the decision off, via another).
Measured before anything was changed (`tools/or_sharing_census.py`, read-only,
2 G): over 3 776 co-evaluated pairs of decided decisions, the 2×2 of every
footprint shape over the co-evaluated profiles classifies **2 295 pairs
ALL-OR** (every shape OR / A-only / B-only / ALWAYS), **602 ANY-AND** (a shape
present only with both on: `findpublic_like`/`findpublic_reshare` under the
dispatch arm AND the previous finder's miss — the act→like→reshare
fall-through; `Person#name`; `COUNT(*) FROM photos`), 407 UNDETERMINED (an
unobserved cell), 8 non-monotone. Pricing, pre-registered as §69.1 outcome
(3): the Z3-free structural proxy (calibrated exactly on the census's own
1 901 / 6 494 sets and widths) gives sets 6 494 → 1 677, max width 36 → 27,
wide sets 6 365 → 999, Σ2^width 8.94e12 → 4.47e9 (2 002×), i.e. remaining
≈ 4×10^7 at the census's own Z3 ratio; the identical-flags exact run needs
~3.3 G and was OOM-killed at the 2 G cap (not raised). The residual is named:
AND / UNDETERMINED / own-downstream pairs.

**The rule.** A pair the strict rule does not license is licensed anyway iff
EVERY shape in fp(A) ∪ fp(B) has a benign 2×2 over the co-evaluated profiles
(`classify_cells`): presence monotone in each decision under some
orientation of "on" — OR, A-only, B-only, ALWAYS, NEVER — so no combination
yields a shape the singles do not explain. A shape present only with BOTH on
(AND), a non-monotone cell, or an unobserved cell that leaves AND open refuses
the pair, shape, cell and witness run named (`confinement_and_pairs`). The
licence is a UNION with the strict one, so `refined ⊆ strict ⊆ §16b` holds
(`test_or_sharing_is_nested_in_strict_on_random_corpora`, 60 corpora, 20
with OR pairs, 40 byte-identical). The falsifier of an OR licence is one run
in a non-monotone cell — the counterexample search now over cells, at load.

**The gate.** Shared footprint shapes are no longer refused on the corpus
alone: the four replays (base, flip-A, flip-B, both) ARE the pair's 2×2 in
that context, and criterion (viii) classifies each shared shape on them —
AND or non-monotone FAILs. Criteria (iii) and (v) apply to the UNSHARED
shapes only: the additive law `both = base + ΔA + ΔB` is the no-interaction
law for a shape one decision controls, and an OR-shared shape obeys the
monotone law instead (it survives each single flip and vanishes only in the
double one — the coordinator's expectation that (iii) already passed OR pairs
was wrong from an (on,on) base, and the fixture shows it). A shape surviving
a flip is allowed where another producer of it is on in that replay; (vii)
now constructs the ALL-OFF cell (the decision off, every known producer off,
gates open) and FAILs on a route around every known producer. Fixtures: the
OR pair PASSes, the AND pair FAILs (viii), the non-monotone pair FAILs, the
27-shape posts_show pair as an AND table FAILs.

### §16d — ONE Z3 query per demand set, and one witness (decided 2026-09-12)

**Decision record, owner ruling.** *"Shouldn't we just stop at one missing
found? Why are we doing one z3 per node, we should do one per clique right?"*
Both halves are now the engine's behaviour, and neither changes what the
checker CLAIMS — only what it spends and how many examples it prints.

Until today `coverage.py::_next_untried_combo` determinised a demand set's
leaf by a greedy walk: for each member of the set, up to TWO
`check_satisfiability` calls (try `taken`, else `not_taken`), each one a
FULL query — fixed base + every blocking clause accumulated so far + the
prefix chosen so far + the new literal — re-parsed from text by a fresh
`z3.Solver()`. A set of width *w* with *k* leaves therefore cost up to
`(k+1) × 2w` solver calls on a formula that grew with every step. On
posts_show (width 21-27) one pass took 9+ hours; the Z3 work was almost
entirely re-deciding a prefix the solver had already decided.

**The rule now.** A demand set is ONE query: the fixed base, the set's pinned
outcomes, and one blocking clause per OBSERVED leaf — the §16b
foreclosure-pruned leaf structure, unchanged, so a leaf is still the
assignment over the set minus what its own prefix forecloses, and a partial
run still blocks only a CLOSED prefix. **UNSAT ⇒ the set is covered.** SAT ⇒
at least one leaf is missing, and the model names one: every member of the
set is evaluated under that model with **model completion**
(`solver.solve_and_evaluate`, `model.eval(expr, model_completion=True)`), and
the §16b gate-first skip rule is applied to the evaluated assignment exactly
as it was applied to the greedy walk's, so the cube is a well-defined leaf.
The completion costs ZERO extra solver calls: a member the constraints left
free gets Z3's default value instead of a query, which is precisely the
freedom the walk was paying for. **`max_missing_per_clique` now defaults to
1**: a set's verdict is decided by its FIRST missing leaf and one witness is
what the driver needs to construct the next run (§ "How the remaining runs
are chosen" — the run is built from the counterexample plus the enabling
gates, and one counterexample is one run). A cap above 1 still enumerates, at
one query per extra witness plus the closing UNSAT — never one per decision.

**What is identical, and what is not.** The verdict is identical: the same
`complete`, the same demand sets, the same SETS flagged as having a gap, the
same `tree_missing`, the same foreclosure and confinement outputs. It has to
be — `fixed ∧ blocks` is satisfiable iff at least one of its two extensions
by the first member's outcome is, which is exactly what the walk's first pair
of calls tested. What differs is WHICH leaf comes back as the witness (the
model's, not "True first"), and, at the new default, HOW MANY witnesses a set
prints: one instead of up to four. `missing` was never an enumeration — §16b
already recorded that the reported missing list is a LOWER bound on the
remaining work at every intermediate state and only the completeness verdict
is a claim. The default makes that explicit rather than changing it. Note the
consequence for one field: with the cap at 1, a set that has a gap stops AT
the cap, so `truncated` is True on any incomplete pass. `complete` is already
False there, so nothing is weakened — but `truncated` no longer distinguishes
"cut short" from "incomplete".

**One sharpening, in the honest direction.** The walk saw a Z3 `unknown` as
"both outcomes unsatisfiable"; at the FIRST member that is indistinguishable
from a genuine UNSAT, i.e. from *covered*. With a single query there is no
second chance to notice, so `solve_and_evaluate` keeps `sat`/`unsat`/`unknown`
apart and an `unknown` becomes `solver_lost` + `truncated`, never silence. A
timeout can no longer read as coverage.

**And one defect the change exposed, fixed with it.** Z3's choice among the
models of a satisfiable formula depends on state carried in its context: the
IDENTICAL query issued twice in one process demonstrably alternates between
models. That was invisible while the caller only read sat/unsat; it is
decisive when the caller reads the MODEL, because a resumed checkpoint pass
must return what the unbroken pass would have. `solve_and_evaluate` therefore
solves in a PRIVATE `z3.Context`. Verified: four passes over the same corpus
give one witness set, and two separate processes over the 9 573-dump
people_stream subset write byte-identical summaries.

**Measured (2026-09-12, caged at MemoryMax=4G).** Old = the pre-change module,
new = this one; "checker" is `coverage_report.py`'s own wall for the check,
"calls" is every `check_satisfiability` + `solve_and_evaluate` invocation.

| corpus | verdict | checker (old → new) | solver calls (old → new) |
|---|---|---|---|
| people_stream, 13 677 dumps, 21 sets, MISSING=0 | complete, summary byte-identical | 50.0 s → 25.9 s | 82 → 61 |
| comments_index, 26 528 dumps, 80 sets, MISSING=0 | complete, summary byte-identical | 33.4 s → 27.3 s | 244 → 164 |
| people_stream 70 % subset, 9 573 dumps, 21 sets, 12 with a gap | `complete=False`, same 12 sets, same `tree_missing`, same 295 foreclosures | 765.0 s → 61.3 s at cap 4; → **24.3 s** at the new default cap 1 | 782 → 93 (cap 4); → 63 (cap 1) |

The subset's `missing` count drops 38 → 11 at cap 1 (12 flagged sets, one of
their witnesses shared across two sets and deduplicated) — that is the
intended half of the ruling, not a lost gap.

Engine: `src/concolic_engine/solver.py` (`solve_and_evaluate`, `ModelResult`,
`_namespace`), `src/concolic_engine/coverage.py`
(`_next_untried_combo`, the `max_missing_per_clique` default). Tests:
`src/test_coevaluation.py` §8 (four new tests: one query for a covered set,
the default stops at the first leaf, the same query returns the same witness,
a foreclosed member stays out of the cube). The COVERAGE_CHECKPOINT header
keys an engine source hash, so every checkpoint written by the old module is
rotated to `<file>.stale` on its next open rather than reused.

### §16e — foreclosure over gate CONJUNCTIONS (decided 2026-09-13, OPT-IN)

**Decision record, owner ruling.** *"Why are the assumptions not enough to
prune the space such that you can get a complete drive."* Because the
foreclosure inference was strictly PAIRWISE. §16b reads `(g, o)` forecloses
`d` off single literals; the app forecloses members under gate
CONJUNCTIONS, and a decision that two gates only remove ACTING TOGETHER was
never inferred, so its cubes stayed demanded for ever. §16e is the same
relation, one conjunction wide. It is the fourth INFERRED relation after
co-evaluation (§16), foreclosure (§16b) and confinement (§16c): nothing is
declared, no `AssumptionSet` entry exists, and it re-derives itself on every
corpus.

#### The rule

> For a demand set `S` with leaf-group gate prefix `P` — the gate-first
> ordered assignment over `S`'s foreclosure gates, exactly as the §16b
> pruned walk already defines a leaf — a surviving member `d` is
> **FORECLOSED under `P`** iff **(a)** at least one run's profile MATCHES
> `P` and **(b)** no run matching `P` evaluates `d`.

"Matches" carries §16b's and co-evaluation's own semantics, per literal: a
run matches `P` iff for every `(g, o)` of `P` it evaluated `g` with outcome
`o` at least once. A run that recorded a recurrent, per-row decision BOTH
ways therefore matches either literal, so `A` and `B` can only be
OVERSTATED and a `B = 0` verdict is conservative in the direction that
matters.

A foreclosed member is **not part of the leaf**, exactly as a
§16b-foreclosed member is not: the leaf is the assignment over the
survivors minus `F(P)`, the leaves stay pairwise incompatible (two leaves
differ at the first gate they diverge on, and that gate is in both cubes),
and there is one blocking clause per OBSERVED leaf. **Both sides move
together**: the emission side (`_next_untried_combo`'s cube) and the
closed-prefix test that lets a PARTIAL run block. If only the first moved,
a leaf the inference coarsened could never acquire its clause and would be
reported missing for ever — which is the whole defect being fixed.

Gates are never conjunction-foreclosed. They DEFINE `P`, and the falsifier's
own member list is `surv − P`.

#### Falsifier — the inference's own test

**Any run that matches `P` and evaluates `d`.** It is the same universal
over the corpus that §16b's clause (b) is, one conjunction wide instead of
one literal, so it is self-re-deriving: the run removes the foreclosure on
the next pass with nothing to retract by hand. Monotone in the corpus in the
same way, provisional in the same way —
`CoverageResult.conjunction_foreclosures_provisional` follows
`tree_complete`, `summary()` prints PROVISIONAL, and the combination claim
stays refused while the tree layer is incomplete. **Precondition unchanged:**
the tree layer must be complete or the report refuses the claim. A
conjunction foreclosure never excuses a branch.

The measurement that decided it, on notifications_index and computed twice
on two corpora 12 951 constructed runs apart (`_c14_falsifier.py`, campaign
§27.5/§27.10): B=0 groups 208 / 1 728 cubes before and after, of them A>0
120 / 1 728 → 1 152 cubes, IDENTICAL to the group and to the cube, while the
class §19.2 does NOT claim (FULLY FALSIFIED) emptied by 90.5 %. Ten thousand
constructed runs at 96.6 % per-key honour did not cause ONE member of ONE
B=0 group to be evaluated under its own gate conjunction. That is the
strongest form the evidence can take from the driver's side: the class is
not a driving backlog.

#### The `A = 0` class — REPORTED, never inferred

A gate conjunction NO run of the corpus matches at all is **absence, not
evidence**: nothing has been observed under it, so "never evaluates `d`"
says nothing. Those leaf groups keep their demand in full and are reported
— `unmatched_gate_conjunctions` (count) and
`unmatched_gate_conjunction_prefixes` (the literals, capped) — so the
driver can CONSTRUCT the prefix. §16 co-evaluation still demands them. No
inference licenses them; the driver and the owner decide. This is §13.3's
multi-gate-unreachable class and it is a different question.

#### Nesting

Conjunction foreclosure only ever removes members a §16b leaf still held, so

    §16e ⊆ foreclosure-aware (§16b) ⊆ set-level (§16) ⊆ complete-graph

with each §16e leaf a SUB-CUBE of the §16b leaf it came from. Old-complete
therefore still implies new-complete and **Rule T is NOT triggered**: on a
corpus complete under §16b every leaf was covered, and coarsening a covered
leaf leaves it covered. Pinned by
`src/test_conjunction_foreclosure.py::test_demand_is_nested_16e_16b_16`
(60 random corpora, three settings, counts and ⊆ on every leaf) and by
`::test_missing_is_nested_on_random_corpora` (the same through the checker).

#### Opt-in, and why

`CoverageChecker(foreclosure_conjunctions=True)`, **default False**. Every
summary written before 2026-09-13 reproduces byte-for-byte with the flag
unset, which is what keeps the closed endpoints closed without re-arguing
them. The flag is folded into the step-6 CHECKPOINT key (`params`), so a
checkpoint written under one setting is rotated to `<file>.stale` rather
than replayed under the other, and a resumed pass re-folds the same
counters (the per-witness `conj` record is part of the checkpoint, because
the foreclosed members cannot be read back off a pruned cube).

#### The gate test — derived, in the §16b/OneSideUntracked style

`assumption_checker.py::_test_conjunction_foreclosure`, dispatched on the
inferred type `ConjunctionForeclosureAssumption` that
`assumptions_to_dict()` now emits (marked `inferred: True`, so a report can
tell it from a declaration). Base = the richest snapshot that recorded `d`
TOGETHER WITH every gate of `P` — a run in which `d` IS evaluated, which is
"`d`'s inputs seeded to force its evaluation"; probe = that snapshot's
seeds with every gate whose recorded outcome differs from `P`'s flipped, at
the runtime (ordinal) key the runner seeds by (X10).

| verdict | when |
|---|---|
| **FAIL** | the probe realises `P` and RECORDS `d` — refuted, the foreclosure is withdrawn |
| **PASS** | the probe realises `P` and leaves `d` unevaluated |
| **NOT-TESTABLE** | the probe does not REALISE `P` (the realised-value rule: seeding is not realising), no snapshot records the member with the gates, no flip value can be inferred, or the replay produced no dump |
| **NOT-COMPARABLE** | a flip changed what an aliased ordinal resolved to |

One replay per class; classes sharing a seed dict share their probe. The
verdict-row dedup key now carries `prefix`, so two foreclosures of the SAME
member under different conjunctions are two claims and never collapse. The
test can never be VACUOUS: the base is chosen because it records the member,
so if it already matched `P` the corpus would have falsified the inference and
the engine would not have made it — at least one gate must be flipped.

**First run (notifications_index, 2026-09-13):** the endpoint's 89 inferred
(prefix, member) pairs collapse to 2 classes (2 distinct foreclosed members);
`PASS 2, FAIL 0, ERROR 0, NOT-TESTABLE 0, NOT-COMPARABLE 0`, both on a probe
that REALISED the conjunction after flipping 2 and 1 gate from a base that
records the member. 41 m 23 s, peak 3 341 MB, of which ~40 min is
`corpus_index` over 304 586 dumps; the probes are one batch of two roots.

**First measurement of what it BUYS** (same endpoint, same 129 521-run corpus,
cap 1): **103 gap-sets -> 84**, identical demand universe (1 630/1 630 set
digests), 0 newly gapped, and the pass 34 % faster (1 621 s -> 1 069 s: a
coarser leaf is a shorter cube and a shorter blocking clause). The campaign's
own projection of "clears 71 of 103" was an over-count from a falsifier
flattened to a per-EXPRESSION B=0 set; measured per (leaf group, member) as
the rule specifies, 28 of the 103 witness leaves are touched at all. See
`results3/notifications_index/_COMPLETION_CAMPAIGN_20260910.md` §28.

Engine: `src/concolic_engine/coverage.py`
(`profile_literal_masks`, `prefix_match_mask`, `conjunction_foreclosed`,
`render_prefix`, the `foreclosure_conjunctions` argument, step 5c′, the
emission side in step 6's witness loop and the closed-prefix test in its
cube census, `conjunction_foreclosures_to_dict`). Gate:
`src/end_to_end_completion_checker/assumption/assumption_checker.py`
(`_test_conjunction_foreclosure`). Tests:
`src/test_conjunction_foreclosure.py` (13; suite 283 -> 296 green).

### §16f — foreclosure over a SUB-CONJUNCTION (decided 2026-09-13, OPT-IN)

**Decision record, owner ruling.** *"An inference of an already-accepted
kind, derived from the corpus, self-falsifying, nested-subset-provable and
gate-testable, is implemented under that discipline — not parked."* §16e
widened §16b from one literal to the leaf group's EXACT gate prefix `P`, and
wrote down two limits: `C` must be `P` entire, and *"gates are never
conjunction-foreclosed"*. On notifications_index those two lines ARE the
residue — all 60 remaining gap-sets, measured per (leaf, member) on the
corpus (campaign §31.5/§31.6a):

* 31 leaves each have exactly one never-evaluated member, and **39/39 of the
  foreclosures that explain them condition on at least one NON-GATE member,
  0/39 on gates alone** (`_c18_minimal_cond.json`; widths 1/2/3, A = 3-110 167,
  B = 0 — e.g. `notifications_rows > 1 ∧ find_by_1_not_found == True`
  forecloses `devise_user_first_1_person_profile_not_found`, A = 108-128);
* the 28 A = 0 leaf groups are ONE gate, `..._row_target_mentions_container_
  not_found`, which is foreclosed under a PROPER SUB-conjunction of its own
  gate prefix — the eight dispatch literals alone, **A = 9 270, B = 0**, with
  the mechanism in `targets.rb:872-901` / `:1517-1529` (an out-of-range
  `SYM_NOTE_TYPE_PROFILE` renders a Post-target notification and never reads
  `target.mentions_container`). Declaring it as a Z3 constraint is not
  available — over a free Bool the two directions collapse to
  `Not(out-of-range)`, which 9 270 runs refute (§31.3, §31.6a).

§16f is the same INFERRED relation, one conjunction narrower. It is the
fifth after co-evaluation (§16), foreclosure (§16b), confinement (§16c) and
gate-conjunction foreclosure (§16e): nothing is declared, no `AssumptionSet`
entry exists, and it re-derives itself on every corpus.

#### The rule

> For a demand set `S` and one of its leaves, walk the leaf's members in the
> set's own order (the §16b gate-first topological order, unchanged). Let
> `acc` be the literals FIXED SO FAR. A member `d` is **FORECLOSED under `C`**
> iff `C ⊆ acc`, `|C| <= W`, **(a)** at least one profile matches every
> literal of `C` (`A(C) > 0`) and **(b)** no matching profile evaluates `d`
> (`B(C, d) = 0`). `C` is the MINIMUM-cardinality such set. A foreclosed
> member is not part of the leaf and **contributes no literal downstream**.

`W = foreclosure_conjunction_width`, default 3. "Matches" is §16b's and
§16e's own per-literal reading, so `A` and `B` can only be OVERSTATED and a
`B = 0` verdict stays conservative. Two things §16e forbids and this allows,
and they are exactly the two halves of the residue: **`C` may contain
NON-GATE literals**, and **`d` may itself be a GATE**.

**The walk order is the definition, not a tie-break.** `C` is drawn from the
literals fixed EARLIER, never from the whole cube. Widening it to the whole
cube would let two members foreclose each other in a cycle and the leaf would
not be well defined; restricting it to a prefix makes the drop decision a
function of the prefix alone, which is what makes the leaves a decision tree.
The order is the one `restrict_foreclosures` already produces — no member
moved, so §16b and §16e are untouched.

#### Both sides move, as §16e's did

The emission side (`_next_untried_combo`'s cube) AND the closed-prefix test
that lets a PARTIAL run block. If only the first moved, a leaf the inference
coarsened could never acquire its clause and would be reported missing for
ever — the defect §16e's `test_the_blocking_side_reads_its_own_shapes_gate_
list` pins. On the blocking side the walk runs over the profile's own
assignment and tests **only the UNEVALUATED members**; that is not a
shortcut but a theorem: every literal of `acc` is one this profile matches,
so the profile is in `A(C)` for any `C` drawn from it and a member it
evaluates has `B >= 1`. A member recorded BOTH ways contributes no literal
(as a both-sided gate does not join `P`), which can only shrink `acc` and
foreclose less — the conservative direction. One further consequence: a set
with NO §16b gate at all used to be skipped outright on the blocking side;
§16f's conditioning set need not contain a gate, so that skip is lifted with
the flag on.

#### Nesting — and what it costs

The drop set is §16e's **union** the walk's: §16e's `F(P)` is computed first,
on the unchanged §16b cube, and its members leave the cube before the walk
starts (so they contribute no literal either). Therefore

    §16f  ⊆  §16e  ⊆  foreclosure-aware (§16b)  ⊆  set-level (§16)
         ⊆  complete-graph

**by construction, not by argument**, with each §16f leaf a SUB-CUBE of the
§16e leaf it came from. Old-complete still implies new-complete and **Rule T
is NOT triggered**. Pinned by `src/test_subconjunction_foreclosure.py::
test_demand_is_nested_16f_16e_16b_16` — 60 random corpora, four settings,
leaves summed over every demand set

    §16 4 288  ->  §16b 2 293  ->  §16e 2 246  ->  §16f 1 903

with `⊆` checked on EVERY leaf and 75 sets shrinking on a sub-conjunction —
and by `::test_missing_is_nested_through_the_checker` (the same through the
checker: 54 of 60 corpora fire, `⊆` holds on every reported cube, the other 6
report identically to the §16e pass).

**And the price, stated rather than hidden.** §16e could promise its leaves
were pairwise INCOMPATIBLE, because it never drops a GATE: two leaves always
disagree on the first gate they diverge on. §16f drops gates — that IS the
28 — so a leaf may now be a strict SUB-CUBE of a sibling: the sibling's extra
literal was foreclosed under a gate the coarser leaf no longer carries.
Measured at **27 of 13 914 leaf pairs (0.19 %) over 40 random corpora**, and
the relation is always containment, never a crossing
(`::test_coarsened_leaves_are_nested_never_overlapping`).

That cannot reach a verdict, and the reason is structural:

1. the BLOCKING side never emits a coarsened clause. A run's clause is its
   EXACT evaluated assignment (`fixed_outcomes` is every single-outcome
   member it evaluated); the leaf structure only decides whether a PARTIAL
   run qualifies to contribute one at all, and every drop it uses is
   certified against literals that run itself matched;
2. `complete` is decided by a demand set's FIRST query, whose clauses are all
   run-derived. A witness clause is added only AFTER a `sat`, i.e. after the
   set is already incomplete.

So a contained pair can only change WHICH witness is printed — which §16b and
§16d already record ("the reported missing list is a LOWER bound at every
intermediate state, and only the completeness verdict is a claim"). The
ground-truth check is `::test_no_leaf_of_a_complete_pass_is_unwalked`: over
35 corpora on which the §16f checker returns `complete`, all 489 leaves of
every demand set were walked by a run of that corpus.

#### Falsifier — the inference's own test

**Any run that matches `C` and evaluates `d`.** Same universal over the corpus
as §16b's clause (b) and §16e's, one sub-conjunction wide, so it is
self-re-deriving: the run removes the foreclosure on the next pass with
nothing to retract by hand. Monotone in the same way, provisional in the same
way — `CoverageResult.subconjunction_foreclosures_provisional` follows
`tree_complete`, `summary()` prints PROVISIONAL, and the combination claim
stays refused while the tree layer is incomplete. **Precondition unchanged**:
a sub-conjunction foreclosure never excuses a branch.

**`A(C) = 0` infers nothing, and cannot even be returned.** The search prunes
every branch whose running mask hits zero, so a conjunction the corpus has
never walked can never license anything — it stays in §16e's
`unmatched_gate_conjunctions` report class, whose demand is intact. What DOES
change there is that a gate the corpus never realises under a sub-prefix is
now foreclosed rather than demanded, so that class SHRINKS where its A = 0
was an artefact of an unrealisable gate literal.

#### Cost — a bounded SET COVER, not `C(n, k)`

`minimal_subconjunction` reads the demand as a cover: with `R` the profiles
that evaluate `d`, `A(C) = ⋂ takes[l]` and the requirement is
`A(C) ∩ R = ∅ ∧ A(C) ≠ ∅` — i.e. the complements of the chosen literals must
COVER `R`. Iterative deepening over that cover (take one profile still
evaluating `d`, branch only on the literals it does NOT match) is exact and
minimum-cardinality, with a branching factor set by the literals that exclude
one profile rather than by the whole list. Candidates are deduplicated by
profile mask and literals that constrain nothing or everything are dropped.
`foreclosure_conjunction_budget` (20 000 nodes) caps it; exhausting it returns
NO inference, which leaves the member in the leaf. Results are memoized per
(fixed literals, member) — leaves share their prefixes across sets.

#### Opt-in, and why

`CoverageChecker(foreclosure_subconjunctions=True)`, **default False**, and
it IMPLIES `foreclosure_conjunctions` (the union above). Every summary
written before 2026-09-13 reproduces byte-for-byte with both flags unset, and
a `foreclosure_conjunctions=True` pass is byte-identical to a pre-§16f one —
which is what keeps the closed endpoints closed without re-arguing them. The
flag AND the width are folded into the step-6 CHECKPOINT key (`params`, added
only when §16f is on, so an existing §16e checkpoint still replays), and the
per-witness `subconj` record is part of the checkpoint because the foreclosed
members cannot be read back off a pruned cube.

#### The gate test — derived, in the §16e style

`assumption_checker.py::_test_subconjunction_foreclosure`, dispatched on the
inferred type `SubconjunctionForeclosureAssumption` that
`assumptions_to_dict()` emits (marked `inferred: True`, carrying `C` as both
`conditioning` and `gates` so ONE probe serves both kinds). Base = the
richest snapshot that records `d` together with every literal of `C`; probe =
that snapshot's seeds with every literal whose recorded outcome differs from
`C`'s flipped, at the runtime (ordinal) key (X10). **FAIL** = the probe
realises `C` and RECORDS `d`; **PASS** = it realises `C` and leaves `d`
unevaluated; **NOT-TESTABLE** = it does not REALISE `C` (the realised-value
rule), no snapshot records the member with the literals, no flip value can be
inferred, or the replay produced no dump; **NOT-COMPARABLE** = a flip changed
what an aliased ordinal resolved to. The verdict-row dedup already carries
`prefix`, so two foreclosures of the same member under different conjunctions
are two claims. Cost is bounded by `W`: at most `W` literals can need
flipping.

**First run (notifications_index, 2026-09-13):** the endpoint's 24 inferred
(C, d) classes, one representative each, 20 distinct probes —
`PASS 12, FAIL 0, ERROR 0, NOT-TESTABLE 12, NOT-COMPARABLE 0`, 38 m 03 s, peak
3 367 MB (of which ~29 min is `corpus_index` over 306 251 dumps at 165-171
dumps/s). Nothing was refuted. The PASSes cover every class that carries the
result — all 4 of the `devise ... person_profile_not_found` family, 3 of the 4
`row_target_mentions_container_not_found` **GATE** classes (the inference the
28 A = 0 sets rest on), and all 4 `exists__5` classes — each on a probe that
REALISED the conjunction after flipping 1-3 literals from a base that DOES
record the member. Every NOT-TESTABLE is the realised-value rule with the same
unmet literal shape (`(SYM_NOTE_TYPE_PROFILE == 3) :: not_taken`, x11): the
base is chosen BECAUSE it records the member, which on that endpoint means the
dispatch IS that index, and no inferable flip moves it off. A NOT-TESTABLE is
not a licence.

**First measurement of what it BUYS** (notifications_index, the same
131 186-run corpus as the §16e verdict, cap 1): **60 gap-sets -> 11**, 49
closed, 0 newly gapped, identical demand universe (1 630/1 630 set digests),
`unmatched_gate_conjunctions` **8 -> 0** — the A = 0 class was one
unrealisable GATE and §16f forecloses it. 24 (C, d) classes over 10
conditioning sets, all `|C| <= 3`. The pass costs +55 % on the coverage phase
(1 253 s -> 1 938 s) at the same peak RSS. See
`results3/notifications_index/_COMPLETION_CAMPAIGN_20260910.md` §32.

Engine: `src/concolic_engine/coverage.py` (`minimal_subconjunction`,
`_SubconjBudget`, `_MISS`, the `foreclosure_subconjunctions` /
`foreclosure_conjunction_width` / `foreclosure_conjunction_budget` arguments,
step 5c″ with `_subconj` and `_record_subconj`, the walk in step 6's witness
loop and in its cube census, the `subconj` checkpoint record,
`subconjunction_foreclosures_to_dict`). Gate:
`src/end_to_end_completion_checker/assumption/assumption_checker.py`
(`_test_subconjunction_foreclosure`). Tests:
`src/test_subconjunction_foreclosure.py` (18; suite 296 -> 314 green).

### §16g — WELL-FOUNDED drops: `C` from the whole leaf (decided 2026-09-14, OPT-IN)

**Decision record, owner ruling**, continuing the family §16b -> §16e -> §16f
under the same discipline: *"an inference of an already-accepted kind, derived
from the corpus, self-falsifying, nested-subset-provable and gate-testable, is
implemented — not parked."* §16f widened §16e from the leaf's EXACT gate
prefix to any SUB-conjunction of it, and wrote down the one limit it kept:
`C ⊆ acc`, the literals fixed EARLIER in the walk, *"the walk order is the
definition, not a tie-break, because two members could otherwise foreclose
each other in a cycle and the leaf would not be well defined."*

On notifications_index that line IS the residue (campaign §37, C25):

* four blocking sets survive 2 207 constructed runs with **0 of 865 leaves
  realised**, and `B(C, d)` is MONOTONE NON-INCREASING in `C`, so the FULL
  walk prefix is the strongest conditioning set any subset can reach — and
  `B(full prefix, d) > 0` for **all 46 members**, smallest `B = 1`. Confirmed
  against the shipped `minimal_subconjunction` at every width from 1 to the
  leaf width and at budgets 20 000 AND 10^9: `dropped = 0` everywhere,
  identical at both budgets. **§16f cannot foreclose these at any width, and
  the budget never bites.**
* each of the four leaves DOES have a width-3 `C` with `A > 0, B = 0` when
  `C` may be drawn from the WHOLE cube. Its literals simply sit LATER in the
  walk. Well-founded on 4 of 4 (no `C` literal belongs to a dropped member;
  the one ill-founded case, leaf 1 pos 10, is excluded), and the REDUCED
  leaves are walked by runs already in the corpus: `A(reduced)` =
  8 / 177 / 23 / 23 against `A(full)` = 0 / 0 / 0 / 0.
* not a walk-ORDER artefact: two of the three dropped members are §16b GATES
  whose conditioning sets are mostly NON-gates, and a gate-first topological
  order can never put a non-gate into a gate's `acc`; two of the four sets
  contain no gate at all.

§16g is the same INFERRED relation with `C ⊆ acc` replaced by a foundedness
condition. It is the sixth after co-evaluation (§16), foreclosure (§16b),
confinement (§16c), gate-conjunction foreclosure (§16e) and sub-conjunction
foreclosure (§16f): nothing is declared, no `AssumptionSet` entry exists, and
it re-derives itself on every corpus.

#### The rule

> For a demand set `S` and one of its leaves, let `M` be the cube that
> survives §16b's pruned walk, §16e's gate-prefix drop and §16f's walk
> (unchanged, in that order). A member `d` of `M` is **DROPPED under `C`**
> iff `C` is a set of literals **of the same leaf** with `|C| <= W`,
> **(a)** `A(C) > 0`, **(b)** `B(C, d) = 0`, and **(c)** every literal of `C`
> belongs to a member that is itself **KEPT**. `C` is the
> MINIMUM-cardinality such set. The drop set is the **LEAST FIXED POINT** of
> that condition, and it is APPLIED only if the reduced leaf is matched by
> at least one profile (`A(reduced) > 0`).

`W = foreclosure_conjunction_width`, default 3 — unchanged, and it is enough:
every `C` above has `|C| = 3`. "Matches" is §16b's, §16e's and §16f's own
per-literal reading, so `A` and `B` can only be OVERSTATED and a `B = 0`
verdict stays conservative.

#### The fixed point, and why it is UNIQUE (clause (c) is not a filter)

Clause (c) refers to the answer it is part of, so it has to be resolved, not
evaluated. Write, for a subset `D` of `M`,

```
    cond(d, K)  ==  some C within lits(K - {d}) has |C| <= W, A > 0, B = 0
    K(D)        ==  M - {d' : cond(d', M - D)}        (the DEFINITELY kept)
    Phi(D)      ==  {d : d not pinned, cond(d, K(D))}
```

`cond` is monotone in `K` — a bigger pool can only offer more conditioning
sets — so `K` is monotone in `D` and **`Phi` is monotone in `D`**. On the
finite lattice `2^M`, Knaster–Tarski gives a UNIQUE least fixed point,
reached by Kleene iteration from the empty set. Each round computes a SET and
never chooses between candidates, and a monotone operator's chaotic
(asynchronous) iteration converges to the same least fixed point whatever
order its elements are applied in — so **the answer does not depend on the
order the members are visited in**, which is exactly what §16f bought with
its prefix and what §16g has to buy some other way. Pinned with a
shuffled-order differential: 400 random leaves x 4 shuffles each plus a
one-member-at-a-time chaotic iteration, and 200 random profile tables through
the REAL `minimal_subconjunction` (`src/test_wellfounded_drops.py`, tests
`test_the_fixed_point_is_order_independent_on_random_leaves` and
`test_the_fixed_point_is_order_independent_on_real_bitsets`).

**"Iterate dropping until stable" is NOT well defined, and that is the whole
reason for the fixed point.** Two members that foreclose each other —
`C(a) = {lit(b)}`, `C(b) = {lit(a)}` — have TWO stable answers, `{a}` and
`{b}`, depending on which is visited first; both are individually valid. The
least fixed point drops NEITHER. That is the canonical choice and it is the
CONSERVATIVE one: keeping a member keeps its demand, and §16g may only ever
remove demand it has earned.

**Validity — every drop is justified by a KEPT member — is a theorem, not a
check.** By induction along the Kleene chain: `K(D_k)` and `D_k` are
disjoint (a member of `K(D_k)` is one with NOT `cond(d, M - D_k)`, while the
hypothesis gives every member of `D_k` `cond(d, M - D_k)`), hence `K(D_k)`
sits inside `M - D_{k+1}` and every `d` in `D_{k+1}` has
`cond(d, M - D_{k+1})`. At the fixed point each drop's own `C` is drawn from
`K(D*)`, a set of members none of which is dropped.

#### Soundness — why conditioning on LATER literals is legitimate

The demand is for the WHOLE cube. A run **realises** a leaf only by
evaluating every one of its members with those outcomes; such a run therefore
matches every literal of the cube, including the ones that come later in the
walk than `d`. So if `B(C, d) = 0` for some `C` inside the cube:

> in runs satisfying the rest of this cube, `d` is never evaluated; therefore
> this cube cannot be realised with `d` in it; therefore `d` is not part of
> this leaf.

Nothing in that sentence mentions an order. The walk order was never part of
the EVIDENCE — it was §16f's device for making the drop decision well
defined, and §16g replaces the device, not the evidence. The
minimum-evidence question has §16b's answer, one conjunction wider: ONE run,
and only because of tree completeness (`tree_complete` says every satisfiable
branch outcome has been explored, so "no `C` run reaches `d`" cannot be
explained by `C` being undriven). `A(C) = 0` infers nothing and cannot even
be returned — the search prunes every branch whose running mask hits zero.

**Why that does NOT license a drop resting on a dropped member.** Take the
chain literally. Step 1 drops `d1` under `C1` inside `F` (the full cube): a
run realising `F` matches `C1`, so it cannot evaluate `d1`, so `F` is
unrealisable and the demand becomes `F - {d1}`. Step 2 drops `d2` under `C2`
inside `F - {d1}`: a run realising `F - {d1}` matches `C2`, so `F - {d1}` is
unrealisable with `d2` in it, and the demand becomes `F - {d1, d2}`. Now
suppose `C1` had named `d2`. The coarsened leaf `F - {d1, d2}` has four
sub-cases on whether `d1` and `d2` are evaluated; steps 1 and 2 kill "both"
and "d2 only", but **"d1 only"** — the cube `F - {d2}` with `d1`'s literal —
was never touched, because `C1` is not contained in it and a run realising it
need not match `C1`. Dropping `d1` there deletes the demand for BOTH of
`d1`'s outcomes with no evidence at all. Clause (c) is exactly the condition
that forbids this, and the fixed point is how it is resolved.

**The counterexample shape, concretely.** Two arms of a dispatch, `a` and
`b`, co-evaluated somewhere but mutually exclusive where it matters: no run
with `b` taken evaluates `a`, and no run with `a` taken evaluates `b`. Then
`C(a) = {lit(b)}` and `C(b) = {lit(a)}` both have `A > 0, B = 0`. Dropping
both leaves a cube that says nothing about either — and that cube IS
realisable, by every run that walks one arm. The two real leaves ("a alone"
and "b alone") lose their demand silently, and the endpoint reports complete
having never driven one of the arms. §16g drops neither
(`test_the_lfp_is_the_definition_and_a_naive_walk_is_not`), and the
one-step-longer form — `b` droppable only under `a`'s literal while `a` is
droppable under a member nothing can drop — keeps `b`
(`test_a_drop_may_not_rest_on_a_dropped_member`).

#### The PIN, and the `A(reduced) > 0` GUARD — both load bearing

**Pin.** §16e's drop of `m` rests on every gate of `P` being IN the cube, and
§16f's drop of `m` rests on every literal of its `C` being in the cube. §16g
runs AFTER both, so it could take one of those out from under them and leave
a drop unfounded — the same defect as above, across stages. Every member
whose literal justified an APPLIED §16e or §16f drop on this leaf is
therefore PINNED kept. This also makes "§16g drops a SUPERSET of §16f's" true
by construction: §16g only ever ADDS, it can never withdraw an earlier drop,
which is what the nesting needs. (Measured on the four notifications leaves:
the pin is EMPTY on all four — their own `conj` record carries `F = []` and
no `subconj` class applies to their cube — so it does not stand in the way of
the residue it was written for. `_c26_engine_probe.py` checks this rather
than assuming it.)

**Guard.** Without it §16g is not a coarsening at all. Measured on random
corpora 2026-09-14: a drop whose conditioning literal sits LATER in the walk
can produce a leaf that CROSSES a prefix the corpus has already closed — the
partial run that covered the §16f leaf blocks it through a literal §16g has
just removed, and a covered region comes back as a gap. So the drop set is
applied only if some profile matches every literal of what is LEFT — §16e's
own "`A = 0` is absence, not evidence" applied to the LEAF. `A` is monotone
NON-DECREASING as literals leave the cube, so `A(reduced) = 0` implies every
partial reduction is 0 too and the §16f leaf it came from was ALREADY
unmatched: refusing the whole drop set loses nothing, and it is a function of
the leaf, so it is order-independent. On the BLOCKING side the guard is
VACUOUS — the reduced cube there is the blocking profile's own assignment,
which that profile matches by construction — which is what keeps the two
sides' leaf structures consistent.
(`test_the_guard_refuses_a_leaf_the_corpus_never_matched`.)

#### Both sides move, as §16e's and §16f's did

The emission side (`_next_untried_combo`'s cube) AND the closed-prefix test
that lets a PARTIAL run block. If only the first moved, a leaf the inference
coarsened could never acquire its clause and would be reported missing for
ever — the defect §16e's `test_the_blocking_side_reads_its_own_shapes_gate_
list` and §16f's `test_both_sides_move_the_blocking_test_too` pin; the §16g
analogue is `test_the_blocking_side_moves_too` (the partial run blocks
NOTHING under §16b/§16e/§16f, because the member it does not evaluate is
FIRST in the walk and its `acc` is empty; under §16g it blocks the coarsened
leaf, and that is the only reason the endpoint closes).

On the blocking side the FOUNDEDNESS is free and needs no fixed point, and
that is a theorem rather than a shortcut: the conditioning pool is the
profile's own single-outcome literals — members it EVALUATED — and an
evaluated member can never be dropped (the profile is in `A(C)` for any `C`
drawn from literals it matches, so `B >= 1`). Every conditioning literal
therefore belongs to a KEPT member by construction. The pool is also a
SUPERSET of every `acc2` the §16f walk reaches, so the blocking side coarsens
at least as much as §16f did — and at least as much as the emission side's
fixed point, whose `K(D*)` is a subset of the leaf's surviving members, all of
which a profile realising that leaf evaluates.

#### Nesting — REDONE, and the one part of §16f's claim that does NOT survive

"§16g inside §16f" is no longer true "by construction from a prefix". What is
proved instead, on 60 random corpora built around the §16g shape and set-wise
on real endpoint data, is the SUB-CUBE relation on EVERY leaf:

```
    §16g leaf  <=  §16f leaf  <=  §16e leaf  <=  §16b leaf  <=  flat assignment
```

with the map total in both directions (every §16f leaf is coarsened by at
least one §16g leaf, so nothing is invented) —
`test_demand_is_nested_16g_16f_16e_16b_16`.

**Rule T is NOT triggered, and this is the claim:** `complete` is decided by
each demand set's FIRST Z3 query, whose clauses are ALL run-derived (a witness
clause is only added after a `sat`, i.e. after the set is already incomplete).
§16g's blocking side coarsens at least as much as §16f's, so the clause set
can only GROW, so a first query that was UNSAT stays UNSAT: **§16f-complete
implies §16g-complete**, measured over 240 random corpora
(`test_a_16f_complete_pass_stays_complete`), and on real data by reproducing
people_stream and comments_index with the flag ON
(`results3/_16g_byteid_20260914/`): COMPLETE=True, MISSING=0, BLOCKING=0 on
both, unchanged — people_stream firing 3 §16g classes on the way and
comments_index none.

**What does NOT survive, stated rather than hidden.** §16f could promise
`count(§16f) <= count(§16e)` and that every printed witness lay inside a
printed §16e witness. §16g can promise NEITHER:

1. its drop set is a function of the leaf AND of the pins its §16e/§16f
   justifications leave, so two assignments with the SAME §16f leaf can
   coarsen it differently and one §16f leaf can map to SEVERAL §16g leaves.
   Every one of them is a strict SUB-cube of that leaf, so the demand is
   WEAKER — a run covering the §16f leaf covers all of them — but the leaf
   count is not a coarsening statistic any more;
2. a coarsened cube blocks every extension of itself, so WHICH sibling of a
   nested pair gets PRINTED depends on the order Z3 returns models in. Every
   §16g cube lies inside a §16f LEAF; it need not lie inside a §16f
   *reported* cube (`test_missing_is_nested_through_the_checker`).

Both are consequences of what §16b and §16d already record — *"the reported
missing list is a LOWER bound at every intermediate state, and only the
completeness verdict is a claim"* — and nothing here weakens that verdict.
The ground-truth check is `test_no_leaf_of_a_complete_pass_is_unwalked`: over
the corpora on which the §16g checker returns `complete`, every leaf of every
demand set was walked by a run of that corpus.

#### Falsifier — the inference's own test

**Any run that matches `C` and evaluates `d`.** The same universal over the
corpus as §16b's clause (b), §16e's and §16f's, so it is self-re-deriving:
the run removes the drop on the next pass with nothing to retract by hand.
Monotone in the same way, provisional in the same way —
`CoverageResult.wellfounded_drops_provisional` follows `tree_complete`,
`summary()` prints PROVISIONAL, and the combination claim stays refused while
the tree layer is incomplete. **Precondition unchanged**: a well-founded drop
never excuses a branch. `_c25_mincond.py` and `_c25_backward.py` ARE that
test over any dump list (~5 min over 135 k dumps), and
`_c26_engine_probe.py` cross-checks the SHIPPED engine against them
(4 of 4 leaves AGREE on the drop set, on every `C` and on every `A`, at
budget 20 000 and 10^9).

#### Opt-in, and why

`CoverageChecker(foreclosure_wellfounded_drops=True)`, **default False**, and
it IMPLIES `foreclosure_subconjunctions` (hence `foreclosure_conjunctions`).
Every summary written before 2026-09-14 reproduces byte-for-byte with the
flag unset — proved on the two CLOSED endpoints against the PRE-EDIT engine
(`results3/_16g_byteid_20260914/`: people_stream and comments_index summary
JSONs identical to the byte, logs identical modulo peak RSS and wall time).
The flag is folded into the step-6 CHECKPOINT key **only when it is on**, so
an existing §16e/§16f checkpoint still replays untouched; the per-witness
`wf` record is part of the checkpoint, because the dropped members cannot be
read back off a pruned cube.

#### The gate test — the §16f probe, unchanged

The probe shape does not move: `C` is still at most `W` literals to flip from
a base that RECORDS `d`, and a member that gets recorded REFUTES the
inference. So the classes are emitted as the SAME
`SubconjunctionForeclosureAssumption` type `assumptions_to_dict()` already
produces, carrying `C` as both `conditioning` and `gates`, and marked
`wellfounded: True` / `section: "16g"` so a report can separate the two
claims. `_test_subconjunction_foreclosure` therefore needs NO functional
change; the staged diff only carries the marker into the verdict row.

Engine: `src/concolic_engine/coverage.py` (`wellfounded_drop_set`, the
`foreclosure_wellfounded_drops` argument, step 5c-triple-prime with
`_record_wf`, the fixed-point stage in step 6's witness loop and the
whole-pool walk in its cube census, the `wf` checkpoint record,
`wellfounded_drops_to_dict`). Gate:
`src/end_to_end_completion_checker/assumption/assumption_checker.py`
(`_test_subconjunction_foreclosure`, marker only — STAGED, not merged: that
file is under a batching rule while the posts_show confinement gate runs).
Tests: `src/test_wellfounded_drops.py` (22; suite 363 -> 385 green).

## 17. X12 (2026-09-14) — a derived test built its probe from ONE base, so its
## NOT-TESTABLEs and its PASSes were both artefacts of that base

> **READ THIS FIRST — THE BIAS RUNS THE OTHER WAY.** "The gate was broken"
> reads instinctively as "it licensed things it should not have". **It did
> not.** A single base can only ever FAIL to build the refuting run; it cannot
> manufacture one. So the defect's effect is to turn refutable claims and
> testable claims alike into NOT-TESTABLE — and under §24.4 a NOT-TESTABLE is
> withdrawn, not licensed. **The defect made the gate DEMAND TOO MUCH, not
> license too much.** Measured on posts_show: 87.5 % of its NOT-TESTABLEs are
> testable from another base and 34 of 40 sampled PASS on the base-dependent
> criteria, so the 495 pairs `_p32` withdrew as untestable are mostly
> RECOVERABLE and the booked 4 093 residue SHRINKS. The exceptions are real
> but small and go the other way: 1 of those 40 is a genuine refutation the
> shipped gate missed, and on notifications_index's §16g layer — where the
> inference reaches furthest past the walk prefix — 18 of 24 were refutable.
> Every PASS already on disk was *weakly evidenced*, not wrong: 40 of 40
> sampled posts_show PASSes and 91 of 91 sampled closed-endpoint PASSes held
> under 8 bases, and none was refuted.

**Class: a gate defect that weakens prior verdicts** — the same shape as X10
(the flip was written at the runtime key and read back at the canonical key,
so the probe never ran on any ordinal-canonicalizing endpoint) and X11 (the
flip-both independence probe detects only ADDITIVE dependence and is blind to
REMOVAL). In each case the negative verdict is a fact about HOW the test built
its one probe, not about the claim.

### The defect

Every derived test in `assumption_checker.py` selected its base with
`pick_snapshot_with(batch, exprs, dims)` — **the single richest-seed snapshot
that recorded the claim's expressions** — and built its probe from it:
`_test_conjunction_foreclosure` / `_test_subconjunction_foreclosure` (§16e,
§16f and the §16g drops that ride on them), `_test_confinement`'s
COMPOSITION (criteria (i)-(v) and (viii)), the `IndependenceAssumption`
flip-A/flip-B/flip-both probe, and the untracked-path probe;
`SymbolicConstraintAssumption` did the same through `pick_live_snapshot`.

The probe is DERIVED from the base — which literals still need flipping, which
seed keys exist to flip them with, which outcome the base recorded. So every
one of these verdict reasons is a statement about the BASE:

```
  "the probe did not REALISE the gate conjunction — seeding is not realising"
  "flip-A did not flip A (unevaluated): dead knob, no evidence"
  "snapshot records a member both ways — no single base outcome to flip"
  "cannot infer a flip value from the recorded PC"
  "value not realised: seeded 2, minted 4"
  NOT-COMPARABLE "flip-A: 4 read as comments/43acf058 in the snapshot, ..."
```

None of them is a statement about the claim, and a **PASS** earned on one base
is not a statement about the claim either: another base may put the same pair
in a context where the combination does produce the shape, or where the
member IS evaluated under `C`.

### The measurement — notifications_index C27 (`_COMPLETION_CAMPAIGN_20260910.md` §39)

`_c27_fals.py` changed exactly one thing about the shipped probe: instead of
one base it enumerated EVERY dump of the corpus recording the member `d`
together with all of `C` (1 030 - 1 807 candidates per class), ranked by seed
richness with scenario diversity first, took up to K = 8, and applied the SAME
flips and the SAME verdict helpers (`outcomes_of` / `recorded` /
`_reading_changed`) per base.

```
                        shipped gate (1 base)      multi-base (K = 8)
  §16g   24 classes     NOT-TESTABLE 24/24         FAIL 18, N-T 6   (78 refuting replays)
  §16f   28 classes     (C19: PASS 12, N-T 12)     FAIL  6, PASS 16, N-T 6
  §16e   89 classes     —                          PASS 89, FAIL 0  (450 confirming replays)
```

**18 classes the shipped gate could not test were refuted by runs the corpus
could reach the whole time.** One refutation was hand-verified with no verdict
helper at all (`_c27_fals_verify.py`): the replay records all three `C`
literals with `C`'s outcomes AND evaluates the member — verbatim the falsifier
§16g names.

### The rule

> A derived test probes **K bases**, not one. `ACHK_BASES` (default **8**).
>
> * **A refutation from ANY base is a FAIL.** One run that matches the claim's
>   premise and contradicts its conclusion is the falsifier; that seven other
>   bases could not build such a run is not evidence against it.
> * A **PASS** requires that no probed base refuted AND that at least one base
>   REALISED the premise. The verdict row records `bases_probed` and
>   `bases_realising`: **a PASS from 1 realising base is materially weaker
>   evidence than a PASS from 8, and the record must say which.**
> * **NOT-TESTABLE only when NO probed base realised** the conjunction or the
>   flip. The realised-value rule is unchanged — seeding is not realising, and
>   a base that did not realise the premise vouches for nothing.
> * NOT-COMPARABLE keeps its own rank: a reading that changed under an alias
>   is reported as that, never laundered into "untestable".
>
> **Base ordering.** The richest-seed snapshot FIRST — byte-identically
> `pick_snapshot_with`'s answer, so `ACHK_BASES=1` reproduces the old test
> exactly — then round-robin over the remaining SCENARIOS, richest within
> each. Scenario is the corpus's own partition of context: two dumps from one
> scenario differ in seeds, dumps from different scenarios differ in which
> code the request reaches at all, and it is the second kind of difference
> that decides whether a flip is realisable. §39's refuting bases were spread
> across scenarios.

### Why K = 8 — measured, from §39's own per-base records

Re-reading `_c27_fals_{F1,16f,16e}.json` as a function of the budget (the
cumulative class verdict over the first K bases):

```
  §16e (89)   K=1: PASS 35, N-T 54    K=2: 75/14   K=4: 83/6   K=6: PASS 89, N-T 0
  §16f (28)   K=1: FAIL 5, PASS 12, N-T 11        K=2: FAIL 6  K=4: PASS 13
              K=5: PASS 14   K=7: PASS 16, N-T 6   K=8: no change
  §16g (24)   K=1: FAIL 18, N-T 6   (unchanged through K=8)
```

The refutation curve saturates early (all §16g refutations at base rank 1
under that ordering, §16f's last at rank 2). **It is the REALISING curve that
needs the budget**: the first base that realised the premise was at rank 6 for
6 of §16e's classes and at rank 7 for 2 of §16f's. Nothing moved between K=7
and K=8 across all 141 classes, so **8 is the first budget at which the
marginal base bought nothing** — the measured plateau, plus one.

### Cost — and the shape that makes it affordable

Multi-base multiplies the BASE-DEPENDENT probes by up to K. It multiplies
nothing else, and on the expensive gate that is almost all of the cost:

* `_test_confinement`'s criteria **(vi)** (`_exhaustive_flip` over profile
  representatives) and **(vii)** (`_constructed_route`) are functions of the
  DECISION and the corpus, never of the composition base. They run ONCE, not
  once per base. On posts_show's 2026-09-14 gate they were ~107 000 of the
  111 241 probes (**96 %**); the composition is 3 probes per class.
* `run_declared` runs **two stages**: stage 1 probes ONE base for everything
  and settles every FAIL there (a refutation is decisive and needs no second
  opinion); stage 2 escalates only the PASSes, NOT-TESTABLEs and
  NOT-COMPARABLEs to `ACHK_BASES`. Stage 2 re-derives base 1, whose probes are
  recalled from the ProbeCache for free.

Projected on posts_show's own gate: 111 241 probes -> ~134 100 (+20.6 %:
3 x 7 extra composition probes for the 1 089 classes stage 1 could not
refute), i.e. ~30.9 h -> ~37 h. A foreclosure-only gate (§16e/§16f/§16g, no
(vi)/(vii)) is linear in K: §39 measured 12 distinct probes -> 84 for its 24
classes, 12 min of wall.

### Implementation

`src/end_to_end_completion_checker/assumption/assumption_checker.py`:
`pick_bases_with` (the ordered base list, memoized, purged on a corpus
rebuild), `pick_live_snapshots` (the same for the constraint test's live-key
selection), `_combine_bases` (the verdict rule and the `bases_probed` /
`bases_realising` / `bases_failing` / `bases_passing` / `base_verdicts`
record), the per-base helpers `_conjunction_foreclosure_once`,
`_confinement_composition`, `_independence_once`, `_untracked_once`,
`_symbolic_constraint_once` (each the shipped probe verbatim, with the base
handed in instead of picked), and the two-stage loop in `run_declared`.
`ACHK_BASES` env knob, default 8; `ACHK_BASES=1` is the old behaviour.

Tests: `src/test_multibase_gate.py` (20) — the §39 case as a regression (one
base NOT-TESTABLE, many bases FAIL, hand-checked against the shipped
helpers), one test per rule above, the ordering property (`bases[0]` is
`pick_snapshot_with`'s answer) for both selectors, the independence and
confinement second-base refutations, that (vi)/(vii) run once and not once
per base, and both halves of the escalation. Suite 391 -> 411 green.

### What this does to verdicts already on disk

A **FAIL** stands: it was earned by a run that refuted the claim, and more
bases can only add more of them. Everything else is weakened — but weakened
in a KNOWN DIRECTION. A PASS is weakened as EVIDENCE (it was vouched by one
realising base where the record now demands the count), and measurement so far
has not overturned one: 40 of 40 sampled posts_show confinement PASSes and 91
of 91 sampled closed-endpoint PASSes held at K = 8. A NOT-TESTABLE is not
weakened, it is mostly WRONG, and correcting it RETURNS licences rather than
removing them. Concretely:

* every **NOT-TESTABLE** is un-evidence, and §39 showed 18 of 24 of them were
  refutable;
* every **NOT-COMPARABLE** is a property of the one base's alias resolution;
* every **PASS** is a PASS from one realising base, which the new record would
  have marked as the weakest grade of PASS it can carry — the grade is now on
  EVERY verdict row (`bases_probed`, `bases_realising`, `bases_passing`,
  `bases_failing`, `base_verdicts`), including rows that probed no base at all,
  so "one realising base in the entire corpus" is legible without re-measuring.
  Six of people_stream's 30 PASSes and one of conversations_index's 32 are in
  exactly that position and are the ones to re-probe first if their corpus
  grows.

**The re-gate this implies is small, and it is not a repeat.** A FAIL needs no
revisiting and a PASS needs only a grade; what needs re-running is the
NOT-TESTABLE and NOT-COMPARABLE population — on posts_show that is the 495
withdrawn pairs, not the 1 363 classes.

### The blast radius, MEASURED (2026-09-14)

Every derived test is single-base, so the reach is every gate verdict on disk,
not only §16e/§16f/§16g. The verdicts whose REASON is a property of the one
base, counted on the live verdict files:

| endpoint / file | class | PASS | N-T | N-C | FAIL | how much of the non-FAIL is a base artefact |
|---|---|---|---|---|---|---|
| `posts_show/_p26_gate_results.json` | Confinement (1 363) | 785 | 243 | 61 | 274 | **243/243** N-T are "flip did not take" (202) or "records a member both ways" (41) — both facts about the chosen snapshot; **61/61** N-C are that snapshot's alias reading; 484 of the 785 PASSes had **zero** profiles in (vi), so they rest on one base alone |
| `posts_show/_p30_gate_P30.json` | Subconjunction (26) | 3 | 16 | 2 | 5 | same shape as §39 |
| `notifications_index/_assumption_results.json` | mixed (2 074) | 1 874 | 89 | 33 | 78 | **40/40** ConjForeclosure + **12/12** Subconj N-T are "seeding is not realising"; 8 of 37 SymbolicConstraint N-T are "value not realised"; **33/33** Independence N-C are the base's alias reading |
| `notifications_index/_c27_gate_C27G.json` | Subconj §16g (24) | 0 | 24 | 0 | 0 | **24/24** — §39 refuted 18 of them from other bases |
| `notifications_index/_c19_gate_C19.json` | Subconj §16f (24) | 12 | 12 | 0 | 0 | multi-base on the §16f layer: FAIL 6, PASS 16, N-T 6 |
| `comments_index/_assumption_results.json` | Independence (3 648) | 3 648 | 0 | 0 | 0 | every PASS single-base |
| `conversations_index/_assumption_results.json` | Independence (5 877) | 5 877 | 0 | 0 | 0 | every PASS single-base |
| `people_stream/_assumption_results.json` | Indep 25 + OneSideUntracked 5 | 30 | 0 | 0 | 0 | every PASS single-base |

### posts_show — does `_test_confinement` share the weakness? YES, in part

`_test_confinement` has TWO layers and they differ:

* criteria **(i)-(v)** and **(viii)** — the composition by replay — take their
  base from `pick_snapshot_with(batch, [ea, eb], [da, db])`: **single-base**;
* criterion **(vi)** `_exhaustive_flip` takes ONE representative per outcome
  PROFILE in the corpus (`ACHK_CONF_PROFILES`, default ALL): genuinely
  multi-base — but only over profiles that CARRY a footprint shape. On
  **484 of the 785 PASSes it flipped 0 of 0 profiles**, so for 62 % of them it
  contributed no evidence at all and the PASS is one base's word.

Measured on a stratified sample of 80 of the 1 363 classes (all 19 footprint
families; `_x12_conf_multibase.py`, `_c27_fals.py`'s base enumeration applied
to the shipped `_test_confinement` body by pinning `pick_snapshot_with`;
(vi)/(vii) stubbed, being base-independent; 8 bases each, 1 108 distinct
probes, 535 s):

```
  40 PASS classes           -> PASS 40, FAIL 0       (39 of 40 at 8/8 realising bases)
  40 NOT-TESTABLE classes   -> PASS 34, FAIL 1, N-T 5   (87.5 % MOVED)
  per-base totals: PASS 570, NOT-TESTABLE 64, FAIL 6
```

**The 10.5-hour gate's PASSes stand** — not one of 40 was refuted from any of
8 bases, and they are vouched at the strongest grade the new record can carry.
**Its NOT-TESTABLEs do not**: 35 of 40 were artefacts of the chosen snapshot,
34 of them testable-and-passing and 1 a real refutation
(`findpublic_like_1_not_found` x `as_api_response_1_row_text_empty`, FAIL on
6 of 8 bases, "(i) flip-A changed 1 shape OUTSIDE footprint(A): Photo.url").
So the defect cost posts_show in the direction of DEMANDING TOO MUCH: the
`_p32` withdrawal took 495 pairs out as "untestable" and ~87 % of those are
recoverable, which SHRINKS the booked 4 093 rather than growing it. One pair
goes the other way.

### The closed endpoints are NOT refuted

`people_stream`, `comments_index` and `conversations_index` close on
`IndependenceAssumption` (+ 5 `OneSideUntrackedPathAssumption`) and carry no
§16e/§16f/§16g class at all — but every one of those PASSes is single-base, so
they were in the radius. Measured, K = 8, stratified samples:

```
  people_stream        30 of 30 PASS   -> PASS 30, FAIL 0
  comments_index       40 of 3 648     -> PASS 29, FAIL 0  (11 are the "mutually
                                          exclusive, never co-evaluated" branch,
                                          which has no base to probe)
  conversations_index  40 of 5 877     -> PASS 32, FAIL 0  (8 the same)
```

**No closed endpoint's `complete: true` is refuted by multi-base probing.**
Note the grade, though: 6 of people_stream's 30 and 1 of conversations_index's
32 had only ONE realising base in the whole corpus — the weakest PASS the new
record can carry, and the ones to re-probe first if their corpus grows.
