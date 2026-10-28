# PREFLIGHT — people_stream (2026-09-10, before the completion drive)

Preparation only. **No driving, no `run_dse.rb`, no JRuby slot was taken.**
Every heavy job ran under
`systemd-run --user --slice=concolic-cov.slice --scope -p MemoryMax=3G` with
`JAVA_TOOL_OPTIONS` unset. Reference policies were not read and stay
quarantined. `find`, never `ls`. Every name comparison below is routed through
the engine's own load path (`coverage_report.canonicalize_ordinals`).

> **The 08:58 memory freeze did NOT defer anything on this endpoint.** Every
> measurement below completed before it, and the heaviest job was the coverage
> pass at **170 MB peak RSS** — three orders under the 3 GB cap. The extractor
> dry run peaked under 100 MB and never launched the blockaid JVM (only 1 of
> 1248 views is subsumption-eligible, so the check was never attempted). Nothing
> here is PENDING. posts_show's two pending items are in its own report.

---

## HEADLINE

**people_stream's combination residual is GONE under §16b. `missing = 0`.**
The endpoint is **one branch outcome** away from `complete`, and that branch is
the named defect below: a fourth instance of a `OneSideUntracked` declaration
the endpoint already carries three times, for the same framework short-circuit,
at the same two source lines.

| | §16 (set-level, this morning) | **§16b (foreclosure-aware, measured here)** |
|---|---|---|
| runs / nodes | 755 / 29 | **755 / 29** |
| demand sets | 27 | **27** |
| **demanded** | 531 | **315** (−40.7 %) |
| **covered** | 99 | **315** (+218 %) |
| **uncovered** | 432 (81.4 %) | **0 (0.00 %)** |
| engine `MISSING` / `BLOCKING` | 96 / 96 | **0 / 0** |
| foreclosures applied | 0 | **135** pairs (0 ignored), 99 leaf groups |
| `tree_complete` | false | **false — 1 branch** |
| `truncated` / `solver_lost` | false / 0 | **false / 0** |
| `unevaluable_exprs` | [] | **[]** |
| wall / peak RSS | — | **0.9 s coverage / 170 MB** |

---

## 1. Current state under §16b — the pass, and its own printed lines

`PYTHONPATH=src SKIP_COMPLETION=1 python3 people_stream/coverage_report.py`,
3 GB scope (verified in the cgroup: `memory.max = 3221225472`):

```
loaded 755 runs (0 unparseable)
[assumptions] declared=47 INERT(never-co-evaluated, not declared)=30
COMPLETE=False;NODES=29;MISSING=0;BLOCKING=0;PCS=6021
GENUINE=True;TRUNCATED=False;SOLVER_LOST=0;UNEVALUABLE=[]
DEMAND_SETS=27;TREE_COMPLETE=False;TREE_MISSING=1;FORECLOSURES=135;
  FORECL_IGNORED=0;FORECL_PROVISIONAL=True
   TREE-MISSING (SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid
                 != StringVal('')) :: taken
peak RSS 170 MB
dump_errors={'ActionController::UnknownFormat': 24}
```

`COMPLETE=False` is caused by `TREE_COMPLETE=False` alone. `MISSING=0` means
every demanded leaf of every demand set is observed. `FORECL_PROVISIONAL=True`
is the correct §16b reading: while `tree_missing` is non-empty the foreclosures
— and therefore the `MISSING=0` — are **conditional**, exactly as DISCIPLINE
§16b says. `MISSING=0` is not yet a claim; it becomes one the moment the tree
layer closes.

The exact census (`people_stream/_exact_enum.py`, a port of notifications'
enumerator, both arms in ONE process so the delta is exact, `--verify 8` →
**8/8 OK in both arms**, `bounded_cliques=0` so every figure is exact and not a
lower bound):

```
FORECLOSURE=1: sets=27 satisfiable=315 covered=315 remaining=0 wide(>=13)=0
FORECLOSURE=0: sets=27 satisfiable=531 covered=99  remaining=432 wide(>=13)=0
```

Top foreclosure gates (135 applied pairs over 16 gates):

```
  24  (..._as_api_response_1_row_guid == '')                 :: not_taken
  16  (..._Core__ClassMethods_find_by_1_not_found == True)   :: taken
   8  (SYM_PERSON_via_user_closed_account == True)           :: taken
   8  (..._find_by_1_closed_account == True)                 :: taken
   8  (..._FinderMethods_first_1_{closed_account,not_found}) :: taken
   8  x5  (..._records_posts_<alias>_row_comments_count == 0):: taken
```

