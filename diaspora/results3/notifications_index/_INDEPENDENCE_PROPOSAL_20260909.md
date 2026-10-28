# notifications_index — INDEPENDENCE / PRUNING PROPOSAL (2026-09-09, late)

**Status: PROPOSAL ONLY (DISCIPLINE Rule T3).** Nothing below is installed.
`coverage_assumptions.py`, `src/`, the app and every dump are unmodified.
No JRuby slot was used; the `ndxcov.slice` pass was left alone. Reference
policies were not read. Every number is measured on the artefacts named,
through the engine's load path (`canonicalize_ordinals -> fix_len_names ->
Run.from_dict -> apply_len_bounds`, the same one `_size_job.py` uses).

## 0. Headline

| | cliques | satisfiable assignments (EXACT) | covered | remaining | closed | never co-evaluated |
|---|---|---|---|---|---|---|
| standing model (summary graph, 68 231 runs) | 1 826 | **1 183 264** | 28 009 | **1 155 255** | 8 | 375 |
| + the defensible set (D1-D4 below) | 1 819 | **407 200** | 18 212 | **388 988** | 26 | 367 |
| + second-tier (D5-D6) | 958 | 168 704 | 9 399 | 159 305 | 66 | 36 |
| + everything measured, incl. pairs inside withdrawn classes (D9) | 1 028 | 59 200 | 11 053 | 48 147 | 66 | 41 |

Three corrections to tonight's framing, each of which changes what should be done:

1. **The 491 040 figure was a cap artefact, and the true demand is 2.4x larger.**
   `_size_job.py` capped Z3 enumeration at 4 096 per clique; 65 cliques hit it.
   Enumerating exactly (per variable-connected component, product across
   components — exact because bounds are per variable) gives **1 183 264**
   satisfiable assignments; the four width-21 cliques alone hold 65 536 each
   (8 type values x 2^13), not 4 096. Width >= 10 carries 1 049 600 = 88.7%.
2. **The wide cliques are NOT loop-induced (question A). DecisionAlias widening is
   worth ~5.0% (question B).** Every member of every width >= 10 clique is a
   distinct decision under the P0 canonical names; the only ordinal-named
   decisions left in the missing universe are the contact/block `find_by_N`
   finders, and among those only `find_by_4` is a re-mint of `find_by_1`'s
   statement. The width comes from the WITHDRAWN classes gluing everything to
   everything: W-E (`> 1` x anything co-evaluated), W-F (any two `_not_found`),
   W-C (dispatch x `_not_found`). See §2.
3. **One declaration removes half of all demand, and it is an instance of a tier
   the batch already runs.** The unread-notifications root family
   (`Relation_records_notifications_8513a914`, `current_user.unread_notifications`
   at controller line 44) sits in **1 826 of 1 826** cliques. Over all 68 231
   runs its many-arm changes **zero** statement shapes and **no note binds its
   rows** — the exact P2 root-family criterion under which aspects / services /
   tags are already untracked. It was left out of `_P2_ROOT_FAMILIES` only
   because P2's regex is written for `CollectionProxy_records_*`. See D3.

The honest residual (§6): after the defensible set the demand is
**388 988** unobserved assignments over 1 819 cliques, of which 367
cliques have never been evaluated whole by any run. At the measured v2 random
rate (~1 new assignment per run, falling) that is not reachable by driving;
after the second tier it is 159 305, still not reachable. Nothing in this
proposal reaches a driveable number, and I have not manufactured declarations
to get one.

## 1. Method and validation (so the numbers can be checked)

- **Graph**: the 87 937 `IndependenceAssumption`s and 8 `UntrackedPathAssumption`s
  serialised in the standing `coverage_summary.json` (44 699-run pass; 435
  nodes = `tree_nodes`) rebuilt as *complete minus declared*, Bron–Kerbosch with
  pivot as in `coverage.py._maximal_cliques`. Result: **1 826 maximal cliques,
  and their expression sets are exactly the 1 826 blocking `missing[]` entries**
  (1 826/1 826 matched). `_graph_inputs.json` (batch dir) holds the inputs.
- **Demand**: per clique, exact satisfiable outcome count — expressions grouped
  into variable-connected components, each component enumerated with Z3 under
  the engine's merged declarations + `apply_len_bounds` bounds (blocking-clause
  loop, no cap), product across components. Reproduces `_size_job.json`
  exactly on every uncapped clique; disagrees only on the 65 capped ones.
- **Observed**: one pass over all 68 231 dumps through the load path, storing
  each run's outcome family over the 435-expression universe
  (`scratchpad/families.json.gz`); coverage counted with `coverage.py` step 6's
  blocking-clause semantics (an expression seen both ways in one run covers both
  outcomes). Reproduces `_size_job.json`: 8 closed, 375 never co-evaluated,
  witness-covered 420.
- **Statements**: a second pass over the raw dumps (notes intact, canonical
  names applied to binds) recording per run the set of statement keys
  (`assumptions.statement_key`, binds kept), every `len(...)` value, every
  `_not_found == True` arm taken and the run's terminal error
  (`scratchpad/notes.json.gz`).
- Candidate effects are computed by editing the graph (remove edge / remove node
  / pin an outcome / merge two nodes) and re-running the same three steps.
  Scripts: `scratchpad/cmodel.py`, `candidates.py`, `candidates2.py`;
  results `candidates_out.json`, `candidates2_out.json`.

Counting note: the brief said "133 cliques of width >= 10". The per-width table
gives 123 (16+23+19+10+9+8+4+6+15+4+5+4); 133 is width >= 9. The 357 376 figure
is the capped sum for width >= 10, so I report against 123.

## 2. Anatomy of the 123 wide cliques (question A)

97 distinct expressions occur in the 123 cliques of width >= 10. By what they are:

| class | expressions | in how many of the 123 | what it is in the app |
|---|---|---|---|
| STI dispatch, one-hot | `(SYM_NOTE_TYPE_PROFILE == 0..7)` (8), `(SYM_POST_STI == 0/1)` (2) | 38 | seeded notification STI / target Post STI (targets.rb §5f). 8 exprs but only **8** satisfiable assignments (bounds 0..7) — they multiply demand by 8, not 256 |
| unread root family | `(SYM_LEN_..Relation_records_notifications_8513a914_rows > 1)` | **123 / 123** (and 1 826 / 1 826 overall) | `current_user.unread_notifications` loaded whole for `group_by(&:type)` (controller :44) |
| principal has_one finders | `devise_user_first_1_person_not_found`, `..._person_profile_not_found` | 119, 117 | `current_user.person`, `.profile` (layout / person_link) |
| paginated list, 4 statement variants | `LEN.to_ary_<v>_rows > 1`, `..._row_actors_row_rows > 1`, `..._row_target_not_found`, `_row_recipient_not_found`, `_row_target_mentions_container[_commentable][_author_profile]_not_found`, `_row_target_author_profile_not_found`, `_row_target_statusmessage*_not_found`, `_row_actors_row_id == principal_person_id` | 28–33 each | `Notification.where(conditions).includes(:target, actors: :profile)` (:36); v = plain / `type=` / `unread=true` / both |
| contact & block finders (ordinal-named) | `FinderMethods_find_by_{1,2,3,4}_not_found`, `find_by_1_person_profile_not_found` | 20, 20, 16, 4, 20 | `recipient.contact_for(target)` (StartedSharing#contact -> contacts by row recipient/target), `current_user.contact_for(person)` and `block_for` inside `gon_load_contact` -> `ContactPresenter` (contacts / blocks by principal) |
| mention / photo / aspect_membership lists | `LEN.mentions_<3 chains>_rows > 1`, `mentions_*_row_person_not_found`, `LEN.photos_<6 chains>_rows > 1`, `LEN.aspect_memberships_<2>_rows > 1` | 12 each; 24 / 20 | `mentions.includes(person: :profile)`, `post.photos`, `contact.aspect_memberships` |
| Person.find_by(diaspora_handle) | `Core__ClassMethods_find_by_1_[profile_]not_found` | 15 | `Mentionable.find_or_fetch_person_by_identifier` |
| tautology | `(X_target_status_message_guid != X_target_status_message_guid)` | 1 | AR `stale_target?` self-compare; **1** satisfiable outcome, adds no demand |

**Are these 21 things in one clique because they interact?** No. A width-21
clique is {8 dispatch} + {6 lengths} + {7 `_not_found`s}. They are pairwise
dependent only because:

- every `> 1` is glued to every decision it is ever co-evaluated with (W-E,
  `_withdrawn_independence` `_GT1_RE`), and the unread family is co-evaluated
  with everything;
- every `_not_found` is glued to every other `_not_found` (W-F as *implemented*:
  `_nf(va) and _nf(vb)` withdraws all not_found pairs in the program, although
  the three refutations it records were `find_by_1 x find_by_2` — contact
  finders that share the §7 memo);
- every dispatch compare is glued to every `_not_found` (W-C) and to every
  `> 1` (W-E).

**Are any of the 21 the same statement at different ordinals (loop
iterations)?** Checked over all 68 231 runs, every non-aliased
`SYM_RESULT_*_<n>` name that still appears in the missing universe
(`_ordinal_stmt_census.json` for the 4 000-run sample, `families.json.gz` `fb`
for the full corpus, statement keys with binds kept and the list variants
collapsed to chain identity, as `_alias_core` does):

| ordinal | statement (binds kept) | keys |
|---|---|---|
| `FinderMethods_find_by_1` | contacts WHERE user_id = $row_recipient_id AND person_id = $row_target_id | 1 (2 411 runs) |
| `find_by_2` | contacts WHERE user_id = $principal_id AND person_id = $find_by_1_person_id LIMIT 1 | 1 (2 398) |
| `find_by_3` | blocks WHERE user_id = $principal_id AND person_id = $find_by_1_person_id LIMIT 1 | 1 (2 397) |
| `find_by_4` | **= find_by_1's statement** (847 of 848 runs; 1 run: find_by_3's) | 2 |
| `find_by_5` | find_by_1's (526) / find_by_2's (321) — ambiguous | 2 |
| `find_by_6..9` | repeats of 3 / 1 / 2 / 3 | 1 each |
| `Core__ClassMethods_find_by_1` | people WHERE diaspora_handle = '?' LIMIT 1 | 1 (345) |
| `devise_user_first_1` | users WHERE id = $SYM_USER_NI_id … LIMIT 1 | 1 (all) |

So there is ONE loop artefact in the wide cliques: `find_by_4` is `find_by_1`
re-minted (the §7 `one_fact` memo keys on `(receiver, sql)`, and the second
`contact_for` call arrives on a fresh relation object, so it is not a memo hit).
It appears in 4 of the 123 wide cliques. Everything else in those cliques is a
distinct decision. **Split: 0 of 123 cliques are loop artefacts as a whole; 4
carry one duplicated member.**

Also verified, because it is the premise the coordinator's message rests on:
the `_not_found` decisions are NOT ordinal-named. `finder_mock`
(`concolic_targets.rb:745`) names them `"#{name}_not_found"` where `name` is
the receiver CHAIN (`…_row_target_mentions_container_author_profile`), and
the P0 alias already canonicalises the list heads of those chains. The
call-ordinal problem is confined to `FinderMethods.find_by/first/last/exists?`,
`Calculations.*`, `Relation.size` and the preloader's `load_intermediate` —
and of those only `find_by_{1..4}` and `Core find_by_1` have decisions in the
missing universe.

## 3. Widening DecisionAlias (question B)

Pattern extension that canonicalises the finders by statement identity,
binds kept, exactly as the list reads are:

    ALIAS_PATTERN = (r"SYM_RESULT_ActiveRecord__(?:Associations__CollectionProxy_records"
                     r"|Relation_records|Relation_to_ary"
                     r"|FinderMethods_find_by|Core__ClassMethods_find_by)_\d+")

Effect on names (full-corpus census above): `find_by_{1,4,5a,7}` -> one
`find_by_contacts_<h1>`; `find_by_{2,5b,8}` -> `find_by_contacts_<h2>`;
`find_by_{3,6,9}` -> `find_by_blocks_<h3>`; `Core find_by_1` unchanged
(single member). Two consequences to state honestly:

- the list-variant binds inside `find_by_1`'s key (`to_ary_notifications_<v>_row_recipient_id`)
  collapse to chain identity, so all four variants' contact reads become ONE
  name — the same rule the shipped alias applies to nested reads, and the
  right one here (the contact statement does not depend on which list variant
  produced the row);
- downstream, `aspect_memberships_{ae3fcf22,6f13edc1}` are keyed on
  `find_by_1_id` / `find_by_2_id`; after widening their keys reference the
  chain identities `find_by_contacts` for BOTH, so the two aspect_memberships
  reads would MERGE into one name. That merge is unsound if the two contacts
  can differ (`_DECISION_ALIAS_REPORT.md` §6 lists ae3f x 6f13 as "two
  contacts of one row: dependent") — but by the §7 memo they are ONE fact
  (`gon_helper.rb:6` disposition in `AGENT_RUN.md`: "the §7 finder memo makes
  the two contacts one fact"), and `recipient == current_user` (controller :26)
  makes `contact_for(target)` and `current_user.contact_for(contact.person)`
  the same row. I did NOT model that merge in the numbers below (the numbers
  merge only `find_by_4 -> find_by_1`, which is the only change visible in the
  missing universe); the gate's `_test_alias` part (i) will accept or reject
  the aspect_memberships merge on the corpus's own statement keys.

**Recomputed with the merge applied (K4):** cliques 1 822, satisfiable
1 125 920 (from 1 183 264), remaining 1 097 914. That is the whole of what
"DecisionAlias harder" buys on this endpoint: 5.0% of demand. It is
still worth declaring (it is an identity claim, the gate's derived test checks
it, and it stops the next demand round from minting `find_by_10`), but it is
not the instrument for this explosion. **Headline for question B: widening
the alias leaves 1 097 914 of 1 155 255 remaining.**

## 4. Candidates, ranked by measured demand reduction

Ranking key = remaining assignments after the declaration, alone on top of the
standing model (column "alone"), and cumulatively in the recommended order
(column "cumulative"). Every candidate is one of the FIVE existing kinds; no
new machinery. "Test" names the existing gate branch that falsifies it.

| rank | id | kind | alone: sat / remaining | cumulative: cliques / sat / remaining / never-coeval |
|---|---|---|---|---|
| 1 | **D3 = K1** unread root-family many-arm | `UntrackedPathAssumption` (P2 tier) | 591 808 / 573 619 | 1 822 / 448 448 / 430 262 / 374 |
| 3 | **D4 = K3-core** closing-arm foreclosure, partners outside every withdrawn class | `IndependenceAssumption` (tier1c-corpus rule, cross-rep) | 1 057 760 / 1 029 718 | 1 819 / 407 200 / 388 988 / 367 |
| 2 | **D2 = K2** row recipient is the principal (Rule D) | `OneSideUntrackedPathAssumption` (or `SymbolicConstraint`) | 925 216 / 897 207 | 1 822 / 896 544 / 868 538 / 374 |
| 4 | **D1 = K4** alias widening | `DecisionAliasAssumption` | 1 125 920 / 1 097 914 | 1 822 / 1 125 920 / 1 097 914 / 374 |
| 5 | D5 = K7 aspect_memberships many-arm | `UntrackedPathAssumption` | 785 152 / 759 103 | 1 684 / 321 040 / 304 367 / 320 |
| 6 | D6 = K6 photos many-arm (6 chains) | `UntrackedPathAssumption` | 854 544 / 837 409 | 958 / 168 704 / 159 305 / 36 |
| — | D7-D9 = K3 pairs whose partner is inside W-F / W-C / W-E | `IndependenceAssumption` | 541 918 / 1 057 463 / 790 774 | 1 028 / 59 200 / 48 147 / 41 |

Recommended: **D1-D4** (the defensible set). D5-D6 clear the mechanical bar
but not P2's stated scope; D7-D9 are inside classes the gate withdrew and I do
not recommend them without an explicit ruling that closing-arm foreclosure is
a different class from the co-evaluated refutations (§5).

### D3 / K1 — unread notifications root family, many-arm untracked (rank 1)

**Expression** (one, canonical):
`(SYM_LEN_SYM_RESULT_ActiveRecord__Relation_records_notifications_8513a914_rows > 1)`.
The `== 0` / `== k` compares on the same variable stay tracked, exactly as P2
keeps them for aspects / services / tags.

**Argument (app code).** `notifications_controller.rb:44`:
`types.each_with_object(current_user.unread_notifications.group_by(&:type))`.
`User#unread_notifications` (`user.rb:109`) is `notifications.where(unread: true)`
— one statement, `SELECT "notifications".* … WHERE recipient_id = $principal
AND unread = true`, binding only the principal. The loaded rows are consumed
by `group_by(&:type)` and `Array#count`: an attribute read and a Ruby count,
no association, no finder, no nested read. The separate badge count
(`@unread_notification_count = current_user.unread_notifications.count`,
:42) and the mobile header's `.size` are COUNT statements on their own
result names (`Calculations_count_2/3`, `Relation_size_1`) and are not this
variable. The list's cardinality therefore determines NO statement shape:
the statement it owns is keyed on the principal, and nothing is keyed on its
rows. That is P2's criterion verbatim ("binds only the principal, owns its
statement, each yields the representative once, no note binds its rows").

