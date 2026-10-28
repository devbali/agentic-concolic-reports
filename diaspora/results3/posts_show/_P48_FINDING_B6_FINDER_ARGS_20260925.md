# B-6 — posts_show's note renderer DROPS every finder's own conditions

**Found 2026-09-25 21:40 by the step-7 cheap checks on the fresh v2 corpus.**
**BLOCKING. Needs an owner decision, because the repair requires a re-drive.**

---

## 1. The symptom

After steps 3 and 4 (ctgt_sample + concrete_run rebuilt), `mock_note_check` on a
20 000-dump stratified sample of v2 has exactly **three** RED shapes left, all
`ActiveRecord::Relation.records`, all tagged `auth-html` / `auth-json`:

```
real: SELECT "likes".* FROM "likes"
        WHERE target_id=? AND target_type=? AND positive=? AND "likes"."author_id" = ? LIMIT ?
note: SELECT "likes".* FROM "likes"
        WHERE target_id=$$(…) AND target_type='Post' AND positive=true

real: SELECT "poll_participations".* FROM "poll_participations"
        WHERE poll_id=? AND "poll_participations"."author_id" = ? LIMIT ?
note: SELECT "poll_participations".* FROM "poll_participations"
        WHERE poll_id=$$(assoc_poll_id)

real: SELECT "posts".* FROM "posts"
        WHERE type IN ('Reshare') AND root_guid=? AND "posts"."author_id" = ? LIMIT ?
note: SELECT "posts".* FROM "posts"
        WHERE type IN ('Reshare') AND root_guid=$$(…)
```

The same three are the only remaining `PRED-OP-DIFF` in `note_fidelity`.

**In every case the note is the receiver relation, and the finder's OWN
condition — `author_id` — is missing.**

## 2. The mechanism — verified, not inferred

All three come from the same app shape (`app/models/post.rb:136-144`,
`app/models/poll.rb:36`), reached from `PostPresenter#build_interactions_json`
via `with_interactions` / `with_initial_interactions`:

```ruby
def reshare_for(user) = reshares.find_by(author_id: user.person.id)
def like_for(user)    = likes.find_by(author_id: user.person.id)
def participation_answer(user) = poll_participations.find_by(author_id: user.person.id)
```

`find_by` IS a declared target and IS firing — measured at **10 000 of the
20 000 sampled dumps, i.e. exactly the auth half** (`return unless user` makes
it anon-free, and the sample is 5 000 auth_html + 5 000 auth_json).

posts_show's renderer, `concolic_targets.rb:158`:

```ruby
def sql_for(receiver, args)
  if receiver.is_a?(Class)
    return "#{receiver.name} query (class-level finder), args=#{render_args(args)}"
  end
  render_relation_sql(receiver)      # <-- `args` is DROPPED on the relation path
end
```

On a Relation receiver **`args` is never used**. So `likes.find_by(author_id: X)`
renders only the `likes` relation, and the condition `find_by` itself supplies
never reaches the note.

## 3. THIS IS A MISSING BACK-PORT, NOT A NEW FIX

Four of the other five endpoints have carried the repair since **2026-08-21**
("the severed contacts chain"). Their `sql_for`:

```ruby
def sql_for(receiver, args)
  return class_finder_sql(receiver, args) if receiver.is_a?(Class)
  base = render_relation_sql(receiver)
  # Statement-shape fidelity (2026-08-21, the severed contacts chain):
  # `relation.find_by(conditions)` … carries its WHERE in ARGS, which the
  # Relation branch never rendered: the note collapsed to the bare relation SQL
  # (`SELECT "contacts".* FROM "contacts"`), severing the producer chain …
  extra = relation_args_where(receiver, args)
  extra ? (base.include?(" WHERE ") ? "#{base} AND #{extra}" : "#{base} WHERE #{extra}") : base
end
```

That comment describes posts_show's current bug **exactly**.

### Which endpoints have the machinery

| endpoint | `sql_for` folds args | `relation_args_where` | `class_finder_sql` | `ConcolicKwargsToPositional` |
|---|---|---|---|---|
| comments_index | YES | 1 | 1 | 7 |
| people_stream | YES | 1 | 1 | 5 |
| notifications_index | YES | — | — | — |
| conversations_index | YES | — | — | — |
| **people_show** | no | **0** | 1 | — |
| **posts_show** | **no** | **0** | **0** | **0** |