`dump_errors` is the declared wall W1 (`_WALLS.md`): `format.all` →
`redirect_to` is a declared target, so the arm ends in
`ActionController::UnknownFormat`. 24 of 755 dumps, up from 6 in the first
corpus; the wall's policy impact is unchanged (a redirect issues no query).

### A verifier defect found and fixed (in the batch tool, not the engine)

The first `--verify 6` reported **1 MISMATCH** (`clique#24 width=2: leaves=3
allsat=2 factorised=1`). Diagnosed exactly, and it is NOT a census error:

* set #24 is `{ SYM_PERSON_via_user_guid == '' , ... != StringVal('') }`, and
  the `!=` member is **pinned** `not_taken` by Argument 5;
* the checker pins over the WHOLE demand set — `coverage.py`: `for expr in
  group: if expr in pinned: fixed.append(_outcome_constraint(...))` — including
  a member the prefix foreclosed away;
* the verifier applied the pin only to the leaf's SURVIVING members, so it
  counted a leaf (`guid == ''` False, alone) that lives entirely on the
  untracked side and that the checker never demands.

The verifier now uses the checker's pin scope. Re-run: **8/8 OK, both arms**,
and the census still agrees with the engine (`remaining=0` ↔ `MISSING=0`). The
same edge exists in `notifications_index/_exact_enum.py`; its 6/6 sample simply
never drew a set with a pinned, foreclosed member. Reported, not edited —
that file belongs to another agent.

---

## 2. THE NAMED DEFECT — proposed `OneSideUntracked`, with evidence and falsifier

**PROPOSED. NOT INSTALLED.** `coverage_assumptions.py` is untouched. The drive
agent installs it under the owner's overnight authorization *after it has
re-verified the two measurements below itself*.

### The declaration

```python
# --- Argument 5, FOURTH instance (proposed 2026-09-10) -------------------
# The json-render instance of the same framework short-circuit E/I/L already
# carry. `A4` below is the guid of the row acts_as_api serialises.
A4 = "(SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid != StringVal(''))"
assumptions.append(OneSideUntrackedPathAssumption(
    expr=A4,
    tracked_side="not_taken",
    description="guid!='' can only ever be observed False (framework short-circuit)",
    agent_notes=GUID_TRUE_UNREACHABLE + (
        " FOURTH INSTANCE (2026-09-10): reached not from stream's `format.all "
        "{ redirect_to person_path(@person) }` but from the `format.json` arm, "
        "via CommentPresenter#as_json -> `@comment.author.as_api_response(:backbone)` "
        "-> Person#as_json (app/models/person.rb:344-356), whose line 351 is "
        "`url: Rails.application.routes.url_helpers.person_path(self)`. SAME route "
        "helper, SAME two actionpack lines, SAME outcome."),
))
```

`GUID_TRUE_UNREACHABLE` needs one word widened — it currently says "reached via
stream's `format.all { redirect_to person_path(@person) }`", and the fourth
instance is reached via `Person#as_json`'s `person_path(self)`. The mechanism it
describes is unchanged.

### Why it is justified EXACTLY as its three siblings are

The argument is `action_dispatch/journey/formatter.rb:38-45` (actionpack
5.2.4.3, stock gem):

```ruby
route.parts.reverse_each do |key|
  break if defaults[key].nil? && parameterized_parts[key].present?   # line 40
  next if parameterized_parts[key].to_s != defaults[key].to_s        # line 41
```

Line 40 BREAKS the loop when the guid is non-blank, so line 41 — the `!=`
pair's site — never runs on that path. When the guid IS blank, line 41 does run
and `guid.to_s != ''` is forced False by the value just established. The True
outcome has no producing path.

**The sites are byte-identical across all four instances**, measured over the
corpus through the load path:

| expression family | `== ''` site | `!= StringVal('')` site | `!=` observed |
|---|---|---|---|
| `SYM_PERSON_via_user_guid` (E, declared) | `blank.rb:126 blank?` | `formatter.rb:41 block in generate` | False only |
| `..._find_by_1_guid` (I, declared) | same | same | False only |
| `..._first_1_guid` (L, declared) | same | same | False only |
| **`..._as_api_response_1_row_guid` (PROPOSED)** | **same** | **same** | **False only** |