**Measured (whole corpus, not a sample).** Statement keys of runs with the
many-arm taken (10 716 runs) minus keys of runs with it not taken (57 353
runs): **0 shapes only on the many arm**. Notes binding
`…notifications_8513a914_row` anywhere in 68 231 dumps: **0**. (Compare the
paginated list: 7 `IN (…)` shapes only on its many arm; actors: 2; mentions:
2 — §5.) The row decision `…8513a914_row_target_is_photo` that exists on this
family's representative is minted at row construction (`targets.rb:922`,
the commentable-profile seed) with no statement, and is unaffected.

**Why W-E does not apply.** W-E's mechanism is a statement whose predicate
operator follows the cardinality (`= ?` vs `IN (…)`). This family has no
such statement: it is never a preload key set, and no read is keyed on it.
The nine W-E refutations were on the paginated list, actors, mentions and
the target photos — every one a list whose rows key a later read. The C7
adjudication's "F4 x F5 stay dependent" is about *length x length
independence* with the paginated list (unread ⊂ list makes `list == 0 ∧
unread > 1` unrealisable) and is untouched: untracking the many-arm removes
the expression from the demand universe, it does not declare a pair, and
the `== 0` arm of both lists stays tracked.

**Differential test (exists, `assumption_checker.py` `test_declared`,
UntrackedPath branch).** Snapshot = richest dump recording the expr; flip the
seed `len(SYM_RESULT_ActiveRecord__Relation_records_1_rows)` 1 -> 3 (and 3 ->
1 from a many-arm snapshot); replay; `delta = base ^ other` over target-call
shapes must be EMPTY, else FAIL and the tier is withdrawn — the same probe P2
passed for the three declared families. A stronger differential the project
already has: `queries_from_runs`' per-request multiplicity check against a
concrete run with 0, 1 and 3 unread notifications — the statement multiset
must differ only in the `notifications … unread = true` row count, never in
a shape.

