# The DETERMINISTIC target list for every people_show concrete manifest:
# DERIVED FROM THE CORPUS (`targets_from_corpus`, concrete_run_probe.rb:52),
# never hand-authored, plus the concrete forms of the batch-local aliases the
# corpus names. Built 2026-09-19 for the completion-gate build.
#
# NOTE this reads `dump_*.json` out of the batch directory, so it must run
# AFTER the corpus is final — otherwise the ground truth is derived from a
# partial corpus and the differential is measured against the wrong target set.
PS_TARGETS = targets_from_corpus(File.expand_path("..", __FILE__), exclude: {
  # rig-terminal plumbing: no SQL evidence in any corpus run, and alias-wrapping
  # its super chain breaks rendering on this JRuby (comments_index, 2026-08-27;
  # people_stream carries the identical waiver).
  "ActionController::Head.head" => "head terminal; no SQL evidence",
  # MEASURED on people_stream, same rig and same JRuby: the probe wraps a
  # target by re-defining it IN its own module and calling the captured
  # UnboundMethod, and `Instrumentation#redirect_to` is a `super`-chaining
  # decorator — under the wrap its `super` finds no superclass method and the
  # whole scenario dies with NoMethodError. It is a redirect: it issues no
  # statement, so nothing observable is lost.
  "ActionController::Instrumentation.redirect_to" =>
    "super-chaining decorator; breaks under alias-wrap on this JRuby. Redirect terminal, issues no SQL",
}, extra: [
  # Concrete forms of corpus names that do not resolve in the clean app
  # (`Anonymous.name_from_attrs` is Person.name_from_attrs,
  #  `Anonymous.escape_segment` is Journey::Router::Utils.escape_segment,
  #  `Anonymous.build` is ConcreteSymbolicString.build) — plus the finder /
  # materialisation frames `concrete_aliases.json` maps the corpus names onto.
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :find_by!],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :take],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Core::ClassMethods, :find_by],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Calculations, :pluck],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  # A has_many read whose owner key is already loaded goes through AR's
  # StatementCache inside `CollectionAssociation#find_target`, NOT through
  # `Relation#records`, so without these frames such a statement lands
  # "outside any target frame" and the note check is RED for a rig blind spot
  # rather than anything about the corpus (people_stream X7, 2026-09-11). The
  # corpus frames the same read one layer up, via the declared
  # CollectionProxy#records / #load_target.
  [ActiveRecord::Associations::CollectionAssociation, :find_target],
  [ActiveRecord::Associations::CollectionAssociation, :load_target],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
  # the DML the signed-in arm issues (mark_corresponding_notifications_read)
  [ActiveRecord::Persistence, :update_column],
  [ActiveRecord::Persistence, :update_columns],
])
