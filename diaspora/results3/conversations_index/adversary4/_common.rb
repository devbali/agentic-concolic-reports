# ADVERSARY ROUND 4 common harness for conversations_index.
# Same env / TestCase dispatch as round 3 (adversary3/_common.rb), carrying
# every instrument fix of that round:
#   INSTR-1  principal memo bound to the per-request warden object
#   INSTR-2  fresh AR query cache per request (CompletionChecker.new_request!)
#   INSTR-3  booleans written through the adapter (true/false, never 1/0)
#   INSTR-5  EVERY principal's salt computed at fixture-load time, outside
#            the capture window (seed_people! takes the list of uids)
# NO mocks, stubs or monkey-patches of app code; fixtures are raw INSERTs and
# the only other inputs are params, headers, session, format and the principal.
#
# NEW in round 4 (both are RIG CONFIGURATION, not app code):
#   * ADV4_DEVISE_WARDEN=1 — the request carries a REAL `Warden::Proxy` built
#     from `Devise.warden_config` (the exact object production's
#     Warden::Manager middleware builds), with the principal in the session
#     under Devise's own key.  Every round so far (and every batch manifest)
#     replaced warden with a stub Object that answers `user`/`authenticate`
#     and therefore NEVER RUNS Warden's `after_set_user` callbacks.
#   * ADV4_REAL_LAYOUT=1 — `ConversationsController.layout(false)` is NOT
#     applied, and the sprockets resolvers on the view are emptied
#     (`ActionView::Base.resolve_assets_with = []`, `unknown_asset_fallback =
#     true`) so `javascript_include_tag`/`image_tag`/`stylesheet_link_tag`
#     fall back to plain public paths instead of raising on the stripped
#     asset tree.  This is the same class of knob every harness already
#     sets (`check_precompiled_asset = false`).  The app renders its REAL
#     layout, header, drawer and gon block.
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
  warn "[adv4] adapter=#{c.adapter_name} quoted_true=#{c.quoted_true.inspect} quoted_false=#{c.quoted_false.inspect}"
end

