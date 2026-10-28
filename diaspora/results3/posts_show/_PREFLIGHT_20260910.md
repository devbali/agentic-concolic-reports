# PREFLIGHT — posts_show (2026-09-10, before the completion drive)

Preparation only. **No driving, no `run_dse.rb`, no JRuby slot was taken.**
Heavy jobs under `systemd-run --user --slice=concolic-cov.slice --scope -p
MemoryMax=<N>`, `JAVA_TOOL_OPTIONS` unset. Reference policies not read, still
quarantined. `find`, never `ls`. Every name comparison routed through the
engine's own load path (`coverage_report.canonicalize_ordinals`).

> **FIVE ITEMS ARE PENDING, NOT DONE (P1-P5, §6).** The coordinator froze jobs over ~1 GB
> RSS at 08:58 (memory emergency: 1 GB free, no swap) and killed the sampled
> pass that was measuring them. §1 records what WAS measured — including the
> hard 3 GB result — and §6 states exactly what remains and what it costs.
> Nothing in §2-§4 depends on them, and §5 (the extractor) completed with
> subsumption skipped.

---

## HEADLINE

0. **The extractor is clean**: 121 views from an 8 000-dump dry run, **0
   unparseable notes**, 0 rotation residue. §5.
1. **This endpoint's §16b state cannot be measured at 3 GB.** The full-corpus
   pass was **OOM-killed 8 min into the LOAD**, before Z3 ran at all. **The
   load, not the solver, is the 3 GB blocker** — so "does the drive agent need
   solver batching" is not yet the binding question. §1, §6.
2. **The named defect is confirmed and is the SAME one as people_stream's**,
   with the same evidence at the same two source lines and the same app site
   (`app/models/person.rb:351`, `person_path(self)`). Four instances here
   against people_stream's one. §2.
3. **Runner and boundary are ready**, with one drift found in both endpoints
   and repaired. §3.
4. **The seeder census is the story of this endpoint: 257 dimensions, of which
   the existing 96 357-dump corpus varies 49.** 84 of 84 `count` dimensions and
   56 of 56 emptyable-string dimensions have never been moved. §4.
5. The extractor is upgraded out of its 2026-08-19 state (it used the base
   `RunTransformer` and had no E11 check); the E11 verdict on this corpus is in
   §5.

---

## 1. Current state under §16b — MEASURED: it does not fit 3 GB

### The full-corpus pass, at 3 GB, on the 96 357-dump snapshot

```
unit    pxcov16b.scope, --slice=concolic-cov.slice, MemoryMax=3G
        VERIFIED IN THE CGROUP: .../pxcov16b.scope/memory.max = 3221225472
env     JAVA_TOOL_OPTIONS unset, SKIP_COMPLETION=1
result  systemd: "pxcov16b.scope: A process of this unit has been killed by
        the OOM killer" / "Failed with result 'oom-kill'", 08:29:41,
        after 5 min 02 s of CPU and ~8 min wall
RSS at the kill   memory.peak = 3 192 811 520 B = 2.97 GiB — pinned at the cap
stdout            EMPTY. Not one line. The kill landed during the LOAD, before
                  the first print; Z3 never started.
```

Per instruction this was **not retried bigger**. For scale, the §16 pass on
2026-09-10 morning used a 9 GB scope and peaked at **6.7 GB**, so 3 GB was
never going to hold this corpus.

### The load cost, measured (this is the number that matters)

The sampled pass instrumented the load before it was killed:

```
[load]  5000/24000 runs= 5000 RSS= 232MB   20s
[load] 10000/24000 runs=10000 RSS= 609MB   63s
[load] 15000/24000 runs=15000 RSS= 939MB  116s
[load] 20000/24000 runs=20000 RSS=1357MB  177s
loaded 24000 runs (0 unparseable)
[assumptions] declared=543 INERT(never-co-evaluated, not declared)=411
```