### The ground-truth differential (all 755 dumps, not a sample)

```
eq=(False,)  ne=()        runs=224   # guid non-blank -> line 40 breaks, `!=` NEVER evaluated
eq=(True,)   ne=(False,)  runs=224   # guid blank     -> line 41 runs, `!=` always False
```

224 of 224 and 224 of 224. The True side is produced by neither arm. This is
also what the engine inferred for itself: `(..._row_guid == '') :: not_taken`
is the **top foreclosure gate** on this endpoint, 24 pairs.

### The falsifier — and it is already built

A run in which `..._as_api_response_1_row_guid != StringVal('')` is recorded
**taken** refutes the declaration. `people_stream/_tree_root.py` (ported here,
§4) has already built that experiment: **5 rooted seeds** (2 `anon_json`,
3 `auth_json`) which are a real dump's own seeds with that one dimension set to
a non-empty guid — `_treeR_t01_anon_json.json`, `_treeR_t01_auth_json.json`.

**The drive agent should run those 5 seeds BEFORE installing the declaration.**
If the branch is driven, `tree_missing` goes to 0 and the endpoint closes with
nothing declared, which is strictly the better outcome. If all 5 come back with
the `!=` unevaluated (the line-40 break) or False, that is the declaration's
evidence, measured on this corpus by the agent that installs it.

A code-level falsifier for completeness: the argument rests on
`defaults[key].nil?` at line 40. If the `person_path` route ever acquired a
default for its `:id` segment, line 40 would stop breaking and the True side
would become reachable.

---

## 3. Runner readiness — `run_dse.rb` and `concolic_targets.rb`

### `concolic_targets.rb` — Rule T re-sync CONFIRMED CLEAN

`diff reports/diaspora/concolic_targets.rb people_stream/concolic_targets.rb`
is **19 lines, all of them one added block** at line 388: the documented
declaration FILTER (`_descend = %i[default_render pluck blocked_people render
render_to_string render_to_body post_ids attach_user_likes]` wrapping
`declare_target`). Not one declaration site differs. The file is a verbatim
copy of the shared boundary plus the filter, exactly as the 2026-09-07
`_PREFLIGHT` demanded and the 2026-09-09 re-sync recorded. **P-1 / P-2 / P-9 /
P-10 are inherited.** The 2026-09-07 BLOCKER is closed.

### `run_dse.rb` — all four mechanisms present, ONE DRIFT (fixed, untested)

| mechanism | present | line |
|---|---|---|
| `LABEL_SUFFIX` in the dump label | yes | 480 |
| `dump["concolic_seeds"] = seeds` | yes | 484 |
| `EXTRA_SEEDS_JSON` → worklist roots | yes | 442-447 |
| `SEEDS_ONLY` replay | yes | 445 |
| corpus not wiped when seeding | yes | 553-555 (`KEEP_DUMPS=0 && !EXTRA_SEEDS_JSON`) |

Verified in the corpus, not just in the source: **296 of 300 randomly sampled
dumps carry a non-empty `concolic_seeds`.**

**DRIFT vs `notifications_index/run_dse.rb` — found and repaired:**

```
notifications:  unless ENV["SEEDS_ONLY"] ... seen_states dedup ... end
                next if !ENV["SEEDS_ONLY"] && seen_paths.include?(sig)
people_stream:  next if seen_seeds.include?(key)          <-- unconditional
                next if seen_paths.include?(sig)          <-- unconditional
```

Every notifications drive script (`_chunk_drive.sh`, `_tree_drive.sh`,
`_diverse_drive.sh`) runs with `SEEDS_ONLY=1`. Under an unconditional
path-dedup a replayed root that walks an already-seen path writes **no dump**,
so the caller cannot tell whether its seed was honoured, contradicted, or never
evaluated — which is the entire evidence a rooted round exists to produce. Both
guards are now gated on `SEEDS_ONLY` exactly as notifications gates them;
`ruby -c` passes.

> **UNTESTED against JRuby** (this preflight ran no runner). Smoke it with a
> 2-seed `SEEDS_ONLY` replay and check that 2 dumps appear, before any bulk
> drive. The change only LOOSENS dedup under `SEEDS_ONLY`; frontier rounds are
> byte-unchanged.

---

## 4. Seeder readiness

### `_v3_seeds.py` (NEW — this endpoint had no diverse seeder at all)