**posts_show has none of it.** It is also the only endpoint whose class-level
finder note is a prose string (`"<Model> query (class-level finder), args=…"`)
rather than real SQL.

Most likely cause: the **2026-09-09 Rule-T re-sync** that made posts_show's copy
verbatim from the shared boundary. That same re-sync is already known to have
silently deleted a local definition here — it dropped `ConcreteSymbolicString`
and cost 41 998 html crashes. This looks like the same event dropping a second
local repair.

### Possible second casualty — NOT investigated, flagged only

`people_show` also lacks `relation_args_where`, and its documented T2 status is
*"policy has a known Class-S gap: no `users` statement despite the endpoint
reading users."* A renderer that drops finder conditions is a plausible root
cause for a missing statement. **Someone should check this independently; it is
not a posts_show question.**

## 4. Why it BLOCKS, and why it is not cosmetic

* It is the **sole remaining `mock_note_check` RED**. That check has **no
  waiver hook** — the handoff §6 records that its "or a waiver" text at :209 is
  prose that still sets `red = True`, and DISCIPLINE.md §9 forbids one by name.
  **Its REDs must be minted, not argued.** So v2 cannot reach `complete:true`.
* The handoff §7A measured the related B-1 gap as "not blocking" **on the OLD
  corpus**. That measurement no longer holds: with the ctgt_sample and
  concrete_run repaired, this is what is left.
* **It is a policy-soundness defect, not just a fidelity one.** The dropped
  conjunct is `author_id = <the signed-in user>` — a **principal** predicate.
  A policy that says

      SELECT likes.* WHERE target_id=? AND target_type=? AND positive=?

  claims posts_show discloses **every like on a post**. The endpoint actually
  discloses **only the viewer's own** like. That is real over-disclosure in the
  extracted policy, it inflates the statement set, and it is exactly what the
  benchmark's `disclosure_precision` measures. The same argument applies to
  reshares and poll participations.

## 5. The cost — and why it is a decision, not a task

**Notes are baked into dumps at exploration time.** No check-side or
extraction-side change can repair them; this is the same property that made B-4
unfixable in place. So the repair implies **regenerating the corpus again** —
a v3 drive, ~10-12 h wall for stage 1 plus ~1 h to redo steps 3/4/7.

Mixing note generations in one corpus is not an option: handoff §3a calls that
"exactly the B-4 mistake", and it is why attempt 1's 83 dumps were set aside.

### Options

**A. Back-port the repair and re-drive (v3).** ~12 h. Yields correct notes,
clears the last `mock_note_check` RED, and — more importantly — makes the
extracted policy carry the principal predicate. **Recommended.**

**B. Ship v2 with the three shapes declared.** **Not available**:
`mock_note_check` has no waiver hook, so this does not reach `complete:true`.

**C. Drive a supplementary auth-only set with the fix and merge.** **Rejected**
— it produces a corpus where some dumps carry the conjunct and some do not, so
footprints and call-shapes disagree across the corpus. That is the B-4 failure
mode with a different cause.

## 6. Status

**NOT APPLIED. Awaiting an owner decision.** Nothing has been edited.

The back-port would be **batch-local** to
`results3/posts_show/concolic_targets.rb` — the category the standing rules
explicitly permit — and would bring posts_show INTO line with the existing
shared boundary rather than changing it. It is therefore not read as a Rule T
boundary change. The pieces to port from `people_stream/concolic_targets.rb`
are `class_finder_sql`, `relation_args_where`, `extract_finder_where`,
`default_projection`, and the `ConcolicKwargsToPositional` shim that supplies
`Thread.current[:concolic_finder_conds]` (the interceptor's param binding drops
the re-packed hash on this Ruby, so the thread-local is load-bearing, not
belt-and-braces).

**Before spending 12 h, the fix should be proven on a bounded differential**
— the `_p46_diff.sh` harness with a `_p48_cand` copy, ~60 dumps, the same
method that validated each of the ten B-4-era fixes: assert the three notes
gain the `author_id` conjunct, and assert path conditions are unchanged.
