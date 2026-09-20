# CONCRETE CHECKER manifest — conversations_index, MOBILE scenario (cycle 3,
# adversary W1-W3): the app's own session switch (ApplicationController
# #mobile_switch: `session[:mobile_view] == true` + html -> request.format =
# :mobile) renders index.mobile.haml / _conversation.mobile.haml /
# _conversation_subject.haml. Same fixtures as the html/json manifest; one
# process (JVM crash isolation).
#
# (original header follows)
# CONCRETE CHECKER manifest — conversations_index, SIGNED-IN scenario (the
# ONLY scenario: `before_action :authenticate_user!` with no `except:` —
# an anonymous request is 401'd by Devise before the action; there is no
# anonymous endpoint state to model). Real sqlite DB, real rows, real
# Devise warden resolution (the notifications_index pattern), real dispatch
# through ActionController::TestCase#process; no mocks, no stubs. One
# scenario per manifest process (JVM crash isolation); the one body drives
# the four request shapes the corpus explores (html/json x with/without
# conversation_id) against the same fixtures.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_mobile.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

# ---- fixtures (raw INSERTs: data, not code-under-test) --------------------
# alice (signed in, person 1), bob (person 2), carol (person 3)
CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1)
CE.insert("people", id: 1, guid: "aliceguid", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: 0, fetch_status: 0)
CE.insert("people", id: 2, guid: "bobguid", diaspora_handle: "bob@remote.example",
          serialized_public_key: "K2", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("people", id: 3, guid: "carolguid", diaspora_handle: "carol@remote.example",
          serialized_public_key: "K3", owner_id: nil, closed_account: 0, fetch_status: 0)
CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A", searchable: 1, nsfw: 0)
CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B", searchable: 1, nsfw: 0)
CE.insert("profiles", id: 13, person_id: 3, first_name: "Carol", last_name: "C", searchable: 1, nsfw: 0)

# alice <-> bob mutual contact (contacts_data pluck row; no_contacts false)
CE.insert("contacts", id: 700, user_id: 9, person_id: 2, sharing: true, receiving: true) # INSTR-3: the adapter quotes booleans 't'/'f'; integer 1 matched nothing
# round 4 (C-12): rows the MOBILE layout reads — _drawer.mobile followed_tags
# (tags JOIN tag_followings), unreviewed_reports_count for an admin (roles),
# and an unread notification for the _header.mobile badge branch.
CE.insert("roles", id: 1, person_id: 1, name: "admin")
CE.insert("tags", id: 1, name: "ruby", taggings_count: 0)
CE.insert("tag_followings", id: 1, tag_id: 1, user_id: 9)
CE.insert("notifications", id: 1, target_type: "Mention", target_id: 1, recipient_id: 9, unread: true, type: "Notifications::Mentioned")

# conversation 1: bob started it, three participants, two messages, alice
# has 1 unread (first_unread_message + set_read's UPDATE fire; the
# `visibility.unread > 0` and `other_participants.count > 1` branches).
CE.insert("conversations", id: 1, subject: "hello alice", guid: "convguid1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 1)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 23, conversation_id: 1, person_id: 3, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "msgguid1",
          text: "hi alice, first message")
CE.insert("messages", id: 32, conversation_id: 1, author_id: 1, guid: "msgguid2",
          text: "hi bob @{bob@remote.example} reply")

# conversation 2: alice + bob, NO messages, nothing unread (the empty-side
# branches: messages.present? false, last_author nil, no unread badge).
CE.insert("conversations", id: 2, subject: "", guid: "convguid2", author_id: 1)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 25, conversation_id: 2, person_id: 2, unread: 0)

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
  "ActionController::Rendering._set_rendered_content_type" => "render plumbing; no SQL evidence",
  "ActionController::Head.head" => "head terminal; no SQL evidence",
}, extra: [
  [ActiveRecord::FinderMethods, :first],     # convidx_conv_lookup / devise_user_first aliases' real method
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Calculations, :pluck],
  # real CollectionProxy frames (the corpus's symbolic reps route the same
  # association reads through plain Relations — ConvoSymAssociations)
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
  [ActiveRecord::Associations::CollectionProxy, :to_a],
])

