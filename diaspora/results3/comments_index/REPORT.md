# comments_index — REPORT (CLOSED)

`CommentsController#index` — `GET /posts/:post_id/comments`.
Closed 2026-09-01 after cycle 12 and adversary round 10.

**All four closure conditions hold on ONE corpus:**

| condition | result |
|---|---|
| engine | `coverage_summary.json` **`complete: true`** — coverage complete, `completion.blocking: []` |
| coordinator's eleven-check sweep | fully green (identity, note lint, bind resolution, skipped PCs, pc_visibility, empty relation, noteless call, cardinality, boundary declaration, rig-crash census, audit self-test) |
| count matrix | 0 under / 0 over per-request shapes, under **both** ground truths |
| adversary round 10 | **ZERO wins** across 37 real requests |

Policy extracted to `results3/queries_from_runs/comments_index.sql`:
**413 594 raw queries → 79 distinct → 0 subsumed → 79 views**, from
26 528/26 528 dumps, 0 extraction errors.

## 1. Result

`coverage_summary.json` — **`complete: true`**, produced by one report over one
corpus with every instrument current.

| axis | value |
|---|---|
| `coverage_complete` | true — 84 PC nodes, **0 missing** branch combinations |
| corpus | **26 528 dumps**, 25 408 runs loaded (1 120 duplicate outcome maps), **928 746 PCs** |
| exploration health | `truncated: false`, `solver_lost: 0`, `unevaluable_exprs: []`, `dump_errors: {}` |
| `completion.complete` | true — `blocking: []` |
| shims | 19 PASS / 11 PROTOCOL / 0 red / 0 NO-TEST (30 extracted) |
| assumptions | 4 182 declared · 3 648 distinct tested · **3 648 PASS / 0 FAIL / 0 NOT-TESTABLE** · 0 unverified · driver exit 0 |
| note check | green |
| engine audits | `format_coverage`, `note_fidelity`, `empty_relation_emission` — all green |
| **waivers** | **zero** — `h6_answered: []` |
| report cost | 22 m 57 s wall, peak RSS 2 004 MB, `CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=1` |

Standalone checks on the same corpus: `identity_symbolicity`,
`statement_note_lint`, `bind_resolution` (0 AMBIGUOUS / 0 UNRESOLVABLE /
0 DERIVED-MISBOUND), `skipped_pcs --patched _experiment/variant_d` (every
recorded PC shape parses), `pc_visibility --gate`, `empty_relation_emission`,
`noteless_call`, `rig_crash_census`, `boundary_declaration_audit`,
`hardening_lint` — all green.

`cardinality_consistency_audit`, with its population and all three escapes:

```
rule population: 123974 (note, list) pair(s) where a BULK loader reads a list's own rows
   39804 events  key-count decision (`keys_many == False`)
    6361 events  parent of the emitting step not found (pre-existing escape)
    6117 events  sibling row's parent not found
RESULT: pass — 123974 pair(s) judged, 52282 explained
```

### What `complete: true` at 84 nodes does and does not mean

The tree was 94 nodes in cycle 11 and is 84 now. The adversary's own framing of
that, which belongs here and not in a footnote:

> the deletion removed the decision, so the checker can no longer demand any
> "discovery succeeded" combination — `complete: true` at 84 nodes is a
> **CHEAPER CLAIM** than at 94, though not a false one.

A reader comparing 94 to 84 must know the tree shrank because **we stopped
asking a question**, not because we answered more of them. The question we
stopped asking is the one §3 declares: what the endpoint does when discovery
succeeds. Round 10 confirmed the shrink is confined to it — a full
cycle-11-vs-cycle-12 differential on five axes (nodes, PC variables, statement
shapes, call pairs, declarations) found that **every lost item names a
`*_discovery_failed` variable, with 0 non-discovery losses**.

