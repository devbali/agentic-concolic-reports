# ADVERSARY ROUND 4 common harness for comments_index.
# Same construction as rounds 1/2 and as the batch's own concrete manifests:
# real ConcreteEnv sqlite DB + the app schema, raw fixture ROWS, real Devise
# `serialize_from_session`, real ActionController::TestCase dispatch (every
# before_action runs), real templates. NOTHING here mocks, stubs or patches app
# code — only fixture rows, session, params, headers and the request format are
# under adversary control.
#
# Differences from round 2's `_common2.rb`:
#  * the per-uid warden memo fix from A10 is built in (A05's shared memo bug);
#  * booleans are passed to ConcreteEnv.insert as true/false so the just-fixed
#    `ConcreteEnv.quote` writes them in the adapter's own representation
#    ('t'/'f') — the D7 instrument defect;
#  * the traced set adds the gem's `Discovery.new` / `Discovery#fetch_and_save`
#    (cycle-4 demoted `Discovery.new` from a TARGET to a SHIM — a shim must mint
#    no note and reach no target, which is checked by TRACING it) and keeps
#    `escape_segment` from round 2 for the same reason.
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
BATCH = "/home/dev/project/reports/diaspora/results3/comments_index"
ADV_DIR = File.expand_path("..", __FILE__)
SALTS = {}
USERS = {}

def adv_setup!(name)
  CE.setup!(db: File.join(ADV_DIR, "runs", "#{name}.sqlite3"))
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
end

def prime_salts!(*uids)
  uids.each { |u| SALTS[u] = User.find(u).authenticatable_salt }
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

def adv_targets(extra_more = [])
  extra = [
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
    [ActionDispatch::Journey::Router::Utils, :escape_segment]
  ]
  if defined?(DiasporaFederation::Discovery::Discovery)
    extra << [DiasporaFederation::Discovery::Discovery, :new]
    extra << [DiasporaFederation::Discovery::Discovery, :fetch_and_save]
  end
  targets_from_corpus(BATCH, exclude: {
    "ActionController::Rendering.render" => "render terminal; no SQL evidence; super-chain breaks under wrap",
    "ActionController::Head.head" => "head terminal; no SQL evidence"
  }, extra: extra + extra_more)
end

def install_real_warden(tc, uid = 9)
  salt = SALTS.fetch(uid)
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| USERS[uid] ||= User.serialize_from_session(uid, salt) }
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
  warn "[adv4] #{tag} #{signed_in ? "auth#{uid}" : 'anon'} #{format} post_id=#{post_id.inspect} " \
       "session=#{session.inspect} -> #{status} (#{body.bytesize} bytes)"
  File.write(File.join(ADV_DIR, "runs", "_body_#{tag || [format, post_id.to_s.gsub(/[^\w]/, '_')].join('_')}.txt"), body)
  [status, body]
rescue StandardError => e
  warn "[adv4] #{tag} #{signed_in ? "auth#{uid}" : 'anon'} #{format} post_id=#{post_id.inspect} -> EXC #{e.class}: #{e.message[0, 240]}"
  ["EXC #{e.class}", e.message.to_s]
end

def adv_scenario(name, targets: adv_targets, &body)
  [{ name: name, targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/}, body: body }]
end

# ---- shared cast -----------------------------------------------------------
#  user 9  alice -> person 1 (local, owner_id 9), profile 11
#  person 2 bob   (remote, profile 12)
#  person 3 carol (remote, closed_account, blank-name profile 13)
#  person 5 erin  (remote, other pod, profile 15)
#  person 6 frank (remote, third pod, profile 16)
def seed_core!(alice_lang: "en")
  CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: alice_lang, getting_started: false, disable_mail: false, sign_in_count: 1)
  CE.insert("people", id: 1, guid: "aliceguid000000001", diaspora_handle: "alice@localhost",
            serialized_public_key: "K1", owner_id: 9, closed_account: false, fetch_status: 0)
  CE.insert("people", id: 2, guid: "bobguid0000000002", diaspora_handle: "bob@remote.example",
            serialized_public_key: "K2", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("people", id: 3, guid: "carolguid00000003", diaspora_handle: "carol@remote.example",
            serialized_public_key: "K3", owner_id: nil, closed_account: true, fetch_status: 0)
  CE.insert("people", id: 5, guid: "eringuid000000005", diaspora_handle: "erin@other.example",
            serialized_public_key: "K5", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("people", id: 6, guid: "frankguid00000006", diaspora_handle: "frank@third.example",
            serialized_public_key: "K6", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: true, nsfw: false)
  CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: true, nsfw: false,
            image_url: "http://remote.example/bob.png")
  CE.insert("profiles", id: 13, person_id: 3, first_name: "", last_name: "", searchable: false, nsfw: true)
  CE.insert("profiles", id: 15, person_id: 5, first_name: "Erin", last_name: "E", searchable: true, nsfw: false)
  CE.insert("profiles", id: 16, person_id: 6, first_name: "Frank", last_name: "F", searchable: true, nsfw: false)
  prime_salts!(9)
end

# ---- round-4 additions ----------------------------------------------------
# extra principals (all real rows; only fixture data, no code is patched)
def seed_user!(uid:, username:, language:, person_id: nil, person_guid: nil,
               handle: nil, profile_id: nil, gender: :unset)
  CE.insert("users", id: uid, username: username, email: "#{username}@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: language, getting_started: false, disable_mail: false, sign_in_count: 1)
  if person_id
    CE.insert("people", id: person_id, guid: person_guid, diaspora_handle: handle,
              serialized_public_key: "KU#{uid}", owner_id: uid, closed_account: false, fetch_status: 0)
    if profile_id
      cols = {id: profile_id, person_id: person_id, first_name: username.capitalize,
              last_name: "U", searchable: true, nsfw: false}
      cols[:gender] = gender unless gender == :unset
      CE.insert("profiles", **cols)
    end
  end
  prime_salts!(uid)
end

# A body that is NOT an HTTP request (used only to isolate where the JVM dies).
def adv_probe(tag)
  warn "[adv4] PROBE #{tag} START"
  $stderr.flush
  r = yield
  warn "[adv4] PROBE #{tag} -> OK #{r.inspect[0, 200]}"
  r
rescue Exception => e # rubocop:disable Lint/RescueException
  warn "[adv4] PROBE #{tag} -> #{e.class}: #{e.message.to_s[0, 200]}"
  nil
end