Port of `notifications_index/_diverse_seeds3.py` (v3.1) carrying all three
repairs the campaign paid for:

* **universe from `symbolic_vars`**, not `concolic_seeds` (§6.1);
* **the stride fix** (§7.3(b)) generalised: the stride ADAPTS (`--max-scan`,
  default 20 000) instead of being a constant, and the run prints a **RARE**
  list of dimensions minted in fewer than 5 scanned dumps — the class the
  stride-120 universe lost. people_stream scans **755 of 755 at stride 1**, so
  nothing can be missed here, and the RARE list is empty;
* **`SYM_PARAM_*` is a REAL dimension** (§7.5). v3.1 deny-listed it wholesale;
  §7.4 later reattributed the abort that justified the ban, and the ban had cost
  a whole dimension. This port varies this endpoint's own request parameters
  over the values the CORPUS produced plus the runner's default plus `''`.
  (Both param names would otherwise have been caught by the `_id` /
  `_person_id` deny suffixes — the same mistake in miniature. `denied()`
  exempts them explicitly.)

**Dry run (`--rebuild --dry-run`, builds seeds, writes nothing):**

```
seed universe: 30 bool, 10 len, 14 count, 13 emptyable-string,
               2 request-param, 0 explicit-int = 69 DIMENSIONS
               (scanned 755 of 755 dumps, stride 1)
  request param SYM_PARAM_person_id: corpus domain [''] + runner default '1' + ''
  request param SYM_PARAM_username:  corpus domain []  + runner default 'bob@example.org' + ''
DIMENSION CENSUS: 69 dimensions the v3 seeder varies; the corpus's EXISTING
                  seeds vary 7 of them (14 appear in a seed dict at all)
   bool               3 varied /  30      len              0 varied / 10
   count              2 varied /  14      emptyable-string 2 varied / 13
   request-param      0 varied /   2
743 seed templates (stride 1 over 755 dumps)
DRY RUN: built 500 seeds IN MEMORY, wrote nothing (0 dropped by PIN_OFF)
bool spread {True: 7502, False: 7498}; keys/seed 60; no denied keys: True
```

**THE DIMENSION CENSUS: 69 dimensions; the existing corpus varies 7.**
There was no OLD seeder on this endpoint — the 755-dump corpus was produced by
base DSE plus rooted demand rounds, so 62 of 69 dimensions have never been
moved at all. Every `len(...)` dimension (10 of 10) sits at its default in every
run, and 27 of 30 booleans do.

### `_demand_root.py` (REPLACED — the old copy carried a known defect)

The 2026-09-09 copy is archived as `_demand_root.py.pre_20260910`. The port
brings:

* **the many-ordinal fix.** The old copy built `inv.setdefault(canon, ordn)` —
  "first ordinal wins" — but the alias map is many-to-one BY DESIGN, so the
  seed landed on one arbitrary ordinal while the path could evaluate another
  and the run then CONTRADICTED the demand. Measured on notifications before
  the fix: 13 423 honoured, **6 656 contradicted**. Every ordinal backing the
  canonical is now seeded.
* **the skip-and-count filter for environmentally unreachable outcomes**,
  `_UNREACHABLE` — **empty on this endpoint**, deliberately: no witness has been
  established here, and an entry removes demand from the round without removing
  it from the checker, so a wrong one hides a real gap. The mechanism, the
  `_FORCE_OFF` pin and both counts are printed on every run.
* `DUMP_LIST`, and the lean index (keep the PATH, load base seeds lazily).

**Dry run:**

```
missing (blocking): 0
indexed 755 dumps, 29 distinct exprs, 0 wanted
anon_all: 0   anon_json: 0   auth_json: 0   rooted seed dicts (DRY RUN)
combinations with no corpus base: 0
combinations SKIPPED as environmentally unreachable (0 witnesses declared): 0
demanded lengths skipped because the base dump never minted that statement: 0
```

Zero roots is the CORRECT output: §16b leaves no blocking combination. **The
demand seeder has nothing to do on this endpoint.**

### `_tree_scan.py` / `_tree_root.py` / `_tree_check.py` (NEW — the tools that matter here)

