# B-8 exposure on the two shipped-policy endpoints — conversations_index and people_show

**Date** 2026-09-14 · **Kind** integrity check, MEASUREMENT ONLY
**Nothing was changed.** No `coverage_summary.json`, `POLICY_HEADER.txt`, `.sql`,
`concolic_targets.rb`, `targets.rb` or endpoint status was touched; no run was
driven; no `src/` edit; no extraction. All work was read-only scans of the two
batches' own dump directories, caged under `concolic-cov.slice` (MemoryMax 3G).

**Verdict up front: NEITHER SHIPPED POLICY IS MISSING A STATEMENT.**
`conversations_index` is GREEN with 0 UNVERIFIED. `people_show` is RED with
58,946 UNVERIFIED events, but every one of them is accounted for and none costs
the policy a statement — 2,812 are the B-8 bare-`nil` finder arm whose statement
is published by the same call site's found arm elsewhere in the same corpus
(and is in the `.sql`), and 56,134 are calls that issue no SQL at all.

---

## 1. The defect in the code — confirmed by reading, not inferred from a grep

`Thread.current[:concolic_pending_note] = …` site counts (verified 2026-09-14):

| batch | `concolic_targets.rb` | `targets.rb` |
|---|---|---|
| notifications_index | 3 | 5 |
| comments_index | 1 | 4 |
| people_stream | 1 | 0 |
| posts_show | 1 | 0 |
| **conversations_index** | **0** | **2** |
| **people_show** | **0** | **1** |
| MASTER `reports/diaspora/concolic_targets.rb` | **0** | — |

### conversations_index — defect present in `concolic_targets.rb`, **fully compensated in `targets.rb`**

`concolic_targets.rb:595-606` `finder_mock(raise_on_missing:)`; the not-found arm is:

```ruby
if not_found == true
  raise ActiveRecord::RecordNotFound, "concolic: empty result for: #{sql}" if raise_on_missing
  nil                       # <- B-8: bare nil, no note published
else
  symbolic_instance(model_class(receiver), name, sql)
end
```

Declared on `ActiveRecord::FinderMethods` `find/take!/first!/last!/find_by!`
(raise) and `find_by/take/first/last` (nil arm), and on
`ActiveRecord::Core::ClassMethods` `find/find_by/find_by!`.

**`targets.rb` then re-declares every `FinderMethods` finder** with
`finder_mock_with_preloads` (`targets.rb:1001-1065`), whose not-found arm is
`next ConversationsIndexTargets.publish_note(sql)` (`targets.rb:1803`), and
`publish_note` (`targets.rb:591-594`) is exactly the B-8 repair
(`Thread.current[:concolic_pending_note] = sql; nil`). `declare_target`
redefines the method, so the later declaration wins. **Compensated: yes.**

Residue: `ActiveRecord::Core::ClassMethods#find_by` is NOT re-declared in
`targets.rb`, so its bare-`nil` arm is live. Measured over the corpus:
**0 `Core::ClassMethods` finder events of any kind** — the path is dormant, not
exercised. It is a forward risk only.

### people_show — defect present in `concolic_targets.rb`, **NOT compensated**

`concolic_targets.rb:514-527` `finder_mock(raise_on_missing:, kind:)` — same
bare `nil` on the not-found arm. `targets.rb` does not re-declare any finder;
its single `concolic_pending_note` site (`targets.rb:246`) is the `Person#remote?`
pod-boundary mock, unrelated to the finders. **Compensated: no. The defect is
live on `FinderMethods#find_by/take/first/last` and `Core::ClassMethods#find_by`.**

---

## 2. The exposure, measured with the verifying audit

`src/queries_from_runs/audits/noteless_call_audit.py` (the 2026-09-13 verifying
version), run read-only over each batch's own dump directory.

| endpoint | dumps | target-call events | wall targets | EVIDENCED (targets/events/dumps) | **UNVERIFIED (targets/events)** | distinct dumps w/ ≥1 UNVERIFIED | result |
|---|---|---|---|---|---|---|---|
| conversations_index | 18,623 | 530,243 | 3 (88,276 ev) | 0 / 0 / 0 | **0 / 0** | 0 | **pass (exit 0)** |
| people_show | 12,997 | 767,812 | 5 (73,108 ev) | 1 / 716 / 358 | **6 / 58,946** | 9,473 | **RED (exit 1)** |

### conversations_index — the repair is working live, not merely present

Independent census of every finder event in the 18,623-dump corpus:

