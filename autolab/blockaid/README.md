# `blockaid/` — the blockaid artefact, and what it can and cannot say

Nothing under `reports/autolab/` had ever produced a blockaid or subsume
artefact before this directory.  So the first job was to establish what the
artefact *is*.  This README is that answer, and the second half is the honest
reading of the five that have been produced.

---

## 1. What the artefact is

`src_new/domains/ruby_rails_sql/` wraps a JVM checker built on **blockaid**
(Calcite + H2 + Z3).  Given a set of SQL *views*, it answers — with a Z3 proof
or a Z3 counterexample — questions of the form *"is this query answerable from
those views?"*.  That is the only blockaid question the harness exposes, and it
comes in two shapes:

| shape | in | out |
|---|---|---|
| **pairwise** | `{"queries": [v0, v1, …]}` | `{"subsumed": [[i,j],…], "errors": {"i": "why not"}}` — view *i* is answerable from view *j*, so *i* is redundant |
| **coverage** | `{"views": […], "queries": […]}` | `{"covered": [true\|false\|null, …], "view_errors": {…}}` |

Entry points:

- `src_new/domains/ruby_rails_sql/subsume_harness/check_subsumed.sh` — the
  checker itself (stdin/stdout JSON; `java -cp classes:<blockaid-jar>
  subsume.SubsumeChecker`), specified in that directory's `README.md`
- `domains.ruby_rails_sql.subsume_solver.check_subsumed_pairs` /
  `prune_subsumed` — the Python wrappers, plus a CLI
- `reports/diaspora/tools/blockaid_coverage.py` — the coverage shape

**This directory produces the pairwise shape**, because that is the shape whose
inputs this corpus actually has.  Two results fall out of one call, and both
are the artefact:

- **loadability** — which of the policy's rendered views blockaid can load and
  type *at all*.  A view it rejects is quarantined with blockaid's own message
  and takes no part in any verdict.
- **redundancy** — which loadable views another loadable view subsumes,
  **solver-proved** rather than string-matched.  Every `rendered.sql` in this
  corpus says in its own header that its subsumption is *"SYNTACTIC ONLY …
  the solver-backed checker is not run from a render"*.  This is that run.

### Inputs, and that they all exist

| input | where | status |
|---|---|---|
| rendered SQL (one `SELECT` per statement, MySQL backticks) | `endpoints/<ep>/<prov>/<run>/rendered.sql` | present |
| app config | `blockaid/config/app.json` (a copy of the diaspora one — autolab *is* the diaspora app) | present |
| 5 schema fixtures: `ddl`, `primary_keys`, `foreign_keys`, `dependencies`, `const_decls` | `blockaid/config/resources/` (copied from `reports/diaspora/queries_config/resources/`) | present |
| JDK 17 | `/home/dev/opt/jdk` | present |
| blockaid jar (33 MB, Calcite + H2 + Z3 bindings) | `src/queries_from_runs/blockaid/target/privacy_proxy-1.0-SNAPSHOT-jar-with-dependencies.jar` | present |
| Z3 4.8.12 (binary + `libz3java.so`) | `/home/dev/opt/z3/z3-4.8.12-x64-glibc-2.31` | present |
| python | `venvs/queries_from_runs/bin/python3` | present |

**No live database is needed** — the DDL is loaded into an in-memory H2 exposed
to blockaid through a Calcite JDBC schema, in place of the MySQL that
blockaid's `PrivacyDriver` would normally introspect.

**One real gap, and it is only a path.**
`src_new/domains/ruby_rails_sql/blockaid/` is an **uninitialised git
submodule** — its working directory is empty, as
`src_new/domains/ruby_rails_sql/README.md` states.  So *that* copy of
`check_subsumed.sh` cannot find the jar and dies with
`NoClassDefFoundError: org/apache/calcite/sql/validate/SqlConformance`.  The
`src/queries_from_runs/subsume/check_subsumed.sh` twin — same checker, same
prebuilt classes — has the built jar as its sibling and works.  This directory
uses that one, and names the jar in `config/app.json` as well.  Nothing in
`src_new/` was changed to make this run.

---

## 2. What is NOT produced, and why that is the honest answer

**The coverage shape is not produced.**  It needs a *query* set, and the query
set has never been built.  The SELECTs each endpoint actually issued are
recorded in its dumps as notes of the form

