# CONCRETE CHECKER manifest — conversations_index, SIGNED-IN scenario (the
# ONLY scenario: `before_action :authenticate_user!` with no `except:` —
# an anonymous request is 401'd by Devise before the action; there is no
# anonymous endpoint state to model). Real sqlite DB, real rows, real
# Devise warden resolution (the notifications_index pattern), real dispatch
# through ActionController::TestCase#process; no mocks, no stubs. One
# scenario per manifest process (JVM crash isolation); the one body drives
# the four request shapes the corpus explores (html/json x with/without
# conversation_id) against the same fixtures.
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_auth.sqlite3", __FILE__))
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
def install_real_warden(tc)
  real_salt = REAL_SALT
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  # INSTR-1 (adversary round 3): the memo MUST live on the WARDEN object (one
  # per request), not on the lambda's `self` (= main, one per PROCESS). With a
  # process-wide memo the Devise `users` read and `current_user.person`'s
  # `people.owner_id` read are issued by the FIRST request only, so every later
  # request in the manifest silently under-reports them (measured: 1 `users`
  # read for a 4-request scenario).
  wuser = lambda { |*_a| warden.instance_variable_get(:@cc_user) ||
                         warden.instance_variable_set(:@cc_user, User.serialize_from_session(9, real_salt)) }
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
ConversationsController.layout(false)

REQUESTS = [
  { format: :html, params: {} },
  # cycle 4 (adversary round 2, NM-2): a page beyond the last one — 2
  # conversations, page 2: will_paginate still COUNTs, the page query returns
  # no rows (`@visibilities.count > 0` with an empty collection)
  { format: :html, params: { page: "2" }, beyond: true },
  { format: :html, params: { conversation_id: "1" } },
  { format: :json, params: {} },
  { format: :json, params: { conversation_id: "1" } },
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
        install_real_warden(tc)
        tc.process(:index, method: :get, params: req[:params], format: req[:format])
        raise "#{req.inspect}: unexpected status #{ctrl.response.status}" unless ctrl.response.status == 200
        body = ctrl.response.body.to_s
        if req[:beyond]
          raise "#{req.inspect}: beyond-page rendered a conversation" if body.include?("hello alice")
        else
          raise "#{req.inspect}: conversation not rendered: #{body[0, 160]}" unless body.include?("hello alice")
        end
      end
    end },
]
