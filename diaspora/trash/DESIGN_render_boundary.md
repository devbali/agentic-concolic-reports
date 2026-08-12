# DESIGN — Render Boundary (treated as terminal)

**Decision:** Adopted per `ACTION_PLAN_fix_crashes.md` §3.2 (decision A).

## Why (from post-find re-verify data 2026-08-08)
Biggest single wall after the class-find fix is the **render / serialization**
plumbing: `NoMethodError` breaks down as
- `[]` for nil ×36
- `to_hash` for nil ×11

Of the 76 nil-`NoMethodError` crashes, **47 trace to render/serialization**
(`render`, `status=`, `serializable_hash`, `@_response`), 15 to associations,
14 to other. That's more than every `NotImplementedError` bucket combined
(`to_i` 15, `each` 15, `empty?` 10, `hash` 6).

## What the boundary means / how it's honest
Treat `render` / `render_to_string` / `respond_with` as **terminal**: when the
controller action reaches a render call, the harness short-circuits the real
view/serialization machinery and records the render **call event** as the
completion marker. Concolic value lives in controller/service/model logic, not
in templates — so this is *sound*, not just expedient.

- Kills: template lookup (`MissingTemplate`), presenter `each`/`map` over
  SymbolicLists, `status=` on nil `@_response` → devise `inspect` →
  `serializable_hash` → `to_hash`/`[]` for nil.
- The dump's `call` event with target `ActionController::Rendering.render`
  documents that the action reached render. Reports must describe completion
  as "**reached render**", not "rendered a page."

## Mechanism (in `reports/diaspora/concolic_targets.rb`, free layer)
Inside `ConcolicTargets.install!` add a section (Z) that `declare_target`s the
render methods with a `returns:` lambda (`receiver, args, name` form):

```ruby
render_mod = ActionController::Rendering
{render: :render_reached, render_to_string: :render_to_string_reached}.each do |m, marker|
  interceptor.declare_target(render_mod, m, returns: lambda do |receiver, args, name|
    unless receiver.instance_variable_get(:@_response)
      reply = receiver.respond_to?(:reply) ? receiver.reply : nil
      receiver.instance_variable_set(:@_response, reply) if reply
    end
    marker  # Symbol is passed through unchanged by the interceptor
  end)
end
interceptor.declare_target(ActionController::MimeResponds, :respond_with,
  returns: ->(receiver, args, name) { :respond_with_reached })
```

Rationale for `@_response` guard: some controllers write `response.status=` /
headers before/after render; a populated response avoids a nil-`@_response`
crash there. `render`'s own `_process_options` (the source of the status=
crash) is never reached because we skip the body.

## What we deliberately do NOT stub
- `respond_to` (block form used to set formats and select a branch): leaving
  it real lets actions still branch on format. Only `respond_with` (which
  actually renders via the responder) is boundaried.
- Template rendering internals are skipped implicitly by short-circuiting
  render.

## Impact prediction (honest)
This converts the ~47 render/serialization crashes from **incomplete** to
**reached-render complete** on those entrypoints, which should move a large
fraction of the 15 `incomplete` into `complete` (and new PCs may re-classify
some differently). It does NOT touch the unchanged `NotImplementedError`
buckets (`to_i`, `each`, `empty?`, `hash`) — those remain as separate walls.

## Verification
1. Smoke: run `likes_destroy` (the known render/serialization crasher) — should
   now record PCs and complete at render, no `to_hash`/`[]`-for-nil error.
2. Re-run affected batches; re-run engine `CoverageChecker`; compare
   genuine/vacuous/incomplete counts.
3. Confirm dumps still show the render `call` event (honesty marker).