**Dependency.** P2 is "declared and gate-probed, NOT ratified" (night report
§6.1). K1 is the same tier; if P2 is rejected, K1 falls with it.

**Effect.** Alone: satisfiable 1 183 264 -> **591 808**, remaining
1 155 255 -> **573 619** (exactly half: the expression is in every clique
and its two outcomes are both satisfiable in every clique). Clique count
unchanged (1 826): it removes a universal node, it does not split anything.

### D4 / K3-core — closing-arm foreclosure by a `_not_found` gate, cross-rep (rank 2)

**Expressions.** Pairs `(g, e)` where `g` is a `(<chain>_not_found == True)`
decision whose True arm is taken in >= 20 runs, and `e` is a decision that is
recorded in some run where `g` is False and in **no** run where `g` is True.
1 309 pairs over 17 gates; full list in
`_INDEPENDENCE_PROPOSAL_20260909_pairs.json` (key `K3.core`). The gates and
their partner counts (partners outside every withdrawn class / inside):

| gate (`… == True`) | True-arm runs | core partners | inside W-F / W-C / W-E |
|---|---|---|---|
| `AR.FinderMethods_devise_user_first_1_person_profile_not_found` | 196 | 153 | 19 / 0 / 3 |
| `TOARY.10254800_row_target_not_found` | 719 | 132 | 19 / 2 / 11 |
| `TOARY.3aa8587a_row_target_not_found` | 2370 | 131 | 18 / 2 / 11 |
| `TOARY.c7e6a7ca_row_target_not_found` | 1398 | 130 | 18 / 2 / 11 |
| `TOARY.cf379872_row_target_not_found` | 457 | 130 | 18 / 2 / 11 |
| `TOARY.3aa8587a_row_target_mentions_container_not_found` | 22 | 77 | 7 / 2 / 6 |
| `TOARY.c7e6a7ca_row_target_mentions_container_not_found` | 33 | 72 | 7 / 2 / 6 |
| `TOARY.10254800_row_target_mentions_container_not_found` | 29 | 69 | 7 / 2 / 6 |
| `TOARY.cf379872_row_target_mentions_container_not_found` | 25 | 69 | 5 / 2 / 6 |
| `TOARY.c7e6a7ca_row_target_author_profile_not_found` | 132 | 63 | 6 / 0 / 3 |
| `TOARY.cf379872_row_target_author_profile_not_found` | 98 | 63 | 6 / 0 / 3 |
| `TOARY.3aa8587a_row_target_author_profile_not_found` | 31 | 60 | 6 / 0 / 3 |
| `TOARY.10254800_row_target_author_profile_not_found` | 23 | 60 | 6 / 0 / 3 |
| `AR.FinderMethods_devise_user_first_1_person_not_found` | 3290 | 44 | 4 / 0 / 0 |
| `REL.mentions_d25799cb_row_person_not_found` | 59 | 21 | 0 / 0 / 0 |
| `REL.mentions_fbb27183_row_person_not_found` | 30 | 20 | 0 / 0 / 0 |
| `REL.mentions_857a1e6b_row_person_not_found` | 237 | 15 | 0 / 0 / 0 |

