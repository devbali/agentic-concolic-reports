# ADVERSARY ROUND 6 common harness (copy of adversary5/_common.rb + remote_addr:, raw_cookie:, fullstack headers) for conversations_index.
# Base: adversary4/_common.rb, carrying INSTR-1/2/3/5/8/9/10 of rounds 3-4
# (warden-bound principal memo, fresh AR query cache per request, adapter-
# quoted booleans, every salt precomputed at fixture load, real layout,
# real Warden::Proxy from Devise.warden_config, positional options hash).
# NO mocks, stubs or monkey-patches of app code; fixtures are raw INSERTs and
# the only other inputs are params, headers, cookies, session, format and
# the principal.
#
# NEW in round 5 (all rig CONFIGURATION / request inputs, no app code):
#   * install_remember_cookie — a REAL signed `remember_user_token` cookie in
#     Devise's own serialize_into_cookie shape, so Devise::Strategies::
#     Rememberable runs when no session principal exists (the "remember me"
#     return visit). session_key: false / salt: <wrong> give a session-less or
#     a stale (password-changed) session principal.
#   * query_string: — a RAW query string (production's `?conversation_id[]`
#     is `[nil]` -> deep_munge -> `[]`; TestCase#process cannot express it).
#   * fullstack_request — the request dispatched through
#     `Rails.application.call(env)`: the app's OWN middleware stack (Warden
#     manager, cookie session store, executor -> AR query cache, exception
#     handling, mobile-fu), with a real encrypted `_diaspora_session` cookie.
#     Nothing is stubbed; this is strictly MORE of the real app than
#     ActionController::TestCase#process.
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
BATCH = "/home/dev/project/reports/diaspora/results3/conversations_index"
ADV_DIR = File.expand_path("..", __FILE__)
REAL_SALT_CACHE = {}

def adv_setup!(name)
  CE.setup!(db: File.join(ADV_DIR, "_db", "#{name}.sqlite3"))
  Rails.application.config.assets.check_precompiled_asset = false
  ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)
  c = ActiveRecord::Base.connection
  warn "[adv6] adapter=#{c.adapter_name} quoted_true=#{c.quoted_true.inspect} query_cache_enabled=#{c.query_cache_enabled.inspect}"
end

def ts(t)
  t.utc.strftime("%Y-%m-%d %H:%M:%S")
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
  CE.insert("contacts", id: 700, user_id: 9, person_id: 2, sharing: true, receiving: true)
  precompute_salt!(9)
end

