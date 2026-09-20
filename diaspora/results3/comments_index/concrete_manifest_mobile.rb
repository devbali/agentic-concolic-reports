# CONCRETE CHECKER manifest — comments_index, MOBILE scenario (cycle 3,
# adversary W2): the app's own session switch (ApplicationController
# #mobile_switch: `session[:mobile_view] == true` + html -> request.format =
# :mobile) renders index.mobile.haml / _comment.mobile.haml for an anonymous
# request, then an explicit `format: :mobile` signed-in request (delete-link
# `comment.author == current_user.person`, person_link_class self/
# hovercardable, render_mentions with a mentioned person). Real sqlite DB,
# real rows, real Devise resolution, real dispatch; no mocks. One process.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../_c12/exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_mobile.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("people", id: 1, guid: "aliceguid000000001", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
CE.insert("people", id: 2, guid: "bobguid0000000002", diaspora_handle: "bob@remote.example",
          serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0,
          image_url: "http://remote.example/bob.png")
CE.insert("posts", id: 100, author_id: 2, guid: "postguid1000000001", type: "StatusMessage",
          text: "a public post", public: true, comments_count: 3)
# alice can see post 100 through a share_visibilities row (the signed-in
# public branch 404s under the JDBC sqlite boolean bind — rig artefact,
# AGENT_RUN.md cycle 1 §F; the vis branch is the one exercised here)
CE.insert("share_visibilities", id: 400, shareable_id: 100, shareable_type: "Post", user_id: 9, hidden: false)
CE.insert("comments", id: 300, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid300", text: "plain comment #tag")
CE.insert("comments", id: 301, commentable_id: 100, commentable_type: "Post",
          author_id: 1, guid: "cguid301", text: "hi @{Bob; bob@remote.example} nice")
CE.insert("mentions", id: 900, mentions_container_id: 301, mentions_container_type: "Comment", person_id: 2)
CE.insert("comments", id: 302, commentable_id: 100, commentable_type: "Post",
          author_id: 2, guid: "cguid302", text: "see diaspora://bob@remote.example/post/postguid1000000001 and " \
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
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Relation, :to_a],
])

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

def install_anon_warden(tc)
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  warden.define_singleton_method(:authenticate!) { |*_a| throw :warden, scope: :user }
  warden.define_singleton_method(:authenticate)  { |*_a| nil }
  warden.define_singleton_method(:authenticated?) { |*_a| false }
  warden.define_singleton_method(:user) { |*_a| nil }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

CONCRETE_SCENARIOS = [
  { name: "comments-mobile-anon-session-switch+auth-explicit",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      # (1) anonymous, html + session[:mobile_view] -> mobile_switch -> :mobile
      CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
      ctrl, tc = make_harness(CommentsController)
      install_anon_warden(tc)
      tc.session[:mobile_view] = true
      ci_wrap { tc.process(:index, method: :get, params: { post_id: "100" }, format: :html) }
      raise "anon mobile: unexpected status #{ctrl.response.status}" unless ctrl.response.status == 200
      raise "anon mobile: not the mobile template" unless ctrl.request.format.to_sym == :mobile
      raise "anon mobile: no comments rendered" unless ctrl.response.body.to_s.include?("plain comment")
      # (2) signed in (alice, author of comment 301), explicit :mobile
      CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
      ctrl, tc = make_harness(CommentsController)
      install_real_warden(tc)
      ci_wrap { tc.process(:index, method: :get, params: { post_id: "100" }, format: :mobile) }
      raise "auth mobile: unexpected status #{ctrl.response.status}" unless ctrl.response.status == 200
      raise "auth mobile: no delete link (own comment)" unless ctrl.response.body.to_s.include?("remove")
    end },
]
