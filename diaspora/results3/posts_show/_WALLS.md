# posts_show — DECLARED WALLS (2026-09-10, completion drive)

Every wall below is an arm a REAL request can take that this corpus does not,
or takes only partly. Form follows `people_stream/_WALLS.md`: what the wall is
/ why it is declared rather than repaired / POLICY IMPACT / what a consumer
must NOT conclude from the absence.

Measurements are from a stride-12 scan of the 99 448-dump snapshot (8 036
dumps) unless stated otherwise, and every name comparison is routed through the
engine's own load path (`coverage_report.canonicalize_ordinals` +
`fix_len_names`).

---

## W1 — `format.html` NEVER COMPLETES  (the big one; Class B, §12)

**What.** Terminal state by scenario:

```
auth_html  n=2237   ActionView::Template::Error=2061  ActiveRecord::RecordNotFound=176
anon_html  n=2239   ActionView::Template::Error=1433  ActiveRecord::RecordNotFound=268  Diaspora::NonPublic=538
auth_json  n=1862   (none)=1861                       ActiveRecord::RecordNotFound=1
anon_json  n=1698   (none)=1691                       ActiveRecord::RecordNotFound=2    Diaspora::NonPublic=5
```

**ZERO html runs reach the end of the action.** Every `ActionView::Template::
Error` carries one message: `uninitialized constant
PostsTargets::ConcreteSymbolicString`, raised at `targets.rb:666` — the W3b
`to_param` wall mock, on the `post_url @post` / `post_path` metas-render path.

**Why it exists.** A regression, not a design decision. The 2026-09-09 Rule-T
re-sync replaced this batch's `concolic_targets.rb` with a verbatim copy of the
shared boundary, which has never defined `ConcreteSymbolicString`
(`concolic_targets.rb.pre_ruleT_resync` defines it at line 479), and added the
unguarded use in the same change.

**Repaired?** PARTLY. The class is restored batch-locally in `targets.rb`
(2026-09-10) with a ground-truth differential: the same seed goes from
`ActionView::Template::Error: uninitialized constant ...` at `targets.rb:666`
(24 PCs, 119 events) to `NotImplementedError: SymbolicString#scrub is not
supported in the concolic runtime` via
`ActiveSupport::Multibyte::Unicode.tidy_bytes` (25 PCs, 135 events). So the
arm goes further and still does not complete: some other string on the html
render reaches Rails' HTML-escape path without having been upgraded. Closing
it needs one or more further narrow string upgrades — Phase-1 mock work.

**POLICY IMPACT.** `format.html` is one of three render formats and the only
one that runs `gon.post = presenter.with_initial_interactions` and
`render locals: {post: presenter}`. **None of the html view's own reads are in
this policy.** The pre-view statements of the html arm ARE (the finder,
`mark_user_notifications`, the presenter build).

**Do NOT conclude** that `format.html` issues only what this file contains.

---

## W2 — `format.mobile` is not driven at all

**What.** `PostsController` declares `respond_to :html, :mobile, :json` and
`show` has a `format.mobile { render locals: {post: post} }` branch.
`run_dse.rb`'s SCENARIOS are auth/anon x html/json only — there is no mobile
scenario and there never has been on this endpoint.

**Why declared.** Adding a scenario changes the runner and requires a corpus
generation; it was out of scope for this drive, which was directed at the
existing corpus's tree and combination demand.

**POLICY IMPACT.** No statement in this file is attributable to the mobile arm.
Its render is `locals: {post: post}` (the raw post, not the presenter), so its
read set is plausibly a SUBSET of html's — but that is a code reading, not a
measurement, and this file does not rest on it.

**Do NOT conclude** the mobile arm reads nothing.

---

## W3 — `Diaspora::NotMine` is not witnessed

**What.** `rescue_from Diaspora::NotMine { render plain: ..., status: 403 }` is
one of the action's two in-action escapes. 0 of 8 036 sampled dumps terminate
in it.

**POLICY IMPACT.** The handler issues no SQL of its own, but whatever raised
`NotMine` ran first, and this file contains nothing attributable to that path.

---

## W4 — `DiasporaFederation::Discovery::Discovery#fetch_and_save` (network I/O)

**What.** Declared as a target at `targets.rb:608-610` under a coordinator
directive. DISCIPLINE §12 records the diagnosis: `Faraday.default_adapter ==
:typhoeus` -> Ethon -> libcurl through JRuby's JFFI, and the JVM dies on the
first `HttpClient.get` — an ABORT, not an exception, with glibc heap corruption
in the sibling processes, and a nil domain aborting identically.

**Why declared rather than repaired.** It is real network I/O in a rig with no
network, and the failure mode is unrecoverable.

**POLICY IMPACT.** The `retry` arm of
`Person.find_or_fetch_by_identifier` — the second
`by_account_identifier(diaspora_id)` after a webfinger — contributes no
statement to this file. The FIRST attempt does. The shim test for the
batch-local reimplementation covers both arms (100 %) only by applying the same
wall directly (`shim_tests.rb`), which is a rig fact, not a corpus fact.

---

## W5 — the concrete round's html arms (ENVIRONMENT, not the endpoint)

