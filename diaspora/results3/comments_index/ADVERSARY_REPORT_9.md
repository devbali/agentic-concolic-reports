# ADVERSARY ROUND 9 — comments_index (CommentsController#index, GET /posts/:post_id/comments)

Date 2026-09-01. Corpus under attack: cycle 11 — `complete: true`, **94 nodes**,
**26 931 dumps** / 882 543 PCs, 0 missing, assumptions 5 315 declared / 4 614
tested / 4 614 PASS / 0 FAIL, shims 19 PASS / 11 PROTOCOL, `hardening_lint`
clean over 69 evidence files, count matrix 0 under / 0 over, rig-crash census 8
application-terminal classes, `cardinality_consistency` 111 345 pairs / 0
findings.

**Ops.** 4 manifests, 4 JRuby processes (`adversary9/J01…J04`), **42 real HTTP
requests + 9 in-process probes; 327 endpoint-scoped SQL statements captured with
their frames** (plus 31 scenario-body statements, kept separate throughout).
**0 JVM aborts** — every discovery probe used a URI-hostile domain, and the
persistence-callback probes touch no network at all. Each process: `unset
JAVA_TOOL_OPTIONS`, `tools/slot scripts/diaspora-concolic …/concrete_run_probe.rb
<manifest>` inside `systemd-run --user --pipe --wait -p MemoryMax=4000M -p
MemorySwapMax=0`; **one JRuby at a time** (MemAvailable was 3.5 GB at the start
of the round). No mocks, stubs or monkey-patches; only fixture rows, session,
params, headers and format. Batch instruments byte-identical after the round —
`md5sum -c adversary9/runs/_batch_md5_before.txt`: **12/12 OK**.

**Result: 2 wins (W9-1, W9-2 — both TARGET-LEVEL), 5 near-misses, 3 named
targets refuted with positive evidence.**

**Entrypoint evidence.** A harness-side `sql.active_record` subscriber
(`adversary9/_frames9.rb`) records `caller` per statement; `J04` additionally
captures the full backtrace of every raise. Every statement in every ENDPOINT
column below has a captured stack ending in `app/controllers/comments_controller.rb:51`
or `:52 in 'index'`, or in `app/views/comments/_comment.mobile.haml` — the
post-auth action frame, principal concretely instantiated (uid 9) within its
symbolic declaration. Files: `adversary9/runs/_frames_J0*.json`,
`adversary9/runs/_backtraces_J04.json`.

