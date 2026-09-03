# BOUNDARY FIX DRAFT — 4 Rule T3 fixes in the shared boundary
# File: reports/diaspora/concolic_targets.rb
# Drafted: 2026-09-03 by the coordinator. **NOT APPLIED** — gated until
# notifications_index closes (then applied ONCE, deliberately, before
# people_show). Reference implementations are the verified batch-local
# overrides in results3/notifications_index/targets.rb (lines ~1357-1442),
# which these fixes absorb. After applying, re-run the closed endpoints'
# note checks (TARGET_FUNCTIONS.md "Rule for both") — a projection change
# can move a policy view even where the note count does not.
#
# Fix order below = the order in docs/TARGET_FUNCTIONS.md.

# ===========================================================================
# FIX 1 — Calculations#sum renders a ROW projection (must collapse to SUM)
# ===========================================================================
# Current (line ~462):
#   %i[count sum].each do |m|
#     interceptor.declare_target(calc, m, returns: lambda do |receiver, args, name|
#       vn = "#{name}_#{m}"
#       symint(vn, seed_for(vn, m == :count ? 1 : 0), note: sql_for(receiver, args))
#     end)
#   end
#
# Problem: `sql_for` renders the ROW projection (`SELECT "tbl".* FROM …`)
# for BOTH count and sum. count survives only because every batch overrides
# it locally. sum's real statement is `SELECT SUM("tbl"."col") FROM …`.
#
# Replacement — split the loop, keep count's semantics, add sum's
# AGG-COLLAPSE (ported from results3/notifications_index/targets.rb 5b-iii(b)):
#   %i[count sum].each do |m|
#     interceptor.declare_target(calc, m, returns: lambda do |receiver, args, name|
#       vn = "#{name}_#{m}"
#       note = sql_for(receiver, args)
#       begin
#         if m == :sum
#           vals = args.is_a?(::Hash) ? args.values : Array(args)
#           col = vals.flatten.compact.find { |a| a.is_a?(::Symbol) || a.is_a?(::String) }
#           if col
#             tbl = (receiver.respond_to?(:table_name) && receiver.table_name) ||
#                   (receiver.respond_to?(:klass) && receiver.klass.table_name)
#             proj = tbl ? %(SUM("#{tbl}"."#{col}")) : %(SUM("#{col}"))
#             note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT #{proj} FROM ")
#           else
#             note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT SUM(*) FROM ")
#           end
#         else
#           note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
#         end
#       rescue StandardError
#         nil # projection rewrite must never crash the mock
#       end
#       symint(vn, seed_for(vn, m == :count ? 1 : 0), note: note)
#     end)
#   end
#
# Note: the batch override seeds sum with 0 (seed_for(vn, 0)) — the shared
# version already does (`m == :count ? 1 : 0`). Keep that.
# After applying, the batch-local calc :count / :sum overrides in
# notifications_index/targets.rb become redundant — REMOVE them (and their
# BOUNDARY NOTE comments) in the same change, so the batch no longer masks a
# boundary that is now correct. conversations' 18 306 sum events must re-check
# to `SELECT SUM(…)` shape.

# ===========================================================================
# FIX 3 — Relation#size renders a ROW projection (must be COUNT aggregate)
# ===========================================================================
# Current (line ~456):
#   interceptor.declare_target(rel, :size, returns: lambda do |receiver, args, name|
#     vn = "#{name}_size"
#     symint(vn, seed_for(vn, 1), note: sql_for(receiver, args))
#   end)
#
# Problem: `size` on an UNLOADED relation issues `SELECT COUNT(*)`, but the
# mock notes the ROW projection. notifications: ONE bug produced BOTH the
# OVER on the row SELECT (3x per mobile dump) and the UNDER on the real
# COUNT.
#
# Replacement (ported from results3/notifications_index/targets.rb 5b-iii(c)):
#   interceptor.declare_target(rel, :size, returns: lambda do |receiver, args, name|
#     vn = "#{name}_size"
#     note = sql_for(receiver, args)
#     begin
#       note = note.sub(/\ASELECT\s+(DISTINCT\s+)?.*?\s+FROM /m, "SELECT COUNT(*) FROM ")
#     rescue StandardError
#       nil
#     end
#     symint(vn, seed_for(vn, 1), note: note)
#   end)
#
# Also remove the batch-local :size override in notifications_index/targets.rb
# in the same change (it becomes redundant).

