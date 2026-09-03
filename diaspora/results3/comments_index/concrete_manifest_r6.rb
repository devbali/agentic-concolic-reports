# CONCRETE CHECKER manifest — comments_index, ROUND-8 REPAIR VERIFICATION
# (cycle 11, 2026-09-01). Real sqlite DB, real rows, real Devise, real
# dispatch; no mocks, no stubs.
#
# This manifest exists because of adversary round 8. Until now this batch's
# OWN ground truth contained no `Person#fix_profile` call at all: every
# concrete scenario gave every person a `profiles` row, so the endpoint's
# discovery path was never exercised by our own evidence and the corpus's
# claims about it rested on the adversary's runs alone.
#
#  M-15  `fix_profile` -> `Discovery#fetch_and_save` IS reachable by a real
#        run. Faraday parses the webfinger URL with `URI.parse` BEFORE the
#        typhoeus adapter (faraday-0.15.4 connection.rb:477 -> utils.rb:275),
#        and `domain` is `diaspora_handle.split("@")[1]` with no format
#        constraint on the column — so a handle whose DOMAIN is not a legal
#        URI host raises `URI::InvalidURIError` in pure Ruby and
#        `fetch_and_save` converts it to `DiscoveryError`. The JVM lives.
#        (A PARSEABLE domain still reaches libcurl and aborts the JVM: this
#        batch measured both, `_c11/probe_uri_hostile.log` exit 0 vs
#        `_c11/probe_parseable.log` SIGSEGV / status 134.)
#  M-16  the SECOND key's missing `profiles` row must have the SAME
#        consequence as the first's. Byte-identical fixture pairs differing
#        ONLY in WHICH author/mention lacks its profile: both must 500.
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"
require File.expand_path("../_c12/exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_r6.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("people", id: 1, guid: "pguid1", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 101, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)

# people WITH a profile (a rendered name needs no discovery)
[2, 3].each do |pid|
  CE.insert("people", id: pid, guid: "pguid#{pid}", diaspora_handle: "p#{pid}@remote.example",
            serialized_public_key: "K#{pid}", owner_id: nil, closed_account: 0, fetch_status: 0)
  CE.insert("profiles", id: 100 + pid, person_id: pid, first_name: "P#{pid}", last_name: "Y",
            searchable: 1, nsfw: 0)
end
# people with NO `profiles` row and a URI-HOSTILE domain: `Person#name` ->
# `fix_profile` -> `Discovery#fetch_and_save` -> URI::InvalidURIError ->
# DiscoveryError, in pure Ruby, with the JVM intact.
[[7, "wraith@ba[d.example"], [8, "spectre@ba[d.example"]].each do |pid, handle|
  CE.insert("people", id: pid, guid: "pguid#{pid}", diaspora_handle: handle,
            serialized_public_key: "K#{pid}", owner_id: nil, closed_account: 0, fetch_status: 0)
end

# --- M-16 author tree: identical fixtures, only WHICH key lacks the profile.
# 810: comment 1 author 2 (profile), comment 2 author 7 (NO profile) -> key 2
# 811: comment 1 author 7 (NO profile), comment 2 author 2 (profile) -> key 1
CE.insert("posts", id: 810, author_id: 2, guid: "postguid8100000001", type: "StatusMessage",
          text: "author key2 missing", public: true, comments_count: 2)
[[820, 2], [821, 7]].each { |cid, aid| CE.insert("comments", id: cid, commentable_id: 810,
        commentable_type: "Post", author_id: aid, guid: "cguid#{cid}", text: "c#{cid}") }
CE.insert("posts", id: 811, author_id: 2, guid: "postguid8110000001", type: "StatusMessage",
          text: "author key1 missing", public: true, comments_count: 2)
[[822, 7], [823, 2]].each { |cid, aid| CE.insert("comments", id: cid, commentable_id: 811,
        commentable_type: "Post", author_id: aid, guid: "cguid#{cid}", text: "c#{cid}") }

# --- M-16 mention tree: two mentions, only WHICH one lacks the profile differs
CE.insert("posts", id: 812, author_id: 2, guid: "postguid8120000001", type: "StatusMessage",
          text: "mention key2 missing", public: true, comments_count: 1)
CE.insert("comments", id: 824, commentable_id: 812, commentable_type: "Post", author_id: 2,
          guid: "cguid824", text: "hi @{p3@remote.example} and @{wraith@ba[d.example}")
CE.insert("mentions", id: 830, mentions_container_id: 824, mentions_container_type: "Comment", person_id: 3)
CE.insert("mentions", id: 831, mentions_container_id: 824, mentions_container_type: "Comment", person_id: 7)
CE.insert("posts", id: 813, author_id: 2, guid: "postguid8130000001", type: "StatusMessage",
          text: "mention key1 missing", public: true, comments_count: 1)
CE.insert("comments", id: 825, commentable_id: 813, commentable_type: "Post", author_id: 2,
          guid: "cguid825", text: "hi @{wraith@ba[d.example} and @{p3@remote.example}")
CE.insert("mentions", id: 832, mentions_container_id: 825, mentions_container_type: "Comment", person_id: 7)
CE.insert("mentions", id: 833, mentions_container_id: 825, mentions_container_type: "Comment", person_id: 3)

# --- CONTROL: same shape, every person has a profile -> a clean 200
CE.insert("posts", id: 814, author_id: 2, guid: "postguid8140000001", type: "StatusMessage",
          text: "control both authors have profiles", public: true, comments_count: 2)
[[826, 2], [827, 3]].each { |cid, aid| CE.insert("comments", id: cid, commentable_id: 814,
        commentable_type: "Post", author_id: aid, guid: "cguid#{cid}", text: "c#{cid}") }

# --- two profile-less authors: BOTH keys missing
CE.insert("posts", id: 815, author_id: 2, guid: "postguid8150000001", type: "StatusMessage",
          text: "both authors profileless", public: true, comments_count: 2)
[[828, 7], [829, 8]].each { |cid, aid| CE.insert("comments", id: cid, commentable_id: 815,
        commentable_type: "Post", author_id: aid, guid: "cguid#{cid}", text: "c#{cid}") }

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
  {name: "r6-m16-author-key2-missing-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(810, format: :json)
     puts "[r6] author key2 missing json -> status=#{status.inspect} err=#{err && err.class}"
     raise "expected a DiscoveryError-class failure, got status #{status.inspect}" unless err
   end},
  {name: "r6-m16-author-key1-missing-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(811, format: :json)
     puts "[r6] author key1 missing json -> status=#{status.inspect} err=#{err && err.class}"
     raise "expected a DiscoveryError-class failure, got status #{status.inspect}" unless err
   end},
  {name: "r6-m16-author-key2-missing-mobile", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(810, format: :mobile)
     puts "[r6] author key2 missing mobile -> status=#{status.inspect} err=#{err && err.class}"
     raise "expected a template failure, got status #{status.inspect}" unless err
   end},
  {name: "r6-m16-author-key1-missing-mobile", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(811, format: :mobile)
     puts "[r6] author key1 missing mobile -> status=#{status.inspect} err=#{err && err.class}"
     raise "expected a template failure, got status #{status.inspect}" unless err
   end},
  {name: "r6-m16-mention-key2-missing-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(812, format: :json)
     puts "[r6] mention key2 missing json -> status=#{status.inspect} err=#{err && err.class}"
   end},
  {name: "r6-m16-mention-key1-missing-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(813, format: :json)
     puts "[r6] mention key1 missing json -> status=#{status.inspect} err=#{err && err.class}"
   end},
  {name: "r6-m16-mention-key2-missing-mobile", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(812, format: :mobile)
     puts "[r6] mention key2 missing mobile -> status=#{status.inspect} err=#{err && err.class}"
   end},
  {name: "r6-m16-both-authors-profileless-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(815, format: :json)
     puts "[r6] both authors profileless json -> status=#{status.inspect} err=#{err && err.class}"
     raise "expected a DiscoveryError-class failure, got status #{status.inspect}" unless err
   end},
  {name: "r6-control-both-authors-have-profiles-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(814, format: :json)
     raise "raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r6] CONTROL 2 authors, both with profiles -> 200 (no discovery)"
   end},
  {name: "r6-control-both-authors-have-profiles-mobile", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(814, format: :mobile)
     raise "raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r6] CONTROL mobile -> 200"
   end},
  {name: "r6-m16-author-key2-missing-auth-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(810, format: :json, uid: 9)
     puts "[r6] author key2 missing SIGNED-IN json -> status=#{status.inspect} err=#{err && err.class}"
   end},
]
