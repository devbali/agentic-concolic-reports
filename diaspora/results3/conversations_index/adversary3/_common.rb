# ADVERSARY ROUND 3 common harness for conversations_index.
# Same env / real-warden / TestCase dispatch as rounds 1 and 2. NO mocks,
# stubs or monkey-patches of app code; fixtures are raw INSERTs and the only
# other inputs are params, headers, session, format and the session user.
#
# DIFFERENCE from round 2: ONE REQUEST PER CONCRETE SCENARIO, so the probe's
# per-scenario `statements` array segments the run by request (round 2 put
# 4-6 requests in one scenario and could not attribute a statement to one).
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
BATCH = "/home/dev/project/reports/diaspora/results3/conversations_index"
ADV_DIR = File.expand_path("..", __FILE__)
REAL_SALT_CACHE = {}

def adv_setup!(name)
  CE.setup!(db: File.join(ADV_DIR, "runs", "#{name}.sqlite3"))
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
  c = ActiveRecord::Base.connection
  warn "[adv3] adapter=#{c.adapter_name} quoted_true=#{c.quoted_true.inspect} quoted_false=#{c.quoted_false.inspect}"
end

# alice = user 9 / person 1 / profile 11; bob = person 2; carol = person 3.
def seed_people!(bob_profile: true, carol_profile: true, alice_profile: true, alice_lang: "en")
  CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: alice_lang, getting_started: false, disable_mail: false, sign_in_count: 1)
  CE.insert("people", id: 1, guid: "aliceguid", diaspora_handle: "alice@localhost",
            serialized_public_key: "K1", owner_id: 9, closed_account: false, fetch_status: 0)
  CE.insert("people", id: 2, guid: "bobguid", diaspora_handle: "bob@remote.example",
            serialized_public_key: "K2", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("people", id: 3, guid: "carolguid", diaspora_handle: "carol@remote.example",
            serialized_public_key: "K3", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: true, nsfw: false) if alice_profile
  CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: true, nsfw: false) if bob_profile
  CE.insert("profiles", id: 13, person_id: 3, first_name: "Carol", last_name: "C", searchable: true, nsfw: false) if carol_profile
  # alice <-> bob mutual contact (contacts_data pluck row; no_contacts false)
  CE.insert("contacts", id: 700, user_id: 9, person_id: 2, sharing: true, receiving: true)
  REAL_SALT_CACHE[9] = User.find(9).authenticatable_salt
end

# the batch's own two conversations, so every scenario is a variation of a
# state the corpus claims to model
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
    [ActiveRecord::FinderMethods, :exists?],
  ] + extra_more)
end

def install_real_warden(tc, uid = 9)
  real_salt = (REAL_SALT_CACHE[uid] ||= User.find(uid).authenticatable_salt)
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  # The memo MUST live on the warden object (one per request), not on the
  # lambda's `self` (= main, one per PROCESS). With a process-wide memo the
  # Devise `users` read and `current_user.person`'s `people.owner_id` read are
  # issued by the FIRST request only and every later request in the manifest
  # silently under-reports them — which is exactly the evidence the M-5 /
  # T-f one-statement multiset is made of. (The batch's own
  # concrete_manifest_auth.rb and both earlier adversary rounds have the
  # process-wide form: 1 `users` statement for 5 requests.)
  wuser = lambda { |*_a| warden.instance_variable_get(:@cc_user) ||
                         warden.instance_variable_set(:@cc_user, User.serialize_from_session(uid, real_salt)) }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

# One request. Never raises: the status/exception is logged so the scenario
# still writes its statements.
def adv_request(format:, params: {}, session: {}, headers: {}, uid: 9, tag: nil)
  ctrl, tc = make_harness(ConversationsController)
  install_real_warden(tc, uid)
  session.each { |k, v| tc.session[k] = v }
  headers.each { |k, v| tc.request.headers[k] = v }
  # Each REAL request gets a fresh ActiveRecord query cache. Without this the
  # cache is shared across every request of the process, `payload[:cached]` is
  # true and concrete_run_probe.rb DROPS the statement (`next if
  # payload[:cached]`) — so the second and later requests of a manifest under-
  # report. (The batch's own concrete_run.json has 1 `users` read for 5
  # requests for exactly this reason.)
  ActiveRecord::Base.connection.clear_query_cache
  begin
    tc.process(:index, method: :get, params: params, format: format)
    status = ctrl.response.status
    body = ctrl.response.body.to_s
    warn "[adv3] #{tag} #{format} #{params.inspect} uid=#{uid} -> #{status} (#{body.bytesize} B) fmt=#{ctrl.request.format.to_sym}"
    File.write(File.join(ADV_DIR, "runs", "_body_#{tag}.txt"), body) if tag
    [status, body]
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "[adv3] #{tag} #{format} #{params.inspect} uid=#{uid} -> RAISED #{e.class}: #{e.message.to_s[0, 180]}"
    [500, "#{e.class}"]
  end
end

# ONE request per concrete scenario -> per-request statement segmentation.
def adv_scenarios(specs, targets: adv_targets)
  specs.map do |sp|
    { name: sp[:name], targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/},
      body: sp[:body] }
  end
end

ConversationsController.layout(false) unless ENV["ADV3_REAL_LAYOUT"] == "1"