**Argument (app code).** Each gate's closing arm makes its partner's code
unreachable:

- `<list>_row_target_not_found == True` — `note.target` nil. `_notification.haml:6`
  `if note.target.present?` skips `gon_load_contact(note.contact)` (so the
  contact/block finders and the ContactPresenter's profile/aspect reads never
  run); `notifications_helper.rb:10` `note.linked_object.nil?` routes to
  `deleted_translation_key`, so `opts_for_post` / `opts_for_mentioned` (the
  post, mentions_container, commentable, author, photos chains) never run.
  Measured: 1 398 / 2 370 / 457 / 719 True-arm runs across the four list
  variants; 130-132 partners never recorded on that arm, all of them
  decisions on the target-derived chains and the photos rows.
- `…_row_target_mentions_container[_commentable]_not_found == True` — the
  same, one level down (`opts_for_mentioned`, `mentioned.parent`).
- `…_author_profile_not_found == True` (target / container / commentable /
  statusmessage authors) and `devise_user_first_1_person_profile_not_found`
  — `person.profile` nil: `person_image_tag` returns "" (`people_helper.rb:38`),
  and `Person#name` reaches `fix_profile`; in this rig every such run ends in
  `ActionView::Template::Error` (196/196, 132/132, 98/98, 31/31, 23/23
  measured), so nothing minted after the gate exists.
