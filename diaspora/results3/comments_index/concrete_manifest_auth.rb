# CONCRETE CHECKER manifest — comments_index, SIGNED-IN scenario (cycle 1,
# 2026-08-25). Real sqlite DB, real rows, real Devise resolution (the
# notifications_index warden pattern), real dispatch through
# ActionController::TestCase#process; no mocks, no stubs. Separate manifest
# from the anon one (per-process crash isolation).
#
# Three posts drive the three branches of EvilQuery::VisibleShareableById
# #post! (lib/evil_query.rb:102-105), the signed-in PostService#find! path:
#   post 100 — visible to alice via a share_visibilities row (branch 1)
#   post 101 — authored by alice's own person, no visibility row (branch 2)
#   post 102 — public post by bob, no visibility row (branch 3)
# Each carries a mention-free and a mention-bearing comment (the latter with
# a real mentions row) so the persisted mentioned_people chain fires.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../_c12/exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_auth.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("people", id: 1, guid: "aliceguid", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
CE.insert("people", id: 2, guid: "bobguid", diaspora_handle: "bob@remote.example",
          serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0)

CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
          text: "a limited post shared with alice", public: false, comments_count: 2)
CE.insert("share_visibilities", id: 400, shareable_id: 100, shareable_type: "Post", user_id: 9, hidden: false)
CE.insert("posts", id: 101, author_id: 1, guid: "postguid2", type: "StatusMessage",
          text: "alice's own private post", public: false, comments_count: 2)
CE.insert("posts", id: 102, author_id: 2, guid: "postguid3", type: "StatusMessage",
          text: "a post by bob shared with alice", public: false, comments_count: 2)
CE.insert("share_visibilities", id: 401, shareable_id: 102, shareable_type: "Post", user_id: 9, hidden: false)

cid = 300
mid = 900
[100, 101, 102].each do |pid|
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: 2, guid: "cguid#{cid}", text: "plain comment #{pid}")
  CE.insert("comments", id: cid + 1, commentable_id: pid, commentable_type: "Post",
            author_id: 1, guid: "cguid#{cid + 1}", text: "hi @{bob@remote.example} on #{pid}")
  CE.insert("mentions", id: mid, mentions_container_id: cid + 1,
            mentions_container_type: "Comment", person_id: 2)
  cid += 2
  mid += 1
end
# cycle 3 (adversary W1): diaspora:// links on the signed-in path too.
CE.insert("comments", id: 399, commentable_id: 100, commentable_type: "Post",
          author_id: 1, guid: "cguid399", text: "see diaspora://bob@remote.example/post/postguid1000000001 and " \
                                              "diaspora://bob@remote.example/comment/cguid300 ok")

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
  "ActionController::Rendering.render" => "render terminal; no SQL evidence; super-chain breaks under wrap",
  "ActionController::Head.head" => "head terminal; no SQL evidence",
}, extra: [
  [ActiveRecord::FinderMethods, :find_by],   # mention_lookup_* aliases' real method
  [ActiveRecord::FinderMethods, :first],     # ci_{vis,author,public}_first aliases' real method
  [ActiveRecord::FinderMethods, :exists?],   # cycle 3: diaspora_links' existence probe
  [ActiveRecord::Relation, :to_a],           # cycle 3: mobile partial collection materialization
])

# honest warden: Devise's REAL serialize_from_session resolves the user
# from the REAL users row (salt = real authenticatable_salt)
# Computed ONCE at fixture-load time (outside the probe's statement-capture
# window) so the harness's own salt lookup is not mistaken for endpoint SQL.
REAL_SALT = User.find(9).authenticatable_salt
def install_real_warden(tc)
  real_salt = REAL_SALT
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  # INSTR-1 (coordinator, 2026-08-29): the memo used to be `@concrete_user ||=`
  # inside a lambda defined at METHOD scope, so it bound to `main` and lived
  # for the whole PROCESS — every request after the first in a manifest was
  # missing the Devise `users` read AND `current_user.person`'s
  # `people.owner_id` read, i.e. ground truth under-reported statements on
  # every signed-in run this batch ever made. Bind it to the WARDEN, which is
  # rebuilt per request.
  wuser = lambda { |*_a|
    warden.instance_variable_get(:@cc_user) ||
      warden.instance_variable_set(:@cc_user, User.serialize_from_session(9, real_salt))
  }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

CONCRETE_SCENARIOS = [
  { name: "comments-auth-visibility-chain",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      [100, 101, 102].each do |pid|
        CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
      ctrl, tc = make_harness(CommentsController)
        install_real_warden(tc)
        ci_wrap { tc.process(:index, method: :get, params: { post_id: pid.to_s }, format: :json) }
        raise "post #{pid}: unexpected status #{ctrl.response.status}" unless ctrl.response.status == 200
        body = ctrl.response.body.to_s
        raise "post #{pid}: no comments rendered: #{body[0, 120]}" unless body.include?("plain comment #{pid}")
      end
    end },
]
