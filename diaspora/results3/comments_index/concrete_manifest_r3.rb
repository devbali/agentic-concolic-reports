# CONCRETE CHECKER manifest — comments_index, ROUND-3 REPAIR VERIFICATION
# (cycle 5, 2026-08-28). Real sqlite DB, real rows, real Devise resolution,
# real dispatch through ActionController::TestCase#process (so the WHOLE
# before_action chain runs); no mocks, no stubs.
#
# It exists to prove, on the real application, the three facts the cycle-5
# repairs assert:
#
#  M-3  a DANGLING `mentions.person_id` (no FK on that column, schema.rb
#       202-209) is a real state: json renders `"mentioned_people":[null]`
#       with 200, mobile raises ActionView::Template::Error (NoMethodError
#       `diaspora_handle` for nil) — and the real run issues the `people`
#       preload and then STOPS: no `profiles` preload at all.
#  M-4  an EMPTY comments relation issues NOTHING below itself: the post
#       finder and the comments SELECT, and no people/profiles/mentions read.
#  N3-1 `users.language` decides a statement: the same user with `pl` issues
#       `SELECT "profiles".* … WHERE "person_id" = ? LIMIT 1` on the DEVISE
#       PRINCIPAL before the action body (set_locale -> set_grammatical_gender
#       -> current_user.gender), with `en` it does not.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require File.expand_path("../_c12/exec_wrap.rb", __FILE__)

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_r3.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

# --- people / users -------------------------------------------------------
CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("users", id: 10, username: "carol", email: "carol@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "pl", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("people", id: 1, guid: "aliceguid", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
CE.insert("people", id: 2, guid: "bobguid", diaspora_handle: "bob@remote.example",
          serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("people", id: 3, guid: "carolguid", diaspora_handle: "carol@localhost",
          serialized_public_key: "K3", owner_id: 10, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0)
CE.insert("profiles", id: 13, person_id: 3, first_name: "Carol", last_name: "C", gender: "female",
          searchable: 1, nsfw: 0)

# --- M-3: a comment whose mentions row points at a person that is NOT there
CE.insert("posts", id: 210, author_id: 2, guid: "postguid2100000001", type: "StatusMessage",
          text: "public post with a dangling mention", public: true, comments_count: 1)
CE.insert("comments", id: 310, commentable_id: 210, commentable_type: "Post",
          author_id: 2, guid: "cguid310", text: "hello @{Ghost; ghost@remote.example} goodbye")
CE.insert("mentions", id: 910, mentions_container_id: 310,
          mentions_container_type: "Comment", person_id: 999) # no people row 999

# --- M-3 control: the same shape with a mention that RESOLVES
CE.insert("posts", id: 213, author_id: 2, guid: "postguid2130000001", type: "StatusMessage",
          text: "public post with a live mention", public: true, comments_count: 1)
CE.insert("comments", id: 313, commentable_id: 213, commentable_type: "Post",
          author_id: 2, guid: "cguid313", text: "hello @{Bob; bob@remote.example} goodbye")
CE.insert("mentions", id: 913, mentions_container_id: 313,
          mentions_container_type: "Comment", person_id: 2)

# --- M-4: a public post with ZERO comments
CE.insert("posts", id: 211, author_id: 2, guid: "postguid2110000001", type: "StatusMessage",
          text: "public post with no comments at all", public: true, comments_count: 0)

# --- N3-1: a public post both principals can read
CE.insert("posts", id: 212, author_id: 2, guid: "postguid2120000001", type: "StatusMessage",
          text: "public post for the locale differential", public: true, comments_count: 1)
CE.insert("comments", id: 312, commentable_id: 212, commentable_type: "Post",
          author_id: 2, guid: "cguid312", text: "plain comment 212")

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

# Salts computed at fixture-load time, OUTSIDE the statement-capture window.
SALTS = { 9 => User.find(9).authenticatable_salt, 10 => User.find(10).authenticatable_salt }.freeze
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

# Anonymous requests still go through the FULL before_action chain, several
# of whose callbacks ask warden (`user_signed_in?`), so the rig needs a
# warden that answers "nobody" — without one Devise raises MissingWarden
# before the action is reached. It grants nothing the real app would not.
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
    ci_wrap { tc.process(:index, method: :get, params: { post_id: post_id.to_s }, format: format) }
    [ctrl.response.status, ctrl.response.body.to_s, nil]
  rescue Exception => e # rubocop:disable Lint/RescueException
    [nil, "", e]
  end
end

CONCRETE_SCENARIOS = [
  # ---- M-3 -------------------------------------------------------------
  { name: "r3-dangling-mention-json",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      status, body, err = get(210, format: :json)
      raise "dangling mention json raised #{err.class}: #{err}" if err
      raise "expected 200, got #{status}" unless status == 200
      raise "expected mentioned_people:[null], got: #{body[0, 300]}" unless body.include?('"mentioned_people":[null]')
      puts "[r3] dangling-mention json -> 200 #{body.bytesize}B #{body[0, 200]}"
    end },

  { name: "r3-dangling-mention-mobile",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      _status, _body, err = get(210, format: :mobile)
      raise "expected a 500 on mobile, got a rendered response" if err.nil?
      unless err.is_a?(ActionView::Template::Error) && err.cause.is_a?(NoMethodError)
        raise "expected Template::Error <- NoMethodError, got #{err.class} <- #{err.cause.class}: #{err.message[0, 160]}"
      end
      puts "[r3] dangling-mention mobile -> EXC #{err.class} <- #{err.cause.class}: #{err.cause.message[0, 120]}"
    end },

  { name: "r3-live-mention-json",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      status, body, err = get(213, format: :json)
      raise "live mention json raised #{err.class}: #{err}" if err
      raise "expected 200, got #{status}" unless status == 200
      raise "expected a resolved mention, got: #{body[0, 300]}" if body.include?('"mentioned_people":[null]')
      puts "[r3] live-mention json -> 200 #{body.bytesize}B"
    end },

  # ---- M-4 -------------------------------------------------------------
  { name: "r3-empty-collection-json",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      status, body, err = get(211, format: :json)
      raise "empty collection json raised #{err.class}: #{err}" if err
      raise "expected 200 [], got #{status} #{body[0, 120]}" unless status == 200 && body.strip == "[]"
      puts "[r3] empty-collection json -> 200 #{body.inspect}"
    end },

  { name: "r3-empty-collection-mobile",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      status, body, err = get(211, format: :mobile)
      raise "empty collection mobile raised #{err.class}: #{err}" if err
      raise "expected 200, got #{status}" unless status == 200
      puts "[r3] empty-collection mobile -> 200 #{body.bytesize}B"
    end },

  # ---- N3-1 ------------------------------------------------------------
  { name: "r3-principal-locale-en",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      status, _body, err = get(212, format: :json, uid: 9) # alice, language "en"
      raise "locale-en raised #{err.class}: #{err}" if err
      raise "expected 200, got #{status}" unless status == 200
      puts "[r3] principal locale en -> 200 (I18n.locale=#{I18n.locale})"
    end },

  { name: "r3-principal-locale-pl",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      status, _body, err = get(212, format: :json, uid: 10) # carol, language "pl"
      raise "locale-pl raised #{err.class}: #{err}" if err
      raise "expected 200, got #{status}" unless status == 200
      puts "[r3] principal locale pl -> 200 (I18n.locale=#{I18n.locale})"
    end },
]