Terminal census (26 528 dumps), every class an application outcome:
`<none>` 20 427 · `DiscoveryError` 4 027 · `ActionView::Template::Error` 2 024 ·
`ActiveRecord::SubclassNotFound` 38 · `Module::DelegationError` 4 ·
`NoMethodError` 4 · `I18n::InvalidLocale` 4.

## 2. Scope

The entrypoint is the POST-AUTH action with a SYMBOLIC principal
(DISCIPLINE §15). The endpoint's complete policy is
`queries_from_runs/comments_index.sql` **UNION** §2 of
`results3/_auth_boundary/BOUNDARY_POLICY.md`.

Endpoint-specific: `authenticate_user!` is `except: :index` on this
controller, so the principal is fetched lazily by `set_locale` /
`user_signed_in?` rather than by the Devise filter. The statements and hooks
are the ones the boundary artifact describes, so it applies unchanged; and an
**anonymous request touches no authentication stage at all**.

## 3. Where this policy stops, and why (M-17)

**This policy describes the endpoint's data access on every path a real
request in this environment can take.** It stops in exactly one place.

Rendering a person's name calls `Person#name` (`person.rb:249`); on a person
with no `profiles` row that calls `Person#fix_profile` (`:373`), which calls
`Discovery#fetch_and_save`. Two arms:

* **The raising arm is modelled in full.** A `people.diaspora_handle` whose
  domain is not a legal URI host makes Faraday raise `URI::InvalidURIError`
  before the adapter, and `fetch_and_save` converts it to `DiscoveryError`. It
  issues no SQL before raising. The reads preceding it and the terminal are in
  the corpus (4 027 `DiscoveryError` terminals).
* **The success arm is unreachable here, and is DECLARED UNMODELLED — not
  shown absent.** Returning normally needs two live HTTP fetches
  (`discovery.rb:73` `webfinger`, `:84` `hcard`, both `HttpClient.get`; no
  local short circuit in that class), and this JRuby/typhoeus/JFFI stack
  SIGSEGVs on any parseable URL. Measured by this batch, each probe in its own
  systemd unit so an abort names itself: `_c12/probe_parseable.log` /
  `_c11/probe_parseable.log` → **SIGSEGV, unit status 134**;
  `_c11/probe_uri_hostile.log` → `DiscoveryError`, **exit 0, JVM alive**.

**What the policy would gain if that arm became reachable**, measured by this
batch by running the application's own `:save_person_after_webfinger` callback
(`config/initializers/diaspora_federation.rb:59-77`) directly, with no network
— probe `_c12/discovery_gap_probe.rb`, evidence
`_c12/_discovery_gap_evidence.json`:

* **new-person branch: 17 statements, 13 of them data access** —
  `people` by `diaspora_handle` · `pods` by `host` · BEGIN ·
  **INSERT INTO pods** · COMMIT · BEGIN ·
  `SELECT 1 AS one FROM people WHERE guid` ·
  **`SELECT people.diaspora_handle FROM people WHERE guid = ? AND diaspora_handle != ?` (a pluck)** ·
  `SELECT 1 AS one FROM people WHERE diaspora_handle` ·
  **INSERT INTO people** · **INSERT INTO profiles** ·
  `tags INNER JOIN taggings` · COMMIT.
* **existing-person branch: did NOT complete under this batch's fixture.**
  Stated as measured, not inferred: it raised
  `ActiveRecord::RecordInvalid: Validation failed: Specify an owner or a pod,
  not both` — the `owner_xor_pod` validation in `person.rb` — after issuing the
  `people` read, the `profiles` read, **INSERT INTO profiles**, the
  `tags INNER JOIN taggings` read and both uniqueness probes, then ROLLBACK.
  The adversary's fixture completed this branch; the statement FAMILIES agree.

So the undescribed arm touches three tables the policy has no note for
(`pods`, `tags`, `taggings`), two predicate columns it has none for
(`people.guid`, `people.diaspora_handle`) and three writes. Extraction, or a
future rig with a working HTTP adapter, should union that set in.