# an extra principal: user uid / person pid / profile pid+40 (person: false -> NO people row)
def seed_principal!(uid, pid, name, lang: "en", profile: true, person: true, extra: {}, person_extra: {})
  CE.insert("users", **{ id: uid, username: name, email: "#{name}@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: lang, getting_started: false, disable_mail: false, sign_in_count: 1 }.merge(extra))
  if person
    CE.insert("people", **{ id: pid, guid: "#{name}guid", diaspora_handle: "#{name}@localhost",
              serialized_public_key: "K#{pid}", owner_id: uid, closed_account: false, fetch_status: 0 }.merge(person_extra))
    CE.insert("profiles", id: pid + 40, person_id: pid, first_name: name.capitalize, last_name: "X", searchable: true, nsfw: false) if profile
  end
  precompute_salt!(uid)
end

# INSTR-5: salts at fixture-load time, OUTSIDE the capture window.
def precompute_salt!(uid)
  REAL_SALT_CACHE[uid] = User.find(uid).authenticatable_salt
end

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

# the layout's rows for alice (round-4 Q02 set)
def seed_layout_rows!(uid: 9, pid: 1, admin: true, services: 1, tags: 2, notif_unread: 1, reports_unreviewed: 1)
  CE.insert("aspects", id: 1, user_id: uid, name: "Friends", order_id: 1)
  CE.insert("aspects", id: 2, user_id: uid, name: "Work", order_id: 2)
  notif_unread.times { |i| CE.insert("notifications", id: 100 + i, target_type: "Mention", target_id: 1, recipient_id: uid, unread: true, type: "Notifications::Mentioned") }
  CE.insert("notifications", id: 199, target_type: "Mention", target_id: 2, recipient_id: uid, unread: false, type: "Notifications::Mentioned")
  services.times { |i| CE.insert("services", id: 1 + i, type: "Services::Twitter", user_id: uid, uid: "tw#{i}", access_token: "t", access_secret: "s", nickname: "a#{i}") }
  tags.times { |i| CE.insert("tags", id: 1 + i, name: "tag#{i}", taggings_count: 0); CE.insert("tag_followings", id: 1 + i, tag_id: 1 + i, user_id: uid) }
  CE.insert("roles", id: 1, person_id: pid, name: "admin") if admin
  reports_unreviewed.times { |i| CE.insert("reports", id: 1 + i, item_id: 1, item_type: "Post", user_id: uid, reviewed: false, text: "spam") }
  CE.insert("reports", id: 99, item_id: 2, item_type: "Post", user_id: uid, reviewed: true, text: "ok")
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

# ---- the REAL warden (INSTR-9) -------------------------------------------
def devise_warden_ready!
  Rails.application.app
  Devise.configure_warden!
  raise "Devise.warden_config not populated" unless Devise.warden_config
  warn "[adv6] Devise.warden_config ready; after_set_user hooks=#{Warden::Manager._after_set_user.size} before_logout=#{Warden::Manager._before_logout.size} strategies=#{Devise.warden_config.default_strategies(scope: :user).inspect}"
end

# session_key: false -> no principal in the session (anonymous unless a
# remember cookie is present); salt: -> override the session's salt (a
# password change on another device leaves the old salt in the session).
def install_devise_warden(tc, uid = 9, session_key: true, salt: nil)
  env = tc.instance_variable_get(:@request).env
  if session_key
    tc.session["warden.user.user.key"] = [[uid], salt || REAL_SALT_CACHE.fetch(uid) { raise "salt for uid #{uid} not precomputed (INSTR-5)" }]
  end
  env["warden"] = Warden::Proxy.new(env, real_warden_manager)
end

# INSTR-11 (round 5): `Warden::Manager.new(nil, Devise.warden_config.dup)`
# (round 4's rig AND the batch's concrete_manifest_auth.rb) is WRONG once a
# strategy has to run: Manager#initialize does `options.delete(:default_strategies)`
# and re-splats that Hash into `default_strategies(*…)`, which files
# `[:user, :rememberable, …]` under `:_all` and drops the `:user` scope —
# every session-less request raises "Invalid strategy user". A session FETCH
# never runs strategies, which is why round 4 and the batch never saw it.
# The manager below is the app's own instance from the built middleware stack.
def real_warden_manager
  $real_warden_manager ||= begin
    m = Rails.application.app
    seen = 0
    until m.nil? || m.is_a?(Warden::Manager) || seen > 200
      m = m.instance_variable_get(:@app); seen += 1
    end
    raise "Warden::Manager not found in the middleware stack" unless m.is_a?(Warden::Manager)
    warn "[adv6] real Warden::Manager from the stack: default_strategies(:user)=#{m.config.default_strategies(scope: :user).inspect}"
    m
  end
end

# Devise's own cookie shape: [record.to_key, record.rememberable_value, Time.now.utc.to_f.to_s]
# (rememberable_value = authenticatable_salt: users has no remember_token column)
def install_remember_cookie(tc, uid, generated_at: nil, token: nil)
  tc.cookies.signed["remember_user_token"] = [[uid], token || REAL_SALT_CACHE.fetch(uid), generated_at || Time.now.utc.to_f.to_s]
end

# One request through ActionController::TestCase#process. Never raises.
# round 6: remote_addr: sets REMOTE_ADDR (trackable's `request.remote_ip` on the
# TestCase rig, which runs no RemoteIp middleware); raw_cookie: puts an UNSIGNED
# string into remember_user_token (a garbage / foreign cookie);
# remember_uid: signs the cookie for a different uid than the principal.
def adv_request(format:, params: {}, session: {}, headers: {}, uid: 9, tag: nil, session_key: true, salt: nil,
                remember: nil, query_string: nil, remote_addr: nil, raw_cookie: nil, remember_uid: nil)
  ctrl, tc = make_harness(ConversationsController)
  session.each { |k, v| tc.session[k] = v }
  headers.each { |k, v| tc.request.headers[k] = v }
  tc.request.env["REMOTE_ADDR"] = remote_addr if remote_addr
  install_devise_warden(tc, uid, session_key: session_key, salt: salt)
  install_remember_cookie(tc, remember_uid || uid, **remember) if remember
  tc.cookies["remember_user_token"] = raw_cookie if raw_cookie
  tc.request.env["QUERY_STRING"] = query_string if query_string
  CompletionChecker.new_request! if defined?(CompletionChecker)
  ActiveRecord::Base.connection.clear_query_cache
  thrown = nil
  begin
    thrown = catch(:warden) do
      tc.process(:index, method: :get, params: params, format: format)
      nil
    end
    status = ctrl.response.status
    body = ctrl.response.body.to_s
    warn "[adv6] #{tag} #{format} #{params.inspect} qs=#{query_string.inspect} uid=#{uid} session_key=#{session_key} remember=#{remember ? 'yes' : 'no'} ip=#{remote_addr.inspect} -> #{status} (#{body.bytesize} B) fmt=#{ctrl.request.format.to_sym rescue '?'}#{thrown ? " THROWN :warden #{thrown.inspect}" : ''} params=#{ctrl.params.to_unsafe_h.inspect[0, 120]}"
    File.write(File.join(ADV_DIR, "_bodies", "_body_#{tag}.txt"), body) if tag
    [status, body, thrown]
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "[adv6] #{tag} #{format} #{params.inspect} qs=#{query_string.inspect} uid=#{uid} -> RAISED #{e.class}: #{e.message.to_s[0, 200]}"
    File.write(File.join(ADV_DIR, "_bodies", "_err_#{tag}.txt"), "#{e.class}: #{e.message}\n#{e.backtrace.first(25).join("\n")}") if tag
    [500, "#{e.class}", nil]
  end
end

# ---- the FULL middleware stack --------------------------------------------
SESSION_KEY = Rails.application.config.session_options[:key] || "_diaspora_session"

def fullstack_cookie_header(uid: nil, session: {}, remember: nil, salt: nil)
  env = Rails.application.env_config.merge(Rack::MockRequest.env_for("/"))
  jar = ActionDispatch::Request.new(env).cookie_jar
  parts = []
  unless uid.nil? && session.empty?
    data = { "session_id" => SecureRandom.hex(16) }.merge(session.transform_keys(&:to_s))
    data["warden.user.user.key"] = [[uid], salt || REAL_SALT_CACHE.fetch(uid)] if uid
    jar.encrypted[SESSION_KEY] = data
    parts << "#{SESSION_KEY}=#{Rack::Utils.escape(jar[SESSION_KEY])}"
  end
  if remember
    ruid = remember[:uid]
    jar.signed["remember_user_token"] = [[ruid], remember[:token] || REAL_SALT_CACHE.fetch(ruid), remember[:generated_at] || Time.now.utc.to_f.to_s]
    parts << "remember_user_token=#{Rack::Utils.escape(jar['remember_user_token'])}"
  end
  parts.join("; ")
end

def fullstack_request(path: "/conversations", headers: {}, uid: nil, session: {}, remember: nil, salt: nil, tag: nil)
  cookie = fullstack_cookie_header(uid: uid, session: session, remember: remember, salt: salt)
  # Rack::SSL (config/initializers/enforce_ssl.rb, AppConfig.environment.require_ssl?) is in the real stack: dispatch over https
  env = Rack::MockRequest.env_for("https://localhost#{path}", { "HTTP_COOKIE" => cookie, "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1" }.merge(headers))
  CompletionChecker.new_request! if defined?(CompletionChecker)
  ActiveRecord::Base.connection.clear_query_cache
  begin
    status, hdrs, body = Rails.application.call(env)
    out = +""
    body.each { |chunk| out << chunk.to_s }
    body.close if body.respond_to?(:close)
    warn "[adv6:fullstack] #{tag} #{path} uid=#{uid.inspect} remember=#{remember ? 'yes' : 'no'} session=#{session.inspect} -> #{status} (#{out.bytesize} B) ct=#{hdrs['Content-Type']} loc=#{hdrs['Location']} setcookie=#{hdrs['Set-Cookie'].to_s[0, 60].inspect}"
    File.write(File.join(ADV_DIR, "_bodies", "_body_#{tag}.txt"), out) if tag
    [status, out]
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "[adv6:fullstack] #{tag} #{path} -> RAISED #{e.class}: #{e.message.to_s[0, 200]}"
    File.write(File.join(ADV_DIR, "_bodies", "_err_#{tag}.txt"), "#{e.class}: #{e.message}\n#{e.backtrace.first(30).join("\n")}") if tag
    [500, "#{e.class}"]
  end
end

def adv_scenarios(specs, targets: adv_targets)
  specs.map do |sp|
    { name: sp[:name], targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/}, body: sp[:body] }
  end
end

if ENV["ADV5_REAL_LAYOUT"] == "0"
  ConversationsController.layout(false)
  warn "[adv6] layout(false) applied (ADV5_REAL_LAYOUT=0)"
else
  ActionView::Base.resolve_assets_with = []
  ActionView::Base.unknown_asset_fallback = true
  warn "[adv6] REAL LAYOUT: layout(false) NOT applied; asset resolvers emptied (INSTR-8)"
end
