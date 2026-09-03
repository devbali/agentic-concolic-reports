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