**Why the statements are not simply added to the policy.** Every note in this
project is verified against a real ENDPOINT statement — that is what
`mock_note_check` and `note_fidelity_audit` do. These have real counterparts
only as scenario-body probes and can never have an endpoint counterpart here.
Asserting them would create ~13 permanently unverifiable note families, each
needing a waiver argued only from code reading — the mechanism DISCIPLINE §14
forbids — and would assert write semantics (T-t/T-v dirty state) that no run
could ever exercise. The corpus does not claim outcomes it cannot exhibit;
that is the same rule that removed `_k2_not_found` in cycle 11.

**Correction to a claim this batch made in cycle 12, and to its first
correction.** The cycle-12 write-up said the exclusion was recorded "in the
wall note in the corpus itself". It is not — there is no wall note. My first
explanation of why was itself wrong; the coordinator's full census caught it,
and both censuses are reproduced here over whole corpora, no sampling:

```
CURRENT (cycle 12):  26 528 dumps · 13 distinct targets
                     discovery `symbolic_call` events        0
                     discovery bare `call` trace events  4 657  (carry no note by kind)
ARCHIVE cycle 11:    26 931 dumps · 15 distinct targets
                     discovery `symbolic_call` events    7 972  — ALL 7 972 NOTED
                     discovery bare `call` trace events  9 142
```

(For accuracy: the cycle-11 decision variable is `*_discovery_failed`;
`discovery_returns` is the name of the rig's lambda and appears in zero dumps
of either corpus.)

My first census omitted the `event["type"] == "symbolic_call"` filter, counted
the 4 657 bare `call` trace events, and I mis-diagnosed that as the
`Thread.current[:concolic_pending_note]` line being a no-op. **That inference is
withdrawn**: cycle 11's 7 972 noted `symbolic_call` events are direct evidence
that the note channel works. The *count* of 4 657 was correct — the
`fetch_and_save` `call` trace event does survive in cycle 12, in 4 657 dumps;
it simply always raises, so it never becomes a `symbolic_call`. The distinction
that matters is **`symbolic_call` (0 here, can carry a note) versus `call`
(4 657, cannot)**, and `noteless_call_audit` passes because `fetch_and_save` is
a documented wall.

What was right, and is the part that mattered: **no wall note exists in the
current corpus**, so under (b) the exclusion had to be declared in the
artifact. A wall note is deliberately NOT re-added — a non-SQL note over a body
now known to issue 13 statements is the H3 / T-a violation and would be a worse
misstatement than silence. `targets.rb` is not modified: the corpus and the
file that produced it stay as the closure artifacts. **The declaration lives in
the artifact**: the header of `queries_from_runs/comments_index.sql`,
maintained canonically at `POLICY_HEADER.txt` and re-applied by every
extraction.

### T-t / T-v — wording for the matrix footnote

> The endpoint's only write site is `:save_person_after_webfinger` on
> `Discovery#fetch_and_save`'s success arm; that arm is UNREACHABLE in this
> environment (two live HTTP fetches) and is DECLARED UNMODELLED, so no write
> is asserted and none is exercised. If the arm is ever modelled — resolution
> (a) — this endpoint gains three writes (`INSERT people`, `INSERT profiles`,
> `UPDATE profiles`) and T-t/T-v become live here.

## 4. M-18 — ground truth is measured outside the app's executor

The rigs dispatch through `ActionController::TestCase#process`, which never
runs `ActionDispatch::Executor`; Rails installs AR's query cache as an executor
hook. `ActionDispatch::Executor` IS in this app's middleware stack, so a real
Rack request caches and the rig does not.

Measured batch-locally without touching the shared probe: `_c12/exec_wrap.rb`
defines `ci_wrap { }` — `Rails.application.executor.wrap` when `CI_EXECUTOR=1`,
a plain `yield` otherwise; each of the seven manifests requires it and wraps its
single dispatch expression. The same file produces both ground truths; wrapped
outputs are `concrete_run_<m>_exec.json` and are excluded from
`merge_concrete_runs.py`.

