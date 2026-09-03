# comments_index — AGENT_RUN (results3 completion drive)

Objective: drive `coverage_summary.json` to `complete: true`
(`complete = coverage_complete AND completion.complete`).

**FINAL RESULT (cycle 12, 2026-09-01) — `complete: true`.**

| axis | value |
|------|-------|
| `coverage_complete` | **true** (0 missing branch combinations; 84 PC nodes; 25 408 runs over 26 528 dumps; 928 746 PCs; truncated=false, solver_lost=0, unevaluable_exprs=[], dump_errors={}) |
| `completion.complete` | **true** (blocking = []) |
| — shims | 19 PASS / 11 PROTOCOL / 0 red / 0 NO-TEST (30 extracted) |
| — note_check | **green** |
| — assumptions | 4 182 declared, 3 648 distinct tested, **3 648 PASS / 0 FAIL / 0 NOT-TESTABLE**, 0 unverified |
| — engine audits | format_coverage / note_fidelity / empty_relation_emission all green |
| `complete` | **true** |
| standalone audits | all 8 green (`cardinality_consistency`: population 123 974 pairs, three escapes printed) |
| hardening lint | clean with **`h6_answered: []` — the batch now carries ZERO waivers** |
| count multiplicity | 0 under / 0 over against BOTH the plain (66 scopes, 731 requests) and the executor-wrapped (8 scopes, 41 requests) ground truth |

Cycle 12 closed adversary round 9 (M-17 by resolution (b); M-18 measured).
The starting state (cycle 0) was `complete: false`: `coverage_complete=false`
with 256 missing combinations, and `completion.complete=false` with a
NOTE-MISMATCH RED (the mentions-table read the real endpoint issues had no
corpus note anywhere).

---

## Root cause of the cycle-0 red, and the discipline it violated

`concolic_targets.rb`'s `symbolic_instance` pinned `@new_record = true` on
**every** symbolic record. `Diaspora::MentionsContainer#mentioned_people`
(`mentions_container.rb:16-21`) branches on `persisted?`:

```ruby
persisted? ? mentions.includes(person: :profile).map(&:person)   # the REAL path for a query-returned comment
           : Diaspora::Mentionable.people_from_string(text)
```

With the pin, every comment was unpersisted, so the endpoint's real
`mentions.includes(person: :profile)` read (people + profiles preloads) was
**structurally unreachable** in the corpus — a **Class B** blinded branch
(the persisted decision never recorded) compounding a **Class S** swallow
(the mentions statement never emitted). `mock_note_check` caught it exactly:
one NOTE-MISMATCH, the `mentions.*` read with no note anywhere.

---

## Cycle 1 — changes and the discipline rule each satisfies

### A. The persisted decision (D2 branch visibility; fixes the note gap)
Ported the notifications_index persisted-decision pattern into
`concolic_targets.rb` `symbolic_instance`: `persisted?`/`new_record?` are now
a **seeded, PC-recorded boundary decision** (`<base>_persisted`), default
persisted (the side every query-returned row inhabits). Effect: the DEFAULT
run now takes the real `mentions.includes(person: :profile)` chain (the
`mentions` + preload notes appear), and DSE flips the seed to explore the
unpersisted `people_from_string` side. The mentions read is minted as
evidence on both concrete scenarios → note_check green.

