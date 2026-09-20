# ADVERSARY harness — notifications_index (concrete checker, round 1).
# Shared boot + fixtures + request driver. Modelled on the batch's own
# concrete_manifest_auth.rb / concrete_manifest_mobile.rb. Real app only:
# real sqlite DB, raw fixture rows, real Devise serialize_from_session,
# real ActionController::TestCase#process, real templates. No mocks, no
# stubs, nothing under src/ or the app touched.
#
# Each scenario manifest sets ADV_TAG then require_relative's this file.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
require "builder"

ADV_DIR   = File.expand_path("..", __FILE__)
BATCH_DIR = File.expand_path("../..", __FILE__)
CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.join(ADV_DIR, "runs", "#{ADV_TAG}.sqlite3"))
Rails.application.config.assets.check_precompiled_asset = false
ActionView::Base.check_precompiled_asset = false if ActionView::Base.respond_to?(:check_precompiled_asset=)

NOW = Time.now.utc

def ts(offset_days = 0, offset_secs = 0)
  (NOW - offset_days * 86_400 + offset_secs).strftime("%Y-%m-%d %H:%M:%S")
end

# ---- base fixtures (identical to the batch's concrete_manifest_auth.rb) ----
def adv_base_fixtures!
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
end

# ---- target tracing ------------------------------------------------------
# The corpus's 20 target names (grep over all 14 951 dumps) resolve to the
# pairs below; batch-local aliases (devise_user_first) and Anonymous.*
# singletons are unresolvable in the clean app exactly as
# targets_from_corpus reports them. Same `extra:` list as the batch's own
# concrete manifests, PLUS ActiveRecord::FinderMethods#exists? so an
# existence probe is attributed to its own frame instead of surfacing as
# "outside any target frame" (round-1 conversations_index instrument note).
# ActionController::Rendering._set_rendered_content_type carries the
# batch's own waiver (render plumbing; no SQL evidence).
ADV_TARGETS = [
  [ActiveRecord::Associations::BelongsToPolymorphicAssociation, :find_target],
  [ActiveRecord::Associations::CollectionProxy, :load_target],
  [ActiveRecord::Associations::CollectionProxy, :records],
  [ActiveRecord::Associations::SingularAssociation, :find_target],
  [ActiveRecord::Base, :to_param],
  [ActiveRecord::Calculations, :count],
  [ActiveRecord::Calculations, :pluck],
  [ActiveRecord::FinderMethods, :find_by],
  [ActiveRecord::FinderMethods, :first],
  [ActiveRecord::FinderMethods, :last],
  [ActiveRecord::FinderMethods, :take],
  [ActiveRecord::FinderMethods, :find],
  [ActiveRecord::FinderMethods, :exists?],
  [ActiveRecord::Relation, :records],
  [ActiveRecord::Relation, :to_a],
  [ActiveRecord::Relation, :to_ary],
  [Diaspora::MessageRenderer, :title],
  [User, :blocks],
]

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

def adv_prime!
  # Devise salt computed OUTSIDE the capture window (round-1 harness artefact)
  $adv_salt = User.find(9).authenticatable_salt
  NotificationsController.layout(false) # render-config parity with the corpus runner
end

def install_real_warden(tc)
  real_salt = $adv_salt
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

# Drive one request. NEVER raises: a 500 / exception in one request must not
# abort the rest of the scenario (each is a separate dispatch anyway).
def adv_request(tag, format: :html, params: {}, session: {}, headers: {}, body_out: nil)
  ctrl, tc = make_harness(NotificationsController)
  install_real_warden(tc)
  headers.each { |k, v| tc.instance_variable_get(:@request).env[k] = v }
  status = nil
  err = nil
  begin
    tc.process(:index, method: :get, params: params, session: session, format: format)
    status = ctrl.response.status
    if body_out
      File.write(File.join(ADV_DIR, "runs", "_body_#{ADV_TAG}_#{body_out}.txt"),
                 ctrl.response.body.to_s)
    end
  rescue Exception => e # rubocop:disable Lint/RescueException
    err = "#{e.class}: #{e.message.to_s[0, 200]}"
  end
  fmt = begin
          ctrl.request.format.to_sym.to_s
        rescue StandardError
          "?"
        end
  puts format("[adv] %-28s req_format=%-7s status=%-5s %s", tag, fmt, status.inspect, err)
  $stdout.flush
  [status, err]
end