| manifest | plain | executor-wrapped | delta |
|---|---|---|---|
| anon | 16 | 11 | −5 |
| auth | 44 | 31 | −13 |
| mobile | 22 | 22 | 0 |
| r3 | 49 | 40 | −9 |
| r4 | 52 | 45 | −7 |
| r5 | 40 | 30 | −10 |
| r6 | 78 | 68 | −10 |
| **total** | **301** | **247** | **−54 (−17.9 %)** |

`mobile` is unchanged: it builds `#message` only, so it reads `mentions` once
per comment where json reads it twice — the format with no repeated statement
has nothing to cache.

**No shape disappears; only multiplicities fall.** 16 distinct shapes both
ways, per manifest and corpus-wide, 0 lost and 0 gained. The five shapes whose
counts change are all repeated per-ROW reads: `mentions` 81→48,
`people.id = @` 30→23, `profiles.person_id = @` 29→22,
`people.id IN (@,@)` 24→20, `profiles.person_id IN (@,@)` 22→19. **M-18
touches the policy's counts, not its content** — the extracted set of statement
shapes and predicate columns is identical under either ground truth.

**`_multiset_counts.py` passes against both**: the wrapped ground truth gives
0 under / 0 over in all 8 scopes (41 requests, count-exact 35/41); the plain
ground truth gives 0 under / 0 over in all 66 scopes (731 requests, 500/731).

**Carry this sentence forward: the count matrix cannot see M-18 on this
endpoint.** Every shape whose multiplicity changes under caching is a per-ROW
shape, which the check excludes in BOTH directions by design (the
one-representative limit and the ROWSCALE rule); the per-REQUEST shapes — the
post finders, the principal fetch, `comments`, `people.owner_id` — all have
multiplicity 1, which caching cannot change. So the verdict is identical under
either ground truth **here**. That is a fact about comments_index, not a general
result: an endpoint whose per-REQUEST shapes repeat will see its ground truth
move, and its verdict may move with it.

## 4b. Closure evidence

**Adversary round 10 — zero wins across 37 real requests.** All four attacks on
the M-17 resolution were refuted with positive evidence, not silence:

1. **A route to `fetch_and_save` returning** — refuted. `validate_diaspora_id`
   evaluates `webfinger` unconditionally, and BOTH the primary URL and the
   legacy host-meta fallback are `HttpClient.get`; all ten wall requests failed
   at the *legacy* URL, which proves the primary was already tried and rescued.
   `find_or_fetch_by_identifier`'s fast path is real but is not on
   `fix_profile`'s route.
2. **A second route to `pods` / `tags` / `taggings`** — refuted. 37 requests,
   293 frame-tagged statements, **zero** naming those tables, including three
   whose author sits on a real `pods` row and two with `#hashtag` text.
3. **Collateral blast radius of the M-17 deletion** — refuted. A full
   cycle-11-vs-cycle-12 differential on five axes (nodes, PC variables,
   statement shapes, call pairs, declarations) shows **every lost item names a
   `*_discovery_failed` variable, 0 non-discovery losses**.
4. **Statements before the raise** — 16 EXACT / 0 MISSING, with both
   format-specific wall orders reproduced.

**The coordinator's independent eleven-check sweep on cycle 12: fully green** —
identity symbolicity, statement note lint, bind resolution, skipped PCs,
pc_visibility, empty relation emission, noteless call, cardinality consistency
(**123 974 pairs judged / 52 282 explained**, matching this batch's numbers
exactly), boundary declaration, rig-crash census, audit self-test.

## 4c. Extraction

Driver: `results3/queries_from_runs/_extract_comments_index_streaming.py`
(ported from the conversations/posts_show streaming extractor; `src/`
untouched). Output `results3/queries_from_runs/comments_index.sql`,
summary `_summary_comments_index.json`.

