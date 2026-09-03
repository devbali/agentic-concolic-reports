# CONCRETE CHECKER manifest — notifications_index, SIGNED-IN scenario
# (html + json + xml). Real sqlite DB, real fixture rows, real Devise warden
# resolution, real ActionController::TestCase#process dispatch, real
# templates. NO mocks, NO stubs: every target function runs for real; the
# probe only OBSERVES which ones are invoked and what SQL each issues.
# One scenario per manifest process (JVM crash isolation).
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"
require "builder"

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_auth.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

# C7 (2026-09-01) — the `layout(false)` line that used to sit in this file
# "for render-config parity with the corpus runner" is WITHDRAWN. Parity
# between a rig and its own ground truth is a tautology, not evidence
# (DISCIPLINE 14): with the pin on BOTH sides no judge could see the layout,
# and the real app renders `layouts/application.html.haml` /
# `application.mobile.haml` on every request to this action. Measured delta
# on the un-pinned probe: html 42 statements vs 25, mobile 35 vs 21, with
# SEVEN shapes absent from the entire 39 956-dump pinned corpus.
#
# The sprockets gap that ORIGINALLY justified the pin is real and is closed
# here the way conversations_index closed it: with no resolver strategy
# `resolve_asset_path` returns nil and the fallback path is taken instead of
# AssetNotFound (sprockets-rails 3.2.1 helper.rb:76-95).
ActionView::Base.resolve_assets_with = []
ActionView::Base.unknown_asset_fallback = true

# ---- fixtures (raw INSERTs: data, not code-under-test) --------------------
# alice (signed-in recipient, person 1), bob (actor, person 2)
CE.insert("users", id: 9, username: "alice", email: "alice@example.org",
          encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
          language: "en", getting_started: false, disable_mail: false, sign_in_count: 1)
CE.insert("people", id: 1, guid: "aliceguid", diaspora_handle: "alice@localhost",
          serialized_public_key: "K1", owner_id: 9, closed_account: false, fetch_status: 0)
CE.insert("people", id: 2, guid: "bobguid", diaspora_handle: "bob@remote.example",
          serialized_public_key: "K2", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 11, person_id: 1, first_name: "Alice", last_name: "A",
          searchable: true, nsfw: false, public_details: false)
CE.insert("profiles", id: 12, person_id: 2, first_name: "Bob", last_name: "B",
          searchable: true, nsfw: false, public_details: false)

# a post by bob (Liked/Reshared target; also the mention container)
CE.insert("posts", id: 100, author_id: 2, guid: "postguid1", type: "StatusMessage",
          text: "hello @{alice@localhost} world", public: true,
          likes_count: 1, comments_count: 0, reshares_count: 0,
          interacted_at: Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"))

# four notification families for alice (one per major render branch)
CE.insert("notifications", id: 500, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 100, unread: true)
CE.insert("notification_actors", id: 600, notification_id: 500, person_id: 2)
CE.insert("notifications", id: 501, recipient_id: 9, type: "Notifications::StartedSharing",
          target_type: "Person", target_id: 2, unread: true)
CE.insert("notification_actors", id: 601, notification_id: 501, person_id: 2)
CE.insert("mentions", id: 900, mentions_container_id: 100,
          mentions_container_type: "Post", person_id: 1)
CE.insert("notifications", id: 502, recipient_id: 9, type: "Notifications::MentionedInPost",
          target_type: "Mention", target_id: 900, unread: true)
CE.insert("notification_actors", id: 602, notification_id: 502, person_id: 2)
CE.insert("notifications", id: 503, recipient_id: 9, type: "Notifications::Reshared",
          target_type: "Post", target_id: 100, unread: false)
CE.insert("notification_actors", id: 603, notification_id: 503, person_id: 2)

# contact + aspect (the StartedSharing gon_load_contact / dropdown path)
CE.insert("contacts", id: 700, user_id: 9, person_id: 2, sharing: true, receiving: true)
CE.insert("aspects", id: 950, user_id: 9, name: "Friends", order_id: 1)
CE.insert("aspect_memberships", id: 951, aspect_id: 950, contact_id: 700)

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
}, extra: [
  # cycle 2 (W1): the existence probe is a target of its own now — trace it so
  # `Post.exists?(guid:)` is attributed to its own frame instead of being
  # absorbed by the enclosing one (the adversary had to add it by hand: N9).
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :last],
  [ActiveRecord::FinderMethods, :take],
  [ActiveRecord::FinderMethods, :find],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Relation, :to_ary],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Calculations, :pluck],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
  [ActiveRecord::Associations::BelongsToPolymorphicAssociation, :find_target],
])

REAL_SALT = User.find(9).authenticatable_salt
def install_real_warden(tc)
  real_salt = REAL_SALT
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  # INSTR-1 (coordinator, 2026-08-29): the memo MUST bind to the per-request
      # warden, not to the lambda's enclosing `self` (`main`) — an ivar on main
      # made it ONE principal resolution per PROCESS, so every request after the
      # first in a manifest lost the Devise `users` read and `current_user.person`'s
      # `people.owner_id` read from ground truth.
      wuser = lambda { |*_a|
        warden.instance_variable_get(:@cc_user) ||
          warden.instance_variable_set(:@cc_user, User.serialize_from_session(9, real_salt))
      }
  warden.define_singleton_method(:authenticate!) { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)  { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user) { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session) { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end


REQUESTS = [
  { format: :html, params: {} },
  { format: :html, params: { type: "liked" } },
  { format: :json, params: {} },
  { format: :xml,  params: {} },
]


# ===========================================================================
# C7 (2026-09-01) — ONE REQUEST PER PROCESS.
#
# Measured, not assumed: driving TWO requests in one process makes the SECOND
# under-report its statements, and `Rails.application.executor.wrap` does NOT
# fix it (wrapped-and-second lost the same shapes; wrapped-and-first did not).
# On html the second request loses four shapes — `aspect_memberships` by
# contact_id, `aspects` by id, `blocks`, and `tags INNER JOIN taggings` — which
# are exactly `ContactPresenter#full_hash_with_person`'s reads. The mechanism is
# the app's own `GonHelper#gon_load_contact` (gon_helper.rb:4-8): it accumulates
# into the PROCESS-level `Gon.preloads[:contacts]` and SKIPS building the
# presenter when a contact with the same person_id is already stored. In
# production that store is per-request; in a multi-request process it is not.
# Established by running the same four scenarios in both orders: the four
# "losses" follow the ORDER, not the executor (4 forward, 0 reversed).
#
# So this manifest now drives exactly ONE request per process, selected by
# CC_REQ (0-based index into REQUESTS). `_c7_concrete_all.sh` loops the indices
# and merges. Same requests, same fixtures — one process each.
# ===========================================================================
CC_REQ = Integer(ENV.fetch("CC_REQ", "0"))
raise "CC_REQ=#{CC_REQ} out of range (#{REQUESTS.length} requests)" if CC_REQ >= REQUESTS.length

CONCRETE_SCENARIOS = [
  { name: "notifications-index-auth-req#{CC_REQ}",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      [REQUESTS[CC_REQ]].each do |req|
        ctrl, tc = make_harness(NotificationsController)
        install_real_warden(tc)
        tc.process(:index, method: :get, params: req[:params], format: req[:format])
        raise "#{req.inspect}: unexpected status #{ctrl.response.status}" unless ctrl.response.status == 200
      end
    end },
]