**What.** The Phase-5 concrete round's two html scenarios stop at
`ActionView::Template::Error: couldn't find file 'underscore' ...`.
`app/assets/javascripts/main.js` is a Sprockets bundle with ~40 `//= require`
directives for third-party libraries this stripped checkout does not vendor.

**Why declared rather than stubbed.** A single stub worked mechanically and the
round then failed on `backbone` — one step down the same chain. Stubbing forty
would fabricate a JavaScript environment; shadowing the app's own `main.js`
would change what the view emits. Neither buys a statement: the JS bundle
issues no SQL.

**POLICY IMPACT.** Not on the policy's CONTENT — on its CHECKS. `note_fidelity`
and `hardening_lint` H6 compare corpus notes against what the concrete round
issued, so corpus note shapes that only the html VIEW would issue will be
reported as "never issued by any concrete run". Some of those are this wall,
not over-emission. Note that W1 hides the same reads on the corpus side, for an
unrelated reason.

---

## W6 — `NullRelation` reads (a modelling wall that is FAITHFUL)

**What.** `targets.rb`'s `rows_mock` returns a length-0 list for an
`ActiveRecord::NullRelation` receiver, ignoring any seed.

**Why it is not a defect.** `NullRelation` is what `.none` returns and its
`to_a` really is `[]`, so a real run cannot produce a non-empty result there
either. It is the reason three of the seven pins exist (ARGUMENT P1).

**POLICY IMPACT.** None on statements — a NullRelation issues no SQL, and its
note says so. It removes three branch outcomes from the demand.

---

## W1 — SUPERSEDED 2026-09-10 21:00 UTC (see `_COMPLETION_20260910.md` §46)

The wall above is HISTORY as of the §46 repairs, and this note is appended
rather than editing it because the numbers in it describe the corpus that
actually exists on disk for every dump written before 2026-09-10 21:00 UTC.

**The arm now completes.** Three strings reached Rails' HTML-escape path and
were carried render-safe (`MessageRenderer::Processor.process`,
`MessageRenderer#title`, `Photo#url` — NOT `Person#name`, which §42 had named
from the last CALL event and whose wrap measured as a byte-identical no-op).
Four-variant smoke, 48 runs: 0 `ActionView::Template::Error`, 0 rig terminals,
every terminal an application terminal.

**What a consumer must still not conclude.** A policy extracted from any
snapshot dated before that timestamp contains NO html view read, for the reason
W1 gives. Whether a given policy file does is answered by its own POLICY_HEADER
extraction line and by §48's measurement.

---

## W7 — `MessageRenderer#title` and `Photo#url` record NO comparison

**What.** Both are declared SQL-free display targets whose value the MOCK
invents (a constant title; a URL assembled from the variable's own name). They
are carried in `ConcreteSymbolicString`, a real `::String` subclass, so the
render works and **no `==` / `!=` over them is recorded**.

**Why declared, not repaired and not pinned.** Recording them would mint
decisions whose outcome is fixed by this file rather than by the program — a
permanently one-sided expression, and then a pin whose argument is about the
mock. That is the direction DISCIPLINE exists to prevent. The honest statement
is that the real `MessageRenderer#title` extracts a heading FROM THE POST TEXT
and the real `Photo#url` is built FROM THE PHOTO ROW, and neither dependency is
modelled here.

**POLICY IMPACT.** None on statements (both are SQL-free). It costs WHERE
precision on any predicate a caller might build over a title or a photo URL —
this corpus contains no such predicate.

**Contrast, and it is the point:** the same question on the post TEXT was
answered the other way. There the mock's two-valued constant was WIDENED (W10,
`_text_empty`) instead of pinned, because an empty post is a real diaspora
state — and widening it opened the `posts.show.photos_by` arm and closed a tree
gap by driving. A mock constant gets a declared gap; a modellable app state
gets a dimension.

---

## W8 — `CollectionProxy#size` is a seeded `SymbolicInt`, not a real count

**What.** `targets.rb` W11 declares `size` on
`ActiveRecord::Associations::CollectionProxy`, returning the same seeded
`SymbolicInt` (under the same rewritten `SELECT COUNT(*)` note) that the
boundary's `Relation#size` mock returns.

**Why.** `CollectionProxy` OVERRIDES `size`, so the boundary's Relation
declaration never fired on an association and the real body ran
`unsaved_records.size + count_records` — `Integer + SymbolicInt`, which reflects
onto `SymbolicInt#coerce`, refused BY DESIGN by the runtime. Measured: with
W10's empty text seeded, `posts_helper.rb:17` takes the `post.photos.size` arm
and the run dies exactly there.

**Faithfulness, stated exactly.** `unsaved_records` is always `[]` in this rig
(nothing is built unsaved), so the real `size` IS `count_records`, and the mock
is exact for that. What is NOT modelled is any relationship between this count
and the length of the same association's `records` list — they are independent
seeded dimensions, so a run can record `size = 4` and iterate 1 row.

**POLICY IMPACT.** The COUNT(*) statement is emitted with its note, so the
statement is in the policy. The count VALUE is a seed, not a fact.