**Probe hygiene (N7-7, and the coordinator's explicit instruction).**
`mock_note_check` and `note_fidelity_audit` have no notion of request
boundaries. J01's judge is RED, and **every one of its RED shapes comes from my
own scenario-body probes**, not from the four endpoint requests in that
manifest. The four endpoint requests of J01 issued exactly
`{posts×1, comments×1, people×1, profiles×1, mentions×1..3}` and nothing else.
J02, J03 and J04 are green on both judges (J02: 14 EXACT / 0 MISSING; J03: 8
EXACT). Which statements belong to which zone is stated per scenario below and
is machine-derivable from the `frames` field of each capture.

---

## 1. Scenario table

| manifest | scenarios | requests / probes | outcome | new? |
|---|---|---|---|---|
| **J01** `discovery_arm` | author with no `profiles` row (1 and 2 comments) × json/mobile; then probes: `find_or_fetch_by_identifier` on a known and an unknown handle; **the app's own `:save_person_after_webfinger` callback** for an EXISTING and for a NEW person | 4 / 5 | 4 × DiscoveryError; both callback probes returned `true` with **no network** | **W9-1** |
| **J02** `keys_and_rows` | 3 distinct authors (all with profiles; third without; first without); 3 rows / 2 keys; signed-in mobile with the principal as row 1, as row 2, and as both; 3 mentions mixed (dangling + profile-less + live); 3 live mentions | 13 / 0 | 8 × 200, 4 × DiscoveryError/Template::Error, 1 × 401 | positives, N9-1…N9-3 |
| **J03** `memo_and_shapes` | 0/1/2 comments × 0/1 mentions × json/mobile; same-author pair; empty list; blank comment text; closed account with a blank-name profile; mention person == author; guid arm; non-public anon | 18 / 2 | 17 × 200, 1 × 401(`throw :warden`) | positives, N9-4 |
| **J04** `entrypoint_backtrace` | full backtraces of the DiscoveryError (author tree and mention tree, anon and signed-in, json and mobile); the **same request dispatched plainly and inside `Rails.application.executor.wrap`** | 7 / 2 | 5 backtraces, 2 × 200 | **W9-2**, entrypoint evidence |

---

## 2. WINS

### W9-1 — the `discovery_failed == False` arm asserts the two statements that come AFTER the thirteen it omits

**Class: S (mis-shaped evidence — a modelled state whose statement set is a
proper subset of the application's). TARGET-LEVEL**: `Discovery.fetch_and_save`
is on the shared wall list (`TARGET_FUNCTIONS.md §3`) and `Person#fix_profile`
is reachable from every endpoint that renders a person's name.

**The claim under test**, `AGENT_RUN.md` cycle 11, verbatim:

> The success arm's note ended "no SQL". That was a positive false claim […]
> The note now says the persistence callback is **UNMODELLED, not absent**.
> **No statement is asserted for an arm no real run in this environment can
> reach.**

**That last sentence is false.** Measured over all 26 931 dumps:

```
dumps with a `…_discovery_failed == True` PC taken FALSE (i.e. fetch_and_save RETURNS): 7 272
   of those that also emit ActiveRecord::Base.reload                                   : 7 272   (100 %)
   symbolic_call events after the first success PC: reload 7 972, find_target 7 972
tables appearing in ANY corpus note: posts, people, profiles, comments, mentions, users
DML notes anywhere in the corpus                                                       : 0
```

So on that arm the corpus asserts, 7 972 times each,

```
SELECT "people".*   FROM "people"   WHERE "people"."id"          = $$(…_row_author_id) LIMIT 1
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = $$(…_row_author_id) LIMIT 1
```

and then a clean 200 with a full render (`dump_anon_json_dse0030` events 40-45 is
the canonical instance).

**Why that state is impossible.** `fetch_and_save`
(`diaspora_federation-0.2.6/lib/diaspora_federation/discovery/discovery.rb:19-31`)
is

```ruby
def fetch_and_save
  validate_diaspora_id
  DiasporaFederation.callbacks.trigger(:save_person_after_webfinger, person)
  person
end
```

It cannot RETURN unless `:save_person_after_webfinger` has run to completion —
any raise inside it is converted to `DiscoveryError` by the method's own
`rescue`, which is the *other* arm. And `reload` (`person.rb:373`) runs only
after that return. So **every `reload` the corpus asserts is preceded by the
app's own callback** (`config/initializers/diaspora_federation.rb:59-77`).

**What that callback really issues** — measured, no network, both branches
(`adversary9/runs/_frames_J01.json`, tags `PROBE_P3b/P3c`; these are
SCENARIO-BODY statements, not endpoint statements, and are reported as such):

*existing person, no `profiles` row (the exact state `fix_profile` runs in) — 13 statements:*
```
SELECT "people".*   FROM "people"   WHERE "people"."diaspora_handle" = ? LIMIT ?
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id"     = ? LIMIT ?
BEGIN TRANSACTION
INSERT INTO "profiles" ("person_id","created_at","updated_at","full_name") VALUES (?,?,?,?)
SELECT "tags".* FROM "tags" INNER JOIN "taggings" ON "tags"."id" = "taggings"."tag_id" WHERE …
COMMIT TRANSACTION
BEGIN TRANSACTION
SELECT 1 AS one FROM "people" WHERE "people"."guid"            = ? AND "people"."id" != ? LIMIT ?
SELECT "pods".*  FROM "pods"   WHERE "pods"."id" = ? LIMIT ?
SELECT 1 AS one FROM "people" WHERE "people"."diaspora_handle" = ? AND "people"."id" != ? LIMIT ?
UPDATE "profiles" SET "first_name" = ?, "last_name" = ?, "image_url" = ?, … WHERE "profiles"."id" = ?
SELECT "tags".* FROM "tags" INNER JOIN "taggings" ON … 
COMMIT TRANSACTION
```

*person not yet known — 13 statements, including `Pod.find_or_create_by`:*
```
SELECT "people".* FROM "people" WHERE "people"."diaspora_handle" = ? LIMIT ?
SELECT "pods".*   FROM "pods"   WHERE "pods"."host" = ? AND "pods"."port" IS NULL LIMIT ?
BEGIN TRANSACTION / INSERT INTO "pods" ("host","ssl","created_at","updated_at") VALUES (?,?,?,?) / COMMIT
BEGIN TRANSACTION
SELECT 1 AS one FROM "people" WHERE "people"."guid" = ? LIMIT ?
SELECT "people"."diaspora_handle" FROM "people" WHERE "people"."guid" = ? AND "people"."diaspora_handle" != ?
SELECT 1 AS one FROM "people" WHERE "people"."diaspora_handle" = ? LIMIT ?
INSERT INTO "people"   ("guid","diaspora_handle","serialized_public_key","created_at","updated_at","pod_id") VALUES …
INSERT INTO "profiles" ("first_name","last_name","image_url",…,"person_id","created_at","updated_at","full_name") VALUES …
SELECT "tags".* FROM "tags" INNER JOIN "taggings" ON …
COMMIT TRANSACTION
```

Against the corpus this contributes, in a state the corpus explores 7 272 times:

* **three tables with no note anywhere**: `pods`, `tags`, `taggings`;
* **two predicate columns with no note anywhere**: `people.diaspora_handle`
  (removed as over-emission in cycle 3, ledger row 65) and `people.guid`;
* a `pluck` projection (`people.diaspora_handle`) — `Calculations.pluck` scores
  NOTE-MISSING;
* **three writes** — `INSERT INTO "people"`, `INSERT INTO "profiles"`,
  `UPDATE "profiles"` — where the corpus has **0 DML notes**, and transactions
  around them.

So the arm is not "unmodelled": it is modelled with 2 of 15 statements, and the
2 it keeps are the ones that come last. A policy consumer reading the
discovery-success arm is told this endpoint performs two single-row reads there.
It performs two reads, three uniqueness/validation probes, a `pods` read, a
`pluck`, two `tags` joins and three writes first.

**Entrypoint verification.** `adversary9/runs/_backtraces_J04.json`, root
`URI::InvalidURIError`, scenario `J04_960_author_anon_json`:

```
gem:diaspora_federation-0.2.6/…/discovery/discovery.rb:22:in `fetch_and_save'
app:app/models/person.rb:373:in `fix_profile'
app:app/models/person.rb:249:in `name'
app:app/presenters/comment_presenter.rb:13:in `as_json'
app:app/presenters/base_presenter.rb:14:in `as_collection'
app:app/controllers/comments_controller.rb:52:in `block in index'   <-- the entrypoint
app:app/controllers/comments_controller.rb:51:in `index'
```

the signed-in twin (`J04_960_author_auth_json`, uid 9 concretely instantiated)
is identical; the mention-tree twin ends `comment_presenter.rb:15`; the mobile
twins end `app/helpers/people_helper.rb:32` →
`app/views/comments/_comment.mobile.haml:12`, i.e. inside the action's own
template. `fetch_and_save` is entered **from the entrypoint**; which arm it then
takes is an environment bound, not a scope question.

**What I could NOT do, stated plainly.** I could not make `fetch_and_save`
RETURN through the endpoint. Probe P2 confirms the only app-level fast path
(`Person.find_or_fetch_by_identifier`) short-circuits *before* `Discovery` and is
not on `fix_profile`'s route; the gem class has no local-pod, cached-hcard or
caller-supplied-entity branch (`discovery.rb:37,80,84` — `webfinger` and `hcard`
are both `HttpClient.get`). So the ENVIRONMENT bound in the `h6_answered` reason
stands. **The defect is not that the arm is unreachable; it is that the corpus
takes it 7 272 times and describes it wrongly.** Two consistent repairs exist —
model the callback's statements on that arm, or make the success arm a true
terminal that asserts no downstream statement — and choosing between them is the
batch's call, not mine.

---

### W9-2 — every per-request statement multiplicity this project has measured is a rig artifact: the real stack caches, the rig does not

**Class: S (ground truth under-/over-reporting, INSTRUMENT). TARGET-LEVEL and
CROSS-BATCH** — it is a property of `concrete_run_probe.rb` + the
`ActionController::TestCase` dispatch every rig on every endpoint uses, and of
the count matrix the coordinator counts as a closing check.

**The claim under test**, `DISCIPLINE.md §13`, verbatim:

> the shared probe skips `payload[:cached]` statements and nothing cleared the AR
> query cache between requests […] Fixed in `concrete_run_probe.rb`: the cache is
> cleared per scenario […] **Within-request caching is left alone, because a real
> request caches too.**

The premise is that the rig caches within a request the way a real request does.
It does not. The rigs dispatch the action directly through
`ActionController::TestCase#process`, which does not run
`ActionDispatch::Executor` — and Rails installs AR query caching as an
**executor hook**, not as controller code.

**Measured, same manifest, same fixtures, same request** (post 962: 2 comments,
2 authors, 1 mention each, json; `adversary9/runs/_frames_J04.json`, tags
`J04_962_plain_dispatch` and `J04_962_executor_wrapped`):

| shape | rig dispatch (`cached:` count) | inside `Rails.application.executor.wrap` | probe-visible in a real Rack request |
|---|---|---|---|
| `SELECT "mentions".* … container_id = ?` | 4 (0 cached) | 4 (**2 cached**) | **2** |
| `SELECT "people".* … "id" = ?` | 4 (0 cached) | 4 (**3 cached**) | **1** |
| `SELECT "profiles".* … "person_id" = ?` | 4 (0 cached) | 4 (**3 cached**) | **1** |
| `posts`, `comments`, `people IN`, `profiles IN` | 1 each | 1 each, 0 cached | 1 each |
| **total** | **16, 0 cached** | **16, 8 cached** | **8** |

`ActionDispatch::Executor` **is** in this application's middleware stack
(J03 probe Q1: `["ActionDispatch::Executor", "ActiveSupport::Cache::Strategy::LocalCache"]`),
so a deployed pod takes the right-hand column. The shared probe skips
`payload[:cached]`, so ground truth through the real stack is 8 statements where
every rig on this project records 16.

**Why this lands on the cycle-11 repair specifically.** M-16b's design decision
is written into `targets.rb:905-916`: *"the second read re-emits every statement
(multiplicity is real and stays exact)"*. It is exact against the rig and 2×
against a real request. The corpus's own maxima are calibrated to the left-hand
column — `anon_json`: `mentions` 4, `people.id = @` 5, `profiles.person_id = @`
5 — i.e. the corpus asserts, per request, roughly twice the repeated-statement
count a real pod issues. The merge (one list answers both reads) is *right*
about the rows being one fact; the statement count it preserved is the quantity
that was mis-measured.

**Entrypoint verification.** Both measurements are the same action invocation
(`comments_controller.rb:51-52`), anon, byte-identical fixtures and params;
nothing was mocked, and the only difference is the app's own executor around the
call. All 16 statements in both runs carry an ENDPOINT frame.

**Scope note, stated honestly.** The executor is above the action, so this is not
a claim that the *entrypoint* issues different statements — the entrypoint issues
the same 16 calls in both runs. The claim is narrower and is about the
INSTRUMENT: **the number a real request's probe would record is 8, and every
multiplicity figure in this project — including the "0 under / 0 over" count
matrix — was derived from 16.** Under §14 ("the count-based multiplicity check
compares per-REQUEST shapes and must match ground truth exactly") that makes the
ground truth itself wrong for every repeated shape, on all three batches.

---

## 3. NEAR-MISSES

**N9-1 — a third distinct key changes arity and nothing else, re-measured on a
mixed nested tree.** J02 post 927 (one comment, three mentions: one dangling
person, one profile-less, one live) issues `people.id IN (?,?,?)` then
`profiles.person_id IN (?,?)` — an outer 3-key step over a nested 2-key step.
The corpus's two representatives can produce (2,2) and (2,1) but never (3,2).
`note_fidelity_audit` scores J02 **14 EXACT / 0 MISSING** and `_multiset_counts`
files both wider lists as `per-row family, wider IN-list than the corpus's
representatives; same predicate {col, IN}`. No new table, predicate or branch at
3 keys — this extends R8's H04 positive from the author tree to a *mixed* nested
tree and it remains the declared `SampledList` ceiling. Status: open (declared
limit), not a win.

**N9-2 — `people.id IN (?,?,?)` / `profiles.person_id IN (?,?,?)` are now
measured at IN-arity 3 on the MENTIONS tree too** (J02 post 928, json ×2 and
mobile ×1). `_multiset_counts` IN-arity census: `real max IN(3), corpus max
IN(2)` for both shapes. Same declared ceiling; recorded so the ceiling is a
measurement rather than an assertion.

**N9-3 — the per-row branch that is not a statement.** `_comment.mobile.haml:18`
(`user_signed_in? && comment.author == current_user.person`) and
`people_helper.rb:81` (`person_link_class`) are three per-row identity compares.
J02 posts 924/925/926 (principal as row 1, as row 2, as both) render 1876 / 1876
/ 2064 bytes with **identical statement multisets** — so the branch is real and
per-row but carries no statement. The corpus expresses it on both rows and in
both polarities (census: `…to_a_N_row_author_id == …devise_user_first_N_person_id`
16 248 events, `…to_a_N_rowN_author_id == …` 7 748, both polarities). N8-5's
by-construction closure is therefore SOUND for this endpoint. Positive result.

**N9-4 — the harness's per-uid warden memo still hides the principal reads after
the first auth request in a process** (ledger row 87, unrepaired). J02_924 issues
`SELECT "people".* … "owner_id" = ? LIMIT ?` from `querent_is_author`
(`evil_query.rb:116`); J02_925 and J02_926, same uid later in the same process,
do not. This is a harness artifact, not an app fact — anyone reading R9's auth
multisets must use the FIRST auth request of each manifest.

**N9-5 — the anonymous class asserts two LIMIT-1 person reads no anonymous
request can issue, and no check can see it.** 4 014 of 12 999 `dump_anon_*`
dumps (30.9 %) carry `SELECT "people".* … "id" = ? LIMIT 1` and/or
`SELECT "profiles".* … "person_id" = ? LIMIT 1`; **all 4 014 are on the
discovery-success arm**, and 34 real anonymous requests in this round issued
neither. It is invisible to both checks by construction: `hardening_lint` H6 is
a GLOBAL presence test and the shapes are issued by real *auth* runs (the
principal's profile), while `_multiset_counts` compares like with like and never
reports a shape the class's ground truth does not contain at all. This is the
over-emission half of W9-1 and shares its repair; it is filed as a near-miss
rather than a third win because it has no separate cause.

---

## 4. TARGETS REFUTED WITH POSITIVE EVIDENCE

1. **The SQL-keyed memo cannot fuse two distinct reads on this endpoint.** The
   only relation read twice is `mentions` (`mentions_container.rb:19` via
   `#message`, and `comment_presenter.rb:15`), nothing between the two reads
   writes, reloads or resets an association, and the two representative rows bind
   different id symbols (`…_row_id` vs `…_row2_id` — the N8-5 repair overwrites
   `author_id`, never `id`), so no two distinct relations render the same SQL.
   The memo is also reset per run (`run_dse.rb:235`), so it cannot leak between
   dumps. Measured multiplicity matches per format: mobile issues the `mentions`
   SELECT once per comment (`markdownified` builds `#message` only), json twice
   (J03: 1 comment → 2 json / 1 mobile; 2 comments → 4 json / 2 mobile).
   *The one way to make the two reads differ legitimately is a successful
   `fix_profile` between them — which is W9-1's arm.*

2. **`needs_second_row?`'s remaining blind spots are not reachable here.** It
   skips polymorphic reflections and returns false for a `has_many` step, and
   `emit_includes_preloads` drops the nested step under a `has_many` (no
   `survivors`). Neither shape occurs on this endpoint: the only two includes
   trees are `comments.includes(author: :profile)` (`comment.rb:36`) and
   `mentions.includes(person: :profile)` (`mentions_container.rb:19`), and both
   contain a `has_one`, so both get a second representative. The `else` branch
   M-16 left behind (`targets.rb:402`, key 2 simply loaded) is unreachable on
   both.

3. **Blank comment text, a closed account with a blank-name profile, a mention
   person that is the comment author, the guid arm and the anon `NonPublic`
   rescue all produce statement sets the corpus already carries** (J03: 17×200
   and one `401(throw :warden)` after a single `posts` read; `mock_note_check`
   EXIT=0, `note_fidelity_audit` 8 EXACT / 0 MISSING).

---

## 5. WHAT I COULD NOT REACH

* `fetch_and_save` returning normally — needs a working HTTP adapter; typhoeus →
  Ethon → libcurl through JFFI kills this JVM on any parseable URL. Confirmed by
  code reading of the gem class (no local short-circuit at
  `discovery.rb:37, 80, 84`) and by probe P2. Not re-measured with a deliberate
  abort this round: R8 and cycle 11 each did it once, and a third abort buys
  nothing.
* A third representative row — the corpus has 0 `_row3_` symbols by
  construction; N9-1/N9-2 measure the consequence rather than remove it.
* Formats other than json/mobile (`html`, `xml`, `js`, `atom`) — R6/R7 already
  measured that they raise after the finders, adding no shape (ledger rows 99,
  111). Not re-run.