Also ported, because the only remaining work IS a tree branch. These are what
took notifications' `tree_missing` from 10 to 3 in 157 runs with 0 aborts.
`_tw/targets.json` is generated from this endpoint's own `coverage_summary.json`
`tree_missing`. `wanted_value` was generalised beyond notifications' two shapes
(`== True`, `== ''`) to cover `!= 0`, `!= StringVal('')`, `> 0`, `== 0`; an
unhandled shape still EXITS rather than guessing.

```
_tree_scan.py:  shard 0/1: 755 dumps scanned
_tree_root.py:  t01:   5 seeds  taken  SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_guid
```

The `DISCOVERY` force-off list is empty here (notifications' entry is its own
libcurl witness).

---

## 5. Extractor readiness — created, and it found a parser defect and a POLICY BLOCKER

**This endpoint had NO extractor at all.**
`queries_from_runs/_extract_people_stream_streaming.py` is new, built from
`_extract_comments_index_streaming.py`: the E1 `AssocFoldingTransformer`, the
E11 RED check on unparseable notes, the broadened-bind NOTE lines, the
`broadened-*` `can_subsume` exclusion, an optional `POLICY_HEADER.txt`, and a
**tri-state subsumption tally**.

### The tri-state tally (as asked)

`subsume_ran` is a bool that conflates three states, and `prune_subsumed`
returns every query as a survivor when the checker is not executable — so a
check that never ran recorded `subsume_ran = True`. The new driver reports:

```
subsumption: state=None (True=ran, False=attempted and FAILED, None=never attempted)
             over 1 eligible of 1248 distinct
   verdict tally  subsumed(true)=0  not-subsumed(false)=1  UNDECIDED(null)=0
```

**null is never folded into false**: an undecided view is KEPT and counted
separately, with its own line. Note the real finding this exposes: only **1 of
1248** views is eligible for subsumption at all (the rest carry placeholders or
`type-mismatched-join`), so subsumption was **never attempted** — a fact the old
bool would have printed as `subsume_ran=False`, indistinguishable from a crash.

### Dry run — 755 dumps, view count and unparseable-note count

| | before the parser fix | after |
|---|---|---|
| views (`n_queries_final`) | **24** | **1248** |
| raw → distinct | 9884 → 24 | 9884 → 1248 |
| **unparseable notes** | **1728 (RED)** | **0** |

### The parser defect — found, fixed, and the fix is differentially clean

The E11 RED fired immediately: **1728 unparseable notes** over
`Relation_records_{1,3,4}` — this endpoint's three `posts` stream reads, i.e.
the statements people_stream exists to record. Cause, reproduced in isolation:

```
_BARE_DATETIME_RE = re.compile(
    r"(?<=[=<>\s])(\d{4}-\d{2}-\d{2} ...)(?=[\s)]|$)")     # OLD
```

The lookbehind/lookahead classes did not include `(` or `,`, so a bare Ruby
`Time#to_s` **inside a list** — `"posts"."type" IN (2026-09-09 09:25:30 +0000,
'StatusMessage')` — was left unquoted, sqlglot raised `ParseError` at the
time's colon, `_primary_table` returned `None`, and `transform.py:246` recorded
"unparseable note" and DROPPED the statement. Exactly the E11 shape.

**Fix (minimal, `src/queries_from_runs/transform.py`, the only src/ edit):**
add `(` and `,` to both boundaries. The datetime pattern itself is unchanged.

```python
r"(?<=[=<>\s(,])(\d{4}-\d{2}-\d{2}"
r"(?: \d{2}:\d{2}:\d{2}(?:\.\d+)?(?: \+\d{4})?)?)(?=[\s),]|$)"
```

`src/queries_from_runs` test suite: **38 passed.**

