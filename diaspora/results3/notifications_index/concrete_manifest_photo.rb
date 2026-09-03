# CONCRETE CHECKER manifest — notifications_index, PHOTO TARGET (W2)
# (html + json + xml). Real sqlite DB, real fixture rows, real Devise warden
# resolution, real ActionController::TestCase#process dispatch, real
# templates. NO mocks, NO stubs: every target function runs for real; the
# probe only OBSERVES which ones are invoked and what SQL each issues.
# One scenario per manifest process (JVM crash isolation).
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"
require "builder"

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../concrete_photo.sqlite3", __FILE__))
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
CE.insert("contacts", id: 700, user_id: 9, person_id: 2, sharing: true, receiving: true)
CE.insert("aspects", id: 950, user_id: 9, name: "Friends", order_id: 1)
CE.insert("aspect_memberships", id: 951, aspect_id: 950, contact_id: 700)
NOW = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")

# W2: a notification whose polymorphic target is a PHOTO. `Comment#commentable`
# is polymorphic and Photo includes Diaspora::Commentable (commentable.rb:11),
# so `Notifications::CommentOnPost.notify` (comment_on_post.rb:22) passes the
# COMMENTABLE — a Photo — and `target_type` is "Photo". Two shapes follow:
# the `includes(:target)` preload `SELECT "photos".* WHERE "photos"."id" = ?`
# and `posts_helper.rb:9-10`'s `post.status_message_author_name` ->
# `Photo#status_message` (photo.rb:43, keyed on guid, STI-scoped).
CE.insert("posts", id: 101, author_id: 2, guid: "advstatusguid00000000001", type: "StatusMessage",
          text: "the status message that owns the photo", public: true,
          likes_count: 0, comments_count: 1, reshares_count: 0, interacted_at: NOW)
CE.insert("photos", id: 200, author_id: 2, guid: "advphotoguid000000000001",
          status_message_guid: "advstatusguid00000000001", public: true,
          remote_photo_path: "https://example.org/", remote_photo_name: "p.jpg",
          random_string: "r", height: 10, width: 10)
CE.insert("comments", id: 300, author_id: 2, guid: "advcommentguid000000001",
          commentable_id: 200, commentable_type: "Photo", text: "nice photo", likes_count: 0)
CE.insert("notifications", id: 510, recipient_id: 9, type: "Notifications::CommentOnPost",
          target_type: "Photo", target_id: 200, unread: true)
CE.insert("notification_actors", id: 610, notification_id: 510, person_id: 2)
CE.insert("notifications", id: 511, recipient_id: 9, type: "Notifications::AlsoCommented",
          target_type: "Photo", target_id: 200, unread: false)
CE.insert("notification_actors", id: 611, notification_id: 511, person_id: 2)
# CYCLE 6 (hardening_lint H6): the `post.photos` SCOPE read. `post_page_title`
# (posts_helper.rb:14-17) takes the photos branch only when the post's message
# is BLANK — `post.message.present?` false — and then calls `post.photos.present?`
# followed by `post.photos.size`, which issues
# `SELECT "photos".* FROM "photos" WHERE "photos"."status_message_guid" = ?`
# on an association the controller's `includes(:target, actors: :profile)` does
# NOT preload. The corpus carried that note with no real counterpart until this
# fixture; a blank-text StatusMessage with two photos is the state that issues it.
CE.insert("posts", id: 102, author_id: 2, guid: "advblanktextguid00000001", type: "StatusMessage",
          text: nil, public: true,
          likes_count: 0, comments_count: 0, reshares_count: 0, interacted_at: NOW)
CE.insert("photos", id: 201, author_id: 2, guid: "advphotoguid000000000002",
          status_message_guid: "advblanktextguid00000001", public: true,
          remote_photo_path: "https://example.org/", remote_photo_name: "q.jpg",
          random_string: "r2", height: 10, width: 10)
CE.insert("photos", id: 202, author_id: 2, guid: "advphotoguid000000000003",
          status_message_guid: "advblanktextguid00000001", public: true,
          remote_photo_path: "https://example.org/", remote_photo_name: "r.jpg",
          random_string: "r3", height: 10, width: 10)
CE.insert("notifications", id: 513, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 102, unread: true)
CE.insert("notification_actors", id: 613, notification_id: 513, person_id: 2)

# control: the same two types with a POST commentable (the corrected pin)
CE.insert("notifications", id: 512, recipient_id: 9, type: "Notifications::CommentOnPost",
          target_type: "Post", target_id: 101, unread: true)
CE.insert("notification_actors", id: 612, notification_id: 512, person_id: 2)

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
  { format: :json, params: {} },
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
  { name: "notifications-index-photo-req#{CC_REQ}",
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