```json
{"refs": {"p0": "SYM_PARAM_id"},
 "text": "SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = $$(p0)"}
```

Every one carries **unresolved symbolic binds**.  A query set could only be
built from the notes by declaring each bind an unconstrained constant — which
asserts *"this could be any value"* where the run in fact proves it is one
specific join target.  That is over-permissive in exactly the direction that
matters for an authorization policy, so the tool refuses to build it and
records the refusal in every `blockaid.json`
(`coverage_shape_not_produced`).

**The blocker this section used to name has been removed.**  It read: *"what
it would take is bind resolution in the renderer — inline the producing call
and emit the join — not a wider constant table.  That is a
`src_new/domains/ruby_rails_sql/render.py` change and is out of scope here."*
That change landed on 2026-10-01 (§3), and the views are now bind-resolved.
So the coverage shape is no longer blocked by the *view* side, and in
principle the same machinery — the policy IR's producer chain — is what a
query set would be built from.  **It still has not been built**, and until it
is, nothing in this directory is a coverage claim.  The refusal stands; only
its stated cause has changed.

---

## 3. The two modes, and the two fixes that emptied the quarantine

Each artefact runs the pairwise shape in up to two modes.

**`asis`** — the views exactly as rendered.  This is the measurement.

**`binds_as_constants`** — each bind rewritten to a declared integer constant,
so views blockaid quarantined in `asis` could at least be loaded and the
redundancy question asked of the whole policy.  **An explicitly
over-permissive diagnostic, never a policy claim** (`over_permissive_diagnostic:
true` in the JSON).  **It is now skipped on every refreshed artefact**, with
the reason recorded inline: *"no `_cN.field` bind appears in these views, so
this mode would be identical to `asis`"*.  The mode existed to work around the
defect §3.1 describes; the defect is gone, so the workaround no longer has
anything to do.

### 3.1 The old finding, and the fix that retired it

The finding this README carried until 2026-10-01 was **"the toolchain works;
the rendered SQL is what blocks it"**: as-is, blockaid loaded **2 of 10**
posts_destroy views and **2 of 11** comments_index views, every rejection the
same message —

```
rejected by solver-type probe:
IllegalArgumentException: unrecognized constant: _c1.id
```

— a backtick-quoted pseudo-column that was neither a column of any `FROM`
table nor a declared constant.  Only fully ground views survived.

Two fixes in `render.py` resolved those binds into joins, and the renders
stored here were refreshed from their stored policies by
`reports/autolab/tools/rerender.py` (which re-renders from
`policy/policy.txt`, not from the dumps — the policy IR round-trips verbatim,
so the IR → SQL hook is the only thing that can move).  **120 of 164 stored
renders changed; none raised.**  The placeholder note
`unresolved symbolic binds kept as placeholders` now appears in **4 of the 164
stored renders**, down from **119 of the 161** source renders still held in
`reports/autolab/evidence_store/` (the upstream the store was built from, which
is the only surviving copy of the pre-fix output).  The four are
`contacts_index`, `likes_index`, `photos_index` and `reshares_index`, all local,
between them 6 placeholders of the `_cN.id` form.  `comments_index` renders the
flat-equijoin shape the
benchmark's own reference answer uses
(`policy-extraction-bench/data/answers/diaspora/comments-index.sql`):

```sql
SELECT `mentions`.* FROM `mentions`, `comments`, `posts`
 WHERE `mentions`.`mentions_container_id` = `comments`.`id`
   AND `mentions`.`mentions_container_type` = 'Comment'
   AND `comments`.`commentable_id` = `posts`.`id`
   AND `comments`.`commentable_type` = 'Post';
```

Measured on the refreshed renders, `asis`, same checker and timeout:

| endpoint | before | after | proved subsumptions |
|---|---|---|---|
| `comments_index` local | 2/11 loadable | **8/8** (11 views became 8) | 1 (`[9,10]`, view 9 redundant) |
| `posts_destroy` local | 2/10 loadable | **9/9** | 0 |
| `posts_destroy` cloud | 2/10 loadable | **9/9** | 0 |
| `comments_index` cloud ×2 | 1/1 loadable | 1/1 | 0 |