# honest warden: Devise's REAL serialize_from_session resolves the user
# from the REAL users row (salt = real authenticatable_salt). Computed ONCE
# at fixture-load time (outside the probe's statement-capture window).
REAL_SALT = User.find(9).authenticatable_salt
# round 4: a NON-admin principal for the mobile drawer's moderator-exists arm
# (`_drawer.mobile.haml:55` runs only when not admin: roles.name IN (...) x2).
CE.insert("users", id: 10, username: "dora", email: "dora@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789", language: "en",
          getting_started: false, disable_mail: false, sign_in_count: 1,
          last_seen: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"))
CE.insert("people", id: 4, guid: "doraguid", diaspora_handle: "dora@localhost",
          serialized_public_key: "K4", owner_id: 10, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 44, person_id: 4, first_name: "Dora", last_name: "X", searchable: true, nsfw: false, gender: "female")
REAL_SALTS = { 9 => REAL_SALT, 10 => User.find(10).authenticatable_salt } # INSTR-5: at load, outside the capture window
# (POST-AUTH SCOPE: the INSTR-9/11 real Warden::Manager block moved to the
# auth-boundary policy — _auth_boundary/evidence/.)
ActionView::Base.resolve_assets_with = []
ActionView::Base.unknown_asset_fallback = true
def install_real_warden(tc, uid = 9)
  # POST-AUTH SCOPE (2026-08-31, Bali): HOOK-LESS resolution — Devise's REAL
  # serialize_from_session resolves the user from the real row (the symbolic
  # fetch's ground truth); the auth-stage hooks (trackable / lastseenable /
  # lockable / rememberable) run ABOVE the entrypoint and belong to the shared
  # auth-boundary policy (reports/diaspora/results3/_auth_boundary/), so this
  # manifest's requests are auth-quiet by construction. (The INSTR-1 memo
  # lives on the WARDEN object — one per request.)
  salt = REAL_SALTS.fetch(uid) { raise "salt for uid #{uid} not precomputed (INSTR-5)" }
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| warden.instance_variable_get(:@cc_user) ||
                         warden.instance_variable_set(:@cc_user, User.serialize_from_session(uid, salt)) }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

# Render-config parity with the corpus runner (run_dse.rb's standing scope
# decision, same as notifications_index's concrete manifest): the site
# chrome layout is out of scope for this endpoint's query surface.
# layout(false) REMOVED (round 4, INSTR-8): the real mobile layout renders

REQUESTS_HTML = [
  { format: :html, params: {} },
  { format: :html, params: { conversation_id: "1" } },
  { format: :json, params: {} },
  { format: :json, params: { conversation_id: "1" } },
]

REQUESTS = [
  { params: {}, session: { mobile_view: true } },
  { params: { conversation_id: "1" }, session: { mobile_view: true } },
  # round 4: a NON-admin principal, selected the same way as the others (the
  # real mobile_switch: session[:mobile_view] + html -> :mobile), so the mobile
  # layout with _header/_drawer renders: moderator-exists x2 on the not-admin arm.
  { params: {}, session: { mobile_view: true }, uid: 10, skip_body: true },
]

CONCRETE_SCENARIOS = [
  { name: "conversations-index-mobile-2-variants",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      REQUESTS.each do |req|
        ctrl, tc = make_harness(ConversationsController)
        # INSTR-2: several requests in ONE process — reset the AR query cache
        # between them, as a real deployment does per request.
        CompletionChecker.new_request! if defined?(CompletionChecker)
        install_real_warden(tc, req[:uid] || 9)
        tc.process(:index, method: :get, params: req[:params], session: req[:session], format: :html)
        raise "#{req.inspect}: unexpected status #{ctrl.response.status}" unless ctrl.response.status == 200
        next if req[:skip_body]
        # A3-14 evidence — the LAYOUT's data access: a real mobile request renders
        # the "application" layout (ApplicationController's layout proc), whose
        # include_gon serialises the UserPresenter pushed by gon_set_current_user.
        # The rig cannot render the layout (sprockets), so the presenter is driven
        # directly, inside the same request — as run_dse.rb does (NM-5).
        # (hand-driven UserPresenter call removed in round 4: application.mobile.haml renders _head/_header/_drawer for real — C-12)
        raise "#{req.inspect}: not the mobile template" unless ctrl.request.format.to_sym == :mobile
        body = ctrl.response.body.to_s
        raise "#{req.inspect}: conversation not rendered: #{body[0, 160]}" unless body.include?("hello alice")
      end
    end },
]