≈ **62 KB resident per run** after the flyweight interning (`share_run_objects`
is already in this batch's loader, so this is the LEAN figure), and the growth
is linear. Extrapolated: 96 357 runs ≈ **6.0 GB**, matching the 6.7 GB the §16
pass actually reached. **A §16b pass on the whole corpus needs a ≥ 8 GB scope.**

Budget for a drive agent, from the same measurements:

| corpus | load wall | load RSS |
|---|---|---|
| 24 000 | 3.7 min | 1.5 GB |
| 48 000 | ~7 min | ~3.0 GB |
| 96 357 | ~15 min | ~6.0 GB |

### What the §16b state is NOT yet

**Do not quote the numbers in `coverage_summary.json`.** That file is the §16
(set-level) pass from this morning, preserved as
`_bak_coverage_summary_16set_20260910.json`. Its last-known values:

```
nodes 101 · demand_sets 563 · missing_branches 2 248 (= 561 sets with a gap x MMC 4)
truncated true · solver_lost 0 · tree_complete FALSE · tree_missing 11
coverage_complete false
```

`missing` there is a GROUP COUNT x MMC, never a gap (STATE_HANDOFF correction
5), and on this endpoint it moved 332 → 2 248 in the OPPOSITE direction to the
demand. **No census exists for posts_show under either rule.** Nothing about
its residual should be quoted until §6 is run.

For calibration, the same two-arm measurement on people_stream (which DID fit)
moved demanded 531 → 315, covered 99 → 315 and uncovered 81.4 % → **0.00 %**;
on notifications the demand fell 89.66 % and uncovered went 97.22 % → 58.88 %.
posts_show's 563 demand sets are 33–36 decisions wide, so the foreclosure prune
has the most room here of any endpoint — but that is an EXPECTATION, and this
report does not turn it into a number.

### `tree_missing` — 11 named branch outcomes (from the §16 pass; carried forward)

```
1  (SYM_LEN_..._Relation_records_10_rows != 0)                        :: taken
2  (SYM_LEN_..._Relation_records_8_rows  != 0)                        :: taken
3  (SYM_LEN_..._Relation_records_7_rows  != 0)                        :: taken
4  (SYM_LEN_..._Relation_records_likes_de8fde22_rows != 0)            :: not_taken
5  (..._ActsAsApi__Collection_as_api_response_1_row_guid != StringVal('')) :: taken
6  (..._as_api_response_2_row_guid != StringVal(''))                  :: taken
7  (..._as_api_response_3_row_guid != StringVal(''))                  :: taken
8  (..._as_api_response_4_row_guid != StringVal(''))                  :: taken
9  (..._as_api_response_2_row_text_has_mention == True)               :: taken
10 (..._Relation_evilq_act_public_1_not_found     == True)            :: taken
11 (..._Relation_evilq_act_public_1_text_has_mention == True)         :: taken
```

Entries 5-8 are the named defect (§2) — **four of eleven, and 36 % of the
tree-completeness blocker, closable by ONE declaration**. The tree layer gates
the combination claim outright, so these are the cheapest work on the endpoint
whatever the census turns out to be.

---

## 2. THE NAMED DEFECT — proposed `OneSideUntracked`, with evidence and falsifier

**PROPOSED. NOT INSTALLED.** `coverage_assumptions.py` is untouched. The drive
agent installs it under the owner's overnight authorization *after re-verifying
the differential below itself*.

posts_show declares **no** instance of this. people_stream declares three
(Argument 5, `GUID_TRUE_UNREACHABLE`) and needs a fourth. Here all four are
undeclared.

### The declaration

```python
# --- guid '!=' side untracked-true, per acts_as_api row (proposed 2026-09-10)
GUID_TRUE_UNREACHABLE = (
    "action_dispatch/journey/formatter.rb:40-41 (actionpack 5.2.4.3, stock gem, "
    "unmodified), reached from PostPresenter/CommentPresenter -> "
    "`author.as_api_response(:backbone)` -> Person#as_json "
    "(app/models/person.rb:344-356), whose line 351 is "
    "`url: Rails.application.routes.url_helpers.person_path(self)`. Line 40's "
    "`break if defaults[key].nil? && parameterized_parts[key].present?` breaks the "
    "route-parts loop BEFORE line 41 (the '!=' pair's site) whenever the guid is "
    "non-blank. When the guid IS blank, line 41 does run and `guid.to_s != ''` is "
    "forced False by the value just established. The '!=' pair's True outcome "
    "cannot be produced by any seed: the only path that evaluates it forces it "
    "False, and the alternative path never evaluates it at all. Identical in "
    "mechanism, site and evidence to people_stream's Argument 5."
)
for _n in (1, 2, 3, 4):
    assumptions.append(OneSideUntrackedPathAssumption(
        expr=f"(SYM_RESULT_ActsAsApi__Collection_as_api_response_{_n}_row_guid "
             f"!= StringVal(''))",
        tracked_side="not_taken",
        description="guid!='' can only ever be observed False (framework short-circuit)",
        agent_notes=GUID_TRUE_UNREACHABLE,
    ))
```

### The app code

`actionpack-5.2.4.3/lib/action_dispatch/journey/formatter.rb:38-45`:

```ruby
route.parts.reverse_each do |key|
  break if defaults[key].nil? && parameterized_parts[key].present?   # line 40
  next if parameterized_parts[key].to_s != defaults[key].to_s        # line 41
  break if required_parts.include?(key)
  parameterized_parts.delete(key)
end
```

`app/models/person.rb:344-356`:

```ruby
def as_json( opts = {} )
  json = { id: id, guid: guid, name: name,
           avatar: profile.image_url(:thumb_small),
           handle: diaspora_handle,
           url: Rails.application.routes.url_helpers.person_path(self) }   # line 351
```

### The corpus evidence, through the load path

Event sites, over a stride-8 scan of **12 045 of 96 357 dumps**:

```
16 540  ('blank.rb', 126, 'blank?',            '==')     # line 40's .present?
 9 613  ('formatter.rb', 41, 'block in generate', '!=')   # the '!=' pair's site
```

Two sites only, and they are **byte-identical to the three people_stream
instances already declared** (`blank.rb:126` / `formatter.rb:41`).

Per-run differential:

```
runs 3431   eq=(False, True)  ne=(False,)    # several rows: '==' both ways, '!=' ALWAYS False
runs 1346   eq=(True,)        ne=(False,)    # blank guid  -> line 41 runs, False
runs  529   eq=(False,)       ne=()          # non-blank   -> line 40 BREAKS, '!=' NEVER evaluated
```

**0 of 9 613 evaluations of the `!=` pair are `taken`, in 5 306 runs that
evaluate it.** 529 runs show the other arm — the break — with the `!=` absent
entirely. Both arms of the argument are exhibited by the corpus.

The immediate app site is the same on both endpoints: the event stream shows
`app/models/person.rb:350 as_json` immediately before the two path conditions,
on every one of the four `as_api_response_N` instances.

### The falsifier — and it is already built

Any run recording `..._as_api_response_N_row_guid != StringVal('')` as **taken**
refutes it. `posts_show/_tree_root.py` (ported in §4) generates exactly that
experiment from a real dump's own seeds with only the guid dimension set
non-empty. **Run those seeds before installing.** Driving even one of the four
would close a tree branch with nothing declared, which is strictly better.

Code-level falsifier: the argument rests on `defaults[key].nil?` at line 40. A
route default on `person_path`'s `:id` segment would stop the break and make
the True side reachable.

**Note the tie-in with `_tree_root.py`'s deny-list:** `*_guid` is on the seeder
deny-list (an identity key), so bulk v3 seeding can never drive these four —
the target key is set explicitly by `_tree_root.py`, which is the only tool that
can attempt them.

---

## 3. Runner readiness — `run_dse.rb` and `concolic_targets.rb`

### `concolic_targets.rb` — Rule T re-sync CONFIRMED CLEAN

`diff reports/diaspora/concolic_targets.rb posts_show/concolic_targets.rb` is
**29 lines, all of them one added block** at line 388: the documented
declaration FILTER (`_descend = %i[default_render pluck blocked_people render
render_to_string render_to_body people_from_string build_mentioned_people_json
mark_user_notifications]`). Not one declaration site differs. **P-1 / P-2 /
P-9 / P-10 inherited**; the 2026-09-07 BLOCKER is closed.

The 2026-09-07 second item is also closed and its adjudication is IN the file:
`ActiveRecord::Base#to_param` was declared here and nowhere else. Ruled a WALL
MOCK, not policy-bearing (Rails 5.2's body is `id && id.to_s`, integration.rb:49-52
— no SQL, and `persisted?` is not a declared target anywhere), and moved to this
batch's `targets.rb` (line 651-666, "W3b to_param"), NOT the shared boundary.
Verified present there.

The 2026-09-07 warning that this is a "results2-era port" is stale: the runner
carries the 2026-09-09 demand-port header.

### `run_dse.rb` — all four mechanisms present, ONE DRIFT (fixed, untested)

| mechanism | present | line |
|---|---|---|
| `LABEL_SUFFIX` in the dump label | yes | 396 |
| `dump["concolic_seeds"] = seeds` | yes | 400 |
| `EXTRA_SEEDS_JSON` → worklist roots | yes | 358-363 |
| `SEEDS_ONLY` replay | yes | 361 |
| corpus wipe | **none at all** — no `File.delete` / `rm` of `dump_*.json` anywhere. The people_stream wipe hazard does not exist here. |

Verified in the corpus: **261 of 300 randomly sampled dumps carry a non-empty
`concolic_seeds`** (the shortfall is pre-port dumps).

**DRIFT vs `notifications_index/run_dse.rb` — the same one people_stream had,
repaired identically:** `next if seen_seeds.include?(key)` and `next if
seen_paths.include?(sig)` were unconditional; notifications gates both on
`!ENV["SEEDS_ONLY"]`, and every notifications drive script runs with
`SEEDS_ONLY=1`. Under an unconditional path-dedup a replayed root that walks an
already-seen path writes no dump, so the caller cannot tell whether its seed was
honoured, contradicted, or never evaluated. Both guards are now gated exactly as
notifications gates them; `ruby -c` passes.

> **UNTESTED against JRuby** (this preflight ran no runner). Smoke with a
> 2-seed `SEEDS_ONLY` replay before any bulk drive. The change only LOOSENS
> dedup under `SEEDS_ONLY`; frontier rounds are byte-unchanged.

---

## 4. Seeder readiness

### `_v3_seeds.py` (NEW — this endpoint had no diverse seeder at all)

Port of `notifications_index/_diverse_seeds3.py` (v3.1) with all three repairs
the campaign paid for: universe from `symbolic_vars` (§6.1); the **stride fix**
(§7.3(b)) generalised to an ADAPTIVE stride plus a printed **RARE** list; and
**`SYM_PARAM_*` as a REAL dimension** (§7.5).

**Dry run (`--census --rebuild`), 900 MB scope:**

```
seed universe: 94 bool, 22 len, 84 count, 56 emptyable-string,
               1 request-param, 0 explicit-int = 257 DIMENSIONS
               (scanned 19 272 of 96 357 dumps, stride 5)
  RARE (minted in < 5 scanned dumps — a coarser stride LOSES these): 1
    4x  SYM_RESULT_ActiveRecord__Relation_records_7_row_count
  request param SYM_PARAM_id: corpus domain ['ggggggggggggggg', 'gggggggggggggggg']
                              + runner default '1' + ''
DIMENSION CENSUS: 257 dimensions the v3 seeder varies; the corpus's EXISTING
                  seeds vary 49 of them (64 appear in a seed dict at all)
   bool              36 varied /  94        len              12 varied / 22
   count              0 varied /  84        emptyable-string  0 varied / 56
   request-param      1 varied /   1
```

**THE DIMENSION CENSUS: 257 dimensions; the existing corpus varies 49.**
There was no OLD seeder here — the corpus is base DSE plus rooted demand
rounds. **84 of 84 `count` dimensions and 56 of 56 emptyable-string dimensions
have never been moved**, and 58 of 94 booleans sit at their default in every one
of 96 357 runs. That is the same shape as notifications' "24 of 146", and on
that endpoint it was the seeder, not the app, that was the constraint on tree
completeness.

**The stride fix earns its keep on the first run**: one dimension
(`..._Relation_records_7_row_count`) is minted in **4 of 19 272** scanned dumps
— precisely the class the stride-120 universe lost on notifications, which made
target T5 unreachable BY CONSTRUCTION. Note the family: `records_7` is also the
subject of `tree_missing` #3. **Build the seed universe with `--max-scan` high
enough to keep the RARE list empty, or scan the whole corpus.**

`SYM_PARAM_id`'s corpus domain is `['ggggggggggggggg', 'gggggggggggggggg']` —
15 and 16 characters, i.e. the two sides of run_dse.rb's own
`Length(SYM_PARAM_id) < 16` decision. It is a genuine dimension and it is varied
(it would otherwise have been swallowed by the `_id` deny suffix; `denied()`
exempts declared params explicitly).

### `_demand_root.py` (REPLACED — the old copy carried a known defect)

Old copy archived as `_demand_root.py.pre_20260910`. The port brings the
**many-ordinal fix** (the old copy's `inv.setdefault(canon, ordn)` — "first
ordinal wins" — against a map that is many-to-one BY DESIGN; measured on
notifications before the fix: 13 423 honoured, **6 656 contradicted**), the
**skip-and-count filter** for environmentally unreachable outcomes
(`_UNREACHABLE`, **empty here** — no witness established; the mechanism, the
`_FORCE_OFF` pin and both counts print on every run), `DUMP_LIST`, and the lean
index (keep the PATH, load base seeds lazily — the old copy held every dump's
seed dict, which on 96 357 dumps with v3-sized seeds is several GB and OOMs the
round).

**Dry run** (12 045-dump `DUMP_LIST` subset, 900 MB scope — the full 96 357-dump
index was not run under the memory freeze):

```
missing (blocking): 400
DUMP_LIST ...px_sub12k.txt: 12045 dumps (fixed snapshot)
indexed 12045 dumps, 101 distinct exprs, 79 wanted
auth_html: 0   anon_html: 0   auth_json: 144   anon_json: 0   rooted seed dicts
combinations with no corpus base: 0
combinations SKIPPED as environmentally unreachable (0 witnesses declared): 0
demanded lengths skipped because the base dump never minted that statement: 0
```

It builds roots, translates canonical→ordinal with no untranslatable variable,
and finds a corpus base for every combination. Only `auth_json` produces roots:
the demanded expressions are recorded in that scenario alone.

> **These roots are built from the §16 (set-level) missing list.** §16b will
> shrink that demand — on people_stream it went to zero. **Re-run
> `_demand_root.py` after the §16b pass of §6**, never before.

### `_tree_scan.py` / `_tree_root.py` / `_tree_check.py` (NEW)

Ported, because 11 tree branches are the hard precondition and 4 of them are
the §2 declaration. `_tw/targets.json` is generated from this endpoint's own
`tree_missing`. `wanted_value` was generalised past notifications' two shapes
(`== True`, `== ''`) to cover `!= 0`, `!= StringVal('')`, `> 0`, `== 0` — which
this endpoint needs for entries 1-4; an unhandled shape still EXITS rather than
guessing. The `DISCOVERY` force-off list is empty (notifications' entry is its
own libcurl witness). `_tree_scan.py` has not been run here — it is a
full-corpus scan and is queued with §6.

---

## 5. Extractor readiness

`queries_from_runs/_extract_posts_show_streaming.py` was dated **2026-08-19**.
Superseded; the old header is archived as `.pre_20260910` with the reasons. It
used the base `RunTransformer` (so every `assoc_*` bind stayed an unresolved
placeholder — E1), collected `errors` and **never failed on unparseable notes**
(E11), did not exclude `broadened-*` from `can_subsume`, emitted no
POLICY_HEADER or provenance block, and reported `subsume_ran` as a bool.

Now in line with `_extract_comments_index_streaming.py`: **E1
`AssocFoldingTransformer`**, the **E11 RED check**, the broadened-bind NOTE
lines, the `broadened-*` `can_subsume` exclusion, an optional POLICY_HEADER with
a loud placeholder, `DUMP_SAMPLE` for dry runs, `SKIP_SUBSUME`, and the
**tri-state subsumption tally** (`state` True = ran / False = attempted and
FAILED / None = never attempted; per-view `subsumed(true)` /
`not-subsumed(false)` / `UNDECIDED(null)`, **null never folded into false** — an
undecided view is KEPT and counted on its own line).

It also carries the new **R1 rotation-residue RED** described in
`people_stream/_PREFLIGHT_20260910.md` §5.

### A parser defect was found (on people_stream) and fixed — posts_show is UNAFFECTED

`_BARE_DATETIME_RE` in `src/queries_from_runs/transform.py` did not include `(`
or `,` in its boundaries, so a bare Ruby `Time#to_s` inside a list —
`"posts"."type" IN (2026-09-09 09:25:30 +0000, 'StatusMessage')` — stayed
unquoted, sqlglot raised `ParseError`, `_primary_table` returned `None` and the
statement was silently DROPPED as an "unparseable note" (1 728 times on
people_stream). Fixed by adding `(` and `,` to both boundaries; the datetime
pattern is unchanged. `src/queries_from_runs` tests: **38 passed**.

Differential over every corpus (old vs new regex applied to every note):

```
posts_show   8 030 / 96 357 dumps   422 680 notes   0 notes render differently
```

and likewise 0 for comments_index, conversations_index, people_show and
notifications_index. **The fix touches people_stream only.** No re-extraction is
forced here or anywhere else.

### Dry run

`DUMP_SAMPLE=8000` (random, seeded — never a sorted prefix, DISCIPLINE 14), 1 GB
scope, `SKIP_SUBSUME=1`, 8 min 19 s CPU:

```
corpus POPULATION: 96357 dump files
SAMPLED EXTRACTION: 8000 of that population, seed=20260901 — a DRY RUN
  8000/8000 dumps, 121 distinct
subsumption: state=None (True=ran, False=attempted and FAILED, None=never attempted)
             over 85 eligible of 121 distinct
   verdict tally  subsumed(true)=0  not-subsumed(false)=85  UNDECIDED(null)=0
*** NO POLICY_HEADER.txt ... the emitted .sql carries a placeholder ***
posts_show: 121 queries (121 distinct, 0 subsumed) from 8000/8000 dumps
```

| | value |
|---|---|
| **views** (`n_queries_final`) | **121** (328 453 raw → 121 distinct) |
| **unparseable notes** | **0 — the E11 RED does NOT fire on this corpus** |
| rotation-residue RED (R1) | **does not fire** — 0 views carry `bind-rotation-repaired` |
| placeholders | 11 families |
| flags | `type-mismatched-join` 8 224, `unscoped` 3 998 |
| subsumption | **PENDING** — skipped under the memory freeze; 85 of 121 eligible |

**posts_show is clean of both extraction defects.** No statement was dropped,
and the bind-rotation render bug that dominates people_stream does not appear
here at all. The E11 check is now installed and silent, which is the outcome you
want from a check.

`skipped_pc_shapes` totals 240 k over 40+ shapes, led by
`(len(..._records_N_rows) != N)` 43 389, `(..._find_by_N_not_found == True)`
22 803 and `(assoc_*_has_mention / _nsfw == True)`. **This is normal residue,
not a defect**: the CLOSED endpoints carry the same shapes at the same or larger
volume — comments_index 893 882 skipped over 52 shapes, people_show 405 945 over
44, both led by the identical `len(...) != N` / `_not_found == True` families.
They are mock-internal decisions with no SQL predicate; they cost WHERE
precision, not statements.

**The blockaid subsumption harness is the memory cost, not the extraction.**
The dump loop runs at **< 100 MB RSS**; the earlier attempt was OOM-killed in a
2 GB scope *after* the loop finished, inside the JVM, which runs in the driver's
own cgroup. Budget it separately and give it its own scope. Unlike people_stream
(1 of 1248 eligible), **85 of 121 views here are subsumption-eligible**, so the
check will do real work and its result is worth having.

---

## 6. PENDING — what the memory freeze deferred, and what it costs

| # | job | why it is pending | cost, from the measurements above |
|---|---|---|---|
| P1 | **§16b coverage pass, full 96 357-dump corpus** | needs ≥ 8 GB; 3 GB OOMs during the LOAD | ~15 min load + the Z3 phase (see P3) |
| P2 | **exact census** (`posts_show/_exact_enum.py`, ported and ready), `FORECLOSURE=1,0` in ONE process, `--verify 6` | same load | one load, both arms |
| P3 | **the §16b Z3 cost, and therefore the solver-batching question** | the sampled pass that was measuring it was killed | see below |
| P4 | **extractor subsumption** (drop `SKIP_SUBSUME`) | the blockaid JVM OOM-killed a 2 GB scope | give it its own ≥ 4 GB scope; 85 of 121 views eligible |
| P5 | **`_tree_scan.py`** over the full corpus (it builds the bases `_tree_root.py` needs for the 11 branches) | full-corpus scan | ~1 pass, low RSS; shardable with `--shards/--shard` |

Use the snapshot list already written:
`posts_show/_snapshot_20260910_preflight.txt` (96 357 paths, `find`-generated),
via `DUMP_LIST=` — the glob is not reproducible while anything writes here.

### The cost warning, stated as honestly as the evidence allows

The §16 pass on the full corpus cost **4 481 s of Z3 over 563 demand sets**
(11 min load, 9 GB scope, 6.7 GB peak). Three engine-side mitigations are
already inside that 4 481 s (profiles deduplicated to distinct outcome
profiles, blocking clauses deduplicated to distinct cubes, profiles indexed by
evaluation set). Batching the per-witness solver calls is the next one.

**Whether the drive agent needs it is not yet decided, and I will not guess a
number.** What is known:

* §16b adds a foreclosure pass. On notifications' 1 010 sets the census went
  29 s → 83 s (≈ 2.9x) *for the census*; the checker's own pass has the same
  extra work.
* §16b also PRUNES: each of posts_show's 563 demand sets is 33-36 decisions
  wide and costs `2 x width` solver calls per witness, and foreclosure removes
  demanded assignments inside exactly those wide sets (on notifications the wide
  sets' mass fell 97.6 %). Fewer demanded leaves means fewer witnesses to find.
* The two pull in opposite directions and only a measurement settles it.

**The measurement is one run**: P1 with `SKIP_COMPLETION=1` prints
`[coverage] phase done in Ns`. If that N is again in the thousands, batching is
the next engine change; if the prune dominates, it is not. Until then, the
operational advice is narrower and certain: **the drive agent cannot iterate at
3 GB at all**, because the load alone does not fit. Either it gets an ≥ 8 GB
scope, or it works on a `DUMP_LIST` subset and says so on every number.

One more lever worth measuring before asking for batching: DISCIPLINE §12's
"a dump count is not a corpus" — conversations_index carried 41 753 exact
duplicates of 60 078 dumps, and deduplicating took its pass from an OOM kill to
a 673 MB peak. No duplicate census exists for posts_show's 96 357 dumps. That
is a cheap streaming scan and it may move the load cost more than any solver
change.

---

## 7. What would block a drive agent

1. **A ≥ 8 GB scope, or the endpoint cannot be measured.** This is the first
   blocker and it is environmental, not analytical.
2. **The four guid branches (§2) are closable by one declaration or by
   `_tree_root.py` seeds.** Try the seeds first. That is 4 of 11
   tree-completeness blockers.
3. **Do not rebuild demand roots from the current `coverage_summary.json`** —
   it is the §16 file. Re-run `_demand_root.py` after P1.
4. **Build the v3 seed universe with a fine enough stride** (the RARE list must
   come back empty) or a rare dimension is unreachable by construction — the
   notifications T5 failure, and this endpoint already shows one such dimension
   at 4 mints in 19 272 dumps.
5. **Smoke the `SEEDS_ONLY` dedup fix** (§3) with a 2-seed replay before any
   bulk drive.
6. `posts_show/POLICY_HEADER.txt` does not exist. Closure needs it (M-17
   resolution (b)); it does not block the drive.

## 8. Files written by this preflight

```
posts_show/_exact_enum.py               NEW (ported; verifier pin-scope fixed)
posts_show/_v3_seeds.py                 NEW
posts_show/_demand_root.py              REPLACED (old -> .pre_20260910)
posts_show/_tree_scan.py                NEW
posts_show/_tree_root.py                NEW
posts_show/_tree_check.py               NEW
posts_show/_tw/targets.json             NEW (11 targets, from its tree_missing)
posts_show/_snapshot_20260910_preflight.txt   NEW (96 357-path fixed snapshot)
posts_show/coverage_report.py           + foreclosure fields & printed lines,
                                          DUMP_LIST / DUMP_SAMPLE / SUMMARY_OUT,
                                          per-5000 load heartbeat, `del raw`
posts_show/run_dse.rb                   + SEEDS_ONLY dedup gate (UNTESTED)
posts_show/_bak_coverage_summary_16set_20260910.json   the §16 baseline
queries_from_runs/_extract_posts_show_streaming.py     UPGRADED (E1 + E11 + tally)
queries_from_runs/_extract_posts_show_streaming.py.pre_20260910   what it replaced
src/queries_from_runs/transform.py      _BARE_DATETIME_RE boundaries (only src/ edit)
```

`coverage_assumptions.py` **untouched.** `coverage_summary.json` **untouched**
(the OOM-killed pass wrote nothing). `src/concolic_engine` **untouched.** No
reference policy read. No JRuby launched.
