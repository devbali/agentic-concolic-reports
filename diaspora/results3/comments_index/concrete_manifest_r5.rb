# CONCRETE CHECKER manifest — comments_index, ROUND-5 REPAIR VERIFICATION
# (cycle 7, 2026-08-29). Real sqlite DB, real rows, real Devise, real
# dispatch; no mocks, no stubs.
#
#  M-7  the preload predicate follows the DISTINCT KEY COUNT: two comments by
#       the SAME author give `people.id = ?`, two by two authors `IN (?, ?)`.
#  M-8  the NESTED step follows the parents actually loaded: two mentions,
#       one dangling, give `people.id IN (?, ?)` then `profiles.person_id = ?`.
#  M-9  a finder that finds nothing still ISSUED its query: the 404 request's
#       only statement is the post finder, and it must be in the corpus.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../_c12/exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_r5.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("people", id: 1, guid: "pguid1", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 101, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
[2, 3, 5].each do |pid|
  CE.insert("people", id: pid, guid: "pguid#{pid}", diaspora_handle: "p#{pid}@remote.example",
            serialized_public_key: "K#{pid}", owner_id: nil, closed_account: 0, fetch_status: 0)
  CE.insert("profiles", id: 100 + pid, person_id: pid, first_name: "P#{pid}", last_name: "Y",
            searchable: 1, nsfw: 0)
end

# M-7: 501 = two comments, ONE author; 502 = two comments, TWO authors
CE.insert("posts", id: 501, author_id: 2, guid: "postguid5010000001", type: "StatusMessage",
          text: "one author two comments", public: true, comments_count: 2)
[601, 602].each { |cid| CE.insert("comments", id: cid, commentable_id: 501, commentable_type: "Post",
                                  author_id: 2, guid: "cguid#{cid}", text: "c#{cid}") }
CE.insert("posts", id: 502, author_id: 2, guid: "postguid5020000001", type: "StatusMessage",
          text: "two authors", public: true, comments_count: 2)
[[603, 2], [604, 3]].each { |cid, aid| CE.insert("comments", id: cid, commentable_id: 502,
                                                 commentable_type: "Post", author_id: aid,
                                                 guid: "cguid#{cid}", text: "c#{cid}") }

# M-8: 503 = one comment, two mentions, ONE dangling; 504 = two LIVE mentions
CE.insert("posts", id: 503, author_id: 2, guid: "postguid5030000001", type: "StatusMessage",
          text: "dangling mention", public: true, comments_count: 1)
CE.insert("comments", id: 605, commentable_id: 503, commentable_type: "Post", author_id: 2,
          guid: "cguid605", text: "hi @{P5; p5@remote.example} and @{Ghost; ghost@remote.example}")
CE.insert("mentions", id: 701, mentions_container_id: 605, mentions_container_type: "Comment", person_id: 5)
CE.insert("mentions", id: 702, mentions_container_id: 605, mentions_container_type: "Comment", person_id: 997)
CE.insert("posts", id: 504, author_id: 2, guid: "postguid5040000001", type: "StatusMessage",
          text: "two live mentions", public: true, comments_count: 1)
CE.insert("comments", id: 606, commentable_id: 504, commentable_type: "Post", author_id: 2,
          guid: "cguid606", text: "hi @{P3; p3@remote.example} and @{P5; p5@remote.example}")
CE.insert("mentions", id: 703, mentions_container_id: 606, mentions_container_type: "Comment", person_id: 3)
CE.insert("mentions", id: 704, mentions_container_id: 606, mentions_container_type: "Comment", person_id: 5)
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
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Relation, :to_a],
])

SALTS = [9].each_with_object({}) { |u, h| h[u] = User.find(u).authenticatable_salt }.freeze
def install_real_warden(tc, uid)
  salt = SALTS.fetch(uid)
  memo = {}
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| memo[uid] ||= User.serialize_from_session(uid, salt) }
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

def get(post_id, format:, uid: nil)
  # INSTR-2 (coordinator, 2026-08-29): the probe skips `payload[:cached]`
  # statements, so any statement a LATER request repeats used to vanish from
  # ground truth. Clear the AR query cache between requests.
  CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
  ctrl, tc = make_harness(CommentsController)
  uid ? install_real_warden(tc, uid) : install_anon_warden(tc)
  begin
    ci_wrap { tc.process(:index, method: :get, params: {post_id: post_id.to_s}, format: format) }
    [ctrl.response.status, ctrl.response.body.to_s, nil]
  rescue Exception => e # rubocop:disable Lint/RescueException
    [nil, "", e]
  end
end

CONCRETE_SCENARIOS = [
  {name: "r5-preload-one-distinct-key", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(501, format: :json)
     raise "raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r5] 2 comments / 1 author -> 200 (expect `people.id = ?`)"
   end},
  {name: "r5-preload-two-distinct-keys", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(502, format: :json)
     raise "raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r5] 2 comments / 2 authors -> 200 (expect `people.id IN (?, ?)`)"
   end},
  {name: "r5-nested-shrinks-dangling", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, body, err = get(503, format: :json)
     raise "raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     raise "expected a nil mention: #{body[0, 200]}" unless body.include?("null")
     puts "[r5] 2 mentions, 1 dangling -> 200 (expect people IN (?, ?) then profiles = ?)"
   end},
  {name: "r5-nested-both-loaded", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(504, format: :json)
     raise "raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r5] 2 live mentions -> 200 (expect people IN (?, ?) then profiles IN (?, ?))"
   end},
  # T-t follow-up (coordinator, 2026-08-29): an UNDECLARED format is invisible
  # to format_coverage_audit, so the audit's silence is not evidence. Measure
  # it. `app/views/comments/` holds ONLY *.mobile.haml — there is no
  # index.js.* and no index.html.* — and the action declares
  # `respond_to :html, :mobile, :json`.
  {name: "r5-format-js-undeclared", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     _s, _b, err = get(501, format: :js)
     raise "expected an UnknownFormat-class failure, got a rendered response" if err.nil?
     puts "[r5] format :js -> EXC #{err.class}: #{err.message.to_s[0, 90]}"
   end},
  {name: "r5-format-xml-undeclared", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     _s, _b, err = get(501, format: :xml)
     raise "expected an UnknownFormat-class failure, got a rendered response" if err.nil?
     puts "[r5] format :xml -> EXC #{err.class}: #{err.message.to_s[0, 90]}"
   end},
  {name: "r5-format-html-declared-templateless", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     _s, _b, err = get(501, format: :html)
     puts "[r5] format :html -> #{err ? "EXC #{err.class}" : 'rendered'}"
   end},

  {name: "r5-finder-miss-404", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(999_999, format: :json)
     raise "raised #{err.class}: #{err}" if err
     raise "expected 404, got #{status}" unless status == 404
     puts "[r5] missing post -> 404 (the post finder is the ONLY statement — M-9)"
   end},
]