# ===========================================================================
# FIX 2 — gon stub: run the real body, delete the stale justification
# ===========================================================================
# Current (line ~978-995): X6b declares Gon::ControllerHelpers#gon -> a
# hand-rolled gon_stub (preloads Hash + method_missing) justified by
# "gon is out of scope there by the standing layout(false) decision" (stale —
# layout(false) is withdrawn on notifications, never applied on conversations).
#
# Fix: run the real body (gon-6.3.2 helpers.rb:29-37, four lines, no SQL;
# the stated blocker — "needs a RequestStore dump missing in the rig" — is a
# request.uuid that ActionController::TestCase supplies) and delete the stale
# rationale. The AUTH_CHAIN branch or the to_json-at-push behavior is NOT the
# fix (it relocates the presenter's reads out of render order).
#
# Draft (subject to verification against gon-6.3.2 in the rig when applied):
#   if defined?(Gon::ControllerHelpers)
#     # X6b. Real body: gon-6.3.2 helpers.rb:29-37 initialises @_gon_attributes,
#     # pushes via method_missing; issue NO SQL. The old stub's justification
#     # ("layout(false) keeps gon out of scope") is stale — the layout pin is
#     # withdrawn on notifications and never applied on conversations, and the
#     # stated RequestStore blocker is a request.uuid the test case supplies.
#     # Keep the declare_target (the interceptor still must see the call), run
#     # the real body, no no-op stub.
#     interceptor.declare_target(Gon::ControllerHelpers, :gon,
#                                returns: ->(receiver, _args, _name) { receiver.gon })
#   end
# ⚠ The exact body must be read from the vendored gon-6.3.2 helpers.rb at
#   apply time; do NOT guess it. The fix's contract: the real 4-line body runs,
#   issues no SQL, and the interceptor still records the call.
#
# IMPORTANT: Fix 2 interacts with Fix 4 below — the mock that push routes
# through must not be the SUBJECT of the find_target memo. Verify no nesting.

# ===========================================================================
# FIX 4 — SingularAssociation#find_target loaded-target memo (by PREPEND)
# ===========================================================================
# Current (line ~793-805): W3 declares SingularAssociation#find_target ->
# symbolic_instance, no memo. A second read of the same has_one/belongs_to in
# one request re-issues (over-emission; conversations 696 occurrences across
# ONE shape).
#
# Fix: add a per-run loaded-target memo keyed on (owner, reflection), by
# PREPEND, never a second declare_target (which would capture the first
# wrapper as its "original" and nest it).
#
# Draft shape (the memo must live in the shared helper layer; exact wiring
# verified at apply time against how the interceptor exposes per-run state):
#   # In the SingularAssociation reader path, BEFORE the W3 find_target mock:
#   # a per-run memo keyed on [owner.object_id, reflection.name] returning the
#   # SAME symbolic instance for repeated reads of the same association in one
#   # request; the memo clears per run with the interceptor's run state
#   # (matches the CollectionProxy loaded-target memo already in the rig).
#   # Implement by PREPEND to SingularAssociation#find_target — never a
#   # second declare_target on the same method.
#
# ⚠ This one needs the rig's existing per-run memo mechanism (the CollectionProxy
#   loaded-target memo referenced in TARGET_FUNCTIONS.md fix #4's text; see
#   notifications targets.rb §5b-CP) — port its exact keying and clearing.
#
# After applying: conversations' 696-repetition shape must collapse to 1 per
# request; comments stays 0. No view added or removed — multiplicity only.

# ===========================================================================
# VERIFICATION AFTER APPLY (mandatory, in order)
# ===========================================================================
# 1. Re-run conversations_index note-check: sum events → `SELECT SUM(…)` shape
#    (18 306 events), no new/moved policy views. `size` stays 0-invoked.
# 2. Re-run comments_index note-check: unchanged (neither sum nor size
#    invoked; find_target 0 occurrences).
# 3. notifications_index closing pass (already completed — apply fixes AFTER
#    its final report is written; the batch-local overrides removed then only
#    if its corpus is already final; otherwise keep them until the final pass).
# 4. people_show campaign starts with the fixed boundary.