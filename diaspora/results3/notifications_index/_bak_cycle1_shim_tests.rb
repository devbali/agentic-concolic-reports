# Agent-provided shim test bodies for notifications_index — keys ENUMERATED
# BY THE ENGINE (shim_extractor output); a key missing here is a NO-TEST red.
# Waivers carry a one-line reason (byte-faithful naming prepends / session
# plumbing / rep plumbing / pure leaf slices — never over app logic that can
# reach a target).
#
# NOTE on the extractor (engine limitation): for `Owner.prepend(Module)` it
# enumerates only the module's FIRST method. Every prepended module here is
# single-method or its extra methods are listed anyway so the reasoning is on
# file.

AR_TARGETS = [
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :find],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :last],
  [ActiveRecord::FinderMethods, :take],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Calculations, :sum],
  [ActiveRecord::Calculations, :pluck],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Relation, :to_ary],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
]

SHIM_TESTS = {
  # --- REAL app-code shim: Person.name_from_attrs replaces the removed
  #     Person#name TARGET mock (concolic_targets.rb X6i). Real body
  #     (name_from_attrs prepend) is pure string logic reaching ZERO targets,
  #     with ONE conditional (both names blank -> handle; else the name).
  #     Both branches probed.
  "Person.singleton_class.name_from_attrs" => {
    targets: AR_TARGETS,
    coverage_of: [Person, :name_from_attrs, :singleton],
    fixture: -> {
      Person.name_from_attrs("Alice", " A ", "alice@localhost")   # non-blank branch
      Person.name_from_attrs("", "", "alice@localhost")           # blank -> handle branch
    } },

  # --- asset-path resolution provisioning (sprockets can't resolve the JS
  #     bundle chain in the rig). Pure string interpolation, zero targets;
  #     the zero-target probe is the contract, coverage of a one-line body is
  #     not a meaningful bar.
  "helper_proxy.singleton_class.compute_asset_path" =>
    { waiver: "environment provisioning prepend (sprockets cannot resolve the JS bundle chain — 'underscore' — in the rig): the shim body is a static '/assets/<src>' interpolation reaching no target; the REAL underlying method it replaces is sprockets asset resolution, which is not app query logic and is not installed in the shim-test runner (so the probe would exercise real sprockets and its FileNotFound env gap, not the shim). Pure leaf, env provisioning" },
  "ActionView::Base.compute_asset_path" =>
    { waiver: "asset-path provisioning prepend (same module as helper_proxy.compute_asset_path); framework body, static asset string, reaches no target" },

  # --- symbolic-rep attribute plumbing: replaces AR attribute machinery so
  #     column reads mint symbolic vars; evidence flows through the attr vars.
  "obj.read_attribute"   => { waiver: "rep attribute plumbing (symbolic var minting); evidence = attr vars" },
  "obj._read_attribute"  => { waiver: "rep attribute plumbing; see obj.read_attribute" },
  "obj.concolic_attrs"   => { waiver: "rep introspection accessor (runtime-internal, no app counterpart)" },
  "obj.concolic_note"    => { waiver: "rep introspection accessor (runtime-internal)" },
  "obj.attributes"       => { waiver: "rep attribute plumbing (to_hash); see obj.read_attribute" },
  "obj.write_attribute"  => { waiver: "rep attribute plumbing (write side)" },
  "obj._write_attribute" => { waiver: "rep attribute plumbing (write side)" },
  "obj.inspect"          => { waiver: "debug rendering only; no evidence, no branches consumed" },
  "obj.image_url"        => { waiver: "Profile#image_url per-instance pin to a static asset path (concolic_targets.rb:511); display-only URL, reaches no target; the real column/camo branches are display-only, out of query scope" },
  "obj.hidden_shareables" => { waiver: "serialized-column default ({}); real body is a serialize cast, reaches no target; not query-relevant" },
  "obj.post_location"    => { waiver: "presenter display hash default (Reshare shape); pure, reaches no target" },

  # --- seeded, PC-recorded boundary decisions (evidence IS the PC), not shims
  #     over app logic.
  "obj.persisted?"  => { waiver: "seeded PC-recorded boundary decision (evidence = the _persisted PC); AR state reader, not app logic" },
  "obj.new_record?" => { waiver: "same decision as obj.persisted? (negated reader over the one _persisted var)" },

  # --- STI / polymorphic type pins (concrete values so constantize/is_a?/
  #     Hash#key/Array#include? behave; TypeLinkedString records the linking
  #     PC on the type var). Readers, not app logic.
  "obj.type"                   => { waiver: "STI type pin reader (TypeLinkedString concrete value; its own ==/!= record the type PC); reader, not app logic" },
  "obj.mentions_container_type" => { waiver: "polymorphic Mention container-type pin (concrete class string for compute_type/constantize); reader, not app logic" },
  "obj.commentable_type"       => { waiver: "polymorphic Comment commentable-type pin (concrete 'Post'); reader, not app logic" },
  "obj.guid"                   => { waiver: "Mention/Comment guid anchor leaf pin (render-safe ConcreteSymbolicString; no branchable compare on these guids on this endpoint)" },

  # --- User plumbing pins (set_locale / set_grammatical_gender walls;
  #     identity/query-irrelevant).
  "obj.language" => { waiver: "User#language plumbing pin ('en'); before_action I18n.locale wall, not identity/query column" },
  "obj.gender"   => { waiver: "User#gender plumbing pin (''); SymbolicString#tr wall in set_grammatical_gender, not identity/query column" },

  # --- signed-in Devise plumbing (NotifDeviseUserNaming): the session user is
  #     resolved through REAL Devise so the users + has_one :person lookups
  #     mint corpus notes (D1). None is a mock over endpoint logic.
  "u.persisted?"  => { waiver: "session-user resolution pin: Devise middleware guarantees a persisted user reaches the action; boolean literal, reaches no target" },
  "u.new_record?" => { waiver: "session-user resolution pin (negation of u.persisted?)" },
  "u.unread_notifications" => { waiver: "manual scoping of has_many :notifications + .where(unread:true) on the symbolic Devise user (the real reader cannot build a scope off a symbolic owner id on an allocated instance); SAME SQL shape the association issues, consumed by the declared count target BY DESIGN (D1-equivalent)" },
  "User.authenticatable_salt" => { waiver: "leaf shim: Devise's real body is a pure encrypted_password[0,29] string slice, reaches no target function; validated in notifications/comments/conversations" },
  "OrmAdapter::ActiveRecord.DYNAMIC" => { waiver: "OrmAdapterGetNaming prepend; byte-faithful orm_adapter-0.5.0 #get (klass.where(pk=>id).first), routes the one .first to the devise_user_first declared target BY DESIGN (the aliased finder mints the users note)" },

  # --- Gon.preloads: JS-var accumulation accessor (class-level); pure, no SQL,
  #     not branchable. The ContactPresenter descent it guards runs for real.
  "::Gon.singleton_class.preloads" => { waiver: "class-level Gon.preloads accessor (JS-var accumulation memo); no SQL, not branchable" },

  # --- CollectionAssociation#size coerce-leaf: routes 0 + count_records to the
  #     declared count target (reflected SymbolicInt arithmetic is unsupported);
  #     super otherwise. Consumed by the declared target BY DESIGN.
  "ActiveRecord::Associations::CollectionAssociation.size" =>
    { waiver: "size coerce-leaf: returns count_records (the declared Calculations#count target) when the in-memory target is empty, super otherwise; consumed by the declared target BY DESIGN" },

  # --- Relation#pluck prepend: captures the pluck column list (interceptor's
  #     *rest binding drops it) then super = the declared pluck target.
  "ActiveRecord::Relation.pluck" =>
    { waiver: "pluck-column capture prepend (thread-local stash for the projection; interceptor param binding drops splat cols); super = the declared pluck target" },

  # --- shared kwargs re-pack prepend (violation-6 fix), tagged value_class.
  "ActiveRecord::Base.singleton_class.DYNAMIC" =>
    { waiver: "shared ConcolicKwargsToPositional prepend (kwargs re-pack + thread-local conditions stash; violation-6 fix)" },
  "ActiveRecord::Relation.DYNAMIC" =>
    { waiver: "shared ConcolicKwargsToPositional prepend (Relation copy)" },
}
