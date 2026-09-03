# results2/conversations_index — rerun with symbolic entrypoint arguments

(Report authored by the batch agent; saved by the coordinating session.)

96 dumps over 4 request variants (html/json × with/without
`params[:conversation_id]`, the param symbolic as `SYM_PARAM_conversation_id`),
signed-in, fully symbolic identity, scoped associations. Zero errors.

## Acceptance test — PASSED

From `dump_html_plain_dse0001.json` (real app code, not a shim):

```
SELECT  "conversation_visibilities".* FROM "conversation_visibilities" WHERE "conversation_visibilities"."person_id" = $$(SYM_PERSON_CONV_id) ORDER BY conversations.updated_at DESC LIMIT 15 OFFSET 0
```

## Symbolic identity (all five source-batch pins removed)

`person.id` → `SYM_PERSON_CONV_id`; `user.id` → `SYM_USER_CONV_id`;
`person_id`/`guid`/`diaspora_handle` resolve through the real
`delegate ... to: :person` (no override needed). id/person_id exercised and
symbolic in every dump; guid/handle wired but genuinely unreached by this
action. `user.person` remains a stand-in object (AR's has_one can't resolve
on an allocated owner) — its id is fully symbolic.

## Association scoping (source batch was fully unscoped)

- `user.contacts` → `Contact.where(user_id: user.id)` — verified
  `"contacts"."user_id" = $$(SYM_USER_CONV_id) AND sharing = true AND receiving = true`.
- `Conversation#conversation_visibilities` → scoped by conversation id —
  verified `conversation_id = $$(SYM_RESULT_..._first_1_id) AND person_id = $$(SYM_PERSON_CONV_id) AND (unread > 0)`.
- `Conversation#messages` → scoped by conversation id (verified bind).
- `ConversationVisibility#conversation` → real finder
  (`Conversation.where(id: conversation_id).first`) — a genuinely NEW branch
  (`first_3_not_found` observed both ways) that the source batch's
  fixed-instance version never recorded.
- `participants` / `user.conversations` rescoped for parity; unreached by
  index. Nothing reachable was left unscoped.

## Private-copy runtime fix — bind-rotation ROOT CAUSE (raise to Bali)

`collect_binds`'s `instance_variables` walk assumes JRuby preserves ivar
order; for `Arel::Nodes::SelectStatement` it does not (observed
`[:@limit, :@lock, :@offset, :@cores, ...]` vs definition order, arel-9.0.0),
so a paginated symbolic query rendered
`person_id = 15 ... LIMIT 0 OFFSET $$(SYM_PERSON_CONV_id)`. Rendering-only
(PC recording unaffected) but corrupts the `$$()` audit trail. Fixed in THIS
DIRECTORY's private `concolic_targets.rb` by traversing
`SelectStatement`/`SelectCore` children in ToSql render order. Every older
batch pairing symbolic WHERE values with paginate/limit/offset is silently
affected (concrete pins made it invisible).

## Coverage

```
coverage_complete: true, tree_nodes: 30, missing_branches: 0,
total_runs: 96, total_path_conditions: 556, genuine, zero dump errors,
assumptions: [] (none needed)
```

## Honest exploration accounting

The runner's single LIFO stack has no fairness across variant roots: pass 1
(MAX_RUNS=3000) spent the whole budget on `json_withcid`; passes 2-3 used a
`VARIANTS=` filter to cover the rest. Drained: `html_plain` only; the other
three variants have untried stack tails. `coverage_complete: true` means
every DISCOVERED node has both sides observed — not a proven exploration
fixpoint. Tree growth was saturating (late paths added fewer, shallower
PCs), so the result is judged confident but the LIFO-fairness gap is flagged
for a future `run_dse.rb` refactor (per-variant queues, round-robin).

## Truthiness note (documented, not new)

`no_contacts: current_user.contacts.mutual.empty?` evaluates for real (its
scoped query + symbolic_call recorded) but yields no PC: the result lands in
`render locals:` and the body-skipped render/Haml never branches on it — the
render-boundary limitation from the main README.