```
  73,997 SingularAssociation.find_target   falsy 2,496  of which noted 2,496
  37,309 FinderMethods.exists?             falsy 33,906 of which noted 33,906
  22,930 FinderMethods.find_by             falsy 2,158  of which noted 2,158
  21,181 FinderMethods.first               falsy 3,169  of which noted 3,169
  18,623 FinderMethods.devise_user_first   falsy 0
     115 FinderMethods.take                falsy 115    of which noted 115
  ------ 174,155 finder events; 41,844 falsy; NOTED 41,844 / 41,844
```

Every falsy-returning finder call in the corpus carries its statement. That is
`publish_note` firing, measured.

### people_show — what the 58,946 UNVERIFIED events actually are

| target | events | call site | `result_value` | what it is |
|---|---|---|---|---|
| `Stream::Base.post_ids` | 25,462 | `stream/base.rb:85:like_posts_for_stream!` | `[1]` | declared SQL-FREE mock (`concolic_targets.rb:906-910`, `posts.map(&:id)`) — issues no statement |
| `Stream::Base.attach_user_likes` | 25,462 | `stream/base.rb:87:like_posts_for_stream!` | the relation | declared SQL-FREE mock (`concolic_targets.rb:916-921`, inject+each) — issues no statement |
| `ActiveRecord::Relation.records` | 5,210 | `relation.rb:504:blank?` | `[]` (5,210/5,210) | the `NullRelation` early return in `targets.rb:423` (`next [] if receiver.is_a?(NullRelation)`) — real Rails `NullRelation` issues no query. It is the ONLY note-less arm of `rows_mock`; every other return is an `IterableSymbolicList` carrying the note |
| `FinderMethods.first` | 2,081 | 2,073 `mobile_helper.rb:10:mobile_reshare_icon`, 8 `people_controller.rb:132:find_person` | `nil` (2,081/2,081) | **B-8** |
| `FinderMethods.find_by` | 715 | `concolic_targets.rb:1827 ConcolicKwargsToPositional` | `nil` (715/715) | **B-8** |
| `Core::ClassMethods.find_by` | 16 | `concolic_targets.rb:1827 ConcolicKwargsToPositional` | `nil` (16/16) | **B-8** |

**56,134 of the 58,946 issue no SQL by construction** (two documented SQL-free
mocks and the `NullRelation` arm); they are UNVERIFIED only because the audit's
`WALLS` list matches on target-name substrings and these three names are not in
it. **2,812 events are the genuine B-8 defect** — a finder that issued its
statement, got no row, and returned bare `nil`.

---

## 3. Are the B-8-lost statements in the shipped `people_show.sql`? — YES, all of them

The lost note is recoverable because each note-less event carries its call site,
and every one of those sites publishes its statement on the *found* arm
elsewhere in the same corpus. Shapes, from the engine's own record only
(`/home/dev/_reference_locked` NOT consulted):

