# ADVERSARY ROUND 2 common harness for comments_index.
# Same construction as round 1 (`adversary/_common.rb`) and as the batch's own
# concrete manifests: real ConcreteEnv sqlite DB + app schema, raw fixture
# ROWS, real Devise `serialize_from_session`, real ActionController::TestCase
# dispatch (every before_action runs), real templates. NOTHING here mocks,
# stubs or patches app code — only fixture rows, session, params, headers and
# the request format are under adversary control.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
BATCH = "/home/dev/project/reports/diaspora/results3/comments_index"
ADV_DIR = File.expand_path("..", __FILE__)
REAL_SALT_CACHE = {}

def adv_setup!(name)
  CE.setup!(db: File.join(ADV_DIR, "runs", "#{name}.sqlite3"))
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
end

# Cast:
#  user 9  alice  -> person 1 (local, owner_id 9), profile 11
#          person 2 bob    (remote), profile 12
#          person 3 carol  (remote, closed_account), profile 13
#          person 5 erin   (remote), profile 15
#          person 6 frank  (remote), profile 16
#  person 4 dave (remote) with NO profiles row only when dave_profile: false
#  user 8  gina  -> NO people row at all (only when orphan_user: true)
def seed_people!(alice_lang: "en", dave: false, dave_profile: true, extra_people: false,
                 orphan_user: false, alice_guid: "aliceguid000000001")
  CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: alice_lang, getting_started: 0, disable_mail: 0, sign_in_count: 1)
  CE.insert("people", id: 1, guid: alice_guid, diaspora_handle: "alice@localhost",
            serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
  CE.insert("people", id: 2, guid: "bobguid0000000002", diaspora_handle: "bob@remote.example",
            serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
  CE.insert("people", id: 3, guid: "carolguid00000003", diaspora_handle: "carol@remote.example",
            serialized_public_key: "K3", owner_id: nil, closed_account: 1, fetch_status: 0)
  CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
  CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0,
            image_url: "http://remote.example/bob.png")
  CE.insert("profiles", id: 13, person_id: 3, first_name: "", last_name: "", searchable: 0, nsfw: 1)
  if extra_people
    CE.insert("people", id: 5, guid: "eringuid000000005", diaspora_handle: "erin@other.example",
              serialized_public_key: "K5", owner_id: nil, closed_account: 0, fetch_status: 0)
    CE.insert("profiles", id: 15, person_id: 5, first_name: "Erin", last_name: "E", searchable: 1, nsfw: 0)
    CE.insert("people", id: 6, guid: "frankguid00000006", diaspora_handle: "frank@third.example",
              serialized_public_key: "K6", owner_id: nil, closed_account: 0, fetch_status: 0)
    CE.insert("profiles", id: 16, person_id: 6, first_name: "Frank", last_name: "F", searchable: 1, nsfw: 0)
  end
  if dave
    CE.insert("people", id: 4, guid: "daveguid000000004", diaspora_handle: "dave@remote.example",
              serialized_public_key: "K4", owner_id: nil, closed_account: 0, fetch_status: 0)
    CE.insert("profiles", id: 14, person_id: 4, first_name: "Dave", last_name: "D", searchable: 1, nsfw: 0) if dave_profile
  end
  if orphan_user
    CE.insert("users", id: 8, username: "gina", email: "gina@example.org",
              encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
              language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
  end
  REAL_SALT_CACHE[:salt] = User.find(9).authenticatable_salt
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

# Corpus targets + the real methods behind the batch's aliases + families a
# reader of the real path expects could be reached and the corpus has no event
# for. `escape_segment` is traced DELIBERATELY: cycle 3 (B-2) demoted it from a
# TARGET to a SHIM, and a shim must reach no target / issue no SQL — tracing it
# is how that claim is checked. Adding a frame label never changes behaviour.
def adv_targets(extra_more = [])
  targets_from_corpus(BATCH, exclude: {
    "ActionController::Rendering.render" => "render terminal; no SQL evidence; super-chain breaks under wrap",
    "ActionController::Head.head" => "head terminal; no SQL evidence",
  }, extra: [
    [ActiveRecord::FinderMethods, :first],
    [ActiveRecord::FinderMethods, :find_by],
    [ActiveRecord::FinderMethods, :exists?],
    [ActiveRecord::Relation, :records],
    [ActiveRecord::Relation, :to_a],
    [ActiveRecord::Calculations, :count],
    [ActiveRecord::Calculations, :pluck],
    [ActiveRecord::Associations::CollectionProxy, :records],
    [ActiveRecord::Associations::CollectionProxy, :load_target],
    [ActiveRecord::Persistence, :save],
    [ActiveRecord::Persistence, :reload],
    [ActiveRecord::Base, :reload],
    [Person, :fix_profile],
    [Diaspora::Mentionable, :people_from_string],
    [ActionDispatch::Journey::Router::Utils, :escape_segment],
  ] + extra_more)
end

def install_real_warden(tc, uid = 9)
  real_salt = (REAL_SALT_CACHE[:salt] ||= User.find(9).authenticatable_salt)
  salt = uid == 9 ? real_salt : User.find(uid).authenticatable_salt
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| @concrete_user ||= User.serialize_from_session(uid, salt) }
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

# One request: returns [status, body].
def adv_request(post_id:, format:, signed_in: false, uid: 9, params: {}, session: {}, headers: {}, tag: nil)
  ctrl, tc = make_harness(CommentsController)
  signed_in ? install_real_warden(tc, uid) : install_anon_warden(tc)
  session.each { |k, v| tc.session[k] = v }
  headers.each { |k, v| tc.request.headers[k] = v }
  thrown = catch(:warden) do
    tc.process(:index, method: :get, params: { post_id: post_id }.merge(params), format: format)
    nil
  end
  status = thrown ? "401(throw :warden)" : ctrl.response.status
  body = ctrl.response.body.to_s
  warn "[adv2] #{signed_in ? "auth#{uid}" : 'anon'} #{format} post_id=#{post_id.inspect} #{params.inspect} " \
       "session=#{session.inspect} hdr=#{headers.keys.inspect} -> #{status} (#{body.bytesize} bytes)"
  File.write(File.join(ADV_DIR, "runs", "_body_#{tag || [format, post_id.to_s.gsub(/[^\w]/, '_')].join('_')}.txt"), body)
  [status, body]
rescue StandardError => e
  warn "[adv2] #{signed_in ? "auth#{uid}" : 'anon'} #{format} post_id=#{post_id.inspect} -> EXC #{e.class}: #{e.message[0, 240]}"
  ["EXC #{e.class}", e.message.to_s]
end

def adv_scenario(name, targets: adv_targets, &body)
  [{ name: name, targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/}, body: body }]
end