**Differential over EVERY corpus, so no closed endpoint is disturbed** (the old
and new regex applied to every note; a difference means the fix changes that
endpoint's extraction):

```
comments_index      8843/26528 dumps   138133 notes    0 differ
conversations_index 9312/18623 dumps   221328 notes    0 differ
people_show        12997/12997 dumps   635042 notes    0 differ
notifications_index 8163/163252 dumps  161168 notes    0 differ
posts_show          8030/96357 dumps   422680 notes    0 differ
people_stream         755/755 dumps     11067 notes  1728 differ
```

The fix touches **people_stream only**. No re-extraction is forced anywhere
else; nothing Rule-T-adjacent follows.

`skipped_pc_shapes` totals 4 405 over 13 shapes, led by
`(..._find_by_N_not_found == True)` 1 056 and `(SYM_PROFILE_PERSON_nsfw ==
True)` 672 — the same mock-internal families the CLOSED endpoints carry
(comments_index 893 882 over 52 shapes, people_show 405 945 over 44). Normal
residue, not a defect: they cost WHERE precision, not statements.

### ...and it exposes a BLOCKER the drop was hiding — DO NOT SHIP THIS POLICY

Recovering the 1728 statements shows WHY they were unparseable: the note the
runtime writes is bind-ROTATED.

```
SELECT "posts".* FROM "posts"
 WHERE "posts"."author_id" = 15
   AND "posts"."public"     = $$(SYM_..._first_1_id)     <- should be `true`
   AND "posts"."created_at" < true                        <- should be a timestamp
   AND "posts"."type" IN (2026-09-09 09:25:30 +0000, 'StatusMessage')
 ORDER BY posts.created_at DESC, posts.id DESC LIMIT 'Reshare'   <- should be an int
```

`transform.py:401 _repair_rotation` exists for this known runner render bug and
fired **2688** times on this corpus — but it rotates only slots whose RHS is a
LITERAL, so when a symbolic bind (`$$(...)`) occupies a rotated position the
slot list is one short and every value lands one place off. Measured: **1246 of
1248 emitted views still carry `bind-rotation-repaired`** and read

```
posts.author_id = 'Reshare'   posts.created_at < <a people.id>
posts.type IN ('<timestamp>', 'StatusMessage')
```

A present-and-wrong statement is worse than an absent one unless it is said out
loud, so the new extractor RED-flags any surviving `bind-rotation-repaired`
view with that explanation. **The fix is NOT mine to make** and is one of two
things, both above this agent's authority:

1. the RUNTIME note render (the shared boundary — Rule T, and `transform.py:24`
   already calls it "the runner's bind-rotation render bug"), or
2. `_repair_rotation` counting bind slots as slots.

This is pre-existing and documented in `src/`, not a new boundary discovery;
what is new is that people_stream is the endpoint where it dominates (≈40 % of
all 11 067 notes are rotation-affected) and that it was invisible while the
statements were being dropped.

### Also blocking closure (not the drive)

**`people_stream/POLICY_HEADER.txt` does not exist.** The extractor emits a loud
placeholder and says so on stdout. Under M-17 resolution (b) the declaration IS
the safeguard and must live in the artifact; `_WALLS.md` W1 is the material.

---

## 6. What would block a drive agent

1. **Nothing blocks the tree drive.** 5 rooted seeds are built and waiting;
   `run_dse.rb` is ready; smoke the `SEEDS_ONLY` dedup fix first (§3).
2. **Do not install the declaration before running those 5 seeds.** Driving the
   branch closes the endpoint with nothing declared, which is strictly better.
3. **Extraction/closure is blocked** by the bind-rotation residue (§5) and by
   the missing `POLICY_HEADER.txt`. Neither blocks exploration or the engine's
   verdict — DISCIPLINE's own lesson from E11: exploration and extraction are
   different stages, and `complete: true` certifies only the first.
4. Re-run the §16b coverage pass after any driving; `MISSING=0` is
   **PROVISIONAL** while `tree_missing` stands, and a run that walks what a
   foreclosure forbids ADDS demand.

## 7. Files written by this preflight

```
people_stream/_exact_enum.py            NEW (ported; verifier pin-scope fixed)
people_stream/_v3_seeds.py              NEW
people_stream/_demand_root.py           REPLACED (old -> .pre_20260910)
people_stream/_tree_scan.py             NEW
people_stream/_tree_root.py             NEW
people_stream/_tree_check.py            NEW
people_stream/_tw/targets.json          NEW (from this endpoint's tree_missing)
people_stream/_treeR_t01_{anon,auth}_json.json   NEW (5 falsifier seeds)
people_stream/coverage_report.py        + foreclosure fields & printed lines
people_stream/run_dse.rb                + SEEDS_ONLY dedup gate (UNTESTED)
people_stream/coverage_summary.json     regenerated under §16b
people_stream/_bak_coverage_summary_16set_20260910.json   the §16 baseline
queries_from_runs/_extract_people_stream_streaming.py     NEW
src/queries_from_runs/transform.py      _BARE_DATETIME_RE boundaries (only src/ edit)
```

`coverage_assumptions.py` **untouched.** `src/concolic_engine` **untouched.**
No reference policy read. No JRuby launched.
