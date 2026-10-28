# The DETERMINISTIC target list for every people_stream concrete manifest:
# derived from the corpus (targets_from_corpus), never hand-authored, plus the
# concrete forms of the batch-local aliases the corpus names.
PS_TARGETS = targets_from_corpus(File.expand_path("..", __FILE__), exclude: {
  # rig-terminal plumbing: no SQL evidence in any corpus run, and alias-wrapping
  # its super chain breaks rendering on this JRuby (comments_index, 2026-08-27)
  "ActionController::Head.head" => "head terminal; no SQL evidence",
  # MEASURED, not assumed: the probe wraps a target by re-defining it IN its own
  # module and calling the captured UnboundMethod, and `Instrumentation#redirect_to`
  # is a `super`-chaining decorator — under the wrap its `super` finds no
  # superclass method and the whole scenario dies with NoMethodError (first
  # anon_all run, 2026-09-10). Same class as comments_index's `render` waiver.
  # It is a redirect: it issues no statement, so nothing observable is lost.
  "ActionController::Instrumentation.redirect_to" =>
    "super-chaining decorator; breaks under alias-wrap on this JRuby. Redirect terminal, issues no SQL",
}, extra: [
  # concrete forms of corpus names that do not resolve in the clean app
  # (`Anonymous.process` = Diaspora::MessageRenderer::Processor.process,
  #  `Anonymous.escape_segment` = Journey::Router::Utils.escape_segment)
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  # X7 (2026-09-11) — THE FRAME THE `photos` STATEMENT NEVER HAD.
  # `mock_note_check` scored `SELECT "photos".* FROM "photos" WHERE
  # "photos"."status_message_guid" = ?` as "outside any target frame", which is
  # RED whatever the corpus contains: a has_many read whose owner key is already
  # loaded goes through AR's StatementCache inside
  # `CollectionAssociation#find_target`, NOT through `Relation#records`, so no
  # frame on this list ever saw it. In the CORPUS the same logical read is
  # framed one layer up — the batch declares `CollectionProxy#records` /
  # `#load_target` (targets.rb §5b), and `load_target` is what CALLS
  # `find_target` — so the concrete run simply had a blind spot the corpus did
  # not. Naming the deeper frame here closes it; `concrete_aliases.json` maps it
  # to the CollectionProxy/Relation materialisation names the corpus uses.
  [ActiveRecord::Associations::CollectionAssociation, :find_target],
  [ActiveRecord::Associations::CollectionAssociation, :load_target],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
])