```
corpus  : 26 528 dumps, 26 528 runs loaded, 0 errors
queries : 413 594 raw -> 79 distinct -> 0 subsumed -> 79 VIEWS
base tables selected: profiles 32 · people 30 · mentions 6 · posts 5 · comments 4 · users 1
53 of the 79 views carry an unresolved-placeholder NOTE (8 distinct placeholders,
all `_row2_*` second-representative columns plus the principal's person_id)
```

`POLICY_HEADER.txt` is re-applied verbatim at the top, followed by an
EXTRACTION PROVENANCE block; the STALE BODY banner is removed because the body
is now current. The declared-gap tables (`pods`, `tags`, `taggings`) and the
three writes appear **only in the header prose** — the policy body contains
zero occurrences, which is the intended state under resolution (b).

**The patched fold is mandatory here, and this is measured, not inherited.**
`skipped_pcs_audit` on the cycle-12 corpus:

```
vanilla src/ fold          parsed 575 447 | DROPPED 73 461  -> RED
variant_d assoc_fold       parsed 575 447 | dropped      0  -> pass
```

The dropped shape is `(VAR == VAR(_))` — every StringVal equality branch, i.e.
the `users.language == 'pl' / 'xx'` locale arms and the `posts.type == 'Photo'`
STI arm. Extracting with the vanilla fold would have silently dropped 73 461
recorded constraints from the policy. The extractor therefore installs
`_experiment/variant_d/assoc_fold` exactly as `skipped_pcs_audit --patched`
does, and says so in the emitted header. **Flagging for the coordinator: the
conversations_index extractor does not install it** (RUNBOOK gap 3 — the
patches are still not upstreamed into `src/`), so that closed endpoint's policy
may be missing the same class of constraint; worth a check before its numbers
are relied on.

## 5. Known limits, declared

1. **The discovery-success arm** — §3. The single place the policy stops.
2. **The one-representative `SampledList` ceiling.** Bulk preloads bind at most
   2 distinct keys in the corpus (`IN (?, ?)`); real fixtures with 3–4 distinct
   authors or mentions bind 3–4. Attacked twice (R8 H04, R9 N9-1/N9-2) and not
   broken: no new table, predicate column or branch appears at 3+ keys, on the
   author tree or the mention tree. The arity is printed as an IN-ARITY census
   on every multiset run.
3. **Per-ROW statement multiplicity** is a designed under-count of the shared
   runtime (one representative row rendered where the app renders N), reported
   as LIMIT/ROWSCALE and never as a defect (DISCIPLINE §14).
4. **The harness's per-uid warden memo** hides the principal `people.owner_id`
   read after the first auth request in a process (ledger row 87, unrepaired).
   Anyone reading auth multisets must use the FIRST auth request of a manifest.
5. **`_VARIANTS` / `VARIANTS`** in `coverage_assumptions.py` and
   `demand_round.py` are copied tuples that attribute a dump by label prefix.
   Measured agreement with `concolic_scenario.name`: 20 879/20 879 when last
   checked; a new scenario would silently go to `unknown`.

## 6. Where the evidence is

`coverage_summary.json` · `AGENT_RUN.md` (cycle-by-cycle derivations) ·
`POLICY_HEADER.txt` (canonical `.sql` header) ·
`targets.rb`, `concolic_targets.rb`, `run_dse.rb`, `coverage_assumptions.py`,
`coverage_report.py`, `completion_config.json`, `assumption_manifest.json` ·
`concrete_manifest_{anon,auth,mobile,r3,r4,r5,r6}.rb` and their
`concrete_run_*.json` (plain) and `concrete_run_*_exec.json` (executor-wrapped) ·
`_multiset_counts.py` · `_c12/` (this cycle's rounds, audits, report and gate
logs, the discovery probes and `_discovery_gap_evidence.json`, the executor
measurements) · `_c11/`, `_c10/` (previous cycles) ·
`adversary/` … `adversary9/` (nine adversary rounds and their reports).
