# CONCRETE CHECKER manifest — C7 fix_profile INNER-SQL PROBE
# (html + json + xml). Real sqlite DB, real fixture rows, real Devise warden
# resolution, real ActionController::TestCase#process dispatch, real
# templates. NO mocks, NO stubs: every target function runs for real; the
# probe only OBSERVES which ones are invoked and what SQL each issues.
# One scenario per manifest process (JVM crash isolation).
require "/home/dev/project/src/ruby_runtime/completion_checker/concrete_env.rb"
require "builder"

CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../_c7_fixprofile_probe.sqlite3", __FILE__))
Rails.application.config.assets.check_precompiled_asset = false

# C-12 / INSTR-8 (ported from conversations_index/run_dse.rb:144): the sprockets
# gap that "justified" layout(false) is closed by emptying the asset resolvers —
# with no resolver strategy `resolve_asset_path` returns nil and the fallback
# path is taken instead of AssetNotFound (sprockets-rails 3.2.1 helper.rb:76-95).
# Runtime reconfiguration, not an app-source edit.
ActionView::Base.resolve_assets_with = []
ActionView::Base.unknown_asset_fallback = true

ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

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


# ===========================================================================
# C7 fix_profile INNER-SQL PROBE (2026-09-01, batch agent).
#
# Every corpus runner AND every concrete manifest in this batch calls
# `NotificationsController.layout(false)` "for render-config parity with the
# corpus runner" — so the ground truth is pinned to match the model and no
# judge can see the layout's statements on either side.
#
# NotificationsController declares no layout, so the REAL app renders
# `layouts/application.html.haml` (html) and `layouts/application.mobile.haml`
# (mobile).  This manifest runs the SAME request four ways and reports the
# statement delta.  Scenario ORDER matters: the unpinned scenarios run first,
# then the pin is installed for the pinned ones.
# ===========================================================================

def drive(fmt, session)
  ctrl, tc = make_harness(NotificationsController)
  install_real_warden(tc)
  tc.process(:index, method: :get, params: {}, session: session, format: :html)
  raise "unexpected status #{ctrl.response.status}" unless ctrl.response.status == 200
  got = ctrl.request.format.to_sym
  raise "expected #{fmt} got #{got}" unless got == fmt
end


# ===========================================================================
# C7 fix_profile INNER-SQL PROBE (2026-09-01, batch agent).
#
# targets.rb:1520-1550 walls `DiasporaFederation::Discovery::Discovery.new`
# and `#fetch_and_save`, with the stated reason "the real path aborts the JVM
# natively on this JRuby (SIGSEGV in __libc_free)".
#
# DISCIPLINE 12 amendment / matrix row T-ac (M-15, adversary R8) REFUTES that
# argument as stated: Faraday parses the webfinger URL with `URI.parse` BEFORE
# the typhoeus adapter runs, so a `people.diaspora_handle` whose DOMAIN is not
# a legal URI host raises `URI::InvalidURIError` in PURE RUBY and returns a
# DiscoveryError -- no FFI call, no abort.
#
# This manifest reaches `Person#name` on an actor whose `profiles` row does
# NOT exist, so `fix_profile` runs for real.  Fixtures give that actor an
# unparseable host.  Expected if M-15 holds here: the request 500s with a
# DiscoveryError raised from pure Ruby, `fetch_and_save` is entered, and the
# JVM survives -- which would make BOTH walls' stated reason false on this
# endpoint too.
#
# ONE scenario only: a JVM abort kills the process, so this file names its own
# crasher (DISCIPLINE, crash isolation).
# ===========================================================================

# actor `wraith` (person 3) with NO profiles row and an UNPARSEABLE URI host.
CE.insert("people", id: 3, guid: "wraithguid", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K3", owner_id: nil, closed_account: false, fetch_status: 0)
# a notification whose ACTOR is the profile-less wraith
CE.insert("notifications", id: 510, recipient_id: 9, type: "Notifications::Liked",
          target_type: "Post", target_id: 100, unread: true)
CE.insert("notification_actors", id: 610, notification_id: 510, person_id: 3)


# ---------------------------------------------------------------------------
# C7 CONDITION 1 (coordinator, 2026-09-01): walling `Person#fix_profile` skips
# `Discovery.new`, `#fetch_and_save` AND `reload`. If ANY of that body issued a
# statement before the raise, walling it would DROP a real read and the
# "same statement set" claim would be false. "Consistent with none" is not
# measured, so this brackets the real method and counts the statements issued
# strictly INSIDE it.
# ---------------------------------------------------------------------------
$FP_INNER = []
$FP_DEPTH = 0
ActiveSupport::Notifications.subscribe("sql.active_record") do |*a|
  p = a.last
  next if p[:cached]
  $FP_INNER << p[:sql].to_s.gsub(/\s+/, " ").strip if $FP_DEPTH > 0
end
::Person
Person.prepend(Module.new do
  def fix_profile
    $FP_DEPTH += 1
    STDERR.puts "[F1] ENTER Person#fix_profile (handle=#{diaspora_handle})"
    super
  rescue Exception => e
    STDERR.puts "[F1] fix_profile RAISED #{e.class}"
    raise
  ensure
    $FP_DEPTH -= 1
    STDERR.puts "[F1] EXIT  Person#fix_profile; statements issued INSIDE it: #{$FP_INNER.length}"
    $FP_INNER.each { |s| STDERR.puts "[F1]    INNER-SQL #{s[0, 160]}" }
    $FP_INNER.clear
  end
end)

CONCRETE_SCENARIOS = [
  { name: "F1-fix_profile-inner-sql",
    targets: TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl, tc = make_harness(NotificationsController)
      install_real_warden(tc)
      begin
        tc.process(:index, method: :get, params: {}, format: :html)
        STDERR.puts "[F1] status=#{ctrl.response.status}"
      rescue Exception => e
        STDERR.puts "[F1] RAISED #{e.class}: #{e.message[0, 300]}"
        cause = e.cause
        while cause
          STDERR.puts "[F1]   <- cause #{cause.class}: #{cause.message[0, 300]}"
          cause = cause.cause
        end
        STDERR.puts "[F1] JVM SURVIVED the discovery path (no abort)."
      end
    end },
]
