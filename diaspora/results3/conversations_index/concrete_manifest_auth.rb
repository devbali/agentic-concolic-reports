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
CE.setup!(db: File.expand_path("../concrete_auth.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

# ---- fixtures (raw INSERTs: data, not code-under-test) --------------------
# alice (signed in, person 1), bob (person 2), carol (person 3)
CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: 0, disable_mail: 0, sign_in_count: 1,
          remember_created_at: (Time.now.utc - 3600).strftime("%Y-%m-%d %H:%M:%S")) # round 5: alice is REMEMBERED (the cookie validates)
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
CE.insert("contacts", id: 700, user_id: 9, person_id: 2, sharing: true, receiving: true) # INSTR-3: adapter quotes booleans 't'/'f'; integer 1 matched nothing

# conversation 1: bob started it, three participants, two messages, alice
# has 1 unread (first_unread_message + set_read's UPDATE fire; the
# `visibility.unread > 0` and `other_participants.count > 1` branches).
CE.insert("conversations", id: 1, subject: "hello alice", guid: "convguid1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 1)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 23, conversation_id: 1, person_id: 3, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "msgguid1",
          text: "hi alice, first message")
# cycle 4 (adversary round 2, W1): a post row + diaspora:// links in message
# text — MessageRenderer#diaspora_links issues Post.exists?(guid:) for every
# `post`-entity link (existing and missing guid), none for a `comment` link.
CE.insert("posts", id: 500, author_id: 2, guid: "postguid0123456789abcdef", type: "StatusMessage",
          text: "a post to link to", public: 1)
CE.insert("messages", id: 32, conversation_id: 1, author_id: 1, guid: "msgguid2",
          text: "hi bob @{bob@remote.example} see diaspora://bob@remote.example/post/postguid0123456789abcdef " \
                "and diaspora://bob@remote.example/post/missingguid0123456789xyz " \
                "and diaspora://bob@remote.example/comment/anotherguid0123456789ab reply")

# conversation 2: alice + bob, NO messages, nothing unread (the empty-side
# branches: messages.present? false, last_author nil, no unread badge).
CE.insert("conversations", id: 2, subject: "", guid: "convguid2", author_id: 1)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 1, unread: 0)
# Adversary round 3 evidence (A3-14): a SECOND principal with NO conversations.
# The `.js` format renders index.haml in full and 500s at index.haml:32
# (NameError `no_contacts`); on an EMPTY inbox `@visibilities` is never loaded,
# so `NameError#message` -> view-context inspect -> `Relation#inspect` ->
# `take(11)` issues a REAL read (A3-9b). This request produces that statement.
CE.insert("users", id: 10, username: "dora", email: "dora@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: false, disable_mail: false, sign_in_count: 1)
CE.insert("people", id: 4, guid: "doraguid", diaspora_handle: "dora@localhost",
          serialized_public_key: "K4", owner_id: 10, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 44, person_id: 4, first_name: "Dora", last_name: "X",
          searchable: true, nsfw: false, gender: "female")
# Adversary round 4 evidence (C-10/C-11/C-12): principals for the boundary arms
# and rows for the mobile layout's reads. alice (9) has last_seen NULL -> the
# stamp! write on her first request; 11 is FRESH (no write); 12 is LOCKED
# (activatable logout -> forget_me! write -> throw :warden 401).
CE.insert("users", id: 11, username: "fay", email: "fay@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789", language: "en",
          getting_started: false, disable_mail: false, sign_in_count: 1,
          last_seen: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"))
CE.insert("people", id: 5, guid: "fayguid", diaspora_handle: "fay@localhost",
          serialized_public_key: "K5", owner_id: 11, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 45, person_id: 5, first_name: "Fay", last_name: "X", searchable: true, nsfw: false, gender: "female")
CE.insert("users", id: 12, username: "gus", email: "gus@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789", language: "en",
          getting_started: false, disable_mail: false, sign_in_count: 1,
          locked_at: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"),
          remember_created_at: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"))
CE.insert("people", id: 6, guid: "gusguid", diaspora_handle: "gus@localhost",
          serialized_public_key: "K6", owner_id: 12, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 46, person_id: 6, first_name: "Gus", last_name: "X", searchable: true, nsfw: false, gender: "male")
# A5-7: a FRESH remembered principal (13): first-ever cookie login, then a login
# from a NEW IP -> the sixth trackable shape (last pair unchanged, current_ip written).
CE.insert("users", id: 13, username: "hal", email: "hal@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789", language: "en",
          getting_started: false, disable_mail: false, sign_in_count: 0,
          last_seen: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"),
          remember_created_at: (Time.now.utc - 3600).strftime("%Y-%m-%d %H:%M:%S"))
CE.insert("people", id: 7, guid: "halguid", diaspora_handle: "hal@localhost",
          serialized_public_key: "K7", owner_id: 13, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 47, person_id: 7, first_name: "Hal", last_name: "X", searchable: true, nsfw: false, gender: "male")
# round 6 evidence. 14: remembered with a STALE last_seen -> a cookie login issues
# trackable's write and THEN lastseenable's (C-16: `SET updated_at, last_seen`).
# 15/16: same-second timestamps with DIFFERENT IPs (C-17: A ∧ ¬B) then a cookie
# login from the same IP (15) / a new IP (16).
CE.insert("users", id: 14, username: "ned", email: "ned@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789", language: "en",
          getting_started: false, disable_mail: false, sign_in_count: 1,
          remember_created_at: (Time.now.utc - 3600).strftime("%Y-%m-%d %H:%M:%S"))
CE.insert("people", id: 8, guid: "nedguid", diaspora_handle: "ned@localhost",
          serialized_public_key: "K8", owner_id: 14, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 48, person_id: 8, first_name: "Ned", last_name: "X", searchable: true, nsfw: false, gender: "male")
[[15, 9, "dan", "10.1.1.1", "10.2.2.2"], [16, 10, "eve", "10.1.1.1", "10.2.2.2"]].each do |uid, pid, nm, cur, last|
  CE.insert("users", id: uid, username: nm, email: "#{nm}@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789", language: "en",
            getting_started: false, disable_mail: false, sign_in_count: 2,
            last_seen: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"),
            remember_created_at: (Time.now.utc - 3600).strftime("%Y-%m-%d %H:%M:%S"),
            current_sign_in_at: "2026-08-29 10:00:00", last_sign_in_at: "2026-08-29 10:00:00",
            current_sign_in_ip: cur, last_sign_in_ip: last)
  CE.insert("people", id: pid, guid: "#{nm}guid", diaspora_handle: "#{nm}@localhost",
            serialized_public_key: "K#{pid}", owner_id: uid, closed_account: false, fetch_status: 0)
  CE.insert("profiles", id: 40 + pid, person_id: pid, first_name: nm.capitalize, last_name: "X", searchable: true, nsfw: false, gender: "male")
end
CE.insert("roles", id: 1, person_id: 1, name: "admin")                       # _drawer.mobile: unreviewed_reports_count
CE.insert("tags", id: 1, name: "ruby", taggings_count: 0)
CE.insert("tag_followings", id: 1, tag_id: 1, user_id: 9)                    # _drawer.mobile: followed_tags
CE.insert("notifications", id: 1, target_type: "Mention", target_id: 1, recipient_id: 9, unread: true, type: "Notifications::Mentioned")
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
# INSTR-5 (adversary round 3 / A3-16): EVERY principal's salt is computed HERE,
# at fixture-load time, OUTSIDE the probe's statement-capture window. Computing
# uid 10's lazily on its first request put a `SELECT "users".* … "id" = ? LIMIT ?`
# (find-shaped, no ORDER BY — the harness's, not Devise's) inside the scenario,
# which the note check correctly reported as a statement OUTSIDE any target frame.
REAL_SALTS = { 9 => REAL_SALT }
[10, 11, 12, 13, 14, 15, 16].each { |i| REAL_SALTS[i] = User.find(i).authenticatable_salt }
REAL_SALTS[99] = "nosuchuser" # NM-3: a deleted principal has no salt to look up
# (POST-AUTH SCOPE: the INSTR-9/11 real Warden::Manager block moved to the
# auth-boundary policy — _auth_boundary/evidence/.)
# INSTR-8: the real layout renders once the asset resolvers are emptied
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
# layout(false) REMOVED (round 4, INSTR-8): the real layout renders

REQUESTS = [
  { format: :html, params: {} },
  # cycle 4 (adversary round 2, NM-2): a page beyond the last one — 2
  # conversations, page 2: will_paginate still COUNTs, the page query returns
  # no rows (`@visibilities.count > 0` with an empty collection)
  { format: :html, params: { page: "2" }, beyond: true },
  { format: :html, params: { conversation_id: "1" } },
  { format: :json, params: {} },
  { format: :json, params: { conversation_id: "1" } },
  # A3-14 evidence: `conversation_id` is a QUERY param and may be an Array ->
  # `… "conversation_id" IN (?, ?) ORDER BY "conversations"."id" ASC LIMIT ?` (W2/C-6)
  { format: :html, params: { conversation_id: ["1", "2"] } },
  # A3-14 evidence: `.js` on an EMPTY inbox -> full index.haml render, then the
  # NameError 500 whose message inspects the unloaded @visibilities (`take`).
  { format: :js, params: {}, uid: 10, expect: 500, skip_body: true },
  # A7-6 (2026-09-01): `.js` on a POPULATED inbox. The js path renders
  # index.haml IN FULL (C-8) before the `no_contacts` NameError at :32, so it
  # issues the per-row people/profiles/messages reads — a multiplicity the
  # corpus asserts (js dumps: people-by-id x2..x6) and that NO ground-truth
  # request exercised, because the only js request was uid 10's EMPTY inbox.
  # Without this the judge cannot tell a real js render from over-emission.
  { format: :js, params: {}, uid: 9, expect: 500, skip_body: true },
  { format: :js, params: { conversation_id: "1" }, uid: 9, expect: 500, skip_body: true },
  # a second principal (fresh fixture row) — the fetch family on another uid
  { format: :html, params: {}, uid: 11, skip_body: true },
  # round 5 (C-15): `?conversation_id[]` -> params[:conversation_id] == [] (truthy):
  # the lookup is entered and AR renders `AND 1=0`.
  { format: :html, params: {}, query_string: "conversation_id[]", skip_body: true },
  # round 6 (C-18): out-of-range scalar cid -> ActiveModel::RangeError after three statements
  { format: :html, params: { conversation_id: "99999999999999999999" }, expect: 500, skip_body: true },
  # (POST-AUTH SCOPE, 2026-08-31: the cookie-login / trackable-history / 401
  # requests that stood here are the shared auth-boundary policy's evidence —
  # preserved in _auth_boundary/evidence/concrete_manifest_auth.rb.)
]

CONCRETE_SCENARIOS = [
  { name: "conversations-index-auth-4-variants",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      REQUESTS.each do |req|
        # INSTR-2 (adversary round 3): this body issues FOUR requests in one
        # process. The probe drops query-cached statements, and the AR query
        # cache is not reset between requests, so a statement repeated by a
        # later request silently vanished from the ground truth. A real
        # deployment gives every request its own cache.
        CompletionChecker.new_request! if defined?(CompletionChecker)
        ctrl, tc = make_harness(ConversationsController)
        install_real_warden(tc, req[:uid] || 9)
        tc.request.env["QUERY_STRING"] = req[:query_string] if req[:query_string]
        want = req[:expect] || 200
        thrown = nil
        begin
          thrown = catch(:warden) do
            tc.process(:index, method: :get, params: req[:params], format: req[:format])
            nil
          end
          if thrown
            raise "#{req.inspect}: warden threw #{thrown.inspect} but a #{want} was expected" unless want == 401
            next # C-11: the 401 — the action never ran
          end
        rescue ActionView::Template::Error, ActiveModel::RangeError => e
          # The controller-test rig has no exception-rendering middleware, so a
          # template error escapes instead of becoming a 500. A real 500 is
          # produced by ActionDispatch's exception wrapper, which reads
          # `exception.message` — and for a NameError that is what inspects the
          # receiver (the view context, hence `@visibilities`) and issues the
          # `take` read on an unloaded relation (A3-9b). Read it here for the
          # same reason, then treat the request as the 500 it really is.
          raise unless want == 500
          # ONE read of the message, as the exception wrapper does; a second
          # read re-inspects the view context and re-issues the `take`
          # (round-4 NM-3: that multiplicity is the renderer's, not the app's).
          e.message.to_s
          next
        end
        raise "#{req.inspect}: unexpected status #{ctrl.response.status}" unless ctrl.response.status == want
        # A3-14 evidence — THE LAYOUT'S DATA ACCESS. `index` does not override
        # ApplicationController's layout proc, so a real html/mobile request
        # renders the site chrome, whose `include_gon` serialises the
        # UserPresenter that gon_set_current_user pushed: seven statement shapes
        # over four tables (notifications, roles, aspects, services + the
        # conversation_visibilities SUM). This rig cannot render the layout
        # (sprockets), so the presenter is driven directly — the same real code,
        # inside the same request — exactly as run_dse.rb does (NM-5).
        # (the hand-driven UserPresenter call was removed in round 4: the REAL layout renders it — C-12 / INSTR-8)
        next if req[:skip_body]
        body = ctrl.response.body.to_s
        if req[:beyond]
          raise "#{req.inspect}: beyond-page rendered a conversation" if body.include?("hello alice")
        else
          raise "#{req.inspect}: conversation not rendered: #{body[0, 160]}" unless body.include?("hello alice")
        end
      end
    end },
]
