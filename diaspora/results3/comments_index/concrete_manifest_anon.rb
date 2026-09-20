# CONCRETE CHECKER manifest — comments_index, ANON scenario (public post).
# Real sqlite DB, real rows, real dispatch; no mocks, no stubs. One
# scenario per manifest (JVM crash isolation — the mention path can abort
# natively on this JRuby).
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../_c12/exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

# fixtures
CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0)
CE.insert("people", id: 1, guid: "aliceguid", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
CE.insert("people", id: 2, guid: "bobguid", diaspora_handle: "bob@remote.example",
          serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0)
CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
          text: "a public post", public: 1, comments_count: 2)
CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid1", text: "plain comment")
CE.insert("comments", id: 301, commentable_id: 100, commentable_type: "Post",
          author_id: 1, guid: "cguid2", text: "hi @{bob@remote.example} nice")
# cycle 1: a REAL mention row on the mention-bearing comment, so the
# persisted branch of MentionsContainer#mentioned_people (mentions ->
# people -> profiles preload chain) is exercised with data, not just an
# empty mentions read.
CE.insert("mentions", id: 900, mentions_container_id: 301,
          mentions_container_type: "Comment", person_id: 2)
# cycle 3 (adversary W1): a comment whose text carries diaspora:// links —
# MessageRenderer#diaspora_links -> Post.exists?(guid:) on the "post" entity
# (existing guid AND missing guid), no query on the "comment" entity.
CE.insert("comments", id: 302, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid3", text: "see diaspora://bob@remote.example/post/postguid1000000001 and " \
                                            "diaspora://bob@remote.example/post/nosuchguid00000001 and " \
                                            "diaspora://bob@remote.example/comment/cguid1 ok")

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ConcreteTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(_name)
    @concolic_ctrl
  end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  ctrl = tc.instance_variable_get(:@controller)
  ctrl.response = tc.instance_variable_get(:@response)
  [ctrl, tc]
end

TARGETS = targets_from_corpus(File.expand_path("..", __FILE__), exclude: {
  # rig-terminal plumbing: issues no SQL evidence in any corpus run, and
  # alias-wrapping breaks its super chain on this JRuby
  "ActionController::Rendering.render" => "render terminal; no SQL evidence; super-chain breaks under wrap",
  "ActionController::Head.head" => "head terminal; no SQL evidence",
}, extra: [
  # concrete form of the corpus's mention_lookup_* finder aliases
  [ActiveRecord::FinderMethods, :find_by],
  # concrete form of the corpus's ci_{vis,author,public}_first aliases
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :exists?],   # cycle 3: diaspora_links' existence probe
  [ActiveRecord::Relation, :to_a],           # cycle 3: mobile partial collection materialization
])

CONCRETE_SCENARIOS = [
  { name: "comments-anon-public",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
      ctrl, tc = make_harness(CommentsController)
      ctrl.singleton_class.define_method(:current_user)    { nil }
      ctrl.singleton_class.define_method(:user_signed_in?) { false }
      ctrl.request.format = :json
      ctrl.params = { post_id: "100" }.with_indifferent_access
      ci_wrap { ctrl.send(:index) }
      body = ctrl.response.body.to_s
      raise "no comments rendered: #{body[0, 120]}" unless body.include?("plain comment")
    end },
]