The two cloud `comments_index` runs are single-atom policies and were never
blocked; they are in the table so the five artefacts reconcile.

### 3.2 The `row2_` pseudo-column — closed 2026-10-01

**Every quarantine in this corpus is now gone**, and the last three were one
defect. After the binds resolved, a bind that resolved to a *second row* of the
same relation was still rendered as a column with the row index baked in:

```
view 1, 3  RuntimeException: unknown type for column MENTIONS.ROW2_PERSON_ID
view 5     IllegalArgumentException: column not found: COMMENTS.ROW2_ID
```

`mentions.row2_person_id` is not a column of `mentions`. It is the runtime's
SECOND representative row of the relation — `targets/endpoints/comments_index.rb`
mints it with `symbolic_instance(…, "#{name}_row2", sql)`, **passing the same
`sql`**, so there is no second statement and never was.

**Two defects, both in `render.py`, both found by looking for the first.**

1. `_suffix_candidates` had offered `row2_person_id -> person_id` all along —
   the generator exists precisely for this. But the candidate loop asked
   `_table_holding` non-strictly, and its no-schema arm answers *"the first
   table"* for **any** column name. So with no schema the FIRST reading always
   won and no later reading was ever tried. `_table_holding` now takes
   `strict=`, the loop passes it, and the fallback prefers the most-stripped
   reading: a `row_`/`item_` segment is a runtime naming artefact, never a
   column, while the raw suffix is only sometimes one.

2. That left `IN (mentions.person_id, mentions.person_id)` — two binds
   resolving to one column. Not cosmetic: while the row-2 view differed from
   the row-1 view by a dead list entry, the statement prune could not see they
   were the same view. `IN (x, x)` now collapses to `= x`, deduplicating by
   rendered SQL so only syntactically identical operands merge.

The three row-2 views then became byte-identical to the three they duplicate
and the prune removed them. `comments_index` renders **8 views, 8/8 loadable,
0 quarantined** — down from 11 views of which 8 loaded, and from the 11 views
of which 2 loaded before any of this.

The whole corpus was re-rendered after the fix: **1 of 164 runs changed**, and
it is comments_index. The row-representative shape occurs nowhere else, because
it is minted by one endpoint's own target layer.

### Reading the numbers safely

- **An empty `subsumed_pairs` is not proof of distinctness.** A non-subsumed
  pair costs the *full* timeout, and the checker does not report which pairs it
  decided and which it abandoned, so "undecided" and "proved distinct" are the
  same absence.  Each `blockaid.json` says this inline
  (`reading_subsumed_pairs`).  posts_destroy's `0` above is that absence, not a
  claim that its 9 views are pairwise distinct.
- **A quarantined view is not a permitted one.** It is a view no verdict
  covers.  There are none left in this corpus: every view of every artefact
  here loads.  That is a statement about blockaid being able to READ the
  views, not about the policy being right.
- **Nothing here is a completeness claim.** No config in this corpus carries a
  `completion` block, so every endpoint's certificate line reads
  `outcome=UNDECIDED`.  See `../README.md`.

## 4. Layout and how to refresh

```
blockaid/
├── README.md                      this file
├── INDEX.md                       every artefact produced, as a table
├── config/
│   ├── app.json                   the app config the checker is run with
│   └── resources/                 ddl, pk, fk, deps, const-decls
└── endpoints/<ep>/<prov>/<run>/
    ├── blockaid.json              inputs, both modes, the checker's own
    │                              output verbatim, and the caveats inline
    ├── views.asis.sql             exactly what was submitted, mode 1
    └── views.binds_as_constants.sql          … and mode 2
```

```bash
cd /home/dev/project
unset JAVA_TOOL_OPTIONS          # a leaked value breaks the JVM run
venvs/queries_from_runs/bin/python3 \
    reports/autolab/tools/blockaid_artefact.py \
    reports/autolab/endpoints/<ep>/<prov>/<run> [more runs…] \
    [--timeout-ms 5000] [--threads 3]
```

`--threads 3` is the documented safe concurrency; 8 solver threads OOM-killed a
batch on an 8 GB box.  Wall time is roughly
`init + n·(n−1)·timeout / threads` in the worst case, so raising
`--timeout-ms` on a large policy is expensive.  `INDEX.md` is regenerated on
every call.
