# MOCK CHECKER manifest — comments_index (RUNBOOK Phase 1 gate).
# Run: JRUBY_OPTS=--debug scripts/diaspora-concolic \
#        /abs/src/ruby_runtime/completion_checker/mock_checker.rb <this file>
MOCK_PROBES = [
  # shim mock: pure name computation used by presenters (same probe as
  # notifications — both branches for M2's 100%).
  { kind: :shim,
    name: "person-name_from_attrs",
    targets: [[ActiveRecord::FinderMethods, :find_by],
              [ActiveRecord::FinderMethods, :first],
              [ActiveRecord::Associations::SingularAssociation, :find_target]],
    coverage_of: [Person, :name_from_attrs, :singleton],
    fixture: -> {
      Person.name_from_attrs("a", "b", "h@x")
      Person.name_from_attrs("", "", "h@x")
    } },

  # target mock note shape: the mention-lookup finder (the violation-6 port
  # on this batch renders the WHERE via the thread-local; note must match
  # the real statement).
  { kind: :target_note,
    name: "mention-lookup-find_by",
    real_sql: -> { Person.where(diaspora_handle: "concolic_mention@example.org").to_sql },
    note: %(SELECT "people".* FROM "people" WHERE "people"."diaspora_handle" = 'concolic_mention@example.org') },

  # target mock note shape: the post fetch by id (id-branch of the
  # guid-vs-id length dispatch).
  { kind: :target_note,
    name: "post-fetch-by-id",
    real_sql: -> { Post.where(id: 5).to_sql },
    note: %(SELECT "posts".* FROM "posts" WHERE "posts"."id" = $$(SYM_PARAM_post_id)) },

  # target mock note shape: the comments list relation (materialize mock's
  # sql_for render vs the real relation SQL).
  { kind: :target_note,
    name: "comments-for-post",
    real_sql: -> { p = Post.new; p.id = 7; p.comments.to_sql },
    note: %(SELECT "comments".* FROM "comments" WHERE "comments"."commentable_id" = $$(X) AND "comments"."commentable_type" = 'Post') },
]