### B. Removed two target mocks over target-reaching app bodies (D1)
- **`Person#name` target mock removed.** Its real body (`person.rb:247-252`)
  reads `self.profile` — a declared association target — before the pure
  `Person.name_from_attrs`. Mocking `#name` swallowed that profile read and
  emitted a junk `"Person#name"` note (the Person#name violation class). The
  wall it cleared (`SymbolicString#strip` inside `name_from_attrs`) is now
  cleared at the SQL-free leaf: `targets.rb §7` shims **`Person.name_from_attrs`**
  (pure string computation, zero targets — a real shim). `Person#name` now
  runs for real and its profile read mints evidence.
- **`MessageRenderer::Processor.process` target mock removed.** It is app
  code (the renderer pipe → `diaspora_links` can reach `Post.exists?`); on
  this batch `text` is already a concrete String (the §4a has_mention pin),
  so the real pipe runs with no wall — the mock only skipped it.

### C. Call-site-stable finder naming for the signed-in path (soundness)
`EvilQuery::VisibleShareableById#post!` (`evil_query.rb:102-105`) is
`vis.first || author.first || public.first` — three finders on one shared
`.first` ordinal. `targets.rb`'s `CommentsVisibleShareableNaming` aliases
them to `ci_vis_first` / `ci_author_first` / `ci_public_first` (each always
`_1`), so the anon `first_1` (find_public!) never collides with an auth
finder. Byte-faithful prepend of `post!`.

### D. Real Devise current_user resolution in the auth corpus (D1)
The cycle-0 auth runner mocked `current_user` (a pre-built symbolic user)
and `user.person`, so the two statements the signed-in endpoint issues to
resolve the session — `SELECT users.* WHERE id = ?` (Devise
`serialize_from_session` → `OrmAdapter::ActiveRecord#get`) and
`SELECT people.* WHERE owner_id = ?` (`has_one :person`) — were swallowed
(the concrete signed-in run issues them; `mock_note_check` flagged two
NOTE-MISMATCH). `targets.rb`'s `CommentsDeviseUserNaming` resolves
`current_user` through **real** `User.serialize_from_session` (lazy, inside
the interceptor window), with:
- a `authenticatable_salt` leaf shim (pure `encrypted_password[0,29]` slice);
- `devise_user_first`, a call-site-stable alias of `FinderMethods#first` for
  the one `.first` inside a byte-faithful `OrmAdapter::ActiveRecord#get`
  prepend, so the users lookup does not steal the `first_1` ordinal;
- the session user pinned resolved+persisted with **no** PC (Devise
  middleware guarantees a persisted user reaches the action; a failed
  session 401s upstream — not a modeled endpoint state), so no
  auth-plumbing decision enters the coverage universe.

`user.person` is no longer overridden → the real `has_one :person` fires,
minting the `people.owner_id` note.

### E. coverage_assumptions.py — rebuilt for the new PC universe
The persisted decision and the ci_*/devise renaming changed the expr set.
`coverage_assumptions.py` was rewritten as pure **structural gating**: every
`IndependenceAssumption` names the gate, its source line, and the value that
closes it (post_service.rb find!'s `user` dispatch for anon⊥auth; find_public!'s
404 / NonPublic raises; `null_scope?` for unpersisted owners → NullRelation
comments; the `||` short-circuit in `post!`; MentionsContainer's persisted
branch split; person.rb's found-person early-return gating the retry).
Four `UntrackedPathAssumption`s cover the post-text shim flags (a POST's
`text` is never read on this endpoint). A batch-local `pair_coeval_audit.py`
drove this: it flags every PC pair never co-evaluated (or co-evaluated with
missing combos) and not declared — reduced to **0/0**, then the coverage
checker confirmed **0 missing**.

### F. Concrete scenarios (Phase 5 / note check)
- `concrete_manifest_anon.rb`: added a real `mentions` row on the
  mention-bearing comment so the persisted preload chain runs on data.
- `concrete_manifest_auth.rb` (new): signed-in scenario, real Devise warden
  resolution, three posts hitting the vis / author branches of `post!`
  (share_visibility + own-post fixtures), each with a mention-bearing
  comment. `completion_config.json`'s `concrete_run` points at the merged
  anon+auth run (`merge_concrete_runs.py`). Two harness fixes: the salt
  `User.find(9)` is computed at fixture-load time (outside the statement
  capture window, so it is not mistaken for endpoint SQL), and post 102 is
  made vis-visible (the boolean public-branch WHERE 404'd under the JDBC
  sqlite adapter; the public-branch note remains covered corpus-side).

### G. shim_tests.rb
The engine's `shim_extractor` enumerated four new shims from the cycle-1
additions — `u.persisted?`, `u.new_record?`, `User.authenticatable_salt`,
`OrmAdapter::ActiveRecord.get` — each given a reasoned WAIVER (session
plumbing / leaf slice / byte-faithful naming prepend, none a mock over
endpoint logic). Added the `Person.name_from_attrs` shim test (both branches)
and the `EvilQuery::VisibleShareableById.post!` waiver. The checker's
method-range fix newly required `Profile#image_url`'s camo branch (line 70);
its fixture now provisions `AppConfig.privacy.camo.proxy_remote_pod_images?`
true for one call (state provisioning, per the 2026-08-26 shim-test
clarification) → 4/4 shims PASS at 100%.

---

## Assumptions verification

- **Completion cross-check** (engine, 2026-08-26): all **180** declared
  coverage assumptions map to a manifest dimension (0 unverified) after
  adding the `mention_lookup_json_retry_1_persisted` (JRP) manifest entry.
- **Assumption driver**: `assumption_manifest.json` (24 entries) rebuilt for
  the new universe. Verified in the engine's **derived mode**
  (`assumption_checker.py --declared`), which selects, per assumption, a
  snapshot that actually *records* the exprs and tests by the assumption's
  own type via the access trace (independence: flipping both dimensions
  produces no combination-only target-call shape; untracked: the flip is
  access-trace-neutral). Result (`_assumption_derived.json`): **180 tested —
  160 PASS, 0 FAIL, 20 NOT-TESTABLE**, exit 0 (green). The 20 NOT-TESTABLE
  are exactly the `Length(SYM_PARAM_post_id) < 16` pairs — the derived
  checker's expr parser cannot read a `Length(...)` left operand (a parser
  limitation, not an unsound assumption). That single dimension,
  `SYM_PARAM_post_id`, is verified by the legacy manifest's
  `post-key-length-dispatch` independence probe: **PASS, 0 PCs / 0 notes
  evidence diff** when `post_id` is flipped to an 18-char guid. So every
  declared assumption is verified — 160 by the derived access-trace test,
  the remaining L family by the legacy flip probe. (The legacy named-manifest
  mode mis-selects snapshots for the OTHER dimensions on this batch — it keys
  only on the seed dict, not on whether the decision is live in the chosen
  run — so the derived mode is the authoritative verification for those.)

Note: the assumption gate is not wired into `completion_config.json` (it is
optional per the RUNBOOK), so `complete` reflects coverage + shims + note
check; the assumption verification above is run as the loop's Phase-4 gate.

---

## Files changed (all under this batch dir)
`concolic_targets.rb` (persisted decision; removed Person#name + Processor
mocks), `targets.rb` (name_from_attrs shim; CommentsVisibleShareableNaming;
CommentsDeviseUserNaming), `run_dse.rb` (install the two new naming modules;
real Devise auth resolution), `coverage_assumptions.py` (full rewrite),
`assumption_manifest.json` (rebuilt), `shim_tests.rb` (4 waivers +
name_from_attrs test + image_url camo branch), `concrete_manifest_anon.rb`
(mention row), `concrete_manifest_auth.rb` (new), `concrete_aliases.json`
(ci_*/devise aliases), `completion_config.json` (unchanged keys),
`merge_concrete_runs.py` + `pair_coeval_audit.py` (new helpers).

---

## Cycle 2 (2026-08-26) — engine now runs the assumption gate + all audits itself

**What the metric said at the start of the cycle.** `complete: false`.
`coverage_complete: true` (0 missing) but `completion.complete: false`,
blocking = two `assumption FAIL (IndependenceAssumption)` entries, both on
`(Length(SYM_PARAM_post_id) < 16)`:
- `L || ci_vis_first_1_not_found` — flipping both produced a guid-keyed
  `ci_vis_first ... INNER JOIN share_visibilities` shape neither single flip
  produces;
- `L || ci_author_first_1_not_found` — flipping both produced a guid-keyed
  `ci_public_first ... WHERE posts.guid = ?` shape neither single flip
  produces.
All six engine-run audits (identity_symbolicity, note lint, bind resolution,
skipped PCs, pc-visibility `--gate persisted,public`, complement) green;
shims 4 PASS / 22 WAIVED; note check green; assumptions 178 PASS / 2 FAIL.

**Why the engine is right (assumptions.py's independence test).** post_key's
guid-vs-id dispatch changes the *statement shape* of every finder in the
signed-in `||` chain, and a visibility miss is what makes the NEXT finder in
the chain execute — so (guid key, vis miss) reaches a guid-keyed author/public
finder shape that (id key, vis miss) and (guid key, vis hit) do not. The
combination produces an access pattern the individual branch trees do not
cover; that is exactly the forbidden condition. My cycle-1 argument ("L only
selects the column of the same finder call") was true for the anon chain's
single finder and false for the auth chain.

**Changes.**
1. `coverage_assumptions.py`: removed `L ⊥ {V, AU, PU}` (the three
   `ci_*_first_1_not_found` decisions). Structurally identical pairs checked:
   none other — L stays declared only against decisions that do not change
   any finder's argument shape (the anon finder's own outcome decisions,
   the found reps' persisted decisions, and the comment level, which binds
   through the post row's id). Not re-declared in any form; nothing
   untracked. `pair_coeval_audit.py`: 0 undeclared never-co-evaluated pairs,
   0 undeclared partial pairs.
2. The `L × V/AU/PU` combinations are now DEMANDED by the checker (cliques
   `{L, V, <comment level>}`, `{L, AU, <comment level>}`, …). The auth round
   had stopped at `MAX_RUNS=3000` with a non-empty worklist, so it was
   regenerated with `MAX_RUNS=40000` — worklist exhausted at 7 717 runs /
   1 202 distinct paths, `run errors : {}`; every guid-key × visibility-miss
   combination is in the corpus (the prefix-directed DSE flips each PC from
   every discovered path, and both `Length` polarities are flipped from every
   auth root).
3. Kept the coordinator's runner change: `run_dse.rb` resolves the Devise
   session with a SYMBOLIC key (`SYM_USER_CI_id`), so every signed-in view's
   principal bind renders `$$(SYM_USER_CI_id)` (identity_symbolicity green).

**Result — the engine's own final report (`coverage_summary.json`):**

| axis | value |
|------|-------|
| `coverage_complete` | **true** — 0 missing combinations (the demanded `L × V/AU/PU` cliques are all covered by the exhausted corpus), 25 nodes, 1 608 runs, 20 828 PCs, truncated=false, solver_lost=0 |
| `completion.audits` | **5/5 green** — identity_symbolicity, statement_note_lint, bind_resolution, skipped_pcs (`--patched`), pc_visibility `--gate persisted,public` |
| `completion.assumptions` | **177 declared, 177 tested, 177 PASS, 0 FAIL, 0 NOT-TESTABLE**, driver exit 0 |
| `completion.shims` | 4 PASS @ 100%, 22 reasoned WAIVER |
| `completion.note_check` | green |
| `completion.complete` | **true** (blocking = []) |
| **`complete`** | **true** |

The two engine-rejected assumptions were removed, not replaced; the
combinations they hid are now demanded and covered by exploration.

---

## Cycle 3 (2026-08-27) — the adversary voided `complete: true` (ADVERSARY_REPORT.md)

**What the metric said at the start.** `complete: true` from cycle 2 was void:
the adversary's REAL runs (no mocks) won twice and surfaced six fidelity
defects — every one a Class B blind decision with a Class S consequence:

- **W1** `Post.exists?(guid:)` — `message_renderer.rb:118-123 diaspora_links`
  issues `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?`
  whenever a comment's text carries `diaspora://<handle>/post/<guid>`; the
  corpus pinned every comment text link-free, had no `exists?` target and
  no `1 AS one` note (NOTE-MISSING + STAR-OVER in C01/C02/C03).
- **W2** the `:mobile` format (declared `respond_to :html, :mobile, :json`)
  was never a corpus scenario: `index.mobile.haml`/`_comment.mobile.haml`
  materialize through a depth-0 `Relation#to_a` (declared, zero events) and
  every PeopleHelper / `render_mentions` / delete-link conditional was
  invisible. Root cause found while repairing: the shared
  `ActionController::Rendering#render` TARGET mock returned a marker, so
  `render layout: false, locals:` never executed the template tree at all
  (json only "worked" because the presenter runs as render's argument).
- N1 array `post_id` (IN-list finder), N2 per-row `= $$()` preload notes for
  a bulk `IN (…)` + a count returned for a row list, N3 a dangling
  `mentions.person_id` with no nil decision, N5 literal-pinned
  `mention_lookup_*` handle notes, N6 `fetch_and_save` returning nil where
  the real call returns a Person or raises, and the no-profile
  `Person#fix_profile -> Discovery -> reload` path SIGSEGV-ing the JVM.

### Repairs (each: what, where, the rule it satisfies)

1. **W1 — text-content decision family (D2) + `exists?` existence probe (D1).**
   `targets.rb` §4a: the text shim is COMMENT-only now (a Post's text is
   never read on this endpoint) and mints three seeded, PC-recorded
   decisions: `_text_has_mention`, `_text_has_dlink` (a
   `DIASPORA_URL_REGEX` link), `_text_dlink_is_post` (entity `post` vs
   `comment` — the renderer's `== "post"` is on a concrete String, so the
   decision is recorded at the shim boundary). The mention handle and the
   link guid are SYMBOLIC vars whose concrete value is embedded in the text
   and mapped back at the query boundary (`CommentsTargets.text_binds`), so
   the notes bind `$$(<rep>_text_mention_handle)` / `$$(<rep>_text_dlink_guid)`
   (a real producer: the comment row) instead of literal pins (N5).
   `FinderMethods#exists?` is a declared target (§8b): note
   `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = $$(…) LIMIT 1`
   (never `posts.*`); the mock does the explicit compare and returns the
   concrete bool (`if Post.exists?` is bare truthiness), both polarities
   explored.
2. **W2 — mobile VARIANTS + real render.** `run_dse.rb` VARIANTS =
   anon/auth x json/mobile (`request.format = :mobile`, what
   `ApplicationController#mobile_switch` does); `concolic_scenario.format`
   recorded; `ctrl.response` wired. `concolic_targets.rb`: the `render`/
   `render_to_string`/`render_to_body` target mocks are gone — the real
   ActionView/JSON pipeline runs (as conversations_index does). Mobile VALUE
   fixes (§8f): datetime columns are a `ConcolicDate` (timeago), `to_param`
   leaf shim on reps (person_path/comment_path). The check that catches the
   CLASS: `format_coverage_audit.py` (wired into `extra_audit_cmds`) —
   every renderable declared format must have corpus dumps (`html` is
   TEMPLATELESS on index: responders -> MissingTemplate, a real 500).
3. **has_one / dangling-belongs_to decisions (D2; N3, "Unreachable").**
   `SingularAssociation#find_target` redeclared (§8c): `LIMIT 1`; has_one
   `profile` loads carry `<rep>_profile_not_found`; `Mention belongs_to
   :person` carries `<rep>_not_found` (`mentions.person_id` has no FK);
   `comments.author_id` (FK, cascade) and `User has_one :person` stay
   pinned found (pin ledger); a rep reloaded after discovery has its
   profile pinned found. The no-profile path now RECORDS: `Person#name ->
   fix_profile -> Discovery.new` (declared wall at the OBJECT boundary — the
   gem constructor normalizes the symbolic handle) `-> fetch_and_save`
   (declared target on the inert discovery WITH the real return kind, N6: a
   `_failed` decision — False returns a discovered Person rep, True raises
   `DiscoveryError`) `-> reload` (prepend: mints the real
   `SELECT people.* WHERE id = $$(id) LIMIT 1`, clears the association
   cache). Real-app 500s on reachable states are recorded as run OUTCOMES
   (`concolic_terminal`), never as harness failures and never swallowed as
   walls: `Template::Error` whose cause is a nil-receiver NoMethodError
   (mobile, dangling mention) or a DiscoveryError, and a bare
   DiscoveryError (json `fix_profile`).
4. **Preload fidelity (N2).** `emit_includes_preloads` notes are the bulk
   `… WHERE "people"."id" IN ($$(…))` / `"profiles"."person_id" IN (…)`
   the real Preloader issues; the load probe returns a ROW LIST
   (`IterableSymbolicList`), not a count (return-kind fidelity).
5. **Finder note fidelity (N7).** `first`/`ci_*_first`/`devise_user_first`
   notes carry `ORDER BY "posts"."id" ASC LIMIT 1` as Rails' `first` does.
6. **Array param shape (N1).** `SYM_PARAM_post_id_is_array` is a recorded
   decision (a Rack array param -> `posts.id IN (?, ?)`; `post_key` sees the
   Array's `to_s`). Never declared independent of anything (it changes every
   finder's shape — same class as the engine-rejected `Length` pairs).
7. **Assumptions rebuilt as a tier-derived builder** (`coverage_assumptions.py`,
   the conversations_index cycle-3 shape): Tier 0 variant exclusivity;
   Tier 1 a documented GATE_TABLE with explicit CLOSING polarities (source
   line per gate; an undocumented expr raises); Tier 1b never-co-evaluated
   pairs must be separated by a documented gate chain or the build raises
   (a coverage hole is never hidden as an assumption); Tier 2 leaf
   (closing-set-empty) decisions on different reps. `Length(post_id)` and
   the array-param shape are excluded from EVERY tier (withdrawn
   assumptions are never re-declared in any form) — their combinations are
   demanded and explored to worklist exhaustion. `coverage_report.py`:
   `apply_len_bounds` (SYM_LEN_* domain {0,1} as SymbolicVar bounds, no
   SymbolicConstraints) + flyweight run sharing.
8. **Concrete scenarios + judges.** `concrete_manifest_anon/auth.rb` gain
   diaspora-link comments (W1 real `exists?`), `concrete_manifest_mobile.rb`
   is new (anon via the app's own `session[:mobile_view]` switch + signed-in
   explicit `:mobile`, own-comment delete link, mentioned person); merged
   into `concrete_run.json`. `completion_config.json`: assumption gate kept
   (mandatory), `extra_audit_cmds` = format_coverage + note_fidelity; the
   five dump audits are the coordinator's. `shim_tests.rb`: `to_param` test
   (both branches), `reload` waiver.
9. **Runner flips.** var-vs-var identity compares (`comment.author ==
   current_user.person`, handle-vs-literal `StringVal` compares) are now
   flippable (seed the free operand; the Devise principal is never
   reseeded); FIFO worklist (low-order combinations first).

**Cycle 3 result — the engine's own final report (`coverage_summary.json`):**

| axis | value |
|------|-------|
| `coverage_complete` | **true** — **0 missing**, 59 nodes (was 25: mobile, the dlink family, the not-found/discovery decisions), 21 623 dumps / 9 112 distinct outcome-maps, 168 233 PCs, truncated=false, solver_lost=0, unevaluable=[] |
| `completion.assumptions` (mandatory gate) | **2 069 declared, 1 826 distinct tested, 1 826 PASS, 0 FAIL — green** |
| `completion.note_check` | **green** — every SQL-issuing target's real statements match a corpus note (anon + auth + MOBILE concrete runs merged) |
| `completion.audits` | **format_coverage green** (json + mobile scenarios present; html TEMPLATELESS), **note_fidelity green** |
| `tools/note_fidelity_audit.py` over batch + **adversary** runs | **0 MISSING / 0 STAR-OVER / 0 AGG-COLLAPSE / 0 PROJ-DIFF / 0 PRED-DIFF, 21 EXACT** — including the `SELECT 1 AS one … WHERE "posts"."guid" = ? LIMIT ?` that won W1 |
| `completion.shims` | **18 PASS, 11 PROTOCOL, 0 red** |
| `bind_resolution` (Rule V) | **UNRESOLVABLE 0, AMBIGUOUS 0, DERIVED-MISBOUND 0** — 45 525 resolved + 20 454 param/leaf |
| corpus | **4 965 dumps, regenerated FROM SCRATCH** after the D1-D9 repairs, `run errors : {}` in every round of all four variants |
| `completion.complete` | **true** — blocking = [] |
| **`complete`** | **TRUE** |
| corpus gate | `run errors : {}` in every round of every variant |

Both adversary wins are closed: W1's `exists?` existence probe is in the corpus
with a `$$()`-bound guid and both polarities of the link decisions; W2's mobile
format is a first-class variant (`Relation#to_a` at depth 0, the partial's
helper compares recorded) and `format_coverage_audit` now fails the batch if a
renderable declared format has no dumps.

The 21 shim reds are the intended Rule S state and are NOT self-waivable: 12
are the symbolic runtime's own rep plumbing (exact list in the Rule S section
below, for central exclusion), 5 are byte-faithful call-site-stable naming
prepends that reach targets BY DESIGN, 2 are boundary questions
(`ActiveRecord::Base.reload` issues SQL and belongs in the target boundary;
`obj.post_location` has no real body on the class it is installed on), and 2
are the rep persistence-state decision (`u.persisted?` / `u.new_record?`).

### Checker-cost episode (coordinator query 2026-08-27) — what the 1,220 were

The first bounded probe on the cycle-3 corpus (6,947 dumps, 4 variants,
55 PC nodes) reported `missing=1220, truncated=True` after 10,281 Z3
queries (647 s of Z3; a wrapper run of the same checker had burned hours
under the shared box's CPU contention). Decomposition: **1,220 = 305
maximal cliques × the cap of 4 witnesses** — every clique truncated, none
combinatorial per se. Each clique was `{Length(post_id), post_id_is_array}
× one post-chain gate × the comment rep's text/persisted gates × ONE
downstream rep chain` (the author chain ≈7 decisions — persisted,
profile_not_found, discovery, guid blank/present, the two orientations of
the same `author == current person` compare —, or a mention-lookup site
chain ≈5, or a mentioned-person chain ≈4). The cause was my Tier-2 model
marking the post chain, the comment-rep gates and the param decisions
"global" (dependent with everything), so every sibling chain was cliqued
with them; no withdrawn assumption was involved. Cost per query was normal
(≤0.43 s; ~850 constraints = one blocking clause per run evaluating the
clique), the query COUNT was the problem (≤120 per clique × 305).

Repair (sound structural claims, engine-verified by the flip-both probe):
the REP-CHAIN model — every decision belongs to exactly one chain (`param`,
`post`, `comment_rep`, `author`, `mention_person_N`, `lookup_msg`,
`lookup_json`, `exists_N`); cross-chain pairs are independent, same-chain
pairs stay dependent; the engine-rejected class `param × ci_*_first_1_
not_found` is excluded from EVERY tier (never re-declared: the key shape
changes which finder runs next and its statement shape). Result: 37 cliques
(max size 6), the checker completes in 26 s of Z3, and the bounded verdict
is **31 missing** = 12 `{Length, is_array} × {vis, author, public} miss`
combinations (the demanded class — exploration) + 19 within-chain
combinations of the json lookup chain / mentioned-person chain
(persisted × profile_not_found × retry, handle/guid compares — exploration).
Closed by checker-demanded rounds (`demand_round.py`: the witnesses' Z3
models replayed as worklist roots per variant).

### Closing the exploration axis (2026-08-27)

The demand rounds plateaued at 10 missing; the decomposition split them 6/4:

- **6 = a structural gate that was written but SHADOWED.** `find_or_fetch_by_identifier`
  (person.rb:318-328) returns the FIRST person only when
  `person.present? && person.profile.present?`; otherwise it discards it and
  returns the RETRY's person. So the first rep's DISPLAY compares (its guid
  blank-check in `person_path`'s journey formatter, `p.diaspora_handle ==
  diaspora_id` in mentionable.rb:35) cannot be recorded when its profile is
  missing. Corpus confirms: of the 885 runs recording a `json_first_1`
  guid/handle compare, **every one** has `profile_not_found == False`; none
  has it True. The GATE_TABLE entry existed with closing `{True, False}`,
  but the generic `_profile_not_found == True` rule (closing `{False}`,
  correct for the AUTHOR rep, which IS rendered without a profile — fix_profile
  → discovery → reload) is scanned first and shadowed it. Fixed by ordering
  the specific rule before the generic one. (Both rules keep their own source
  line; neither encodes a reachable state as impossible.)
- **4 = real states, closed by exploration.** Targeted seed roots built from a
  corpus run that reaches the lookup sites, with the demanded values set:
  msg `(persisted=False, retry_not_found=True)`, msg `(persisted=False,
  discovery_failed=True)`, json `(first_persisted=False, retry_persisted=False,
  retry_profile_not_found=False)` and the retry-discovery variant. 1 001 new
  paths; the combinations are now in the corpus (e.g. 119 dumps carry
  msg `(F, T)`).

One ops repair was needed to get a verdict at all: at 21 623 dumps the checker
was OOM-killed (137) even at 6.2 G on this shared box. `coverage_report.py` now
DEDUPES runs by their outcome map (`expr -> {polarities}`) while loading, from
the raw JSON, without building a `Run` for a duplicate. That is exactly the
representation `CoverageChecker` consumes (its `run_outcomes` + one blocking
clause per run), so no verdict changes; 21 623 dumps → 9 112 distinct maps
(12 511 duplicates skipped), 28 s. The FULL corpus is still what the note
check, the assumption gate, the audits and the hardening lint read.

## BOUNDARY CHANGES (harvest list for `shared/target_boundary.rb`)

Every change this batch made to a TARGET DECLARATION (declare_target, or a
target mock's note/return kind). None of these is endpoint-specific: each is a
property of the application's query boundary.

| target | old | new | justifying real statement / behaviour |
|---|---|---|---|
| `ActiveRecord::FinderMethods#exists?` | **not declared on this batch**; the shared design-#3 declaration returns a `SymbolicBool` with the RELATION's note (`SELECT "posts".* …`) | declared; note = the existence probe `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = $$(<text-derived guid>) LIMIT 1`; returns a **concrete** bool | `message_renderer.rb:118-123 diaspora_links` issues `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` (adversary C01/C02/C03, verbatim). TWO boundary defects: (a) `SELECT t.*` over an existence probe is a STAR-OVER (the policy inherits every column); (b) a `SymbolicBool` return is **always truthy** in `… && Post.exists?(guid: guid) ? A : B`, so the "does not exist" branch is unreachable — the decision must be an explicit compare INSIDE the mock returning a concrete bool. |
| the same `exists?` | note carried on the target event | note carried on a paired probe event (`ConcolicExistsProbe.exists_probe`), because a bare `true`/`false` cannot carry a note (the runtime attaches notes only to `SymbolicVar` returns / `concolic_note` objects) | this is why `hardening_lint` H3 still shows `FinderMethods.exists?` with an empty note. **Boundary decision needed**: either the boundary adopts the probe pattern (statement minted on the probe event, decision on the bool) or the runtime learns to attach a note to a boolean return. Not fixable inside a batch. |
| preload steps (`emit_includes_preloads`, `ConcolicThroughLoadProbe.load_intermediate`) | one note per representative row, `… WHERE "people"."id" = $$(row_author_id)` | one bulk note per preload step, `… WHERE "people"."id" IN ($$(…))` | the real `includes(person: :profile)` Preloader issues ONE statement per association per page: `SELECT "people".* FROM "people" WHERE "people"."id" IN (?, ?)` and `SELECT "profiles".* … WHERE "profiles"."person_id" IN (?, ?)` (adversary N2; every concrete run). |
| the same load probe | returned `symint("<name>_row_count", 1)` — an aggregate kind | returns a row LIST (`IterableSymbolicList`, length-only, no representative) | a preload step returns rows, not a count (adversary N2 return-kind mismatch). |
| `DiasporaFederation::Discovery::Discovery#fetch_and_save` | `-> nil` | declared with a `<rep>_discovery_failed` decision: False ⇒ returns a `Person` rep, True ⇒ raises `DiscoveryError` | discovery.rb:19-24 returns a Person or raises `DiscoveryError`; `find_or_fetch_person_by_identifier` rescues the error to nil (NO retry lookup), while a success makes the retry find the freshly saved row (adversary N6). Returning nil made the retry fire in cases where the real code raises. |
| `DiasporaFederation::Discovery::Discovery.new` | not declared (only `fetch_and_save` was) | declared: returns an inert discovery | the gem CONSTRUCTOR normalizes the handle (`clean_diaspora_id`: strip/sub/downcase) before `fetch_and_save` is reached, so a wall on `fetch_and_save` alone leaves a `SymbolicString#strip` wall — and the real constructor+fetch aborts the JVM natively on this JRuby (adversary C08/C08b/C09/C10 all SIGSEGV). The wall must sit at the object boundary. |
| `SingularAssociation#find_target` | `SELECT "t".* … WHERE fk = $$(…)` (no LIMIT), always returns a rep | `… LIMIT 1`; has_one loads carry a `<rep>_profile_not_found` decision; `Mention belongs_to :person` carries `<rep>_not_found` | the real association load is `SELECT … LIMIT ?`. `profiles.person_id` has NO foreign key and `mentions.person_id` has none either (schema.rb): a person without a profile and a mentions row pointing at a missing person are both real DB states (adversary N3: `[null]` in JSON, a 500 on mobile). Always returning a rep encodes them as impossible. Which belongs_to loads may be PINNED found is per-endpoint (FK + ON DELETE CASCADE), but the has_one decision is boundary-level. |
| single-row finders (`first`/`last`/`take`/`find_by` + the batch's call-site aliases) | relation SQL only | `… ORDER BY "t"."id" ASC LIMIT 1` when the relation carries no order | Rails' `first`/`last` order by the primary key (finder_methods.rb `ordered_relation`) and every single-row finder limits to 1; the real statements show `ORDER BY "posts"."id" ASC LIMIT ?` (adversary N7). |
| `ActionController::Rendering#render` / `render_to_string` / `render_to_body` | declared targets returning a marker symbol | **not declared** — the real ActionView/JSON pipeline runs | the marker swallowed the ENTIRE mobile render tree: `index.mobile.haml` materializes the collection through a depth-0 `Relation#to_a` and every partial/helper conditional (`person_image_link`'s `profile.nil?`, `person_link_class`'s self/hovercardable, the delete link's `comment.author == current_user.person`, `render_mentions`, `format_tags`) was invisible (adversary W2). `conversations_index` already runs render for real; the boundary should say so for every batch that has templates. |
| `MessageRenderer::Processor.process` (and `MessageRenderer#title`) | declared target returning the concrete text | **not declared** — the renderer pipe runs | the pipe reaches `diaspora_links` → `Post.exists?` (a target). A non-SQL note over a target-reaching body is the N-1 class; the correct shim is the pure string leaf, not the pipe entry. |

**Reported, not fixed (Rule 3 — boundary items I did not touch):**
- `ActionDispatch::Journey::Router::Utils.escape_segment` is declared as a TARGET
  in all five copies of `concolic_targets.rb` (36 hits). Its body is pure URL
  escaping that reaches no target — it is a SHIM, not a target, and as a target
  it shows up as an opaque note (`hardening_lint` H3).
- `Anonymous.new` in the corpus target list is the `Discovery.new` wall declared
  on a singleton class (the runtime names singleton-class targets "Anonymous").
  Legibility issue in the boundary, not a swallow: the wall is documented.

## Hardening lint answers (`hardening_lint.py --sample 400`)

- **H1 formats** — green (anon/auth × json/mobile scenarios present).
- **H2 link-bearing text** — the `exists?` target and the `1 AS one` note are
  present. "seeded text values carrying `diaspora://`: NO" is by construction:
  the link is a seeded DECISION (`_text_has_dlink`, `_text_dlink_is_post`) and
  the text is built from it, so the seed dict carries booleans, not the text.
- **H3 opaque notes** — `FinderMethods.exists?`: answered above (the statement
  is minted on the paired probe event; a bare bool cannot carry a note) —
  BOUNDARY item. `Anonymous.new` = the documented `Discovery.new` network wall.
  `Anonymous.escape_segment` = the shared pure-URL leaf mis-declared as a
  target — reported, not fixed (Rule 3).
- **H4 collection length** — the DECISION is explored both ways in the corpus:
  `(len(to_a_1_rows) != 0)` is recorded True in 9 696 runs and False in 383.
  The lint sees a single SEEDED value (0) because 1 is the default and only the
  empty side needs a seed. The domain is {0, 1} by design (Gate 1b sampled
  list: one representative row), which `apply_len_bounds` declares as the
  variable's bounds — "many" is an honest, documented limit of the runtime's
  list model, not a pin.
- **H5 pinned type columns** — `commentable_type = 'Post'`,
  `mentions_container_type = 'Comment'`, `shareable_type = 'Post'` are not pins
  over a decision: each is a CONSTANT of the association scope the statement
  comes from (`post.comments`, `comment.mentions`, EvilQuery's
  `joins(:share_visibilities)`), and the REAL statements carry the same
  literals — the note-fidelity audit matches them EXACT (predicate columns and
  values) against the concrete runs. Ledger: the polymorphic type is fixed by
  the OWNER's class at the call site, not by row data; a Post STI subclass
  still stores `'Post'` in `commentable_type` (`base_class`).





## Rule G (DISCIPLINE §11) — the gate list and the pin ledger, made disjoint (2026-08-28)

`pc_visibility_audit --gate persisted,public` went RED after the D3 fix:
`persisted` reported **BLIND (0 references)**. That was the audit reading the
situation correctly — the column is no longer a decision because D3 PINNED it,
and a pinned column left in the gate list reads as a blind branch.

**`pc_gate_columns` is now `["public", "diaspora_handle", "author_id", "person_id"]`** —
every one VISIBLE (1 745 / 657 / 3 086 / 3 086 references), audit **pass**.
`text` was considered and deliberately left OUT: the app never compares the
`text` column, it SCANS it, and the scan's outcomes are their own decisions
(`_text_has_mention`, `_text_has_dlink`, `_text_dlink_is_post`).

### PIN LEDGER — the columns the app compares that are NOT in the gate
Rule G requires these two lists to be disjoint and jointly complete. Each entry
below is the licence for its column's absence from the gate:

| column / state | pin | ledger entry (the licence) |
|---|---|---|
| `persisted?` | pinned TRUE | **D3**: every rep on this endpoint is produced by a finder / materialize / association-load target, i.e. a row the database returned; the unpersisted arm of `mentions_container.rb:17-23` is a create-path state this action cannot reach. Confirmed by 14 real runs in which `people_from_string`, `fix_profile` and every `find_by(diaspora_handle:)` fired zero times. |
| `guid`, `*_guid` | pinned CONCRETE (non-blank) | **D4**: `Diaspora::Fields::Guid` sets `after_initialize :set_guid` (guid.rb:6-17), so no loaded record carries a blank guid — proved with a real `guid=''` row that rendered 200 with a freshly generated guid (A06). No query on this endpoint binds a rep's guid column. |
| `commentable_type` | pinned `'Post'` | **H5**: a CONSTANT of the association scope the statement comes from (`post.comments`), not row data; the real statements carry the same literal, matched EXACT by the fidelity audit. A Post STI subclass still stores `'Post'` (`base_class`). |
| `mentions_container_type` | pinned `'Comment'` | **H5**: constant of `comment.mentions`' scope; real statements carry the same literal. |
| `shareable_type` | pinned `'Post'` | **H5**: constant of EvilQuery's `joins(:share_visibilities)` scope; real statements carry the same literal. |
| `text` (content) | pinned CONCRETE, with seeded content decisions | the string pipes (`scan`, `gsub`) need a concrete String; its branch-relevant PROPERTIES are decisions (`_text_has_mention`, `_text_has_dlink`, `_text_dlink_is_post`), so the branches stay visible. Blank text is a documented non-state: `Comment validates :text, presence: true` (adversary D9's own classification). |

### Hardening-lint answers against the NEW corpus
- **H1** green. **H2** green (`exists?` target + `1 AS one` note present; the link
  is a seeded DECISION, so the seed dict carries booleans, not `diaspora://`
  text — by construction).
- **H3 — REPAIRED, now green** ("every non-wall target carries SQL notes"). The
  last opaque note was `Anonymous.new` — `Discovery.new` declared as a target,
  which the interceptor names after its singleton class. Constructing the
  discovery client is not data access, so it is now a SHIM (prepend returning
  the inert client) with a shim test over the gem's real constructor; the WALL
  that matters, `fetch_and_save`, is still a declared target carrying the
  `<rep>_discovery_failed` decision. Same treatment as B-2.
- **H4 — answered, no repair possible or needed.** All FOUR length dimensions
  are decisions recorded with BOTH polarities in the corpus
  (`records_1/2/3_rows` and `to_a_1_rows`, each `[False, True]`). The lint sees
  one SEEDED value (0) because 1 is the default and only the empty side needs a
  seed. The domain is {0, 1} by design (Gate 1b: a sampled list holds one
  representative row), declared to the checker as the variable's bounds by
  `apply_len_bounds`; "many" is a documented limit of the runtime's list model,
  not a pin. D9 closed the half of this the lint could not see — the json
  variants now carry the decision too.
- **H5 — documented pins**, ledger entries above.

## Adversary round 2 — defects D1/D3/D4/D5/D6/D8/D9 closed (2026-08-28)

Round 2 found **no wins** (W1/W2 verified closed by real runs, B-2 clean) but
logged nine defects, most of them making the extracted policy BROADER than
reality — which our own rule counts as a defect, not a safe
over-approximation. Seven were mine; all seven are closed. The corpus was
regenerated FROM SCRATCH (the target set and the PC universe both changed).

| # | defect | fix |
|---|--------|-----|
| **D1** | the array-`post_id` family modelled the WRONG `post_key` branch (`posts.guid IN (…)`; `posts.id IN` appears in 0 dumps), left `Length(post_id) < 16` unrecorded in all 3 639 of its dumps, and a real ActionDispatch probe showed `?post_id[]=` can never reach the action (path params win) | **family removed.** `run_dse.rb` passes the scalar the route guarantees; the wrong branch was an artefact of a concolic Array rendering `to_s` as inspect strings (always ≥ 16 chars) |
| **D3** | 9 219 `people.diaspora_handle` note events for the `persisted? == false` arm — a state no query-returned comment can be in (0 real firings across 14 runs) | **`persisted?` PINNED TRUE** with a ledger entry: every rep here comes from a finder/materialize/association-load target, i.e. a row the database returned. The whole unreachable `people_from_string` → handle-lookup chain is gone |
| **D4** | `…_guid == ''` taken TRUE in 3 547 dumps, though `after_initialize :set_guid` makes a blank guid impossible on a loaded record (proved with a real `guid=''` row → 200) | **guid columns PINNED CONCRETE** (non-blank) with a ledger entry; no query on this endpoint binds a rep's guid column, so no evidence is lost |
| **D5** | `User has_one :person` pinned found on a FALSE neutrality argument — a signed-in user with no `people` row is a real DB state that issues the vis SELECT and then 500s at `evil_query.rb:116`, never issuing the author/public SELECTs | **decision modelled** (`<principal>_person_not_found`), and the resulting `NoMethodError` on nil is recorded as a run TERMINAL (scoped to signed-in variants + the nil-receiver message) instead of being swallowed |
| **D6** | `Post.exists?` capped at 1 probe per dump; a real link-bearing comment issues one per `post` link | **cardinality fixed**: the shim text now carries THREE post links, each with its own free-value guid parameter, plus a `comment`-entity link (which issues nothing — the entity compare stays a decision). Corpus now shows `exists__1/2/3` |
| **D8** | 13 626 dumps emitted the bulk preload AND a per-row `find_target` with the identical bind — the same read counted twice, and a second producer edge for the fold | **the preload now ATTACHES the loaded target** to the owner rep (`mark_loaded`), so `comment.author` / `author.profile` hit AR's association cache and never reach `find_target` — exactly what real AR does after `includes(author: :profile)`. The has_one step keeps its `_not_found` DECISION and attaches nil on that side, as the real Preloader leaves it. The only surviving `find_target` is `User has_one :person`, which is the only one real runs issue |
| **D9** | the json variants had NO collection-length decision (H4 held for half the corpus); plus a wrong FK fact in a §8c comment | **`each`/`map` on the sampled list now record the canonical `(len(X) != 0)` compare** — `BasePresenter.as_collection` reaches the list through `Enumerable#map` → `each`, which is why json carried none. The FK comment is corrected: `schema.rb:643` constrains profiles → people, not people → profiles (the conclusion stands, the justification was wrong) |

D2 and D7 are instrument defects (D7 was the coordinator's `ConcreteEnv.quote`
boolean bug, now fixed — the real cause of the long-standing "JDBC boolean
artefact"). **B-1 `reload` remains unverifiable by a real run**, because its
only call site sits behind the JVM-aborting discovery path — recorded as a
documented limitation, not hidden.

Effect on the universe: **59 → 31 PC nodes**. The removed nodes were the
phantom families (array param, persisted, blank guid, the handle-lookup chain);
the added ones are real (three exists probes, the principal's person decision,
the json collection length).

## BOUNDARY CHANGES — applied from coordinator harvest B-1/B-2 (2026-08-28, Rule T2)

Both applied verbatim in this batch, then the corpus was regenerated FROM
SCRATCH (full exploration — the target set changed, so a replay would have
been invalid).

### B-1 — `ActiveRecord::Base#reload` is now a TARGET (was a shim)
`targets.rb` §8d. The prepend is gone; the declaration mints exactly the
statement the real body (`self.class.unscoped { self.class.find(id) }`)
issues, with the bind taken from the RECEIVER's own id var via
`render_arg_value` — never a literal:

```
SELECT "<table>".* FROM "<table>" WHERE "<table>"."id" = $$(<rep>_id) LIMIT 1
```
e.g. `SELECT "people".* FROM "people" WHERE "people"."id" = $$(SYM_RESULT_…_row_person_id) LIMIT 1`

- **return**: the RECEIVER itself (`reload` returns self). The rep's attribute
  vars are deliberately NOT re-minted — this batch models a row as ONE var
  family, and a second family for the same row would fork the fold's producer
  chain (the var identity IS the evidence). The receiver's `concolic_note` is
  re-pointed at the reload statement so the event carries that note, and the
  association cache is cleared exactly as `Base#reload` does.
- **not-found**: `find` raises `RecordNotFound`, but on this endpoint `reload`
  is reached only from `Person#fix_profile` — after the row was returned by a
  finder in the SAME request and after discovery either saved it or raised. The
  row cannot be gone, so it is **PINNED FOUND** with a pin-ledger entry
  (`<rep>_reload_not_found`, pinned false, neutrality argument in the code
  comment); no `_not_found` decision is minted.
- the `reload` entry was DELETED from `shim_tests.rb` — it is no longer a shim.

### B-2 — `escape_segment` is no longer a target, it is a SHIM
`concolic_targets.rb` X8d. The `declare_target(…singleton_class, :escape_segment)`
block is replaced by a prepend that concretizes the argument and `super`s into
the REAL escaper, so no junk note and no symbolic result are minted on every
route generation:

```ruby
module ConcolicEscapeSegmentShim
  def escape_segment(segment)
    super(segment.respond_to?(:value) ? segment.value.to_s : segment.to_s)
  end
end
ActionDispatch::Journey::Router::Utils.singleton_class.prepend(ConcolicEscapeSegmentShim)
```

and the shim test that proves the contract (zero targets, real body, 100 %):

```ruby
"ActionDispatch::Journey::Router::Utils.singleton_class.escape_segment" => {
  targets: AR_TARGETS,
  reaches: [],
  coverage_of: [ActionDispatch::Journey::Router::Utils, :escape_segment, :singleton],
  fixture: -> {
    ActionDispatch::Journey::Router::Utils.escape_segment("a b/c?d")
    ActionDispatch::Journey::Router::Utils.escape_segment("plain")
  } },
```

The shim rig does not install this overlay, so `Utils.escape_segment` there IS
the original body (journey/router/utils.rb:84-86) — the same arrangement the
`h.image_path` shims rely on. Verdict: **PASS**. `escape_segment` no longer
appears in the corpus as a target at all.

## bind_resolution repair (2026-08-28) — text-derived values are PARAMETERS, not row columns

The five SQL-consumer audits found `bind_resolution` RED on the cycle-3
corpus: **7 183 UNRESOLVABLE binds**, all of them the values I introduced when
modelling the link/mention families —
`…_row_text_mention_handle` (4 207 + 2 976), consumed by
`SELECT "people".* … WHERE "people"."diaspora_handle" = $$(…)`. An
unresolvable bind becomes a PLACEHOLDER VIEW at extraction, i.e. the very
queries cycle 3 made reachable would have been lost on the way out.

**Repair.** Both text-derived values are now minted as free VALUES of the
policy — `SYM_PARAM_mention_handle_<rep>` and `SYM_PARAM_dlink_guid_<rep>`,
with a NON-SQL note ("free value … parsed out of the comment text") — so the
fold classifies them `param/leaf` and renders a parameter placeholder.
Verified: `UNRESOLVABLE: 0, AMBIGUOUS: 0` over 141 329 resolved + 37 932
param/leaf binds. No PC anywhere referenced either var (checked before the
change), so the PC universe, the assumption set and every coverage verdict are
untouched; the corpus was regenerated by REPLAYING every existing seed set
(`SEEDS_ONLY`, one dump per root), which reproduces the same paths
deterministically — 13 767 dumps, `run errors : {}` in all four variants.

**Why the parameter family and not a producer link** (coordinator asked to
prefer the producer link where one exists): at column granularity it does not
exist here. The fold resolves `$$(VAR)` to `producer_row.column`, and
`_match_column` accepts the LONGEST underscore-delimited suffix of the var
name that is a real column of the producer's table. A mention handle or a
link guid is a SUBSTRING OF `comments.text`, not a column of the comments row,
so the only honest rendering is a parameter placeholder — binding it to a
column would assert a join the app never performs.

**Finding for the coordinator (same class as violation 5, mis-attributed
chain).** `conversations_index` mints the identical shape
(`#{base_name}_text_dlink_guid`, `note: sql`) and its audit passes — but only
by ACCIDENT of that suffix rule: the name ends in `guid`, which IS a column of
`messages`, so the bind silently resolves to **the row's own `messages.guid`**.
Their extracted view therefore claims `posts.guid = messages.guid` — the
link-target guid folded onto the containing message's guid, a join the app
never makes. A green `bind_resolution` does not distinguish "resolved
correctly" from "resolved to whatever column the name happens to end with";
their `_text_dlink_guid` (and any future `_text_*_<column-name>` var) should
move to the `SYM_PARAM_*` family for the same reason mine did.

## Rule S round 2 (2026-08-27 evening) — shims worked to green

With the two mechanisms in place (`PROTOCOL` decided by the runner from the
real class; `reaches:` equality for dispatch/naming layers), the shim table is
**13 PASS + 13 PROTOCOL + 2 red**, both reds coordinator-owned:

| verdict | count | keys |
|---|---|---|
| PASS (final, 2026-08-28) | 17 | the 14 below **plus** `obj.post_location`, `ActiveRecord::Base.singleton_class.DYNAMIC`, `ActiveRecord::Relation.DYNAMIC` — see "three that the updated runner re-classified" |
| PASS (as of 2026-08-27) | 14 | h.image_path, h.path_to_image, Person.name_from_attrs, User.authenticatable_salt, ActiveRecord::Base.to_param, obj.image_url, obj.hidden_shareables, u.persisted?, u.new_record?, EvilQuery::VisibleShareableById.post!, OrmAdapter::ActiveRecord.get, Person.singleton_class.find_or_fetch_by_identifier, Person.singleton_class.DYNAMIC, **CommentPresenter.as_json** |
| PROTOCOL | 13 | obj.{read_attribute, _read_attribute, attributes, write_attribute, _write_attribute, inspect, concolic_attrs, concolic_note, persisted?, new_record?, post_location}, ActiveRecord::Base.singleton_class.DYNAMIC, ActiveRecord::Relation.DYNAMIC |
| FAIL-WAIVER-NOT-ALLOWED | 1 | `ActiveRecord::Base.reload` — **BOUNDARY B-1**, left red per directive |

`CommentPresenter.as_json` turned PASS under DISCIPLINE §9 rule 6 (2026-08-28):
a STRAIGHT-LINE body (no conditional, loop, block-iterator, rescue/ensure,
ternary or short-circuit anywhere in its range) whose ENTRY line executed is
accepted as covered — such a body cannot be partially executed, so the claim
is stronger than the line counter's. The evidence this batch produced (the
returned key list plus `counts 8..17=[1, nil, 1, 0, 0, 0, 0, 0, nil, nil]`)
is what the rule was written from. NOTE for other batches: a presenter
`as_json` that DOES contain a conditional keeps the 100 % bar and must be
tested per branch.

What changed in `shim_tests.rb`:
- **Deleted** every rep-plumbing entry (they now come back PROTOCOL from the
  runner's runtime check). No entry came back NO-TEST, so there is no tagging
  gap to report. `obj.post_location` is PROTOCOL for the right reason: base
  `Post` defines no such method (only `Reshare` does).
- **New real tests** (real body, zero targets, 100 % lines): `u.persisted?` /
  `u.new_record?` against the AR persistence protocol on a real `User`;
  `User.authenticatable_salt`; `obj.hidden_shareables`; and the two asset
  helpers with their coverage waivers removed.
- **New `reaches:` specs** for the dispatch/naming layers, each running the
  REAL shadowed body against a real sqlite fixture DB (the concrete rig — data
  only, no code-under-test stubbed) and asserting target-set EQUALITY:
  - `EvilQuery::VisibleShareableById.post!` → `{FinderMethods#first}`; the
    fixture's post is public, unshared and not the querent's, so all three
    branches of the `||` chain evaluate (100 % lines).
  - `OrmAdapter::ActiveRecord.get` → `{FinderMethods#first}`.
  - `Person.find_or_fetch_by_identifier` → `{Core::ClassMethods#find_by,
    SingularAssociation#find_target}`; `dave` has no profiles row, so the
    guard fails and the discovery + retry lines run. ONE justified mock: the
    federation gem is swapped for an inert double for the duration — a network
    boundary no test may cross (it also natively aborts this JRuby).
  - `Person.singleton_class.DYNAMIC` (kwargs wrappers) → `{FinderMethods#find_by}`,
    covering both the happy line and the `rescue ::RangeError` arm.
- **Byte-faithfulness** is asserted inside each prepend fixture
  (`assert_byte_faithful!`): both method bodies are extracted from source,
  comments/blank lines dropped, whitespace collapsed, the declared renames
  applied to the ORIGINAL, and the two compared — e.g. `post!`'s three
  successive `.first` → `ci_vis_first` / `ci_author_first` / `ci_public_first`.
  The assertion is live: it FAILED the first run (a too-naive rename spec) and
  had to be made exact.


### Three that the updated runner re-classified (2026-08-28)

The runner's new `machinery?` only grants PROTOCOL for an unresolvable
receiver when the method is in the protocol API, so three keys that had been
PROTOCOL came back NO-TEST. All three now have real tests, and one of my prose
claims was REFUTED by the runner in the process:

- `obj.post_location` — I had written "base `Post` defines no such method, so
  there is no real body to run". Stating it as a checkable
  `real_class: "Post"` returned **FAIL-NOT-PROTOCOL**: the rule is "not
  protocol ⇒ test it", whatever the receiver lacks. The body the rep actually
  stands in for is `StatusMessage#post_location` (status_message.rb:98-104),
  which READS the `location` has_one — so it is a `reaches:` test
  (`{SingularAssociation#find_target}`), not a zero-target one, on a real
  `StatusMessage` from the fixture DB. PASS.
- `ActiveRecord::Base.singleton_class.DYNAMIC` — the kwargs re-pack on a CLASS
  receiver. My first spec pointed at `FinderMethods#find_by!` and the runner
  answered FAIL-REACHES with that body never entered: `Model.find_by!`
  resolves to `Core::ClassMethods#find_by!`. Re-pointed at the body that
  actually runs. PASS.
- `ActiveRecord::Relation.DYNAMIC` — same layer on a RELATION receiver;
  `FinderMethods#find_by`, both the happy line and the `rescue ::RangeError`
  arm. (Its `find_by!` sibling was FAIL-COVERAGE at 75 %: the missed line is
  the continuation line of a multi-line `raise` inside a `rescue`, so §9
  rule 6 does not apply — choosing the body that the layer really shadows
  fixed it honestly rather than arguing about the counter.)

### PATTERN — testing a shim whose real body crosses a NETWORK boundary
(named at the coordinator's request, 2026-08-28, so other batches copy it
rather than invent their own)

`Person.find_or_fetch_by_identifier` (person.rb:318-328) cannot be covered
without running its discovery arm, and that arm is a real webfinger fetch —
a boundary no test may cross, and on this JRuby it also aborts the JVM
natively (SIGSEGV; the adversary could not run it at all: C08/C08b/C09/C10).
The shape that works:

```ruby
fixture: -> {
  shim_env!                                   # real sqlite DB + real rows
  real  = DiasporaFederation::Discovery::Discovery
  inert = Class.new { def initialize(*); end; def fetch_and_save; nil; end }
  DiasporaFederation::Discovery.send(:remove_const, :Discovery)
  DiasporaFederation::Discovery.const_set(:Discovery, inert)
  begin
    Person.find_or_fetch_by_identifier("alice@localhost")    # profile found -> early return
    Person.find_or_fetch_by_identifier("dave@remote.example")# no profiles row -> discovery + retry
  ensure                                                     # ALWAYS restored
    DiasporaFederation::Discovery.send(:remove_const, :Discovery)
    DiasporaFederation::Discovery.const_set(:Discovery, real)
  end
}
```

Four properties make it legitimate, and a copy should keep all four:
1. **The double replaces only the boundary class**, never the method under
   test: `find_or_fetch_by_identifier`'s own body — the guard, the discovery
   CALL, the retry lookup — runs for real, which is what the coverage and the
   `reaches:` equality are measured over.
2. **The double is inert, not a stand-in for logic**: it returns `nil`, the
   same shape the walled target returns; it makes no decision the test then
   relies on.
3. **Both arms are driven by DATA, not by the double** — `alice` has a
   profiles row, `dave` (deliberately) has none. The branch is chosen by the
   fixture DB, so the test exercises the real guard.
4. **The swap is reverted in `ensure`**, so no later shim test in the same
   process sees a patched constant.

The same shape applies to any gem boundary a batch walls (Sidekiq push,
federation entities, HTTP fetchers): swap the CLASS at its edge, keep the app
method real, drive the branch from fixture data, restore in `ensure`.

### The one non-coordinator red: `CommentPresenter.as_json` is a JRuby artifact
`coverage_pct` 28.6, missed lines 11-15 — the five element lines of the
multi-line hash literal. The fixture now PROVES the method evaluates all of
them: it asserts the returned hash carries all six keys, and the run prints
`as_json returned keys=[:id, :guid, :text, :author, :created_at,
:mentioned_people] coverage counts 8..17=[1, nil, 1, 0, 0, 0, 0, 0, nil, nil]`.
The method returns every value, so every element expression executed; JRuby's
Coverage attributes them all to line 10 (the literal's first element) and
reports 0 for lines 11-15. No fixture can lift this to 100 %: it is a
measurement limitation of JRuby line coverage inside a multi-line hash
literal, not an unexercised branch. **Coordinator decision requested** (the
same shape will hit every presenter `as_json` in every batch).

## Rule S round 1 (superseded by the table above) — the original exclusion list

Standalone shim run after converting every convertible waiver into a real
test (`_shim_results_rules.json`): **7 PASS, 21 FAIL-WAIVER-NOT-ALLOWED**
(was 4 PASS / 22 waivers).

Converted to real tests (real body, real receiver, zero targets, 100 % lines):
- `h.image_path`, `h.path_to_image` — the coverage waivers were unnecessary:
  `AssetUrlHelper#image_path` is a one-line delegation and covers 100 % once
  `check_precompiled_asset` is provisioned (a config VALUE, not a stand-in).
- `User.authenticatable_salt` — real Devise body (`encrypted_password[0,29]`)
  on a constructed `User` carrying an `encrypted_password` fixture value.
- `obj.hidden_shareables` — real `User#hidden_shareables`
  (`self[:hidden_shareables] ||= {}`), both sides of the `||=`.
(plus the already-passing `Person.name_from_attrs`, `obj.image_url`,
`ActiveRecord::Base.to_param`.)

### A. Runtime rep plumbing — EXACT LIST for central exclusion (Rule S structural exception)
These are the symbolic runtime's own rep plumbing on `symbolic_instance`
objects (`concolic_targets.rb`), not mocks over application code:
```
obj.read_attribute      obj._read_attribute     obj.attributes
obj.write_attribute     obj._write_attribute    obj.inspect
obj.concolic_attrs      obj.concolic_note
```
Two more that I believe belong to the same class (coordinator to decide):
```
obj.persisted?   obj.new_record?    # the rep's persistence-state boundary
u.persisted?     u.new_record?      # decision; replaces AR's @new_record ivar
                                    # read on an allocated rep. Its EVIDENCE is
                                    # the `<rep>_persisted` PC, which is what
                                    # makes the mentions/1=0 branches visible.
ActiveRecord::Base.singleton_class.DYNAMIC   # ConcolicKwargsToPositional:
ActiveRecord::Relation.DYNAMIC               # the runtime's kwargs re-pack for
Person.singleton_class.DYNAMIC               # the interceptor's param binding
```

### B. Call-site-stable naming prepends — cannot satisfy the zero-target probe
Their entire purpose is to call the aliased finder TARGETS; running the real
body under the probe necessarily reports targets reached. Byte-faithfulness is
the property that matters, and it is checkable by reading them against the app
source (each is a verbatim copy with only the finder NAME changed):
`EvilQuery::VisibleShareableById.post!` (evil_query.rb:102-105),
`Person.singleton_class.find_or_fetch_by_identifier` (person.rb:318-328),
`OrmAdapter::ActiveRecord.get` (orm_adapter 0.5.0 #get),
`CommentPresenter.as_json` (comment_presenter.rb),
`Person#fix_profile` (person.rb:371-375, thread-local tag around `super`).
**Coordinator decision requested** — what assertion replaces zero-target for a
naming prepend (e.g. "the set of target calls is IDENTICAL to the unprepended
body's", which is the property that actually matters)?

### C. Two that are boundary questions, not shims
- `ActiveRecord::Base.reload` — AR's real `reload` ISSUES SQL
  (`self.class.unscoped { self.class.find(id) }`). A method that issues a
  statement is a TARGET, not a shim: it belongs in
  `shared/target_boundary.rb` with the note
  `SELECT "t".* FROM "t" WHERE "t"."id" = $$(id) LIMIT 1` (this batch already
  mints exactly that through the load probe). Listed under BOUNDARY CHANGES.
- `obj.post_location` — base `Post` does NOT define `post_location` (only
  `Reshare` does); the shim supplies a method the receiver class lacks, so
  there is no real body to run for a Post rep. Either the rep should not carry
  it (and `PostPresenter#non_directly_retrieved_attributes` is then out of
  scope for this endpoint) or it is a Reshare-only shim tested on Reshare.

---

## Cycle 5 (2026-08-28) — adversary round 3: M-3 and M-4 closed, plus N3-1…N3-4

Round 3 (`ADVERSARY_REPORT_3.md`) scored **two wins** against the cycle-4
corpus and logged five near-misses. Both wins and four near-misses are closed
here. The corpus was regenerated **from scratch** (the modelling of the
preload step and of the comment text both changed; a replay would have been
invalid).

### The metric table

| metric | cycle 4 (attacked) | cycle 5 |
|---|---|---|
| `complete` | true | **true** |
| coverage | 0 missing, 31 PC nodes | **0 missing, 46 PC nodes** |
| corpus | 4 965 dumps / 4 957 runs / 73 032 PCs | **8 243 dumps / 6 872 runs / 120 309 PCs** |
| `run errors` | {} | **{} in all four variants** |
| assumptions | 559 declared, 489 tested, 489 PASS | **1 241 declared, 1 095 tested, 1 095 PASS** |
| assumption manifest | 24 entries, **17 of them dead** | **21 entries, all live** |
| shims | 19 PASS / 11 PROTOCOL / 0 red | **19 PASS / 11 PROTOCOL / 0 red** |
| note check | green | **green** (`find_target` now matches **2** real shapes) |
| note fidelity | 21 EXACT / 0 MISSING | **14 EXACT / 0 MISSING / 0 STAR-OVER / 0 PROJ-DIFF / 0 PRED-DIFF** |
| SQL-consumer audits | 5 green | **6 green** (the new `empty_relation_emission_audit` included) |
| `…_row_person_not_found` PCs | **0** (the regression) | **11 112** (2 235 True) |
| `Template::Error ← NoMethodError` terminals | **0** | **199** |
| empty-relation over-emission | 2 619 states / 5 238 phantom notes | **0** (2 275 empty-list states, audit PASS) |
| `Post.exists?` per-dump cardinality | {0, 2, 3} | **{0, 1, 2, 3, 4}** (3 039 / 2 156 / 1 263 / 806 / 979) |
| `users.language` | in neither gate nor ledger | **gated and VISIBLE (4 901 refs)**; 1 646 T / 3 255 F |
| principal `profiles` read | absent from every dump | **1 642 dumps** carry its not-found decision; the note is EXACT |

### W3-1 / M-3 — the `Mention belongs_to :person` not-found decision, restored as ONE predicate used by BOTH sites

Root cause exactly as reported: the cycle-4 **D8** preload-attach repair gave
`emit_includes_preloads` a not-found arm on the `has_one` side only, so the
`belongs_to` side always attached a rep — and, because the attach made
`find_target` unreachable, `targets.rb`'s own `Mention belongs_to :person`
decision became dead code. Two places modelled the same load and disagreed.

Repair (`targets.rb`, `CommentsTargets.dangling_belongs_to?`): **one
predicate, both call sites.**

```ruby
FK_UNCONSTRAINED_BELONGS_TO = { "Mention" => %w[person] }.freeze   # schema.rb:202-209, no add_foreign_key
def dangling_belongs_to?(owner, refl)   # asked by emit_includes_preloads AND by §8c find_target
```

- the preload step's own statement is still emitted on both arms (the real
  run issues `SELECT people.* … IN (…)` and gets zero rows);
- the not-found arm attaches **nil** (`mark_loaded`) and **skips the nested
  `profiles` step**, because AR preloads the next level from the records it
  actually loaded;
- `comments.author_id` is deliberately NOT in the table: `schema.rb:624`
  carries `add_foreign_key "comments", "people", column: "author_id",
  on_delete: :cascade`, so a dangling comment author is not a database state
  (pin ledger).

**Verified by a REAL run** — `concrete_manifest_r3.rb` (new; real sqlite,
real Devise, real `ActionController::TestCase#process`, so the whole
before_action chain runs), scenarios `r3-dangling-mention-json` /
`-mobile` / `r3-live-mention-json`:

```
r3-dangling-mention-json   200, body …"mentioned_people":[null]
   … SELECT "mentions".* …            SELECT "people".* WHERE "id" = ?     <- and STOPS
r3-dangling-mention-mobile EXC ActionView::Template::Error <- NoMethodError:
                                undefined method `diaspora_handle' for nil:NilClass
r3-live-mention-json       200; every mentions load IS followed by a profiles read
```

The control (`live-mention`) issues `people` **and** `profiles` for the same
shape, so the missing `profiles` read in the dangling case is the decision's
consequence, not a fixture artefact.

### W3-2 / M-4 — no preload, no representative row, before the list length is known

`rows_mock` read the list length FIRST and mints nothing below the list until
it is known non-empty:

```ruby
len = Integer(ct.seed_for("len(#{vn})", 1))
rep = nil
if len.positive?
  rep = ct.symbolic_instance(...)           # a query that returned no rows has no row to represent
  emit_includes_preloads(ct, receiver, rep) # Preloader#preload returns early on zero records
end
IterableSymbolicList.new(len, name: vn, note: sql, representative: rep)
```

This removes BOTH halves of the finding: the 5 238 phantom preload notes and
the 3 080 decisions over rows that do not exist (the text/`profile_not_found`
families were minted by `symbolic_instance` itself, so gating the preload
alone would have left them). `IterableSymbolicList` gained `first`/`last`/`[]`
overrides returning **nil** for an empty list — Ruby's own `[].first`, and the
only case where `SymbolicList`'s rep-less raise is the wrong answer; every
other rep-less access still raises.

**Verified by a REAL run**: `r3-empty-collection-json` (body `[]`) and
`-mobile` (68 B) issue exactly two statements — the post finder and the
comments SELECT — and no people/profiles/mentions read.

**ACCEPTANCE**: `empty_relation_emission_audit` **PASS** (8 243 dumps, 2 275
empty-list states, 0 findings; it reported 9 shapes / 6 004 note events on the
cycle-4 corpus). The audit is now in `completion_config.json`'s
`extra_audit_cmds`, so the ENGINE runs it on every report — rule P: the check
that catches the class is wired into the gate, not into an agent's habit.

### N3-1 — `users.language`: a decision, and the principal's `profiles` read enters the corpus (Rule G)

Two defects in one: a blind branch, and a Rule G violation (the column was in
neither the gate list nor the pin ledger).

1. **The branch is recorded on the column's own var.** The `User` rep's
   `language` attribute is compared once, at the identity-shim boundary, and
   replaced by the concrete locale that comparison selects:
   `attrs["language"] = ((attrs["language"] == "pl") ? "pl" : "en")`, which
   records `(…devise_user_first_1_language == StringVal('pl'))`. The decision
   means "the user's language is an inflected locale";
   `config/locales/inflections/pl.yml` is the app's only one, so `pl` is its
   witness and `en` its complement. Both values are real locale codes, so
   `I18n.locale=` and the inflector run for real.
2. **The callbacks that read data now run.** `run_dse.rb` invokes
   `set_locale` and `set_grammatical_gender` on the signed-in path before the
   action body, as the real dispatch does. Ground truth that these two and no
   others touch data on this action: the adversary's full-dispatch runs B09
   (`pl`) and B11 (`en`) differ by exactly one statement. Re-established here
   by `r3-principal-locale-pl` vs `-en`:

```
pl:  users … | people.owner_id … LIMIT ? | profiles.person_id = ? LIMIT ?  | posts JOIN share_visibilities …
en:  users … | posts JOIN share_visibilities … | people.owner_id … LIMIT ? | …          (no profiles read)
```

3. **Its consequences are modelled, not swallowed.** `User#gender` and
   `Person#gender` are plain `delegate`s with no `allow_nil`, so a principal
   with no `people` row — or a person with no `profiles` row — raises
   `Module::DelegationError` (a `NoMethodError` subclass) **inside the
   callback, before the action body**. Recorded as a run terminal
   (`person_less_user_terminal?`), 8 dumps; the corpus no longer claims the
   visibility SELECT is always issued in that state.
4. **The dead `symbolic_user_ci` helper is deleted.** It contained explicit
   `language` / `gender` pins in a code path no run has taken since cycle 1 —
   the adversary read it as a licence, correctly, and it was not one.

### N3-2 — `Post.exists?` cardinality is a decision chain, not a fixed three

The round-2 repair replaced a cap of one with a FIXED text of three post links
plus a comment link, which can only express probe counts {0, 2, 3}. A fixed
count is a pin over a multiset. The count is now a nested decision chain —
`_text_has_dlink` (≥1), then `_text_dlink_ge2`, `_ge3`, `_ge4` — combined with
the entity decision on the first link, giving **{0, 1, 2, 3, 4}** per rep.
The unconditional trailing `comment`-entity link is gone: `is_post == False`
already makes the first link a `comment` one, so it only added a guid
parameter no decision depended on.
HONEST LIMIT, stated as the sampled list's `{0, 1}` is: **4 stands for "four
or more"**. The real text is unbounded; no finite chain expresses every count.
Real counts observed by the adversary were 0, 1, 2, 3 and 5 — 1 and "≥ 4" were
the inexpressible ones, and both are now expressible.

### N3-3 — the mention display name is a decision

`_text_mention_has_name` chooses between `@{Concolic Mention; <handle>}` and
`@{<handle>}` (`Mentionable::REGEX` makes the name optional). With the name
present, `PeopleHelper#person_link` uses `opts[:display_name]` and never calls
`Person#name`, so the mobile mention rep's `profile_not_found == True` arm
minted no consequence at all. It does now:

| mobile dumps | has_name | mention profile missing | discovery decision minted |
|---|---|---|---|
| 390 | true | false | no |
| 188 | true | **true** | **no** (the display name forecloses it — this was the whole corpus before) |
| 216 | false | false | no |
| 69 | false | **true** | no (found on the retry path) |
| **35** | **false** | **true** | **yes** — `name` → `fix_profile` → Discovery → reload → the profiles re-read, bound to the MOBILE mention rep |

### N3-4 — stale `concrete_aliases.json`, and a stale assumption manifest

`ActiveRecord::FinderMethods.find_by → [mention_lookup_*]` removed: the D3
repair deleted that family from the corpus, and a stale alias silently widens
judge matching. Auditing the same class in the neighbouring file found the
manifest was worse: **17 of its 24 entries named dimensions no corpus run
seeds any more** (the four post-text flags, five `_persisted` entries pinned
away by D3, and the whole seven-entry `mention_lookup_*` family). Pruned, and
**14 entries added for the decisions this batch actually makes** — the link
family and its count chain, the mention display name, the mention person and
its profile, the comment author's profile, the empty comment collection, the
principal's person / profile / locale, and discovery failure. 21 live entries.

### Rule G (DISCIPLINE §11) — gate list and pin ledger after this cycle

`pc_gate_columns` = **`public, diaspora_handle, author_id, person_id,
language`** — all five VISIBLE (3 334 / 898 / 3 840 / 3 840 / 4 901
references), audit **pass**.

PIN LEDGER — unchanged entries: `persisted?` (D3), `guid`/`*_guid` (D4),
`commentable_type` / `mentions_container_type` / `shareable_type` (H5),
`text` content (seeded content decisions), `<rep>_reload_not_found` (B-1).
**New entry:**

| column / state | pin | ledger entry (the licence) |
|---|---|---|
| `profiles.gender` | pinned CONCRETE, non-blank (`"male"`) | The only reader on this endpoint is `set_grammatical_gender`: `current_user.gender.to_s.tr('…','').downcase`, then `unless gender.empty?` and `I18n.inflector.true_token(gender, :gender, lang)`. NEUTRALITY: both arms reach only in-memory I18n inflector lookups — no statement, no association, no difference in data access; the only product is `@grammatical_gender`, which neither renderable format of `#index` reads. The EVIDENCE the column exists to produce — the principal's `SELECT "profiles".* … WHERE "person_id" = ? LIMIT 1` — is issued BEFORE the compare and is therefore minted on both arms. Pinning also keeps the value a real String: `String#tr` on a `SymbolicString` returns a bare subclass allocation with no `@value`, so a symbolic gender turns the callback into a wall rather than a decision. |

`gender` is therefore in the ledger and NOT in the gate; the two sets stay
disjoint and jointly cover every column this endpoint compares.

### BOUNDARY CHANGES (Rule T3 — reported, not applied outside this batch)

Neither is a `declare_target` edit; both are defects of the SHARED portable
repair toolkit (`emit_includes_preloads` / `rows_mock`) that every batch
copied, so both are almost certainly live on `conversations_index` and
`notifications_index` today.

| # | finding | where it must land |
|---|---|---|
| **B-4** | A `belongs_to` preload step over a column with **no database foreign key** must carry a `<base>_not_found` DECISION, attach **nil** on the not-found arm, and **skip the nested step** — mirroring the `has_one` arm. And the predicate that decides "may this association dangle?" must be the SAME one `SingularAssociation#find_target` uses: modelling the same load in two places with two rules is what produced M-3 (a decision alive in one corpus and dead code in the next). Justifying real run: `concrete_manifest_r3.rb` `r3-dangling-mention-json` / `-mobile`. | `shared/target_boundary.rb` (the toolkit half) — Rule T2 regenerate |
| **B-5** | `rows_mock` must read the list length BEFORE minting anything below the list: **no representative row and no `emit_includes_preloads` for a relation of length 0**. The real `Associations::Preloader#preload` preloads from the loaded records, so zero records means zero statements; emitting first asserted reads — and attribute decisions — over rows no query returned, in 47 % of this corpus. Detector: `src/queries_from_runs/audits/empty_relation_emission_audit.py`. Justifying real run: `r3-empty-collection-json` / `-mobile` (2 statements each). | same file; and the audit belongs in every batch's `extra_audit_cmds` |

### Instrument / tooling notes (not batch defects)

- **`skipped_pcs_audit --patched` must point at
  `reports/diaspora/results3/_experiment/variant_d`.** `variant_e` lacks the
  violation-8 `StringVal` unwrapper and reports a false RED (5 799 dropped
  `(VAR == StringVal(_))` PCs — every string-equality branch in the corpus).
  With `variant_d`: 8 243 dumps, 46 exprs, **dropped 0**.
- **`demand_round.py` cannot reach a combination the corpus has never
  co-evaluated.** Its base seed is "the smallest seed dict of a dump that
  evaluated EVERY expr of the combo"; when no such dump exists it falls back
  to `{}` and the replay starts from defaults, so the clique is unreachable
  and the round adds no path. Four demand iterations produced byte-identical
  path sets here. Closed by hand: take the seed dict of a dump that has the
  combination's *other* polarity and flip the one bit (`_targeted_*.json`) —
  one round, 46 nodes, 0 missing. Worth teaching the tool.
- `coverage.py`'s declaration builder still prints
  `Failed to eval var decl 'Length(SYM_PARAM_post_id) = Int(…)'` once per run;
  the expr is nonetheless handled (`unevaluable_exprs` is empty and the
  `Length(...) < 16` node is in the tree). Cosmetic, pre-existing.

### Ops

Two locks, each taken exactly once: `flock /tmp/concolic-slot.lock` around
every `scripts/diaspora-concolic` launch (base rounds, demand rounds, targeted
round, the four concrete probes), `flock /tmp/concolic-heavy.lock` around
every `coverage_report.py` pass. `unset JAVA_TOOL_OPTIONS` everywhere; every
job under `systemd-run --user -p MemoryMax=… -p MemorySwapMax=0` with a DONE
marker in its log. The final report holds `heavy` across the assumption gate
as well as the Z3 pass (15 min 47 s wall, peak RSS 427 MB) — noted because the
RUNBOOK's rule is that the gate itself need not take `heavy`; it is one
process here, and the gate's own JRuby launches take `slot` per launch.

### Files changed (all inside this batch dir)

`targets.rb` · `run_dse.rb` · `coverage_assumptions.py` (GATE_TABLE + chain
membership for the five new decisions) · `completion_config.json` (gate list
+ the `empty_relation_emission` audit) · `assumption_manifest.json` (pruned
and extended) · `concrete_aliases.json` (stale family removed) ·
`concrete_manifest_r3.rb` (new) · `merge_concrete_runs.py` (merges it) ·
`_bak_*_cycle4.*` (the cycle-4 originals, for diffing).

### Cycle 5b (2026-08-28) — the coordinator's two hardening-lint items

**1. H4 — `len(…to_a_1_rows)` one-sided.** On the FULL corpus the check is
clean: `4 len(...) decisions recorded as PCs; 0 appear with ONE polarity
only`. The flag came from `--sample 400`: the empty side of the MOBILE
comment collection lived in 14 of 8 243 dumps, so a 400-dump sample misses it
about half the time. The thinness is nevertheless real, so it was
investigated rather than explained away.

**It is structural, and the state is completely explored.** The empty side is
a TERMINAL LEAF: when the mobile collection is empty, `index.mobile.haml`
renders an empty `<ul>` and nothing below the list runs, so a path through it
is fully determined by the decisions ABOVE it — the key-length dispatch, the
post finders / visibility chain, and (signed-in) the principal's person,
profile and locale. Everything else is foreclosed.

Proof rather than assertion: every DISTINCT upstream prefix in the mobile
corpus was enumerated (6 anon + 24 auth = 30) and replayed as its own
worklist root with `len(…to_a_1_rows) = 0`
(`_targeted_empty_{anon,auth}_mobile.json`, 597 runs, `run errors: {}`).
Result: **28 dumps carrying the empty-list PC, collapsing to the SAME 14
distinct path signatures** — the 30 prefixes differ only in decisions the
empty list forecloses. 14 is the complete set of paths through that leaf, not
a sample of a larger one, and the coverage checker agrees (0 missing over the
node in every pass). No pin, therefore, and no ledger entry: the decision is
explored both ways and stays a decision.

Corpus after the round: **8 840 dumps** (6 872 distinct outcome maps, 1 968
duplicates), coverage unchanged at **46 nodes / 0 missing**, engine re-run
end to end on the enlarged corpus — `complete: true`, `blocking: []`,
assumptions **1 095/1 095 PASS**, shims 19 PASS / 11 PROTOCOL, note check
green, three engine audits green. All six SQL-consumer audits re-run and
green (`_audits_phase3.log`); `bind_resolution` 74 799 resolved / 27 675
param-leaf / **UNRESOLVABLE 0 / DERIVED-MISBOUND 0 / AMBIGUOUS 0**.

**2. H5 — `pc_pin_ledger` in `completion_config.json`.** Added as the
machine-readable half of Rule G; the PIN LEDGER table above stays the
reasoning half.

```json
"pc_gate_columns": ["public", "diaspora_handle", "author_id", "person_id", "language"],
"pc_pin_ledger":   ["persisted", "guid", "commentable_type", "mentions_container_type",
                    "shareable_type", "text", "gender", "reload_not_found"]
```

The two sets are disjoint (asserted when the file is written) and jointly
cover every column this endpoint compares. `hardening_lint` now reports
**`RESULT: all hardening checks clean`** — H1…H6, no CHECK outstanding, on
the full corpus with the merged `concrete_run.json` (10 real scenarios).

**Ops note (cycle 5b) — a lost DONE marker is not a lost job.** The final
report's launcher shell was killed when the tool call that spawned it timed
out, so `c5_report2.log` never got its `exit=` / `C5REPORT2DONE` lines. The
`systemd-run --user` UNIT survived the parent and ran to completion: the log
carries `OVERALL_COMPLETE=True … wrote coverage_summary.json in 19.2s`, which
`coverage_report.py` prints only AFTER the file is written, and
`_assumption_results.json` and `coverage_summary.json` share a timestamp
(11:52:42) — i.e. the completion gate ran and the summary is a full report,
not a coverage-only pass. Two consequences worth carrying forward:
(a) verify a job by its OWN output (the report's last lines + the artifact's
`completion` section), never by the marker alone — the marker is written by
the wrapper, which is the part that dies;
(b) killing the wrapper also kills the `flock` holding
`/tmp/concolic-heavy.lock`, so the heavy lock was released while the unit was
still computing. Nothing collided here (the other two batches were in JRuby
rounds, which take `slot`), but a long report should hold the lock INSIDE the
unit, not in the launcher, so the lock's lifetime matches the work's.

---

## Cycle 6 (2026-08-28) — adversary round 4: M-5 and M-6 closed, plus N4-3

Round 4 (`ADVERSARY_REPORT_4.md`) scored **two wins** against the cycle-5/5b
corpus and landed one instrument fix. Both wins and the instrument's first
finding are closed here. The corpus was regenerated **from scratch** (the
domain of two columns and the cardinality model of every collection changed).

### The metric table

| metric | cycle 5b (attacked) | cycle 6 |
|---|---|---|
| `complete` / `blocking` | true / [] | **true / []** |
| coverage | 0 missing, 46 PC nodes | **0 missing, 55 PC nodes** |
| corpus | 8 840 dumps / 6 872 runs / 120 309 PCs | **14 982 dumps / 11 756 runs / 245 656 PCs** |
| `run errors` | {} | **{} in all four variants** |
| assumptions | 1 095 tested, 1 095 PASS | **1 558 tested, 1 558 PASS** (1 741 declared) |
| assumption manifest | 21 entries | **25**, four calibrated `flip_to` values |
| shims | 19 PASS / 11 PROTOCOL | **19 PASS / 11 PROTOCOL / 0 red** |
| note check | green | **green** (`find_target` 2 shapes, `records` 6) |
| note fidelity (NEW judge) | **2 LIMIT-DIFF (RED)** | **22 EXACT, 0 MISSING / STAR-OVER / AGG-COLLAPSE / PROJ-DIFF / PRED-OP-DIFF / LIMIT-DIFF / ORDER-DIFF / PRED-DIFF** over my 5 run files **and the adversary's rounds 3 + 4** |
| six SQL-consumer audits | green | **green** (bind resolution 125 723 resolved / 43 798 param-leaf / UNRESOLVABLE 0 / DERIVED-MISBOUND 0; skipped PCs 194 114 parsed / 0 dropped) |
| `hardening_lint` | clean | **clean (H1–H6)** |
| gate list | 5 columns | **6** — `type` added, VISIBLE (14 927 refs) |
| `I18n::InvalidLocale` terminal | **0 dumps** | **6** |
| `SubclassNotFound` terminal | **0 dumps** | **71** |
| one-statement signed-in path `{users}` | **0 dumps** | **48 dumps have exactly one statement** |
| preload predicate operator | `IN` only (17 914 would-be) | **`=` 60 412 / `IN` 17 914** — both real shapes |

### W4-1 / M-5 — `users.language` has three arms, and the third one ends the run

`set_locale` runs `I18n.locale = current_user.language` with
`I18n.enforce_available_locales == true`, so a NON-NIL code that is not an
available locale raises `I18n::InvalidLocale` **before the action body**. The
corpus pinned the column to `{"pl","en"}` — both available — with no ledger
entry, which is precisely what DISCIPLINE §11 forbids: a decision's DOMAIN
quietly narrowed without a licence.

The identity shim now encodes a **three-valued domain as a compare chain** on
the column's own var, so both compares are PC-visible:

```ruby
attrs["language"] = if    lang == "pl" then "pl"    # available AND inflected
                    elsif lang == "xx" then "xx"    # not an available locale
                    else                    "en"    # available, not inflected
                    end
```

`pl` is not merely a witness for the inflected arm — it is the whole inflected
set (`I18n.inflector.inflected_locales(:gender)` is `["all", "pl"]`, the
adversary's own C12 probe). NULL is deliberately **not** a fourth arm: i18n
treats nil as "use the default" and the real run 200s, so a nil language is
behaviourally the `en` arm — verified here, not assumed
(`r4-locale-null-control`).

`run_dse.rb` records `I18n::InvalidLocale` as a run terminal. Corpus:
`== StringVal('pl')` 3 505 T / 5 037 F, `== StringVal('xx')` 6 T / 5 031 F,
6 `InvalidLocale` terminals, and **48 dumps whose entire data access is one
statement** — the shape that occurred in 0 of the previous 8 840.

**Verified by a REAL run** (`concrete_manifest_r4.rb`, real dispatch so the
whole before_action chain runs):

```
r4-locale-invalid          EXC I18n::InvalidLocale: "xx" is not a valid locale
   statements: SELECT "users".* … LIMIT ?          <- and nothing else
r4-locale-null-control     200   (10 statements — NULL is not the third arm)
r4-locale-inflected-control 200  (11 statements, incl. the principal's profiles read)
```

### W4-2 / M-6 — `posts.type` is a decision, and an out-of-tree row stops after the finder

`posts.type` was a placeholder string in neither the gate list nor the pin
ledger (29 087 blind mints). `t.string "type", limit: 40, null: false` has no
CHECK, no FK and no application validation, and `Photo` /
`ActivityStreams::Photo` are ordinary legacy values on an upgraded pod. Such a
row makes AR raise `SubclassNotFound` **while instantiating it**, so the real
run issues the post finder and nothing else.

Round 3 filed this as "a limitation, not a defect, because no statement is
lost". That criterion was wrong and is retired: M-3 and M-4 both established
that **a state the application can be in that the corpus cannot represent is a
gap**, whether or not it adds a statement — here the corpus asserted a
comments SELECT, the preloads, the mention loads and the `exists?` probes for
a request that performs none of them.

The decision is minted in `symbolic_instance` — instantiation is exactly what
that function stands for and exactly where the real raise happens — so all
four post finders (anon `first`, `ci_vis`, `ci_author`, `ci_public`) inherit it,
and the finder mock has already decided `_not_found` before calling it, so a
finder that returns no row cannot raise, as in the real code. It is two-valued
because the IN-TREE subclass choice is evidence-neutral: the adversary's C06
rendered `StatusMessage` and two `Reshare` shapes, json and mobile, anon and
signed-in, with identical statement sets.

**The subtle half — and why this is not a Class-S regression.** The runtime
records a target's `symbolic_call` event (and its NOTE) only AFTER the mock's
`returns` lambda comes back, so raising from inside the mock would have
**swallowed the post finder's own statement** — introducing the exact defect
M-3/M-4 were about while fixing a Class-B one. So the mock returns an
`UninstantiableRow` instead: the interceptor reads its `concolic_note` (the
finder SQL), records the event, hands it to the app, and the first thing the
app does with it raises. It poisons **every** method rather than the two the
current call sites happen to touch (`public?` on the anon path, `comments` on
the signed-in one) — enumerating call sites is the instance-shaped fix rule P
forbids; "an object that does not exist cannot be used at all" is the
class-shaped one, and it stays correct when a new path reaches it.

Corpus: `_type == StringVal('Photo')` 71 T / 14 856 F on four finder reps,
71 `SubclassNotFound` terminals, and those dumps carry **exactly one note** —
the post finder's.

**Verified by a REAL run**: `r4-sti-out-of-tree-anon-json` (three out-of-tree
types → three `SubclassNotFound`, one `posts` statement each),
`r4-sti-in-tree-control-anon-json` (200, full render),
`r4-sti-out-of-tree-auth-json` (`{users, join, people.owner_id,
posts…author_id, posts…public}` then stop).

### N4-3 — the preload's predicate operator, and collection cardinality 0 / 1 / MANY

The coordinator's judge upgrade (`PRED-OP-DIFF`, `LIMIT-DIFF`, `ORDER-DIFF`)
went **RED on this batch immediately**: two LIMIT-DIFFs. The real preload of a
ONE-row collection is `SELECT "people".* WHERE "people"."id" = ?` with no
LIMIT, and the corpus had no note of that shape — only the bulk
`IN ($$(…))` preload note and the singular `= $$(…) LIMIT 1` reload/find_target
note, neither of which is that statement.

Both of this batch's own concrete runs contain **both** real shapes (60 412
`=` and 17 914 `IN` note events now correspond to 19 and 12 real statements),
because AR emits `IN` only for two or more ids. A corpus that models "one
sampled row" can express only one of them, so:

- the sampled list's **cardinality** is now `0 / 1 / MANY`
  (`apply_len_bounds` high 1 → 2; 2 IS "two or more", the same convention as
  the link chain's 4). The Gate-1b limit on row **content** is unchanged and
  undiminished — one representative row — but the cardinality is what the
  statement shape depends on, so it is now a recorded decision
  (`(len(X) > 1)`, 9 335 T / 25 232 F);
- `emit_includes_preloads` renders `col = $$(v)` or `col IN ($$(v))`
  according to it.

This is also, at last, a real answer to cross-endpoint rule 4 ("collection
length must be a decision 0 / 1 / many") — previous cycles answered it with
"the domain is {0,1} by design".

**Verified by a REAL run**: `r4-preload-one-author` → `people.id = ?` /
`profiles.person_id = ?`; `r4-preload-three-authors` → `people.id IN (?, ?, ?)`
/ `profiles.person_id IN (?, ?, ?)`. Judge over my five run files **and the
adversary's rounds 3 and 4**: 22 EXACT, every new verdict class zero.

### Rule G after this cycle

`pc_gate_columns` = **`public, diaspora_handle, author_id, person_id,
language, type`** — all six VISIBLE. `pc_pin_ledger` unchanged
(`persisted, guid, commentable_type, mentions_container_type, shareable_type,
text, gender, reload_not_found`); the two sets stay disjoint (asserted when
the config is written). Note the two are about different columns that share a
suffix: `posts.type` is ROW DATA and is gated; `commentable_type` /
`mentions_container_type` / `shareable_type` are CONSTANTS of the association
scope the statement comes from and stay pinned (H5).

### Assumption manifest — four calibrated flips

Three of the new dimensions cannot use the driver's automatic flip, because
it turns a non-empty string into `""` and an integer into `v+1`, and this
batch's domains are small sets of REAL values:

| entry | dimension | flip_to | why |
|---|---|---|---|
| `sti-out-of-tree-foreclosure` | `…first_1_type` | `"StatusMessage"` | `""` is not an STI type |
| `sti-out-of-tree-vis-foreclosure` | `…ci_vis_first_1_type` | `"StatusMessage"` | same |
| `principal-locale-invalid-foreclosure` | `…_language` | `"xx"` | the third arm is a specific value, not "not-pl" |
| `comment-collection-empty-foreclosure` | `len(…records_1_rows)` | `0` | the domain is now {0,1,2}; auto `v+1` on the richest snapshot (2) gives 3 — outside the domain AND evidence-identical to 2 |
| `comment-collection-many-foreclosure` | `len(…records_1_rows)` | `1` | the 1-vs-MANY half |

`run_dse.rb`'s flipper got the matching runner-local rule: for `_language` and
`_type` the "not this literal" seed is the SIBLING value (`"en"` /
`"StatusMessage"`), never `""`, so the corpus never contains a value outside
the modelled domain and the gate's directed flip is deterministic.

### Encoding-chain foreclosures (new GATE_TABLE entries)

`(_language == StringVal('pl'))` now closes on **both** polarities: False
closes `set_grammatical_gender`'s body (as before), and **True closes the
`== 'xx'` compare**, because a three-valued domain encoded as two binary
compares never evaluates the second one on the first one's True arm. Same
shape as the already-declared `_text_dlink_ge2/ge3/ge4` chain. Without it the
checker demanded the structurally unreachable combination
`pl == True ∧ xx == False`. `(_type == StringVal('Photo'))` closes on True
(the run ends at the finder). `(len(X) > 1)` closes **nothing** and is
demanded in every combination.

### Ops

The whole tail of this cycle ran **inside** `systemd-run --user --unit=…`
rather than under a wrapper shell, applying cycle 5b's own lesson: a wrapper
shell dies with the tool call that launched it, and this cycle lost a targeted
round and a coverage pass that way before the chain was moved into a unit.
Two locks, each taken exactly once; `unset JAVA_TOOL_OPTIONS`; DONE marker per
log; final report 23 min 18 s, peak RSS 739 MB at 14 982 dumps.

### Files changed (all inside this batch dir)

`targets.rb` (the language chain, the STI decision + `UninstantiableRow`, the
cardinality-aware preload operator, `pred_op`) · `run_dse.rb` (two terminals,
the `> 1` flipper, sibling-literal seeds) · `coverage_report.py` (length
domain {0,1,2}) · `coverage_assumptions.py` (three GATE_TABLE entries, the
`pl` chain foreclosure, `_type` rep-key suffix) · `completion_config.json`
(`type` gated) · `assumption_manifest.json` (+4 entries, 5 calibrated flips) ·
`concrete_manifest_r4.rb` (new) · `merge_concrete_runs.py` ·
`_bak_*_cycle5.*`.

---

## Cycle 7 (2026-08-29) — adversary round 5: M-7, M-8, M-9 closed (all TARGET-LEVEL)

Round 5 scored **three wins**, all at the target boundary, plus near-miss
N5-1. All four are closed here. The corpus was regenerated from scratch.

### The metric table

| metric | cycle 6 (attacked) | cycle 7 |
|---|---|---|
| `complete` / `blocking` | true / [] | **true / []** |
| coverage | 0 missing, 55 nodes | **0 missing, 73 nodes** |
| corpus | 14 982 dumps / 11 756 runs / 245 656 PCs | **16 895 dumps / 13 804 runs / 290 424 PCs** (after on-disk dedupe of 2 099 exact duplicates) |
| `run errors` | {} | **{} in all four variants** |
| assumptions | 1 558 tested, all PASS | **2 806 tested, 2 806 PASS** (3 234 declared); one engine REJECTION withdrawn, see below |
| shims | 19 PASS / 11 PROTOCOL | **19 PASS / 11 PROTOCOL / 0 red** |
| **`noteless_call_audit`** | **RED — 20 670 events / 6 targets** | **PASS — every non-wall target call carries a note** |
| note fidelity (alias-fixed judge) | 22 EXACT | **22 EXACT, 0 in every defect class**, over 28 run files incl. adversary rounds 3, 4 **and 5** |
| six other audits | green | **green** (bind 145 673 resolved / UNRESOLVABLE 0 / DERIVED-MISBOUND 0; skipped PCs 228 466 parsed / 0 dropped; pc_visibility 6 gated columns) |
| preload predicate | `IN` iff `len > 1` (25 232 `=` / 9 335 `IN`, zero mixed) | **`=` 69 558 / `IN` 5 642, decided by the DISTINCT-KEY count** |
| outer→nested pairs | `=`→`=` 22 429, `IN`→`IN` 8 579, **`IN`→`=` 0** | **`=`→`=` 30 629, `IN`→`IN` 1 054, `IN`→`=` 3 104** |
| targets in the corpus | incl. phantom `Anonymous.exists_probe` | **probe removed** — `exists?` carries its own note |

### W5-3 / M-9 (B-8) — a finder that finds nothing still ran its query

The most serious defect of the whole effort, and the fix is three lines in
three places. The interceptor takes a target's note from the RETURNED value,
so every mock arm that returns a falsy value dropped its statement:

- `finder_mock_faithful` (targets.rb) — the three `ci_*_first` visibility
  finders and the anon post finder, i.e. **this endpoint's entire access
  control** on a miss;
- `finder_mock` (concolic_targets.rb) — the shared single-row finder;
- `SingularAssociation#find_target` — the not-found association load;
- `FinderMethods#exists?` — a bare `true`/`false` is as note-less as `nil`.

Each now publishes on the engine's new one-shot channel immediately before
returning:

```ruby
Thread.current[:concolic_pending_note] = sql
next nil
```

**And the `exists?` probe is gone.** `Anonymous.exists_probe` existed *only*
because a bare bool could not carry a note; it cost a phantom target, a second
producer edge for one read, and the standing boundary question in this file's
BOUNDARY CHANGES table ("either the boundary adopts the probe pattern or the
runtime learns to attach a note to a boolean return"). The runtime has now
learned, so the pattern is withdrawn: `exists?` carries its own statement, the
decision var keeps the note it always had, and `concrete_aliases.json` loses
the alias. **That boundary item can be closed.**

`noteless_call_audit`: **20 670 events / 6 targets → 0.** Real-run evidence
that the lost statement is real: `r5-finder-miss-404` — a 404 request whose
ONLY statement is the post finder.

### W5-1 / M-7 — the predicate follows the DISTINCT KEY COUNT

`Preloader::Association` does `owners.group_by { … }` and binds
`owners_by_key.keys`; `PredicateBuilder::ArrayHandler` then picks equality for
one key and `IN` for two or more. So ten comments by one author give
`people.id = ?`. Cycle 6 tied the operator to the LIST LENGTH — a different
fact — and got the commonest multi-comment state exactly wrong, while emitting
`IN ($$(one_bind))`, a shape ActiveRecord never produces.

`emit_includes_preloads` now carries a per-step **distinct-key count**:

- at the TOP level it is a DECISION, `<base>_keys_many`, bounded by (not equal
  to) the row count — 10 290 F / 5 642 T;
- the second key is a real column value of a second row, minted as
  `<owner-prefix>2_<column>` with the OWNER's own producing query as its note,
  so the fold resolves it to that column of that query (not a `SYM_PARAM_*` —
  Rule V is about values with no producing column, and this one has one);
- `pred_for` renders `= $$(k1)` or `IN ($$(k1), $$(k2))`.

The list-length decision stays (0/1/many is real) but now only BOUNDS the key
count: `(len > 1) == False` forecloses `_keys_many` entirely.

**Real runs**: `r5-preload-one-distinct-key` (2 comments, 1 author) →
`people.id = ?` / `profiles.person_id = ?`; `r5-preload-two-distinct-keys` →
`IN (?, ?)` for both.

### W5-2 / M-8 — the nested step follows the parents actually loaded

The nested step's key count is **derived, never inherited**: it is the number
of parents the step above actually loaded. Per step that needs it (has_one, or
an FK-unconstrained belongs_to) the outcomes are `_not_found` for the first
key and `_k2_not_found` for the second, so the loaded count is 0, 1 or 2 and
the level below binds exactly that many keys. Key 1 is LABELLED as a key that
matched, so all three counts are expressible without a rep-less state; which
physical row is "key 1" is not observable — only the count reaches a
statement.

`IN`→`=` went from **0 to 3 104 dumps**. **Real runs**:
`r5-nested-shrinks-dangling` (2 mentions, 1 dangling) → `people.id IN (?, ?)`
then `profiles.person_id = ?`; `r5-nested-both-loaded` → `IN` then `IN`.

### N5-1 — the poison is now complete by construction

`UninstantiableRow` inherited all of Object/ActiveSupport, so `try` answered
nil, `is_a?` answered false and `present?` answered true — three silent ways
around a row that does not exist. It now **undefines every instance method**
except the handful the RUNTIME calls on a mock's return value
(`concolic_note`, `nil?`, `is_a?`, `respond_to?`, `to_s`/`inspect`/`to_json`,
and the object-identity primitives); `is_a?` answers only for the runtime's
own type tests and raises for anything else. A method the runtime needs and
the list forgets fails LOUDLY as a run error, never silently.

### One engine REJECTION, withdrawn (never re-declared)

The gate rejected `IndependenceAssumption((Length(SYM_PARAM_post_id) < 16),
(…ci_vis_first_1_type == StringVal('Photo')))`: flipping BOTH produces a
guid-keyed visibility SELECT in the `SubclassNotFound` state, a target-call
shape neither single flip produces. `_never_declare` now covers **param × the
STI type decision** as well as the cycle-2 param × visibility-chain class.
Those combinations are DEMANDED; coverage stayed complete without them.

### Two encoding-chain foreclosures the new decisions needed

- `_k2_not_found == True` closes the level below: with the second key
  unmatched the next step binds ONE key, so it has no `_keys_many` decision
  and no second-key outcome of its own (64 → 16 missing).
- `_profile_not_found == True` now closes as well as `== False`: zero parents
  loaded means no second-key decision and no nested step at all (16 → 2).

### On the four instrument fixes

Re-checked before acting, as instructed:
1. **fidelity alias map** — no ghost here: my judge run was green before and
   after, and is green over all 28 run files with the fixed judge.
2. **H6 raw-prefix** — the fix is incomplete and produced a **false RED on
   this batch**: `real` is built from `sql[:60]` but the NOTE is shaped in
   full, so every statement longer than 60 characters can never match. The
   principal's `SELECT "people".* … "owner_id" = ? LIMIT ?` is 69 characters
   and was reported as over-emission although the real runs issue it. Corrected
   by hand (shape the full real statement), the honest count is **6 shapes, not
   52**, and both families have written answers — see below.
3. **bind_resolution venv** — already always run as
   `PYTHONPATH=src venvs/queries_from_runs/bin/python …`; no ghost.
4. **`[value, sort]` 2-element array** — checked: the only Array a `returns`
   lambda of this batch can produce is `[]` (the NullRelation arm), length 0,
   so the trap never applied. The one place that DID use the pattern —
   `ConcolicExistsProbe.exists_probe` returning `[sql, vn]` — was deleted by
   the M-9 repair.

**H6's two answered families** (with the truncation corrected):
`ActiveRecord::Base.reload` (4 shapes) — its only call site is
`Person#fix_profile`, behind the typhoeus/libcurl/JFFI JVM abort diagnosed in
N4-1 and now DISCIPLINE §12, so it is unreachable by ANY real run on this rig
for an established reason; and `ci_public_first`'s `"posts"."public" = true`
(2 shapes) — the note carries the literal where the real statement carries a
bind, because `true` is a CONSTANT of `EvilQuery#public_post`'s scope
(`where(@key => @id, :public => true)`), the same argument as the H5
polymorphic-type ledger entries. The fidelity judge scores both EXACT.

### Corpus hygiene — "a dump count is not a corpus"

Adopted the conversations_index finding: `dedupe_dumps.py` removes dump FILES
that are the same observation (variant/scenario, path signature, SELECT-note
multiset, terminal, seeds). This cycle it dropped **2 099** of 18 994 files.
Nothing the checkers read is lost — every verdict is a function of the
distinct observations — and the coverage pass now loads 13 804 runs in 50 s.

### Ops

Every phase ran inside its own `systemd-run --user --unit=…`; the wrapper-kill
failure mode from cycle 6 did not recur. One coverage pass waited ~40 minutes
on `/tmp/concolic-heavy.lock` behind another batch, which is the lock working
as intended. Verdicts were read from each pass's own `COMPLETE=` line, never
from a summary file a crashed pass might not have written.

### Files changed (all inside this batch dir)

`targets.rb` (pending-note on three falsy arms, `exists?` self-noting + probe
deleted, `pred_for`/`second_key`, the distinct-key `emit_includes_preloads`,
the hardened `UninstantiableRow`) · `concolic_targets.rb` (`finder_mock`
pending-note) · `coverage_assumptions.py` (`_keys_many` / `_k2_not_found`
entries, two chain foreclosures, the engine-rejected param × type class) ·
`assumption_manifest.json` (+3 entries) · `concrete_aliases.json` (probe alias
removed) · `concrete_manifest_r5.rb` (new) · `merge_concrete_runs.py` ·
`dedupe_dumps.py` (new) · `_bak_*_cycle6.*`.

---

## Cycle 8 (2026-08-29) — adversary round 6: M-10, M-11, M-12 closed (Rule D)

Round 6's three wins were all inside the distinct-key machinery cycle 7 added.
All three are closed by applying DISCIPLINE §13 (Rule D) — *derive what is
determined, decide only what is free* — to every preload step.

### The metric table

| metric | cycle 7 (attacked) | cycle 8 |
|---|---|---|
| `complete` / `blocking` | true / [] | **true / []** |
| coverage | 0 missing, 73 nodes | **0 missing, 64 nodes** (9 free decisions removed as determined) |
| corpus | 16 895 dumps / 13 804 runs | **14 010 dumps / 11 368 runs / 236 896 PCs**, `run errors {}` ×4 |
| assumptions | 2 806 PASS | **2 152 tested, 2 152 PASS** (2 463 declared) |
| shims / note check | 19 PASS / 11 PROTOCOL · green | **unchanged · green** |
| seven other checks | green | **green** (bind 135 145 resolved / UNRESOLVABLE 0 / DERIVED-MISBOUND 0; skipped PCs 200 063 / 0 dropped; noteless 0; empty-relation 0) |
| **M-11** `len(mentions)>1` ⇒ outer `people` op | `IN` and `=` both, freely decided | **`IN` 5 584 / `=` 0**; `len>1` False ⇒ **`=` 13 882 / `IN` 0** |
| **M-10** outer→nested pairs | `IN`→`=` from a free nested decision | **`=`→`=` 20 787, `IN`→`IN` 7 422, `IN`→`=` 1 013 — and every `IN`→`=` is a partial load** |
| **M-12** split second-key vars | 2 names for 1 row | **0** — all 16 928 `IN` binds use the one shared `_row2_` variable |
| free key decisions | on every step | **only `Comment belongs_to :author`** (3 734 T / 10 101 F) |

### The three fixes, as one rule

`DETERMINED_BY_ROWS` + `key_count_free?` classify each step once:

- **`Comment belongs_to :author` — FREE.** Two comments can share an author;
  ten comments by one author really do give `people.id = ?`. This is the only
  step on the endpoint that keeps a `_keys_many` decision.
- **`Mention belongs_to :person` — DETERMINED (M-11).** `db/schema.rb:207` is
  UNIQUE on `(person_id, mentions_container_id, mentions_container_type)` and a
  comment's `mentions` relation fixes the last two, so every row has a
  different `person_id`: **key count IS row count**. The step now derives its
  key set from `(len(X) > 1)`, and the state the adversary's probe could not
  even insert (`RecordNotUnique`) is gone from the corpus.
- **every `has_one`/`has_many` step — DETERMINED**: it binds the owner's
  primary key, distinct per owner row by definition.
- **every NESTED step — DETERMINED (M-10)**: `emit` now receives the parents'
  key set as `in_keys` and uses it verbatim; there is no nested decision at
  all. `people.id IN (a, b)` followed by `profiles.person_id = a` can no
  longer arise from a free choice — only from a parent that did not load.
- **M-12**: the nested step binds **the same values** it inherited, so the
  second row has one variable end to end, exactly as the first key always did.
  The `…_row_author2_id` / `…_row_person2_id` names are gone.

Consequently the relation itself records only the fact that is free:
`preload_rows_driven?` decides whether a list records `(len(X) > 1)` (the
mentions relation, where the row count IS the key count) or records only its
distinct-key decision (the comments relation, where the row count follows from
it — a second distinct author implies a second comment). Recording both would
be two variables for one fact.

**Real-run evidence** (unchanged manifests, re-run this cycle):
`r5-preload-one-distinct-key` → `people.id = ?`; `r5-preload-two-distinct-keys`
→ `IN (?, ?)`; `r5-nested-shrinks-dangling` → `IN (?, ?)` then `= ?`;
`r5-nested-both-loaded` → `IN` then `IN`.

### `cardinality_consistency_audit` — one residual family, and why it is the audit

After the fixes the audit reports **3 shapes / 1 042 dumps**, and every one of
the 1 042 is the SAME state. Measured over the whole corpus, the run's own
decisions explain **100 %** of them:

```
explanations: {('k2_not_found=True', 'not_found=False'): 1042}
```

That is: the step requested two keys, the FIRST parent loaded and the SECOND
did not, so the nested step binds one key — `people.id IN (?, ?)` followed by
`profiles.person_id = ?`. It is exactly the shape **round 5's M-8 demanded**
and that the adversary's own real run `r5-nested-shrinks-dangling` recorded
(and round 6 re-verified as correct). The corpus is right; the check compares
a nested step's DERIVED key set against the parent LIST's row count instead of
against the parents actually loaded — which is what its own RESULT line says
it is checking ("a nested step follows its loaded parents").

The dump already carries the missing input. A minimal refinement, in the same
place the emitter test lives: when a bulk note's key set is smaller than the
list's row count, look up the emitting step's `<prefix>_not_found` /
`<prefix>_k2_not_found` decisions (prefix = the note's first bind minus its
column suffix) and treat the shortfall as explained when they account for it.
On this corpus that turns 1 042 findings into 0 and leaves every genuine
contradiction — M-10's free nested decision, M-11's impossible one-bind state,
and `IN` over a single bind — still failing, because none of those carries a
not-found decision that explains it.

Reported rather than worked around: the two ways to make it green from inside
the batch are to stop modelling the partial load (undoing M-8) or to stop
recording the mentions row count (undoing M-11), and both are worse than a
documented false positive.

### H6 (hardening lint) — unchanged answer, and the truncation bug still stands

The lint prints 9 unissued shapes; with its 60-character truncation of the
REAL side corrected (reported last cycle, still present), the honest count is
**6**, and they are the same two answered families as cycle 7: `reload`
(4 shapes — unreachable behind the typhoeus/JFFI abort, DISCIPLINE §12) and
`ci_public_first`'s `"posts"."public" = true` (2 — a constant of
`EvilQuery#public_post`'s scope, the H5 argument). The fidelity judge scores
both EXACT.

### Files changed (all inside this batch dir)

`targets.rb` (`DETERMINED_BY_ROWS`, `key_count_free?`, `preload_rows_driven?`,
the `in_keys` rewrite of `emit_includes_preloads`, `loaded_keys` replacing the
loaded COUNT, rows-driven vs keys-driven list construction) ·
`coverage_assumptions.py` (gate-table text for the narrowed decisions) ·
`_bak_*_cycle7.*`.

### Cycle 8b (2026-08-29) — H6 answered on evidence, not on omission

The coordinator's sweep was never passing `--runs`, so H6 had been SKIPPED
silently in every check run — a skipped check reading as a pass. Fixed on
their side (explicit SKIPPED line, all 50 run files passed, and a batch may
now DECLARE an answered family). Added here:

```json
"h6_answered": [
  {"match": "ActiveRecord::Base.reload",       "reason": "…DISCIPLINE §12 JFFI abort…"},
  {"match": "ci_public_first",                 "reason": "…scope constant, judge EXACT…"}
]
```

With all 50 run files (this batch's 6 `concrete_run*.json` + 44 adversary run
files from rounds 3–6) the residue is EXACTLY the six shapes classified in
cycle 8 — 4 `reload`, 2 `ci_public_first` — each printed with its reason:

```
PYTHONPATH=src python3 reports/diaspora/tools/hardening_lint.py <batch> \
  --runs <batch>/concrete_run*.json <batch>/adversary*/runs/*.json
-> H1 ok · H2 ok · H3 ok · H4 0 one-sided · H5 3 pins declared · H6 6 answered, ok
RESULT: all hardening checks clean.
```

Full output: `_hardening_lint.out`.

**Invocation trap worth knowing:** `--runs` takes a LIST after ONE flag and
stops at the next `--`. Passing repeated `--runs f1 --runs f2 …` silently
keeps only the first list — the lint then reported "the 1 concrete run(s)"
and 12 false CHECKs (`find_target`, `ci_author_first`, `ci_vis_first`), which
look exactly like real over-emission. Verified both forms; only the list form
is correct.

**Deferred to after adversary round 7** (not touching `concrete_run*.json`
while the adversary compares md5s): add a guid-keyed SIGNED-IN request to
`concrete_manifest_auth.rb`, so this batch's own evidence covers the
guid-keyed `first` / `ci_author_first` / `ci_vis_first` finders instead of
relying on the adversary's run files for them.

---

## Cycle 9 (2026-08-29) — adversary round 7: M-13 and M-14 closed, then PAUSED

Recorded here in cycle 10; the cycle-9 agent was paused by coordinator
directive before it could write this section (see `PAUSED.md`, which is
accurate and is the source for everything below that cycle 10 did not
re-measure itself).

### The metric table

| axis | value |
|---|---|
| corpus | **20 879 dumps** (16 496 distinct outcome maps, 4 383 duplicates), `run errors: {}` in all four variants |
| generated by | 4 base rounds (11 000 runs each) → 3 demand rounds → 1 targeted round, `dedupe_dumps.py` after each |
| coverage | **complete: true**, 71 tree nodes, 0 missing, 359 770 PCs |
| assumptions | 3 073 declared / 2 713 distinct tested / **2 713 PASS**, driver exit 0 |
| shims | 19 PASS / 11 PROTOCOL / 0 red |
| engine report | 35 min 27 s wall, peak RSS 1 067 MB (unit peak 2.0 GB incl. the JRuby probes) |

### W7-1 / M-13 — a nil BESIDE a live parent

One `_not_found` variable cannot carry both "a parent is missing" and "a
parent loaded". The two facts are two variables: a `_not_found` decision PER
ROW on that row's own association base, and the loaded-key union the nested
step binds. A list whose rows carry an FK-less `belongs_to` preload now
materializes a SECOND representative row once its row count says "two or
more" (`needs_second_row?`), so `[nil, live]` and `[live, nil]` are both
reachable, each producing the `ActionView::Template::Error ← NoMethodError`
terminal; the nested step recurses from whichever parent survived, so a
missing FIRST parent no longer suppresses the nested read.

### W7-2 / M-14 — a bound is not a determination

`(len(X) > 1)` is recorded for EVERY list again and `preload_rows_driven?` is
gone. Only the KEY count is derived, and only where a schema constraint or a
parent step determines it; `_keys_many` is BOUNDED by the row count (two
distinct authors need two comments) — the reverse over-reach, caught by the
audit inside the same cycle.

### INSTR-1 / INSTR-2 (coordinator instruments, adopted)

- **INSTR-1** the warden memo was bound to `main`, so a scenario's several
  requests shared one principal resolution. `concrete_manifest_auth.rb` and
  `concrete_manifest_mobile.rb` now bind it to the WARDEN (`@cc_user`), which
  is rebuilt per request; r3/r4/r5 were already correct. Measured effect:
  `concrete_run_auth.json`'s Devise read went 1 → 3 for its three requests
  (221 → 223 statements overall).
- **INSTR-2** `CompletionChecker.new_request!` between requests in all six
  manifests. No statement-count change beyond INSTR-1's on this batch.

### Undeclared formats — measured, not argued

`concrete_manifest_r5.rb` drives `format: :js` → `ActionController::UnknownFormat`,
`:xml` → `UnknownFormat`, `:html` → `ActionView::MissingTemplate`.
`app/views/comments/` holds only `*.mobile.haml`, so no undeclared format
renders anything and none reaches data access beyond the post finder.

---

## Cycle 10 (2026-09-01) — the paused check sweep, run with the CURRENT instruments

No corpus regeneration. The cycle-9 corpus (20 879 dumps) was re-verified with
every instrument that changed while the batch was paused; the evidence decided
what needed repair, and what needed repair was the CHECKING side, not the
corpus.

### A. Entrypoint scope (DISCIPLINE §15) — already compliant, with evidence

The rig invokes `set_locale`, `set_grammatical_gender` and then
`ctrl.send(:index)` (`run_dse.rb:326-331`) — the controller action with its
data-touching filter chain, principal SYMBOLIC. No authentication stage is
modelled: no Warden strategy, no session/cookie plumbing, no `after_set_user`
hooks. Evidence, not assertion:

- `identity_symbolicity_audit`: **pass** — `user_id` symbolic 11 331 / literal
  0, `users.id` symbolic 11 352 / literal 0.
- The only boundary-stage statement the corpus carries is the principal
  SELECT (`devise_user_first`, 11 352 dumps) — exactly BOUNDARY_POLICY §6's
  "what endpoints keep".
- The corpus contains **19 distinct note shapes, all SELECT**: no
  `UPDATE "users"`, i.e. no trackable / lastseenable / rememberable write.
  Those are boundary material (BOUNDARY_POLICY §2) and are unioned in at
  extraction, not re-derived here.
- The concrete manifests resolve the principal through the REAL
  `User.serialize_from_session` (the boundary's §1.2 SELECT) on a stub warden
  object, so they carry the fetch and none of the hook writes. Under §15 that
  is the correct endpoint scope; no manifest change was needed.

**Endpoint-specific nuance worth carrying:** `authenticate_user!` is
`except: :index` on this controller, so the principal is fetched LAZILY by
`set_locale` / `user_signed_in?` rather than by the Devise filter. The
statements and hooks are the same ones the boundary artifact describes, so the
artifact applies unchanged; and an ANONYMOUS request touches no boundary stage
at all.

### B. INSTR-7 (SELECT-only judges) — re-derived, and why the verdicts did not move

Every statement in every one of this batch's 57 evidence files is a `SELECT`
(measured: 7 concrete runs = 446 statements, 50 adversary run files, 0
INSERT/UPDATE/DELETE issued under any target frame). So the SELECT-only filter
and `_is_dml` select the same set here and the cycle-9 verdicts were not
wrong — but they were re-derived rather than inherited:

| judge | evidence | verdict |
|---|---|---|
| `mock_note_check` | each of the 7 `concrete_run*.json`, separately | green, 7/7 |
| `note_fidelity_audit` | the 7 batch runs | green |
| `hardening_lint` (H1–H6, DML-aware) | all 57 run files, list form | **all clean** |

### C. The eight standalone audits (the PAUSED "NEXT" list)

| audit | verdict |
|---|---|
| `identity_symbolicity` | pass |
| `statement_note_lint` | pass (no red-level findings) |
| `bind_resolution` (schema-aware, venv) | pass — 252 272 binds, 0 AMBIGUOUS / 0 UNRESOLVABLE / 0 DERIVED-MISBOUND |
| `skipped_pcs --patched _experiment/variant_d` (venv) | pass — 292 614 parsed, **0 dropped**, 150 382 dropped-by-design |
| `pc_visibility --gate public,diaspora_handle,author_id,person_id,language,type` | pass |
| `empty_relation_emission` | pass — 3 487 empty-list states, none read |
| `noteless_call` | pass |
| `cardinality_consistency` | **RED — 6 shapes / 13 460 dumps. See below: 100 % explained by decisions in the same dump; the gap is in the audit.** |

Two of them (`bind_resolution`, `skipped_pcs`) exit 2/1 as a SETUP failure
under plain `python3` — they need the `queries_from_runs` venv. That is not a
corpus finding and the tools say so themselves; run them as
`PYTHONPATH=src venvs/queries_from_runs/bin/python …`.

### D. `cardinality_consistency_audit` — the RED is the audit's, and here is the proof

The audit flags 13 460 events of one shape family: "MANY state, BULK loader
emitting a single-key note (`=`)". `_c10/verify_cardinality_escapes.py`
re-implements the audit's flagging logic VERBATIM and then asks, per flagged
event, whether the SAME DUMP records a decision that explains it:

```
== escape verification over 20879 dumps ==
   11366  MANY/bulk/`=`    E1 keys_many=False
    2094  MANY/bulk/`=`    E2 sibling not_found
unexplained events: 0
```

* **E1 (11 366)** — the dump records `<step>_keys_many == False` beside
  `len(rows) > 1`: ten comments by ONE author, so ActiveRecord emits
  `people.id = ?`. That is **matrix row T-o / M-7**, already ✅ on this
  endpoint; the audit's rule ("MANY ⇒ the bulk loader must use `IN`")
  contradicts it, because it follows the ROW count where AR follows the
  DISTINCT KEY count.
* **E2 (2 094)** — a `_not_found == True` on a SIBLING row of the same list
  (M-13's `[nil, live]`). The audit's existing not-found escape only fires
  when the not-found prefix matches one of the note's own binds, so it misses
  the sibling case.

**BOUNDARY CHANGES (Rule T3 — reported, not applied).** The fix belongs in
`src/queries_from_runs/audits/cardinality_consistency_audit.py` and is
shared, so this batch does not make it. Proposed: widen the escape to "for the
same LIST, either a `_keys_many == False` on the emitting step or a
`_not_found == True` on ANY row of that step". On this corpus that turns
13 460 findings into 0 and leaves every genuine contradiction (M-10's free
nested decision, M-11's impossible one-bind state, `IN` over a single bind)
still failing. Reported rather than worked around: the only ways to make it
green from inside the batch are to undo M-7 or to undo M-13.

### E. Rig-crash census — pass, and an instrument blind spot found

`tools/rig_crash_census.py`: **20 879 `<ok>`, 0 rig-class terminals** — but it
reads `dump["error"]`, and THIS rig records application terminals in
`dump["concolic_terminal"]` (`run_dse.rb:340`), reserving `error` for
unexpected ones. The census is therefore vacuous over the terminal classes
that matter here unless it is told about that field. The equivalent census was
run by hand over `concolic_terminal`; every class is an APPLICATION terminal:

| terminal | dumps | real app outcome? |
|---|---|---|
| `<none>` (200 / rescued 404) | 18 507 | yes |
| `DiasporaFederation::Discovery::DiscoveryError` | 1 177 | yes — discovery failure is a real outcome |
| `ActionView::Template::Error ← NoMethodError` | 728 | yes — M-13's nil author in the template |
| `ActionView::Template::Error ← DiscoveryError` | 352 | yes — the same wall inside the render |
| `ActiveRecord::SubclassNotFound` | 80 | yes — T-g / M-6, out-of-tree `posts.type` |
| `NoMethodError` (person-less user) | 14 | yes |
| `Module::DelegationError ← NoMethodError` | 14 | yes |
| `I18n::InvalidLocale` | 7 | yes — T-f / M-5, unavailable `users.language` |

**Instrument note for the coordinator:** `rig_crash_census.py` should also
read a batch-declared terminal field (or the batch should be required to
record terminals in `error`), otherwise a rig that classifies its own crash as
an "app outcome" passes the census silently.

### F. The count-based multiplicity matrix — new, and it found things

`_multiset_counts.py` (adapted from conversations_index; the header records
every deviation and why). Four adaptations, each measured rather than assumed:

1. **Request splitting is corpus-derived.** conversations opened every request
   with the Devise `users` read; comments#index is anonymous-reachable, so an
   anon request has no such opener. A corpus dump IS one request, so the
   opener set is the set of first-note shapes — measured: exactly 3, each
   occurring ONLY in first position (users 11 352/11 352, posts-by-id
   6 093/6 093, posts-by-guid 3 420/3 420). A second, ACTION opener set (the
   first `posts` read of a request — `CommentService#find_for_post` is the
   action's first data access) splits requests in run files whose rig
   memoizes the principal across requests (the pre-INSTR-1 adversary rigs):
   4 shapes, each exactly once per request corpus-wide.
2. **Layout class → AUTH class.** comments#index renders NO layout on either
   renderable format (`render json:` and `render layout: false`,
   `comments_controller.rb:52-53` — the APP's code, not a rig pin), so the
   conversations layout axis is constant here. The axis that carries
   statement structure is anon vs auth, classified on both sides by the
   presence of the principal fetch (a positive marker, per A7-8).
3. **The format axis carries no per-REQUEST statement information** — and the
   script re-measures that every run instead of asserting it: json and mobile
   have identical note-shape SETS, and the 7 shapes whose maxima differ are
   all per-ROW. A per-request shape that ever differs is reported RED.
4. **Scenario-body traffic is not request traffic.** Two rules, both stated in
   the output: a statement with `under: null` was issued under no target frame
   (23 such — every one an adversary fixture INSERT/UPDATE/DELETE or a raw
   probe query), and a framed statement BEFORE a scenario's first action
   opener is scenario-body inspection (55 such — `post.comments.to_a`,
   `Comment.find`, `Post.find_by`, `pluck`, `count`), with 3 scenarios never
   reaching the action at all. Both counts are printed, never silent.

One more splitter defect was found and fixed BY this check rather than
argued away: the first rewind kept the principal fetch only when it sat
IMMEDIATELY before the action opener. On this endpoint it does not —
`authenticate_user!` is `except: :index`, so the principal is fetched by
`set_locale` and is followed by `user.person` (`people.owner_id`) and the
gender `profiles` read before the post finder. Measured distance: 3, not 1,
in 9 of the 25 auth scenarios; those 9 first requests were losing their
principal read and being classified `anon`. Rewinding to the LAST principal
fetch before the opener fixes it (real classes 573/72 → 564/81 anon/auth).

**Result — 0 under-emitted / 0 over-emitted per-request shapes, in all 58
scopes** (each of the 57 evidence files on its own, and combined):

```
== multiset_counts: 645 real requests, 20865 dumps ==
   auth classes — real: anonx564, authx81 | corpus: anonx9513, authx11352
   dropped 23 unframed statement(s) and 28 framed statements before a
   scenario's first action opener; 3 scenarios never reached the action
count-exact real requests reproduced by some dump: 396/645
RESULT: pass — per-request shapes under-emitted 0, over-emitted 0;
        per-row shapes at the one-representative limit 16 (known, not judged);
        format-split needed for 0 per-request shape(s)
```

Two declared classes keep their evidence visible instead of erasing it:

- **per-row family, wider IN-list.** The corpus's SampledList carries at most
  two representative rows, so a bulk preload binds at most 2 distinct keys
  while a 3- or 4-author fixture binds 3 or 4. The project's own statement
  currency does not distinguish `IN` arity (`note_fidelity_audit` compares
  {(column, `=`|`IN`)}), so these are the same predicate — but the arities are
  printed in an IN-ARITY census (real max IN(4) vs corpus max IN(2)) so the
  0/1/many abstraction's ceiling stays on the record.
- **out-of-domain** (`completion_config.json` `multiset_out_of_domain`): the
  array-valued `params[:post_id]` family. `ADVERSARY_REPORT_2.md` D1 measured
  with a real ActionDispatch probe that `post_id` is a PATH parameter and
  Rails merges path params LAST, so `?post_id[]=1&post_id[]=2` reaches the
  action as `"100"`; the array family was removed from the corpus in cycle 3
  as over-emission, and A04's `IN (?, ?)` finder comes from the adversary
  calling the action directly with a value the route cannot deliver. Declared
  with that reason, printed on every run, and still counted as an opener so it
  cannot corrupt the split.

### G. H6 re-derived against the corrected ground truth (the coordinator's ask)

`_c10/h6_rederive.py` runs H6's comparison over the WHOLE corpus (not the
lint's 1 200-dump sample) with the DML-aware shape function and all 57
evidence files. Residue: **one** note shape.

- **`ActiveRecord::Base.reload` — STILL REQUIRED, and now 1 shape, not 4.**
  `SELECT "people".* … "people"."id" = $$(…row_author_id) LIMIT 1`, ×6 475.
  It is unissued because of the `LIMIT 1`: every real people-by-id read here
  is the preload (`= ?` / `IN (…)`, no LIMIT); only `reload` re-reads one row
  with `LIMIT 1`. `reload`'s only call site on this endpoint is
  `Person#fix_profile` (`person.rb:371-375`), reached only after
  `Discovery.new(handle).fetch_and_save` RETURNS NORMALLY — and every path
  into it aborts the JVM on the first FFI call (typhoeus → Ethon → libcurl
  through JRuby's JFFI, DISCIPLINE §12). Corpus event ordering confirms the
  chain: `fetch_and_save → reload → find_target`, 1:1 with the 6 475 reload
  events. The other 3 shapes of cycle 8 now match real statements once the
  real side stopped being truncated at 60 characters.
- **`ci_public_first` — WITHDRAWN.** `"posts"."public" = true` now matches a
  real statement: `_shape` normalizes inlined booleans (the conversations
  2026-08-29 fix), so the scope constant is no longer a mismatch and the
  waiver excuses nothing. `h6_answered` went from two entries to one, and
  `hardening_lint` is still clean — a waiver removed is a check strengthened.

### H. A3-12 (a copied variant tuple goes stale) — measured, no instance

`coverage_assumptions.py` (`_VARIANTS`) and `demand_round.py` (`VARIANTS`)
both carry a private 4-tuple and attribute a dump by its label/filename
prefix rather than by `concolic_scenario.name`. Measured over all 20 879
dumps: **filename prefix == `concolic_scenario.name` in 20 879 / 20 879**, and
the corpus contains exactly those four scenario names. The defect has no
instance here; the mechanism is still a copy, so a future scenario addition
must migrate both to the dump field. (The concrete manifests' js/xml/html
scenarios are CONCRETE scenarios and never enter the concolic corpus.)

### I. The Z3-model overlay defect (notifications `_demand_root.py`,
conversations `mk_hand_seeds2.py`) — not present

This batch has no hand-seeder. `demand_round.py` already overlays ONLY the
variables that occur in the demanded combination's own exprs, onto the seed
dict of a real dump (same variant) that evaluated every expr of the
combination — the exact repair the coordinator describes, found here
independently in cycle 3 and commented in place
(`demand_round.py:81-85`). There is likewise no `_boundary_family`
substring classifier in this batch.

### J. Propagation matrix reconciliation (ADVERSARY_WINS.md)

Every ⏳ row for the comments column, dispositioned with evidence:

| row | disposition |
|---|---|
| **T-f** (M-5 `set_locale` InvalidLocale) | ✅ **applied, cycle 6 (W4-1).** Corpus records `devise_user_first_1_language == StringVal('pl')` and `== StringVal('xx')` with both polarities; 7 dumps terminate `I18n::InvalidLocale`. Matrix should read ✅. |
| **T-g** (M-6 STI `*_type` placeholder → `SubclassNotFound`) | ✅ **applied, cycle 6 (W4-2).** `Photo` is the out-of-tree witness (`targets.rb:1170-1176`), decided on four finder families with both polarities; 80 dumps terminate `ActiveRecord::SubclassNotFound`. |
| **T-l** (B-7 preload predicate follows cardinality) | ✅ **superseded by T-n/T-o and applied, cycle 7 (M-7).** The matrix's own note says comments' ✅ is superseded by T-n; T-n is ✅. |
| **T-q** (M-10 nested step on the parent PK has a DETERMINED key count) | ✅ **applied, cycle 8.** |
| **T-r** (M-11 unique-index-covered step: key count = row count) | ✅ **applied, cycle 8.** |
| **T-s** (M-12 schema-equal variables are ONE variable at EVERY key position) | ✅ **applied, cycle 8.** |
| **T-t (C-5, write conditional on dirtiness)** | **ledger: no instance.** `CommentsController#index` models no write: 19 distinct note shapes in 20 879 dumps, all SELECT; the corpus target census (15 names) contains no invoked write target. The one write-capable name on the path, `CommentsInertDiscovery.fetch_and_save`, is a declared network wall whose note is the non-SQL string "network wall, no SQL" — tolerated only because the real path aborts the JVM (DISCIPLINE §12) and no real run can reach it. **If that wall is ever lifted, T-t lands there.** |
| **T-t (M-13, partial FK-less `belongs_to` preload)** | ✅ **applied, cycle 9.** `[nil, live]` and `[live, nil]` both reachable; 2 094 events of the sibling-not-found state are in this corpus. |
| **T-u** (M-14 a row count may not be derived from a key count) | ✅ **applied, cycle 9.** |
| **T-v** (C-5 write target dirty state; the write is a second fact) | **ledger: no instance** — same evidence as T-t (C-5) above. |
| **T-w** (C-9 finder after a decided row count; `loaded?` phantom reads) | **ledger: no instance for part 1, mechanized for part 2.** Part 1: the corpus target census contains NO `count` / `size` / `any?` / `empty?` invocation at all, and the one `exists?` family (`Post.exists?(guid:)`, `message_renderer.rb:103`) is followed by no finder on that relation — its result only rewrites the URL. Part 2 (a phantom re-read from a relation that will not say `loaded?`) is exactly per-request over-emission, and the count matrix reports **0 over-emitted** in all 58 scopes. |
| **T-y** (C-12 the layout is TWO templates) | **ledger: unreachable on this endpoint.** `#index` renders NO layout on either renderable format — `format.json { render json: … }` and `format.mobile { render layout: false, … }` (`comments_controller.rb:52-53`). This is the APPLICATION's own code, not a rig pin: `grep -n layout run_dse.rb targets.rb` finds no layout stub, and `boundary_declaration_audit` passes (all 7 boundary families declared), so no target family is hidden behind it — the exact failure mode DISCIPLINE §14 warns about is checked, not assumed. |
| **T-z** (C-13 a `has_many` proxy read twice loads ONCE) | **mechanized and green.** `post.comments.for_a_stream` is materialized once and passed to the render as a local (`comments_controller.rb:50-54`, `index.mobile.haml` renders the collection); a phantom second read is per-request over-emission, and the count matrix reports **0 over-emitted** in all 58 scopes, corpus max ×1 per dump vs real max ×1 per request. |
| **T-x3** (C-16/C-17 auth SET-order and IP facts) | **—, and now also out of scope.** The matrix already marks comments `—`; under DISCIPLINE §15 it is auth-boundary material regardless. |

**Nothing here closes a target-level row by arguing the endpoint is special
without evidence**; each "no instance" row names the app source line and the
corpus measurement that establishes it.

### K. Parallel probe slots (RUNBOOK "Parallel probe slots", 2026-09-01) — measured

`tools/slot` was already wired into `assumption_manifest.json` (`runner`) and
`completion_config.json` (`test_cmd`); verified before use. First gate run
with `CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=2`, with a 60-second
MemAvailable/JVM tick beside it:

| measurement | sequential (cycle 9) | parallel (cycle 10) | ratio |
|---|---|---|---|
| assumption gate, standalone | ≈ 27 m 52 s (derived, see below) | **14 m 17 s** (measured, `/usr/bin/time -v`) | **1.95×** |
| the WHOLE engine report | **35 m 27 s** (measured, cycle-9 log) | **21 m 52 s** (measured) | **1.62×** |

Both beat the ~1.5× bar, so 2 workers stay. The sequential gate figure is
derived, not measured, and is labelled as such: the non-gate part of the
report is `21 m 52 s − 14 m 17 s = 7 m 35 s` (corpus load, the Z3 pass — 40.3 s
to write the summary —, shim extraction and tests, the note check and the
three audits), and subtracting it from the cycle-9 total gives the sequential
gate. A directly measured sequential gate was not run because it costs another
~28 minutes on a box that is already memory-bound.

**Memory, not cores, is the ceiling and it was close.** Two JRubys peaked at
1 725 MB together and MemAvailable touched **409 MB** against the shared
watchdog's 300 MB floor (`_experiment/_mem_watchdog_lowfloor.sh`, which has
been killing another batch's JRubys as recently as 02:55 today). It held —
no kill, gate verdicts complete — but a third worker would not fit, and on a
busier box even 2 would be at risk. The report's own Python peaked at
1 066 MB (the lean loader; the RUNBOOK's "5.5–6.3 GB at 20k dumps" is not this
batch's figure).

### L. Final state — ONE corpus, every instrument current

```
complete: true          coverage_complete: true      completion.blocking: []
tree nodes 71           missing_branches 0           truncated false   solver_lost 0
runs 16 496 (20 879 dumps, 4 383 duplicate outcome maps)   PCs 359 770
unevaluable_exprs []    dump_errors {}
shims        19 PASS / 11 PROTOCOL / 0 red / 0 NO-TEST (30 extracted)
assumptions  3 073 declared, 2 713 distinct tested, 2 713 PASS, 0 FAIL,
             0 NOT-TESTABLE, 0 unverified, driver exit 0
note_check   green        audits  format_coverage / note_fidelity /
                                  empty_relation_emission all green
report       21 m 52 s wall, peak RSS 1 066 MB
```

Everything above was produced on the SAME corpus, with no regeneration in this
cycle: nothing the current instruments found was a corpus defect.

### M. Open items handed to the coordinator

1. **`cardinality_consistency_audit` needs the two-escape widening** (§D).
   `src/` is shared, so this batch did not make the change. Until it lands the
   audit is RED on this corpus and the RED is the audit's, with
   `_c10/verify_cardinality_escapes.py` as the proof (13 460 flagged, 13 460
   explained, 0 unexplained).
2. **`rig_crash_census.py` is blind to a batch-declared terminal field** (§E).
   It reads `dump["error"]` only; this rig records app terminals in
   `dump["concolic_terminal"]`. Pass on this batch is real but was confirmed by
   a hand census, not by the tool.
3. **The `CommentsInertDiscovery.fetch_and_save` wall stands** — a non-SQL
   note over a body that in the real gem persists a Person, tolerated only
   because the real path aborts the JVM (DISCIPLINE §12). It is the single
   place where T-t/T-v (write dirtiness) could land on this endpoint, and the
   `reload` H6 waiver rests on the same fact.
4. **The one-representative SampledList ceiling on this endpoint**, recorded
   per DISCIPLINE §14: bulk preloads bind at most 2 distinct keys in the
   corpus (`IN (?, ?)`), while real fixtures with 3–4 distinct authors bind 3–4;
   per-row multiplicities are corpus max ×2–4 against real ×7–28.
5. **`_VARIANTS` / `VARIANTS` are still copied tuples** attributing a dump by
   label prefix (§H). No instance today (20 879/20 879 agree), but a new
   scenario would go silently to `unknown`.

---

## Cycle 11 (2026-09-01) — adversary round 8: M-16 and M-15 closed, plus three defects the repair itself exposed

Round 8 scored 2 wins, both TARGET-LEVEL, and voided cycle 10's
`complete: true`. Worked in the order the coordinator set: M-16, then M-15's
newly reachable arms, then the instrument questions, then a full regeneration.

### W8-2 / M-16 — a second KEY needs a second OWNER OBJECT

**The defect.** Cycle 9's M-13 repair materialised a second representative row
only where the step was an FK-less `belongs_to` (`dangling_belongs_to?`), and
only at the TOP of an `includes` tree. Every other step recorded the second
key's outcome as a bare `_k2_not_found` boolean whose only effect was
`loaded_keys << keys[1] unless …` — and `loaded_keys` is consumed solely by the
NESTED step. On the DEEPEST step of a tree (`Comment{author: :profile}`,
`Mention{person: :profile}`) the True arm therefore reached nothing: no child
attached, `Person#name` never called on key 2, no `_discovery_failed` decision,
no terminal. 1 345 dumps asserted a clean 200 and a full render where the real
request 500s after fewer statements.

**The repair, in three parts** (`targets.rb`):

1. **`needs_second_row?` now walks the WHOLE tree and counts `has_one`.** The
   rule is no longer "an FK-less `belongs_to` at the top" but "any step, at any
   depth, whose outcome is a DECISION" — `has_one` (no FK forces the child row
   to exist) or an FK-unconstrained `belongs_to`. Those are exactly the steps
   that can attach nil, and the decision is per KEY.
2. **The nested step recurses from BOTH surviving parents.** `emit.call(child
   || child2, nil, …)` was the other half: the nested step then had two KEYS
   and one OWNER, so its second key fell into the `_k2_not_found` branch. It is
   now `emit.call(survivors[0], survivors[1], …)`, so the deepest step gets a
   per-object `_not_found` on its own base.
3. **The `_k2_not_found` boolean is gone.** Where no second owner object exists
   the key is simply LOADED: the corpus never claims an outcome it cannot
   exhibit.

**Verified, not assumed.** Smoke corpus after the repair: **0 dumps carry any
`_k2_not_found`**; `…_row2_author_profile_not_found` and
`…_row2_person_profile_not_found` exist as real per-object decisions; and a
directed `SEEDS_ONLY` replay of the exact state shows both arms with the right
consequence:

```
nf2=True df2=True  -> DiasporaFederation::Discovery::DiscoveryError, 13 statements
nf2=True df2=False -> no terminal,                                   18 statements
```

i.e. the arm that used to be a clean 200 now 500s AND truncates — which is what
H06's real runs do (870 json: 7 statements then DiscoveryError).

### M-16b — one relation read twice is ONE FACT (found while verifying M-16)

`MentionsContainer#mentioned_people` is called TWICE per comment on this
endpoint (the text pipeline through `Mentionable.format`, and
`CommentPresenter#as_json:15`), and each call rebuilds
`mentions.includes(person: :profile)`, so the app really issues the SELECT
twice (R8 N8-2). The rig minted an INDEPENDENT list per call, each with its own
length decision and its own per-row outcomes. Measured on the smoke corpus:
**1 661 relations read twice, 654 of them with DISAGREEING `len > 1`
decisions** — one comment's `mentions` holding two rows in the first read and
one in the second, a state no database produces. It also MASKED the M-16 repair
on the mention tree: in `dump_anon_json_dse0136` the read that carried the
missing profile was not the read the presenter serialised, so no `name` call
followed.

Repair: the materialised list is MEMOIZED by its own SQL for the life of the
run (`Thread.current[:comments_rows_memo]`, reset per run in `run_dse.rb`). The
second read re-emits every statement — multiplicity is real and stays exact,
0..4 `mentions` statements per dump as before — and re-records the same
decisions under the same variable names, but it is the SAME list. Measured:
distinct list-length variables per dump went from **max 5 to max 3** (the
comments list plus one mentions list per comment row), which is the correct
count.

### The over-emission my own repair introduced, caught before regeneration

With a second comment row present, the FK-constrained `belongs_to` branch minted
`child2` unconditionally — a second author Person even when `keys_many == False`
says there is ONE distinct author. Measured on the smoke corpus: **488 dumps**
emitted a second `profiles.person_id = ?` read for an author that does not
exist. Fixed: a second child is minted only where there is a second KEY, and
with one key both rows point at the SAME child (what AR's `Preloader` does).

### W8-1 / M-15 — the waiver's premise, re-derived on this batch's own evidence

The `h6_answered` reason said *"every path into `fix_profile` aborts the JVM on
the first FFI call, so no real run on any rig can reach it"*. Two probes, each
in its own systemd unit so an abort names itself (real gem, real app boot, no
rig):

| probe | handle | result |
|---|---|---|
| `_c11/probe_uri_hostile.log` | `wraith@ba[d.example`, `ghost@ex ample.com` | `DiscoveryError` (`URI::InvalidURIError` inside), **unit exit 0, JVM alive** |
| `_c11/probe_parseable.log` | `ghost@example.invalid` | **SIGSEGV, unit status 134** |

`Faraday.default_adapter == :typhoeus` in both. So the old reason is FALSE —
the abort is at the curl call, not at `fix_profile` — and M-15 is reproduced
independently of the adversary.

**The true reason, and it is narrower than the old one.** `reload`'s only call
site here is `Person#fix_profile` (`person.rb:371-375`), which runs it only
after `fetch_and_save` RETURNS A VALUE. My own reading of the gem
(`discovery.rb:19-31, 55-95`) shows returning normally needs TWO successful live
HTTP fetches — `webfinger` (:73) and `hcard` (:84), both `HttpClient.get` — and
there is no local short circuit in that class. Every fixture-reachable
`fetch_and_save` therefore RAISES: the URI-hostile arm in Ruby, the parseable
arm by killing the process. `reload` is never issued. **This is an ENVIRONMENT
bound (JRuby + typhoeus/JFFI), not an app property** — on a deployed pod the
success arm is reachable. The waiver is re-derived with that reason, and the
scope caveat is written into it.

**The wall's note stopped lying.** The success arm's note ended "no SQL". That
was a positive false claim: on that arm the gem triggers
`:save_person_after_webfinger`, and diaspora's own callback
(`config/initializers/diaspora_federation.rb:59-77`) issues `Person.find_by`,
`Pod.find_or_create_by`, a profile read and `person_entity.save!` — three reads
and one or more writes. The note now says the persistence callback is
**UNMODELLED, not absent**. No statement is asserted for an arm no real run in
this environment can reach.

**T-t / T-v (writes) — the corrected reason.** They still have no instance on
this endpoint, but NOT for the reason the matrix footnote records. The correct
reason: the endpoint's only write site is that callback, on `fetch_and_save`'s
success arm, and that arm needs two live HTTP fetches this stack cannot
perform. The adversary reached `fix_profile` 31 times and `fetch_and_save` 31
times with `reload` 0 times; my own r6 manifest reaches it 9 times, every one a
`DiscoveryError` raised BEFORE any persistence. **If the environment ever gains
a working HTTP adapter, T-t/T-v lands there immediately.**

### The newly reachable `profile_not_found == True` arms are modelled AND explored

DISCIPLINE §12's blanket claim is dead, so those arms had to be real corpus
states, not walls. They are: on the regenerated corpus every
`…_profile_not_found == True` is followed by a `…_discovery_failed` decision
with BOTH polarities, on the author tree and the mention tree, on the first row
and on the second. The 10 smoke dumps where no discovery decision follows were
each checked individually: the run had already terminated on an EARLIER row's
`discovery_failed == True`, so the later person's `name` is genuinely never
called — truncation, not masking.

### Our own ground truth now contains the path (`concrete_manifest_r6.rb`)

Until now this batch's own concrete evidence contained **zero** `fix_profile`
calls: every scenario gave every person a `profiles` row, so the corpus's claims
about the discovery path rested on the adversary's runs alone. `r6` adds 11 real
requests over byte-identical fixture pairs that differ ONLY in which key lacks
its `profiles` row:

```
author key2 missing json   -> DiscoveryError      author key1 missing json   -> DiscoveryError
author key2 missing mobile -> Template::Error     author key1 missing mobile -> Template::Error
mention key2 missing json  -> DiscoveryError      mention key1 missing json  -> DiscoveryError
mention key2 missing mobile-> Template::Error     both authors profileless   -> DiscoveryError
CONTROL both profiles json -> 200                 CONTROL mobile             -> 200
author key2 missing SIGNED-IN json -> DiscoveryError
```

That is M-16's differential and M-15's reachability, reproduced without the
adversary's files.

`merge_concrete_runs.py` silently dropped it: its input list was HARDCODED —
the same "a copied list goes stale" class as DISCIPLINE §14's A3-12. It now
derives the list from the directory, NAMES every file it merged, and exits 1
on a `concrete_manifest_*.rb` with no matching run.

### N8-5 — the unconstrained second key: what I found

The question was whether anything reads `…_row2_author_id` while
`keys_many == False` asserts the key set is one, and whether a solver could
pick a value that makes that assertion false.

**Before the repair it was a real soundness hole, in one direction only.**
Nothing read the variable (the emitted note binds only `…_row_author_id`), so a
model was free to give the second comment's author a DIFFERENT id — a state in
which two rendered comments have two authors while the policy reads one of
them. That direction loses an access-control read, so it is not benign.

**Closed by construction.** In the one-key state the second row's `author_id`
attribute IS the first row's symbol, and no second child is minted. Measured
over the regenerated corpus (22 415 dumps that record the decision):

| `keys_many` | dumps | `…_row2_author_id` bound by a note | appears in a PC |
|---|---|---|---|
| False | **15 591** | **0** | **0** |
| True | 6 824 | 6 824 | 3 994 |

What remains under `keys_many == False` is unread HYGIENE: `symbolic_instance`
mints every column of the second row, so the variable exists in
`symbolic_vars` and is read by nothing. The mirror residue on the `IN` side
(a model could make the two binds equal while the note says `IN (?, ?)`) is
**benign** — an `IN` over two equal values selects the same rows, and the
policy predicate is `{(people.id, IN)}` either way.

### The coverage explosion the second row caused, and why the fix is a Tier-2 pair

With two representative rows the checker demanded every cross-row combination
of two INDEPENDENT text pipelines (395 missing at the peak). `_chain()`
classified both rows' text decisions as one `comment_rep` chain, so Tier 2
could never pair them. They are DISJOINT REPS — two different comments, two
different texts — so the chain key now carries the row. Decisions on the SAME
row stay in one chain and are still demanded. 395 missing -> 2, and the
assumption GATE flip-probes every one of the new pairs, so if the two rows do
interact the probe says FAIL and the assumption is withdrawn.

The last 2 combinations were reached by hand-seeded roots (mobile,
`row2_author_discovery_failed` and `keys_many ∧ discovery_failed` with the
author NOT the principal), seeded from real dumps that already reach the step
and overlaying ONLY the demanded variables.

### Instrument findings of this cycle

1. **`_multiset_counts.py` charged adversary body probes to a request.** The
   cycle-10 rule dropped framed statements only BEFORE a scenario's first
   action opener. R8's H03 ends with three `User.find(uid)` probes (unframed)
   each followed by that fresh User's `people.owner_id` load (framed) — after
   the last request, so the old rule could not see them, and the judge reported
   `people.owner_id` real x3 vs corpus x1. Rule extended: an `under: null`
   statement returns the stream to SCENARIO-BODY context, and framed statements
   after it are the body's own AR calls until the next opener. This batch's own
   concrete runs contain zero unframed statements, so the rule never touches
   them; all three drop counts are printed.
2. **2 probe workers do not fit at this corpus size.** The report was killed by
   the shared watchdog (`_mem_watchdog.log 06:59:53, avail=267412KB < floor`)
   at 1.95 GB Python RSS with 2 JRubys up. At 20 879 dumps (cycle 10) 2 workers
   gave a measured 1.95x on the gate; at 26 931 dumps the coverage tree alone is
   ~2.1 GB and the pair no longer fits. The knob is CORPUS-SIZE dependent on
   this box, not a constant.

### The assumption-gate RED, and what it was not

The first full report after the repair came back
`blocking: ["assumption driver: RED"]` with `driver_exit 1`,
`distinct_tested 0`, `verdict_counts {}` and an `output_tail` full of PASS
lines. Ruled out in the order of cheapest discriminating evidence:

1. **Not the probe worker pool.** That report's own header line reads
   `SLOTS=2 WORKERS=1` — the failing run was ALREADY sequential.
2. **Not a probe raising on a newly reachable M-15 arm.** The driver was then
   run STANDALONE, sequentially, on the same corpus with the same arguments:
   `RESULT: 4614 distinct tested — PASS 4614, FAIL 0, NOT-TESTABLE 0`,
   exit 0, 27 m 31 s, peak RSS 957 MB (`_c11/_gate_stderr.log`).
3. **Not the shared watchdog.** `_mem_watchdog.log` records exactly one kill in
   that window — `06:59:53 avail=267412KB` — and that was the FIRST report
   attempt (WORKERS=2, python at 1.95 GB). The failing 07:00 run has no kill.
4. **Not the engine's environment.** `completion.py:_run` EXTENDS `os.environ`
   rather than replacing it, so the driver had a full environment.

Re-running the identical report with the driver behind a `tee` wrapper gave
`OVERALL_COMPLETE=True; COMPLETION=True`, 4 614/4 614 PASS, driver exit 0.
So the failure **did not reproduce in two subsequent sequential runs** and no
exception exists on disk for it — which is itself the reportable defect:
**`concolic_engine/completion.py` keeps only a TAIL of the driver's stdout and
discards its stderr entirely**, so a one-off driver death is undiagnosable
afterwards. Worked around batch-locally: `assumption_cmd` now points at
`_c11/gate_wrapper.sh`, which tees the full stream to
`_c11/_gate_engine.log` and preserves the driver's exit status via
`PIPESTATUS`. The engine-side fix is the coordinator's to make.

**No test was narrowed to get green.** Declared assumptions went 3 073 → 5 315
and distinct probes 2 713 → 4 614 — the M-15 arms and the second representative
row brought real new state, and every one of the new pairs was flip-probed.
0 FAIL, 0 NOT-TESTABLE, 0 unverified.

### Final state — ONE corpus, every instrument current

```
complete: true      coverage_complete: true      completion.blocking: []
tree nodes 94       missing_branches 0           truncated false   solver_lost 0
runs 25 073 (26 931 dumps, 1 858 duplicate outcome maps)   PCs 882 543
unevaluable_exprs []          dump_errors {}
shims        19 PASS / 11 PROTOCOL / 0 red / 0 NO-TEST (30 extracted)
assumptions  5 315 declared, 4 614 distinct tested, 4 614 PASS,
             0 FAIL, 0 NOT-TESTABLE, 0 unverified, driver exit 0
note_check   green      audits  format_coverage / note_fidelity /
                                empty_relation_emission all green
report       30 m 21 s wall, peak RSS 2 072 MB, WORKERS=1
```

Standalone checks on the same corpus:

| check | verdict |
|---|---|
| `identity_symbolicity` | pass — owner_id 11 812 / user_id 13 923 / users.id 13 932, all symbolic, 0 literal |
| `statement_note_lint` | pass (no red-level findings) |
| `bind_resolution` (venv) | pass — 414 617 binds, 0 AMBIGUOUS / 0 UNRESOLVABLE / 0 DERIVED-MISBOUND |
| `skipped_pcs --patched variant_d` (venv) | pass — every recorded PC shape parses, 0 dropped |
| `pc_visibility --gate` | pass |
| `empty_relation_emission` | pass — 3 837 empty-list states, none read |
| `noteless_call` | pass — 462 022 target-call events |
| `cardinality_consistency` | **pass — population 111 345 (note, list) pairs judged, 41 041 explained: 31 182 `keys_many == False` + 5 036 parent-not-found + 4 823 sibling-not-found; 70 304 pass on their own merits** |
| `rig_crash_census` | pass — 8 terminal classes, every one an application terminal |
| `boundary_declaration_audit` | pass |
| `hardening_lint` (68 evidence files, DML-aware) | all checks clean |
| count multiplicity (63 scopes) | 0 under / 0 over per-request shapes; 730 real requests |

Terminal census (`concolic_terminal`, 26 931 dumps): `<none>` 24 400 ·
`Template::Error ← NoMethodError` 1 322 · `DiscoveryError` 825 ·
`Template::Error ← DiscoveryError` 345 · `SubclassNotFound` 26 ·
`DelegationError ← NoMethodError` 6 · `NoMethodError` 4 ·
`I18n::InvalidLocale` 3. All eight are application outcomes.

---

## Cycle 12 (2026-09-01) — adversary round 9: M-17 and M-18

### W9-1 / M-17 — RESOLUTION (b): the discovery-success arm is no longer explored

**The defect.** The corpus took `_discovery_failed == False` — the arm on which
`Discovery#fetch_and_save` RETURNS — in 7 272 of 26 931 dumps, and asserted
exactly two statements there (`reload`'s `people … LIMIT 1` and the profile
`find_target`, 7 972 calls each) plus a clean 200. But `fetch_and_save`
(discovery.rb:19-31) cannot return until `:save_person_after_webfinger` has
completed, so those two reads come strictly AFTER the callback's statements —
of which the corpus carried none. Cycle 11's written claim, *"No statement is
asserted for an arm no real run in this environment can reach"*, was false.

**I chose (b) — do not explore the arm — and did not choose (a).** The reason
is not cost, it is verifiability:

* Every note in this project is verified against a REAL ENDPOINT statement:
  that is exactly what `mock_note_check` and `note_fidelity_audit` do. The
  callback's statements have real counterparts only as SCENARIO-BODY probes and
  can NEVER have an endpoint counterpart here — `fetch_and_save` returning needs
  two live HTTP fetches (discovery.rb:73 `webfinger`, :84 `hcard`, both
  `HttpClient.get`, no local short circuit) and this JRuby/typhoeus/JFFI stack
  SIGSEGVs on any parseable URL (measured twice by this batch, once by R8).
* Modelling them would create ~13 permanently unverifiable note families, each
  needing an H6 waiver whose only argument is a code reading — the mechanism
  DISCIPLINE §14 forbids — and would assert WRITE semantics (T-t/T-v dirty
  state) that no run could ever exercise.
* (b) is the rule this batch already applied to itself in cycle 11 when it
  deleted `_k2_not_found`: **the corpus never claims an outcome it cannot
  exhibit.** A single-valued decision is a phantom too, so the decision is
  GONE, not pinned: `discovery_returns` now always raises.

**WHAT THE POLICY CLAIMS AFTER (b), exactly.** It describes this endpoint's
data access on every path a real request in THIS environment can take. On the
`fix_profile` path it claims the reads that precede the wall and the
`DiscoveryError` terminal, and **nothing after the wall**. It does NOT claim
that discovery performs no data access — it declines to describe it.

**CORRECTION (2026-09-01), and then a correction OF that correction.** This
sentence originally continued "…and says so in the wall note itself". That was
wrong: no wall note exists in the current corpus. My first attempt to explain
why was ALSO wrong, and the coordinator's full census caught it. Both censuses
reproduced here, whole corpora, no sampling:

```
CURRENT (cycle 12):  26 528 dumps · 13 distinct targets
                     discovery `symbolic_call` events        0
                     discovery bare `call` trace events  4 657  (carry no note by kind)
ARCHIVE cycle 11:    26 931 dumps · 15 distinct targets
                     discovery `symbolic_call` events    7 972  — ALL 7 972 NOTED
                     discovery bare `call` trace events  9 142
```

(Naming, for accuracy: the cycle-11 decision variable is `*_discovery_failed`.
`discovery_returns` is the rig lambda's name and appears in zero dumps of
either corpus.)

* **What I got wrong.** My first census did not filter on
  `event["type"] == "symbolic_call"`, so it counted the 4 657 bare `call`
  trace events — which carry no note *by kind* — and I read that as "the
  events exist with empty notes", then diagnosed a non-existent defect: that
  the `Thread.current[:concolic_pending_note]` line before the `raise` is a
  no-op. **That INFERENCE is refuted** (the count itself was right: the
  `fetch_and_save` `call` trace event does survive in cycle 12, in 4 657
  dumps; it simply always raises and so never becomes a `symbolic_call`). Cycle 11's 7 972 noted `symbolic_call`
  events are direct evidence that the note channel attaches fine. There is no
  known defect in it and the claim has been withdrawn from the limits list;
  a limitation list carrying an invented defect is worse than one omitting a
  real one, because a later reader will chase it or "fix" working code.
* **The real reason no note appears in cycle 12**, stated only as far as the
  evidence goes: the M-17 arm now RAISES before producing a symbolic result, so
  no `symbolic_call` event is recorded for it at all — there is no noted event
  kind to carry a note, which is a different thing from a note failing to
  attach. `noteless_call_audit` passes because `fetch_and_save` is a documented
  wall.
* **What was right, and is what mattered:** the corpus contains no wall note,
  so under resolution (b) the exclusion had to be declared in the artifact.
  A wall note is deliberately NOT re-added — a non-SQL note over a body now
  known to issue 13 statements is the H3 / T-a violation and would be a worse
  misstatement than silence.

`targets.rb` is NOT modified: the corpus and the file that produced it stay as
the closure artifacts.

**The declaration now lives in the ARTIFACT, not in prose.**
`POLICY_HEADER.txt` in this directory is its canonical text and is prepended to
`results3/queries_from_runs/comments_index.sql`; every extraction must re-apply
it. A policy file that simply stops at the wall is indistinguishable from one
that covers everything, so the header states the scope, names the unreachable
arm with the measured SIGSEGV evidence, and lists what the policy would gain
(`INSERT people` / `INSERT profiles` / `UPDATE profiles`; reads of `pods`,
`tags`⋈`taggings`, `people.guid`, `people.diaspora_handle`), citing
`_c12/_discovery_gap_evidence.json` by path. That same `.sql` now also carries a
STALE-BODY banner: its 26 statements are the 2026-08-26 extraction, three corpus
rebuilds out of date, and must be regenerated.

**The declared gap, measured by this batch** (`_c12/discovery_gap_probe.rb`,
`_c12/_discovery_gap_evidence.json` — the app's own callback, no network):

* *new person* — **17 statements, 13 of them data access**: `people` by
  handle · `pods` by host · BEGIN · **INSERT INTO pods** · COMMIT · BEGIN ·
  `1 AS one FROM people WHERE guid` · **`SELECT people.diaspora_handle …` (a
  pluck)** · `1 AS one FROM people WHERE diaspora_handle` · **INSERT INTO
  people** · **INSERT INTO profiles** · `tags ⋈ taggings` · COMMIT.
* *existing person without a profile* — my fixture hit
  `ActiveRecord::RecordInvalid: Specify an owner or a pod, not both` (the
  `owner_xor_pod` validation, person.rb) after issuing the `people` read, the
  `profiles` read, **INSERT INTO profiles**, the `tags ⋈ taggings` join and the
  two uniqueness probes, then ROLLBACK. Stated as measured: that branch did not
  complete under my fixture, the adversary's did; the statement FAMILIES agree.

So the undescribed arm touches three tables the policy has no note for
(`pods`, `tags`, `taggings`), two predicate columns it has none for
(`people.guid`, `people.diaspora_handle`) and three writes. **Extraction or a
future rig with a working HTTP adapter should union that set in.**

**Verified on the regenerated corpus (26 528 dumps):**
`discovery_failed` PCs **0** · `reload` calls **0** · DML notes **0** ·
tables in notes exactly `{users, posts, people, profiles, comments, mentions}`
· `DiscoveryError` terminals 4 027 (the wall arm is fully modelled).

**N9-5 closed by the same repair.** The 4 014 anonymous dumps asserting
`people … id = ? LIMIT 1` / `profiles … person_id = ? LIMIT 1` — statements no
anonymous request can issue — were all on that arm. Measured on the new corpus:
**0**.

**The `h6_answered` waiver is retired — the batch now has ZERO waivers.** With
the arm gone there is no `reload` note to answer for, and `hardening_lint` is
clean with `h6_answered: []`. (The retired entry is archived in
`completion_config.json` as `_h6_answered_retired_cycle12`.)

**T-t / T-v — the matrix footnote needs changing, and here is the correct
wording.** Under (b) this endpoint still has **no write instance**, but the
reason in the footnote (`n/a¹`) must not be "the discovery path aborts the
JVM". The correct statement: *the endpoint's only write site is
`:save_person_after_webfinger` on `Discovery#fetch_and_save`'s success arm;
that arm is UNREACHABLE in this environment (two live HTTP fetches) and is
DECLARED UNMODELLED, so no write is asserted and none is exercised. If the arm
is ever modelled — resolution (a) — this endpoint gains three writes
(`INSERT people`, `INSERT profiles`, `UPDATE profiles`) and T-t/T-v become
live here.*

### W9-2 / M-18 — the measurements you asked for

**How, batch-locally.** The shared probe is untouched. `_c12/exec_wrap.rb`
defines `ci_wrap { }`, which wraps its block in
`Rails.application.executor.wrap` when `CI_EXECUTOR=1` and is a plain `yield`
otherwise; each of the seven manifests requires it and wraps its single
dispatch expression (`tc.process(:index, …)`, or `ctrl.send(:index)` in
`concrete_manifest_anon.rb`). The same manifest file therefore produces BOTH
ground truths; the wrapped outputs are `concrete_run_<m>_exec.json` and are
excluded from `merge_concrete_runs.py` so they cannot double the merged run.

**1. Per manifest, statements plain vs executor-wrapped** (the probe skips
`payload[:cached]`, so the wrapped column IS what a real Rack request's probe
records):

| manifest | plain | wrapped | delta | distinct shapes plain / wrapped |
|---|---|---|---|---|
| anon | 16 | 11 | −5 | 8 / 8 |
| auth | 44 | 31 | −13 | 11 / 11 |
| mobile | 22 | 22 | **0** | 11 / 11 |
| r3 | 49 | 40 | −9 | 11 / 11 |
| r4 | 52 | 45 | −7 | 13 / 13 |
| r5 | 40 | 30 | −10 | 7 / 7 |
| r6 | 78 | 68 | −10 | 12 / 12 |
| **total** | **301** | **247** | **−54 (−17.9 %)** | **16 / 16** |

`mobile` is unchanged because the mobile template builds `#message` only, so it
issues the `mentions` read once per comment where json issues it twice — the
format with no repeated statement has nothing to cache.

**2. Does any SHAPE disappear? NO — only multiplicities fall.** 16 distinct
shapes both ways, per manifest and corpus-wide; **0 shapes lost, 0 gained.**
Exactly five shapes change count, all of them repeated per-ROW reads:

```
mentions … container_id = @                   81 -> 48
people   … id = @                             30 -> 23
profiles … person_id = @                      29 -> 22
people   … id IN (@, @)                       24 -> 20
profiles … person_id IN (@, @)                22 -> 19
```

So M-18 touches the policy's COUNTS, not its CONTENT: the extracted policy —
a set of statement shapes with their predicate columns — is byte-identical
under both ground truths.

**3. `_multiset_counts.py` against the executor-wrapped ground truth: PASS**
— 0 under-emitted / 0 over-emitted per-request shapes in all 8 scopes
(7 wrapped files + combined), 41 real requests, count-exact 35/41. The plain
ground truth on the same corpus also passes (0/0, 66 scopes, 731 requests).

**Why it passes both ways, which is the part worth reading.** Every shape whose
multiplicity changes under caching is a per-ROW shape, and the count check
excludes per-row shapes in BOTH directions by design (the one-representative
LIMIT and the ROWSCALE rule). The per-REQUEST shapes — the post finders, the
principal fetch, `comments`, `people.owner_id` — all have multiplicity 1 and are
unaffected by caching. **So on this endpoint the count matrix cannot see M-18
at all, and its "0 under / 0 over" verdict is the same under either ground
truth.** That is a statement about this endpoint only; on a batch whose
per-REQUEST shapes repeat, the ground truth would move and the verdict could.


---

## CLOSURE (2026-09-01)

Adversary round 10 scored **zero wins** across 37 real requests, refuting all
four attacks on the M-17 resolution with positive evidence (the legacy
host-meta URL proving the primary was tried and rescued; 293 frame-tagged
statements naming no `pods`/`tags`/`taggings`; a five-axis c11-vs-c12
differential in which every lost item names a `*_discovery_failed` variable;
16 EXACT / 0 MISSING on the statements before the raise). With the engine's
`complete: true`, the coordinator's green eleven-check sweep and the count
matrix under both ground truths, all four closure conditions hold on one
corpus.

Policy extracted: **413 594 raw queries → 79 distinct → 0 subsumed → 79
views** over 26 528/26 528 dumps, 0 errors, `POLICY_HEADER.txt` re-applied and
the STALE BODY banner removed. The extractor installs `variant_d`'s
`assoc_fold`, which is mandatory here: the vanilla `src/` fold drops 73 461
`(VAR == VAR(_))` PCs on this corpus (every StringVal equality branch —
`users.language`, `posts.type`) where the patched fold drops 0.

**On the completeness number, in the adversary's words and unsoftened:** *the
deletion removed the decision, so the checker can no longer demand any
"discovery succeeded" combination — `complete: true` at 84 nodes is a CHEAPER
CLAIM than at 94, though not a false one.* The tree shrank because we stopped
asking a question, not because we answered more.

Full closure evidence: `REPORT.md`.
