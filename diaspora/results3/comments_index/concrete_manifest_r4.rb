# CONCRETE CHECKER manifest — comments_index, ROUND-4 REPAIR VERIFICATION
# (cycle 6, 2026-08-28). Real sqlite DB, real rows, real Devise resolution,
# real dispatch through ActionController::TestCase#process (the WHOLE
# before_action chain runs); no mocks, no stubs.
#
# It proves, on the real application, the three facts cycle 6 asserts:
#
#  M-5  `users.language` has a THIRD outcome. A non-nil code that is not an
#       available locale makes `set_locale` raise `I18n::InvalidLocale`
#       BEFORE the action body: the whole data access is one `users` SELECT.
#       NULL is not that arm (it 200s), and an available locale is not either.
#  M-6  `posts.type` outside the Post STI tree makes the finder's row raise
#       `ActiveRecord::SubclassNotFound` DURING INSTANTIATION: an anon run
#       issues the post finder and nothing else.
#  N4-3 the preload's predicate operator follows the collection's cardinality:
#       one author => `WHERE "people"."id" = ?`, three authors =>
#       `WHERE "people"."id" IN (?, ?, ?)`. Both shapes must have a note.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../_c12/exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_r4.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

# --- principals ----------------------------------------------------------
# one uid per arm: the warden memo is per-uid, so only the FIRST request for
# a uid is a clean principal differential (adversary round 4, §7).
{9 => "en", 21 => "xx", 22 => nil, 23 => "pl"}.each do |uid, lang|
  CE.insert("users", id: uid, username: "u#{uid}", email: "u#{uid}@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: lang, getting_started: 0, disable_mail: 0, sign_in_count: 1)
end
[[1, 9], [41, 21], [42, 22], [43, 23]].each_with_index do |(pid, uid), i|
  CE.insert("people", id: pid, guid: "pguid#{pid}", diaspora_handle: "u#{uid}@localhost",
            serialized_public_key: "K#{pid}", owner_id: uid, closed_account: 0, fetch_status: 0)
  CE.insert("profiles", id: 100 + i, person_id: pid, first_name: "U#{uid}", last_name: "X",
            gender: "male", searchable: 1, nsfw: 0)
end
# comment authors
[2, 3, 4].each do |pid|
  CE.insert("people", id: pid, guid: "pguid#{pid}", diaspora_handle: "a#{pid}@remote.example",
            serialized_public_key: "K#{pid}", owner_id: nil, closed_account: 0, fetch_status: 0)
  CE.insert("profiles", id: 110 + pid, person_id: pid, first_name: "A#{pid}", last_name: "Y",
            searchable: 1, nsfw: 0)
end

# --- M-6: STI types ------------------------------------------------------
{380 => "StatusMessage", 381 => "Photo", 382 => "ActivityStreams::Photo", 383 => "Bogus"}
  .each do |pid, type|
  CE.insert("posts", id: pid, author_id: 2, guid: "postguid#{pid}0000001", type: type,
            text: "post #{pid}", public: true, comments_count: 1)
  CE.insert("comments", id: pid + 100, commentable_id: pid, commentable_type: "Post",
            author_id: 2, guid: "cguid#{pid}", text: "a comment on #{pid}")
end

# --- M-5 / N4-3: a public post with ONE author, and one with THREE --------
CE.insert("posts", id: 390, author_id: 2, guid: "postguid3900000001", type: "StatusMessage",
          text: "one author", public: true, comments_count: 1)
CE.insert("comments", id: 490, commentable_id: 390, commentable_type: "Post",
          author_id: 2, guid: "cguid490", text: "single comment")
CE.insert("posts", id: 391, author_id: 2, guid: "postguid3910000001", type: "StatusMessage",
          text: "three authors", public: true, comments_count: 3)
[[491, 2], [492, 3], [493, 4]].each do |cid, aid|
  CE.insert("comments", id: cid, commentable_id: 391, commentable_type: "Post",
            author_id: aid, guid: "cguid#{cid}", text: "comment #{cid}")
end

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

SALTS = [9, 21, 22, 23].each_with_object({}) { |u, h| h[u] = User.find(u).authenticatable_salt }.freeze
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
  # ---- M-6 -------------------------------------------------------------
  {name: "r4-sti-out-of-tree-anon-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     [381, 382, 383].each do |pid|
       _s, _b, err = get(pid, format: :json)
       unless err.is_a?(ActiveRecord::SubclassNotFound)
         raise "post #{pid}: expected SubclassNotFound, got #{err.class}: #{err}"
       end
       puts "[r4] sti #{pid} anon json -> EXC #{err.class}: #{err.message[0, 90]}"
     end
   end},

  {name: "r4-sti-in-tree-control-anon-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, body, err = get(380, format: :json)
     raise "in-tree control raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     raise "no comment rendered: #{body[0, 120]}" unless body.include?("a comment on 380")
     puts "[r4] sti 380 (StatusMessage) anon json -> 200 #{body.bytesize}B"
   end},

  {name: "r4-sti-out-of-tree-auth-json", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     _s, _b, err = get(381, format: :json, uid: 9)
     raise "expected SubclassNotFound, got #{err.class}: #{err}" unless err.is_a?(ActiveRecord::SubclassNotFound)
     puts "[r4] sti 381 auth json -> EXC #{err.class}"
   end},

  # ---- M-5 -------------------------------------------------------------
  {name: "r4-locale-invalid", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     _s, _b, err = get(390, format: :json, uid: 21) # language "xx"
     raise "expected I18n::InvalidLocale, got #{err.class}: #{err}" unless err.is_a?(I18n::InvalidLocale)
     puts "[r4] language 'xx' auth json -> EXC #{err.class}: #{err.message[0, 90]}"
   end},

  {name: "r4-locale-null-control", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(390, format: :json, uid: 22) # language NULL
     raise "NULL language raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r4] language NULL auth json -> 200 (not the invalid arm)"
   end},

  {name: "r4-locale-inflected-control", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(390, format: :json, uid: 23) # language "pl"
     raise "pl raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r4] language 'pl' auth json -> 200 (I18n.locale=#{I18n.locale})"
   end},

  # ---- N4-3 ------------------------------------------------------------
  {name: "r4-preload-one-author", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(390, format: :json)
     raise "one-author raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r4] one author anon json -> 200 (expect `people.id = ?`)"
   end},

  {name: "r4-preload-three-authors", targets: TARGETS,
   coverage_filter: %r{apps/diaspora/(app|lib)/},
   body: lambda do
     status, _b, err = get(391, format: :json)
     raise "three-author raised #{err.class}: #{err}" if err
     raise "expected 200, got #{status}" unless status == 200
     puts "[r4] three authors anon json -> 200 (expect `people.id IN (?, ?, ?)`)"
   end},
]