- `mentions_<chain>_row_person_not_found == True` — the mentioned person's
  profile/link reads never happen (15-21 partners).

**What this is NOT.** It is not a new rule. `_tier1c_empty_list_foreclosure`'s
second half declares exactly this shape of pair for LIST gates ("closing arm
observed, decision observed, never together — an unobservable combination",
1 331 declared and gate-accepted), and `_tier1_samerep_foreclosure` declares
it structurally for `_not_found` gates on the SAME rep. K3-core is the
`_not_found` gate with a CROSS-rep partner, corpus-evidenced the way tier1c
is. The `_rep_key` split (target chain vs contact chain vs photos rows) is
what kept tier1 from reaching these pairs.

**Rule D / W-E / W-F / W-C.** K3-core contains no `> 1` expression, no
dispatch compare and no `_not_found` partner — those 245 pairs are
split out as D7-D9 below and NOT recommended. Every K3-core pair is a gate x
{a `_text_*`, `_disp_*`, `_persisted`, `_guid`, name, `== 0`/`!= 0` length,
own-profile compare} decision on a chain that does not exist on the closing
arm.

**Differential test (exists: `test_declared`, IndependenceAssumption
branch).** Snapshot = richest dump co-recording `g` and `e` (necessarily
`g` False); flip `g` (seed `<chain>_not_found` True), flip `e`, flip both;
`novel = trace(both) − (base ∪ A ∪ B)` must be EMPTY. On the closing arm the
partner's chain is never read, so `trace(both) ⊆ trace(A)`; a FAIL means the
closing arm reads something the corpus never showed — which is exactly what
the declaration must not hide, and the tier is withdrawn as a class. Second,
cheaper differential already in the corpus: the pair's "never together" is
a full-corpus fact re-checked at every pass (P1's tripwire logic — the first
run that records `e` on `g`'s True arm turns the entry into a real probe).

**Evidence threshold.** I used >= 20 True-arm runs per gate. With >= 5 the
list grows to 2 260 + 99 pairs; I do not recommend the low-
evidence gates (`find_by_1/2/3`, `recipient`, `statusmessage`, `author`: 1-11
True runs each) — "never together" over 5 runs is sparse, not structural.

**Effect.** Alone: satisfiable 1 057 760, remaining 1 029 718.
Cumulative after D1-D3: cliques 1 819, satisfiable 407 200, remaining
**388 988**, never-co-evaluated cliques 367.

### D2 / K2 — the list row's recipient IS the principal (rank 3)

**Expressions** (4, one per list variant):
`(SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_<v>_row_recipient_not_found == True)`
for v in `c7e6a7ca, cf379872, 3aa8587a, 10254800`. Proposed as
`OneSideUntrackedPathAssumption(expr, tracked_side="not_taken")` (the gate's
OneSide branch can test it; a `SymbolicConstraintAssumption` on a Bool is
NOT-TESTABLE by the gate's `VAR op INT` rule). Effect on the checker is the
same: the True side is not demanded.

**Argument (Rule D — derive what is determined).** `notifications_controller.rb:26`
`conditions = {recipient_id: current_user.id}`; the list statement is
`WHERE recipient_id = $devise_user_first_1_id`. Every row's `recipient_id` is
the principal's id by the predicate, and the principal row was found (post-auth
entrypoint, `devise_user_first_1` is the row we are signed in as). The
`belongs_to :recipient` read that `StartedSharing#contact` issues
(`recipient.contact_for(target)`) is a real statement — `SELECT "users".* WHERE
id = $row_recipient_id` — and the policy keeps it; but its RESULT is fixed by
a primary-key equality the application itself asserted three statements
earlier. Deciding it freely is the M-13-class mistake Rule D names ("a
quantity the data already determines was modelled as a free decision"):
the True arm (`users` row missing for an id that was just read) is a state
the database cannot present in one request. It manufactures 14 runs, all
`ActionView::Template::Error`, and halves the demand of every clique it is in.

**Differential test.** Ground-truth, in the style of C1: in real mode, load
notifications for a signed-in user and record the `users` reads; assert every
`recipient_id` bind equals the principal id and every such read returns one
row (a schema fact: `notifications.recipient_id` -> `users.id`, principal
present). Gate: OneSide branch — flip `recipient_not_found` to True from a
StartedSharing snapshot; the untracked side must add no shape beyond the
tracked side (it errors before any further read, so it cannot).

**Effect.** Alone: satisfiable 925 216, remaining 897 207. Cumulative
after D1: 868 538.

### D1 / K4 — DecisionAlias widened to the finders (rank 4)

Declaration: the `ALIAS_PATTERN` in §3, `key="statement"`. Gate:
`_test_alias` per canonical name — (i) one statement key across members,
(ii) identical intervention effects from a base snapshot; the deliberately
unsound `key="shape"` control already demonstrated the test fails a wrong
alias. Effect alone: satisfiable 1 125 920, remaining 1 097 914. Ranked
low on demand, recommended anyway for the reason in §3 (stops ordinal
minting from widening cliques in future rounds; three endpoints have needed
the alias).

### D5 / K7 — aspect_memberships many-arm untracked (second tier)

Expressions: `(SYM_LEN_…CollectionProxy_records_aspect_memberships_{ae3fcf22,6f13edc1}_rows > 1)`.
App: `ContactPresenter#full_hash_with_person` -> `contact.aspect_memberships`
-> per membership `aspect` (`SingularAssociation#find_target`, `SELECT "aspects".*
WHERE id = $…_row_aspect_id LIMIT 1`). Measured: the ONLY notes binding these
rows are that per-row `= ?` read (2 322 / 1 237 events); shapes only on the
many arm: **0** for both. Under Rule D's own per-owner-emitter clause a
many-row state issues N `= ?` statements and no `IN`, so cardinality changes
multiplicity, not shape — a designed under-count (multiplicity scope decision,
2026-08-30), not a policy difference. It fails P2's *literal* wording ("no
note binds its rows") and it is nested under the contact finder rather than
the principal, so I rank it below the line: it clears the W-E mechanism but
not P2's stated scope, and the owner should say whether P2 extends to
per-row-`= ?` families. Test: UntrackedPath flip (identical trace as a SET of
shapes). Effect alone: satisfiable 785 152, remaining 759 103.

### D6 / K6 — photos many-arm untracked, 6 chains (second tier)

Expressions: `(SYM_LEN_…CollectionProxy_records_photos_<h>_rows > 1)` for the
six canonical photos reads (three owner chains + typed/unread/`1=0`-scope
variants). App: `post.photos` loaded in `post_page_title` when the message is
blank; the photo rows feed `Photo#status_message`-side text decisions
(`…photos_*_row_text_*`) but no read is keyed on a photo row. Measured: 0
shapes only on the many arm for every chain; 0 notes binding `photos_*_row`
in 68 231 dumps. Same caveat as D5 (nested under the target; the adjudication's
"to_ary x photos stay dependent" is about length x length pairs and is not
what this declares). Effect alone: satisfiable 854 544, remaining 837 409.

### D7-D9 — K3 pairs whose partner is a `_not_found` (W-F), a dispatch compare (W-C) or a `> 1` (W-E) — NOT recommended

146 / 16 / 83 pairs with the same closing-arm
"never together" evidence as K3-core. Mechanically they are the same
argument (on the gate's True arm the partner's list is never read, so the W-E
`IN` mechanism has nothing to act on; the W-C refutation — the dispatch
choosing WHICH chain a not-found sits on — cannot occur when no chain is
read). But they sit inside classes the gate withdrew whole, and the standing
rule is "withdrawn at the class it belongs to, never re-declared narrower".
The C7-A / P1 precedent (never-co-evaluated pairs declared *despite* W-E,
because "a pair with zero co-evaluating runs cannot exhibit that mechanism")
is the argument that would admit them; that precedent is itself
unratified (decision 2). Measured so the owner can price the ruling:
cumulative D9 leaves 48 147.

## 5. Adversarial pass — dropped under Rule D / W-E (and the other withdrawals)

| dropped | why |
|---|---|
| `(SYM_LEN_to_ary_<v>_rows > 1)` many-arm (4) | the paginated list's rows key the actors join-table, people, profiles, posts/mentions target preloads: **7 shapes exist only on the many arm** (`IN ($row_id, $row2_id, …)`), measured over 7 365 / 4 689 / 3 456 / 2 160 many-arm runs. W-E's mechanism exactly. |
| `(SYM_LEN_to_ary_<v>_row_actors_row_rows > 1)` (4) | actors key `people`/`profiles IN (…)`: 2 shapes only on the many arm. Dropped. |
| `(SYM_LEN_mentions_<3>_rows > 1)` (3) | `mentions.includes(person: :profile)` -> `people`/`profiles IN (…)`: 2 shapes only on the many arm. Dropped. |
| any length x length pair beyond the 5 declared C7-A ones | not needed once K1 removes the unread many-arm; F4 x F5, F4 x F7, F6 x F9, same-family pairs stay dependent per the adjudication. Nothing proposed. |
| `(SYM_NOTE_TYPE_PROFILE == k)` x principal `person_not_found` / `person_profile_not_found` | would re-narrow W-C ("dispatch x not_found", withdrawn whole on the container-author refutation). The principal finders are not on a dispatched chain, so the refuting mechanism cannot apply — but that is a narrowing by prefix, which the rule forbids. Not proposed; priced under D8. |
| `devise_user_first_1_person_not_found` as a foreclosure gate | its True arm does NOT terminate: 924 of 3 290 True-arm runs render to completion and 378 partners are recorded on that arm. Genuinely co-evaluated with the content; nothing to declare. |
| `find_by_1 x find_by_2 x find_by_3` (contact/block finders) | W-F's actual refutations; the §7 memo makes them one fact; stay dependent. |
| own-profile compare `…_row_actors_row_id == …_person_id` (274 memberships) | W-B withdrawn (flip changed 3 shapes). Untouched. |
| `(X_target_status_message_guid != X…guid)` | a tautology with ONE satisfiable outcome: it is in 125 cliques but adds no demand. Nothing to declare; the `skipped_pcs` disposition already covers it. |
| K3 with a 5-run evidence floor | 2 260 + 99 pairs; the extra gates have 1-11 True runs. Not proposed. |
| `person_profile_not_found` x anything as a SymbolicConstraint ("profile always exists") | tempting (196/196 runs error) but the profile row is not determined by the request: it is a real has_one that federation can leave absent. A decision, not a derivation. K3-core keeps it as a gate only. |

## 6. Residual, honestly

After the defensible set D1-D4: **388 988** unobserved satisfiable
assignments over 1 819 cliques, max width 20;
367 cliques have never been evaluated whole by any of 68 231 runs
(baseline 375). After D5-D6: 159 305 over 958 cliques,
36 never co-evaluated. After everything measured including the
withdrawn-class pairs (D9): 48 147.

Reachability by driving, at the rates measured tonight (v2 random: 17 327
new assignments in 16 869 runs, ~1.03/run and falling; targeted: ~0.2/run,
one assignment per clique per round): 388 988 needs on the order of
4 x 10^5 runs at the *initial* random rate and far more as returns
diminish; a coverage pass of a corpus that size is measured in hours per
pass at 10 GB. **It is not reachable.** The per-width table after D4 says
why: w9: 23 cliques / 10 503 remaining; w10: 10 cliques / 7 054 remaining; w11: 19 cliques / 23 359 remaining; w12: 16 cliques / 24 414 remaining; w13: 4 cliques / 16 317 remaining; w14: 4 cliques / 16 384 remaining; w15: 4 cliques / 4 048 remaining; w16: 6 cliques / 12 249 remaining; w17: 15 cliques / 61 254 remaining; w18: 4 cliques / 32 710 remaining; w19: 4 cliques / 65 469 remaining; w20: 4 cliques / 65 480 remaining. The width is still the paginated list x actors x
mentions x photos x the not_founds x the 8-way dispatch, every one of which
either keys a bulk read (W-E, correctly) or is a real not-found decision on
a real chain — there is no further independence I can defend that removes
them, and I have not invented one.

What WOULD reach it is outside this proposal's remit and I state it only so
the residual is not mistaken for a driving problem: (a) the demand is
`8 x 2^k` per clique because the eight dispatch compares are one 8-valued
variable modelled as eight Bool decisions kept mutually dependent with
everything (`_tier0c` declares dispatch independent of non-dispatch
decisions, then W-E/W-C withdraw it for every length and not_found) — that
is the checker's model of an enumeration, not an interaction; (b) the four
list-statement variants (plain / typed / unread / both) quadruple every row
chain by construction of the P0 alias key (`_DECISION_ALIAS_REPORT.md` §1),
so the same row decision is demanded four times against four otherwise
identical contexts. Both are model questions for the owner, not
declarations a batch may make.

## 7. Artefacts (batch dir unless noted)

- `_graph_inputs.json` — the summary's declarations as pairs / untracked / universe.
- `_missing_cliques.json` — the 1 826 blocking cliques as expression lists + witnesses.
- `_ordinal_stmt_census.json` — statement keys per ordinal-named result (4 000-run sample).
- `_INDEPENDENCE_PROPOSAL_20260909_pairs.json` — every candidate expression / pair (K1, K2, K4, K6, K7, K3 by class).
- scratchpad (`/tmp/claude-1000/-home-dev-project/94ab9891-…/scratchpad/`): `families.json.gz`,
  `notes.json.gz`, `cmodel.py`, `candidates.py`, `candidates2.py`,
  `candidates_out.json`, `candidates2_out.json`, `baseline_model.json`, `lendiff2.py`, `foreclose.py`.

Not modified: `src/`, the app, `coverage_assumptions.py`, `targets.rb`,
`concolic_targets.rb`, any dump, any reference policy.