# alice = user 9 / person 1 / profile 11; bob = person 2; carol = person 3.
def seed_people!(bob_profile: true, carol_profile: true, alice_profile: true, alice_lang: "en", alice_extra: {})
  CE.insert("users", **{ id: 9, username: "alice", email: "alice@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: alice_lang, getting_started: false, disable_mail: false, sign_in_count: 1 }.merge(alice_extra))
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
  precompute_salt!(9)
end

# an extra principal: user uid / person pid / profile pid+40
def seed_principal!(uid, pid, name, lang: "en", profile: true, extra: {}, person_extra: {})
  CE.insert("users", **{ id: uid, username: name, email: "#{name}@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: lang, getting_started: false, disable_mail: false, sign_in_count: 1 }.merge(extra))
  CE.insert("people", **{ id: pid, guid: "#{name}guid", diaspora_handle: "#{name}@localhost",
            serialized_public_key: "K#{pid}", owner_id: uid, closed_account: false, fetch_status: 0 }.merge(person_extra))
  CE.insert("profiles", id: pid + 40, person_id: pid, first_name: name.capitalize, last_name: "X", searchable: true, nsfw: false) if profile
  precompute_salt!(uid)
end

# INSTR-5: salts at fixture-load time, OUTSIDE the capture window.
def precompute_salt!(uid)
  REAL_SALT_CACHE[uid] = User.find(uid).authenticatable_salt
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
    [ActiveRecord::Calculations, :sum],
    [ActiveRecord::Calculations, :pluck],
    [ActiveRecord::Associations::CollectionProxy, :records],
    [ActiveRecord::Associations::CollectionProxy, :load_target],
    [ActiveRecord::Associations::CollectionProxy, :to_a],
    [ActiveRecord::FinderMethods, :exists?],
    [ActiveRecord::Persistence, :update_attribute],
  ] + extra_more)
end

# ---- the STUB warden every earlier round / batch manifest used ------------
def install_stub_warden(tc, uid = 9)
  real_salt = REAL_SALT_CACHE.fetch(uid) { raise "salt for uid #{uid} not precomputed (INSTR-5)" }
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| warden.instance_variable_get(:@cc_user) ||
                         warden.instance_variable_set(:@cc_user, User.serialize_from_session(uid, real_salt)) }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

# ---- the REAL warden: Devise's own Warden::Manager configuration -----------
# Production wires `Warden::Manager` as middleware with a block that stores
# the config in `Devise.warden_config`; `Devise.configure_warden!` then adds
# the session (de)serializers and every `Warden::Manager.after_set_user`
# hook registered by Devise's modules and by devise_lastseenable applies.
# Building the app's middleware stack once (`Rails.application.app`) is what
# makes that block run in this rig — no code is added, the app's own
# configuration is simply instantiated.
def devise_warden_ready!
  Rails.application.app # builds the middleware stack -> Warden::Manager block -> Devise.warden_config
  Devise.configure_warden!
  raise "Devise.warden_config not populated" unless Devise.warden_config
  warn "[adv4] Devise.warden_config ready; after_set_user hooks=#{Warden::Manager._after_set_user.size}"
end

def install_devise_warden(tc, uid = 9)
  REAL_SALT_CACHE.fetch(uid) { raise "salt for uid #{uid} not precomputed (INSTR-5)" }
  env = tc.instance_variable_get(:@request).env
  # Devise's serialize_into_session = [record.to_key, record.authenticatable_salt]
  tc.session["warden.user.user.key"] = [[uid], REAL_SALT_CACHE[uid]]
  manager = Warden::Manager.new(nil, Devise.warden_config.dup)
  env["warden"] = Warden::Proxy.new(env, manager)
end

# One request. Never raises: the status/exception is logged so the scenario
# still writes its statements.
def adv_request(format:, params: {}, session: {}, headers: {}, uid: 9, tag: nil, warden: nil)
  ctrl, tc = make_harness(ConversationsController)
  session.each { |k, v| tc.session[k] = v }
  headers.each { |k, v| tc.request.headers[k] = v }
  warden ||= (ENV["ADV4_DEVISE_WARDEN"] == "1" ? :devise : :stub)
  warden == :devise ? install_devise_warden(tc, uid) : install_stub_warden(tc, uid)
  CompletionChecker.new_request! if defined?(CompletionChecker) # INSTR-2
  ActiveRecord::Base.connection.clear_query_cache
  thrown = nil
  begin
    thrown = catch(:warden) do
      tc.process(:index, method: :get, params: params, format: format)
      nil
    end
    status = ctrl.response.status
    body = ctrl.response.body.to_s
    warn "[adv4] #{tag} #{format} #{params.inspect} uid=#{uid} warden=#{warden} -> #{status} (#{body.bytesize} B) fmt=#{ctrl.request.format.to_sym}#{thrown ? " THROWN :warden #{thrown.inspect}" : ''}"
    File.write(File.join(ADV_DIR, "runs", "_body_#{tag}.txt"), body) if tag
    [status, body, thrown]
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "[adv4] #{tag} #{format} #{params.inspect} uid=#{uid} warden=#{warden} -> RAISED #{e.class}: #{e.message.to_s[0, 200]}"
    File.write(File.join(ADV_DIR, "runs", "_err_#{tag}.txt"), "#{e.class}: #{e.message}\n#{e.backtrace.first(25).join("\n")}") if tag
    [500, "#{e.class}", nil]
  end
end

# ONE request per concrete scenario -> per-request statement segmentation.
def adv_scenarios(specs, targets: adv_targets)
  specs.map do |sp|
    { name: sp[:name], targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/},
      body: sp[:body] }
  end
end

if ENV["ADV4_REAL_LAYOUT"] == "1"
  # rig knob: no asset pipeline resolution, plain public paths instead of AssetNotFound
  ActionView::Base.resolve_assets_with = []
  ActionView::Base.unknown_asset_fallback = true
  warn "[adv4] REAL LAYOUT: layout(false) NOT applied; asset resolvers emptied"
else
  ConversationsController.layout(false)
end
