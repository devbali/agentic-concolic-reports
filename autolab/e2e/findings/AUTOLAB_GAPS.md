# Gaps in the auto lab itself — measured, and deliberately NOT repaired

What was changed is in `fixes/`; this is what was left alone and why.

**Regenerated 2026-10-03** after the original was deleted on 2026-09-30 (see
`SRC_NEW_DEFECTS.md`'s header). Every number below is **re-derived today**
from the surviving `INVENTORY.json` and the 161 `runs/<id>/` dump sets, except
where it says otherwise.

---

## G-1 — the per-dump type table (§5.2) is empty for every candidate endpoint

**Re-derived today**, counting the `types` key in every surviving round-2 dump:

| | dumps | carries a type table |
|---|---:|---|
| the 2 gold endpoints (`comments_index`, `aspect_memberships_create`) | 40 | 36 of 40 |
| every candidate endpoint | **800** | **0 of 800** |

**Why.** `ConcolicTargets.symbolic_instance` mints one symbol per column but
declares no type. The wrapper that does — `concolic_type_name` plus
`SymbolicFunc.register_type(tname, decl)` — is installed only by the two gold
endpoints' own layers, each of which explains that it lives there because the
core is "this batch's PRIVATE, byte-identical copy of the shared boundary".
That reasoning was about a *copy*; `targets/core.rb` is now the shared
original, so the argument no longer applies to it. Every candidate endpoint
emits `obj<?>` where the model class is perfectly well known.

**Why it was NOT fixed.** Declaring a type turns `obj<?>` into a CONTRACT that
`validate_provenance` then enforces. FIX-11 and FIX-14 are both what that
enforcement looks like when something else is subtly wrong, and between them
they cost 11 endpoints' dumps across the two rounds. Turning the contract on
for 159 endpoints in the same round as fourteen other repairs would have made
any refusal impossible to attribute. **It should be its own round, watching
`dump_ir` only.**

**What it would take.** Lift the wrapper into `targets/core.rb`'s
`symbolic_instance` — which means changing the results4 gold too, since the
file is asserted byte-identical to it (`fixes/SHARED_BOUNDARY_DECISION.md`) —
delete the two now-redundant copies, and re-sweep.

---

## G-2 — `IterableSymbolicList`'s two decisions are attributed to the driver

Not a defect found, but a consequence of FIX-9 the next reader should see
stated. The `each`/`map` the driver prepends onto `SymbolicList` record
`(len(X) != 0)` from inside the runtime shim, so the path condition's frame
points at `autolab_dse.rb` rather than at the application line that iterates.
That is the same choice both gold layers make and the same canonical
expression the runtime's own `any?`/`none?` record, so it is consistent — but
a reader of a candidate endpoint's dump will see a decision attributed to the
rig.

---

## G-3 — three endpoints need a NESTED symbolic param

`ActionController::ParameterMissing` on `params.require(:user)` and friends.
FIX-8 (scan the controller's own private helpers) **did** give these endpoints
a symbolic `user` / `invite` input — it is in their `config.json` now — but the
param is a **hash** that `.permit(...)` is called on, and the scaffold's input
model is flat symbolic strings. Making `:user` "symbolic" as a string does not
satisfy `require(:user).permit(...)`.

Repairing it is a scaffold **design** change — a typed nested input — not a
scan widening, and it is recorded here rather than attempted.

---

## G-4 — the ActiveStorage endpoints are not drivable, and the lab is not why

**Re-derived today** from `INVENTORY.json`: 3 of the 5 are among the 38
zero-reach endpoints, stopping at

```
NoMethodError  undefined method `url_expires_in' for nil:NilClass
  activestorage-5.2.4.3/app/controllers/active_storage/blobs_controller.rb:11
NoMethodError  …/direct_uploads_controller.rb:14
NameError      uninitialized constant ActiveStorage::IntegrityError
  …/disk_controller.rb:19
```

`ActiveStorage::Blob.service` is nil, and that was measured in the
application, not guessed: there is **no `config/storage.yml`**, no environment
sets `config.active_storage.service` (production included), the app uploads
with CarrierWave (`Gemfile:81`), and the routes exist only because
`config/application.rb:5` is `require 'rails/all'`, which mounts the
ActiveStorage engine.

So these are Rails engine routes this deployment never configured, behaving
the same way in production. The recommendation is to mark them out of scope in
`entrypoints/manifest.json` with this evidence attached, **not** to mock a
storage service into existence.

---

## G-5 — a create endpoint records "ActiveRecord issues no statement" eight times

**Re-derived today** — `reshares_create`'s note census: 41 `select`, **8
`prose`**, every prose one identical and on `ActiveRecord::Base#save!`:

```
Reshare#save! (no changed attributes; ActiveRecord issues no statement)
```

**What the endpoint really does.** `ResharesController#create` calls
`reshare_service.create(params[:root_guid])`, and
`app/services/reshare_service.rb` ends in `user.reshare!(post)` — it creates a
Reshare. Real ActiveRecord issues an `INSERT`.

**The mechanism, read from the library.** `targets/core.rb` substitutes that
prose whenever `dml_note` returns nil, and `dml_note` returns nil in exactly
one case: the record is **not new** and `dml_changed_names` is empty. The
comment there is careful and correct about its own case — "a `save` with
nothing to write. Real ActiveRecord skips the statement entirely … a note here
would FABRICATE a statement".

**So the note is true about the object the mock produced and false about what
the application does.** Which of those two is the defect I did **not**
determine, then or now: I have not traced `user.reshare!` to see whether the
Reshare it builds is a real new record that something later pins as persisted,
or a symbolic instance minted persisted from the start (several mocks do set
`persisted? => true` deliberately, including FIX-4's own devise user).
Establishing that needs a probe I did not run.

**Why it matters beyond one endpoint.** This is the shape the shakedown's
write-note work was about — a write endpoint whose corpus contains no evidence
of writing. The shakedown could only see it on the 2 endpoints that reached a
write at all; round 2 reaches writes on **23**, so this is the first
opportunity anyone has had to look. The corpus-wide census is 862 `select`, 88
`write`, **30 `prose`**, 0 `absent` — the 30 prose notes are where to look
next, and every one should be checked before the write notes are trusted.

---

## G-6 — one endpoint's single run does not terminate inside the time budget

`users_auth_token` hit the sweep's 900 s run timeout. `TIME_BUDGET` is 300 s,
and the budget is only checked *between* runs, so one run ran past it. It
still produced 3 dumps that the pipeline processed cleanly (reach 2, 3 path
conditions, every stage `ok`), and the scope was reaped by the sweep's
named-unit cleanup. The timeout cost depth, not the endpoint. Not diagnosed.
