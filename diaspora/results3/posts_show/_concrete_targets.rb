# The DETERMINISTIC target list for every posts_show concrete manifest:
# derived from the corpus (`targets_from_corpus`), never hand-authored, plus
# the concrete forms of the batch-local aliases the corpus names.
#
# WHY A SAMPLE DIRECTORY AND NOT THE BATCH DIR. `targets_from_corpus` globs
# `dump_*.json` and JSON-parses every hit; this batch has 96 000+ dumps, so
# pointing it at the batch would cost ~10 minutes of parsing per scenario.
# `_ctgt_sample/` holds SYMLINKS to a GREEDY SET COVER of the corpus's target
# names, computed over a stride-10 scan of the full snapshot: **4 dumps cover
# all 28 distinct `symbolic_call` targets, with 0 uncovered**. The list this
# produces is therefore identical to the one the whole corpus produces, and it
# is still read off real dumps rather than typed out here.
PSH_TARGETS = targets_from_corpus(File.expand_path("../_ctgt_sample", __FILE__), exclude: {
  # rig-terminal plumbing: no SQL evidence in any corpus run, and alias-wrapping
  # its super chain breaks rendering on this JRuby (comments_index, 2026-08-27)
  "ActionController::Head.head" => "head terminal; no SQL evidence",
  # MEASURED on people_stream (2026-09-10) and inherited with its reason: the
  # probe wraps a target by re-defining it IN its own module and calling the
  # captured UnboundMethod, and `Instrumentation#redirect_to` is a
  # `super`-chaining decorator — under the wrap its `super` finds no superclass
  # method and the scenario dies with NoMethodError. It is a redirect: it
  # issues no statement, so nothing observable is lost.
  "ActionController::Instrumentation.redirect_to" =>
    "super-chaining decorator; breaks under alias-wrap on this JRuby. Redirect terminal, issues no SQL",
}, extra: [
  # Concrete forms of corpus names that do not resolve in the clean app.
  #   `Anonymous.process`        = Diaspora::MessageRenderer::Processor#process
  #   `Anonymous.escape_segment` = ActionDispatch::Journey::Router::Utils.escape_segment
  #   `ActiveRecord::Relation.evilq_<ctx>_<attempt>` and `...findpublic_<ctx>`
  #     are THIS BATCH'S alias_methods of `ActiveRecord::Relation#first`
  #     (targets.rb:795, :801) and exist only under the concolic boundary; the
  #     real body they stand over is `FinderMethods#first`, so that is what the
  #     concrete run must trace.
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :find],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Calculations, :sum],
  [ActiveRecord::Calculations, :ids],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
])
