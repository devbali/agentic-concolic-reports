# ADVERSARY common harness for conversations_index (modelled on the batch's
# concrete_manifest_auth.rb — same env, same real-warden, same TestCase
# dispatch, same layout(false) parity). NO fixtures here: each scenario
# manifest seeds its own rows. Nothing in here mocks or stubs app code.
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
BATCH = "/home/dev/project/reports/diaspora/results3/conversations_index"
ADV_DIR = File.expand_path("..", __FILE__)

def adv_setup!(name)
  CE.setup!(db: File.join(ADV_DIR, "runs", "#{name}.sqlite3"))
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
end

# The standard principal: alice (user 9 / person 1 / profile 11), plus bob
# (person 2, remote) and carol (person 3, remote), alice<->bob mutual
# contact. Scenarios add/omit rows on top of this by passing flags.
def seed_people!(bob_profile: true, carol_profile: true, alice_profile: true, alice_lang: "en",
                 bob_closed: false, carol_closed: false)
  CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: alice_lang, getting_started: 0, disable_mail: 0, sign_in_count: 1)
  CE.insert("people", id: 1, guid: "aliceguid", diaspora_handle: "alice@localhost",
            serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
  CE.insert("people", id: 2, guid: "bobguid", diaspora_handle: "bob@remote.example",
            serialized_public_key: "K2", owner_id: nil, closed_account: bob_closed ? 1 : 0, fetch_status: 0)
  CE.insert("people", id: 3, guid: "carolguid", diaspora_handle: "carol@remote.example",
            serialized_public_key: "K3", owner_id: nil, closed_account: carol_closed ? 1 : 0, fetch_status: 0)
  CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0) if alice_profile
  CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0) if bob_profile
  CE.insert("profiles", id: 13, person_id: 3, first_name: "Carol", last_name: "C", searchable: 1, nsfw: 0) if carol_profile
  CE.insert("contacts", id: 700, user_id: 9, person_id: 2, sharing: 1, receiving: 1)
  REAL_SALT_CACHE[:salt] = User.find(9).authenticatable_salt
end

# The batch's two conversations (so every scenario is a strict superset /
# variation of the batch's own fixture state).
def seed_batch_conversations!
  CE.insert("conversations", id: 1, subject: "hello alice", guid: "convguid1", author_id: 2)
  CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 1)
  CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
  CE.insert("conversation_visibilities", id: 23, conversation_id: 1, person_id: 3, unread: 0)
  CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "msgguid1",
            text: "hi alice, first message")
  CE.insert("messages", id: 32, conversation_id: 1, author_id: 1, guid: "msgguid2",
            text: "hi bob @{bob@remote.example} reply")
  CE.insert("conversations", id: 2, subject: "", guid: "convguid2", author_id: 1)
  CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 1, unread: 0)
  CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 2, unread: 0)
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
  targets_from_corpus(BATCH, exclude: {
    "ActionController::Rendering._set_rendered_content_type" => "render plumbing; no SQL evidence",
    "ActionController::Head.head" => "head terminal; no SQL evidence",
  }, extra: [
    [ActiveRecord::FinderMethods, :first],
    [ActiveRecord::FinderMethods, :find_by],
    [ActiveRecord::Relation, :records],
    [ActiveRecord::Relation, :to_a],
    [ActiveRecord::Calculations, :count],
    [ActiveRecord::Calculations, :pluck],
    [ActiveRecord::Associations::CollectionProxy, :records],
    [ActiveRecord::Associations::CollectionProxy, :load_target],
    [ActiveRecord::Associations::CollectionProxy, :to_a],
  ] + extra_more)
end

# salt computed ONCE at fixture-load time (outside the probe capture window), as the batch does
def install_real_warden(tc)
  real_salt = (REAL_SALT_CACHE[:salt] ||= User.find(9).authenticatable_salt)
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| @concrete_user ||= User.serialize_from_session(9, real_salt) }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

REAL_SALT_CACHE = {}
ConversationsController.layout(false)   # render-config parity with the batch

# One request: returns [status, body]. Never raises on status (the probe's
# per-scenario `error` is reserved for real exceptions out of the app).
def adv_request(format:, params: {}, session: {}, headers: {})
  ctrl, tc = make_harness(ConversationsController)
  install_real_warden(tc)
  session.each { |k, v| tc.session[k] = v }
  headers.each { |k, v| tc.request.headers[k] = v }
  tc.process(:index, method: :get, params: params, format: format)
  status = ctrl.response.status
  body = ctrl.response.body.to_s
  warn "[adversary] #{format} #{params.inspect} session=#{session.inspect} headers=#{headers.keys.inspect} -> #{status} (#{body.bytesize} bytes)"
  File.write(File.join(ADV_DIR, "runs", "_last_body_#{format}_#{params.values.join('_')}.html"), body)
  [status, body]
end

def adv_scenario(name, targets: adv_targets, &body)
  [{ name: name, targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/}, body: body }]
end