| call site | note-less | same-site NOTED (same corpus) | shape | in `queries_from_runs/people_show.sql`? |
|---|---|---|---|---|
| `mobile_helper.rb:10 mobile_reshare_icon` | 2,073 | 2,073 | `SELECT "posts".* … type IN (?) AND author_id = ? AND root_guid = <row_guid> ORDER BY posts.id ASC LIMIT ?` | **YES** — lines 184/186/188 (folded with its producer join) |
| `ConcolicKwargsToPositional` (`find_by`) | 715 | 14,175 (4 shapes) | `SELECT "contacts".* … user_id = ? AND person_id = <id> LIMIT ?` and `SELECT "blocks".* … person_id = <id> AND user_id = ? LIMIT ?` | **YES** — lines 258/261 (contacts) and 253/256 (blocks) |
| `people_controller.rb:132 find_person` | 8 | 11,502 | `SELECT "people".* … diaspora_handle = $$(SYM_PARAM_username) ORDER BY people.id ASC LIMIT ?` | **YES** — line 285 `SELECT \`people\`.* FROM \`people\`;` (the fold cannot express the handle predicate; the policy header's FOLD FIDELITY section already declares this class as "views broader, never narrower") |
| `ConcolicKwargsToPositional` (`Core.find_by`) | 16 | 10,767 (2 shapes) | degenerate placeholders: `Like query (class-level finder; WHERE unavailable …)`, `User query (…)` | n/a — see note below |

**No statement shape behind an UNVERIFIED event is absent from the shipped
policy.** For the first three rows the loss is strictly redundant: the same site
published the same shape 2,073 / 14,175 / 11,502 times in the same corpus, and
those shapes are in the file.

**Adjacent finding, NOT B-8, flagged for the owner rather than acted on.** The
`Core::ClassMethods#find_by` notes on this endpoint are degenerate placeholders,
not SQL — `"<Model> query (class-level finder; WHERE unavailable — interceptor
drops kwargs for *rest-signature finder methods called with keyword syntax)"` —
and neither a `users` statement nor a bare `likes` single-row read appears in
`people_show.sql` (`\`users\`` occurs 0 times in the file). That is a Class-S
shape defect affecting **10,767 NOTED events**, dwarfing the 16 note-less ones;
publishing the note for those 16 would recover nothing, because the note itself
carries no statement. Raised here for adjudication; not repaired, not counted in
the B-8 verdict.

---

## 4. Verdict

* **conversations_index (CLOSED 2026-09-01, `conversations_index.sql`, 58 views).**
  The B-8 defect exists in this batch's `concolic_targets.rb`, and it is
  **entirely dead code**: `targets.rb` overrides every exercised finder with a
  `publish_note`-repaired mock, and all 41,844 falsy finder events in the
  corpus carry their statement. Audit GREEN, 0 UNVERIFIED.
  **The shipped policy is not incomplete. No action owed. No status change.**

* **people_show (SET ASIDE 2026-09-07, milestone close-out — per
  `reports/diaspora/README.md:86` and its own POLICY_HEADER this endpoint is
  explicitly NOT closed by the three-check standard; the completion gate never
  ran).** The B-8 defect is **LIVE and unrepaired**: 2,812 finder calls across
  the 12,997-dump corpus issued a statement, got no row, returned bare `nil`,
  and dropped their note. **It cost the policy nothing** — every affected call
  site published the identical shape on its found arm in the same corpus, and
  all three real shapes are in `people_show.sql`.
  **The shipped policy is not incomplete on account of B-8. No status change.**
  The code defect is real and should be repaired before this endpoint is ever
  re-driven (a future scenario mix in which a site's *only* outcome is
  not-found would lose the statement outright).

* Exactly as on notifications_index (§33.C / §33.C.2): the defect is present in
  the code and cost the corpus nothing.

---

## 5. Forward risk — the MASTER template

`reports/diaspora/concolic_targets.rb` (2026-09-04, 78,025 bytes) has **0**
`concolic_pending_note` sites; its `finder_mock` is at `:367-379` and `:374` is
the bare `nil`. No results3 batch requires it (each batch requires its own
`concolic_targets.rb` via `require_relative`), so no shipped corpus is affected.
It is, however, still required by legacy gen-1 runners under
`reports/diaspora/results/contacts_aspects_blocks/` (`run_dse.rb`,
`run_concolic.rb`, `run_phase2.rb`, `run_phase3.rb`) and by probes under
`reports/diaspora/trash/`.

**Risk: a new batch that copies this template inherits an unrepaired B-8 and,
unlike conversations_index, has no `targets.rb` override to compensate — which
is precisely how people_show acquired the live defect.** The one-line repair
(`Thread.current[:concolic_pending_note] = sql` immediately before the `nil` at
`:374`) is a template change, not an endpoint change, and voids nothing.
Left for the owner to authorise; not made here.

---

## Method / provenance

* Audit: `src/queries_from_runs/audits/noteless_call_audit.py`, unmodified,
  run per batch over `<batch>/dump_*.json` (the live corpora: 18,623 and
  12,997 dumps — the `_pre_r*`, `_dup_dumps`, `corpus_anon_backup`,
  `_corpus_dual` sub-directories were NOT scanned).
* Shape recovery and the `result_value` / call-site census: two throwaway
  read-only scripts in the session scratchpad, joining note-less events to the
  NOTED events of the same `(target, file:lineno:function)` in the same corpus.
* All four scans run as `systemd-run --user --slice=concolic-cov.slice
  --no-block --unit=… -p MemoryMax=3G`. Pre-flight: `free -g` 38 free,
  slice MemoryMax 32 GiB − MemoryCurrent 18.9 GB = 15.4 GB headroom.
* Live work undisturbed: `posts-p26-gate-v3-20260914` advanced from probe
  batch 3 to 4 across the scans (its derive-probes stage had already completed
  at rate 1.2/s); `notif-c23-chain` and the posts_show P32 round untouched.
* `/home/dev/_reference_locked` was NOT read. Every judgement above rests on
  the engine's own corpus and the shipped `.sql`.
