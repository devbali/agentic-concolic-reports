# ADVERSARY ROUND 7 common harness — POST-AUTH SCOPE (Bali, 2026-08-31).
#
# Reuses adversary6's seeding helpers (seed_people!, seed_principal!,
# seed_batch_conversations!, seed_layout_rows!, make_harness, adv_targets,
# precompute_salt!) but SWITCHES the warden to the batch's HOOK-LESS stub
# (the concrete_manifest_auth.rb / notifications_index pattern): Devise's REAL
# `serialize_from_session` resolves the principal from the real users row, and
# NO Warden::Manager / after_set_user hooks / strategies run. The auth stages
# are the shared auth-boundary policy's business (results3/_auth_boundary/),
# ABOVE the entrypoint. Every request this harness issues is auth-quiet by
# construction: the ONLY user-table statement it emits is the memoised
# principal SELECT, exactly the symbolic fetch the corpus models. That makes
# every statement issued after the principal is installed an ENTRYPOINT-frame
# statement (the action + its after-auth before_actions + views), satisfying
# the §15 entrypoint-verification requirement.
#
# NO mocks/stubs/monkey-patches of app code; inputs are fixtures (raw INSERTs),
# params, headers, session, format and the concrete principal uid.
require_relative "../adversary6/_common"

ADV7_DIR = File.dirname(File.expand_path(__FILE__))

# Real layout on (INSTR-8); adv6/_common already emptied the asset resolvers
# unless ADV5_REAL_LAYOUT=0.

# HOOK-LESS warden (post-auth scope). Mirrors concrete_manifest_auth.rb's
# install_real_warden: a bare object answering the Warden protocol the
# controller touches, resolving the principal ONCE per request through the
# REAL Devise serialize_from_session. No manager, no hooks, no strategies.
def install_hookless_warden(tc, uid = 9)
  salt = REAL_SALT_CACHE.fetch(uid) { raise "salt for uid #{uid} not precomputed (INSTR-5)" }
  warden = Object.new
  warden.define_singleton_method(:session_serializer) { nil }
  wuser = lambda { |*_a| warden.instance_variable_get(:@cc_user) ||
                         warden.instance_variable_set(:@cc_user, User.serialize_from_session(uid, salt)) }
  warden.define_singleton_method(:authenticate!)  { |*a| wuser.call(*a) || raise("devise resolve failed") }
  warden.define_singleton_method(:authenticate)   { |*a| wuser.call(*a) }
  warden.define_singleton_method(:authenticated?) { |*_a| true }
  warden.define_singleton_method(:user)           { |*a| wuser.call(*a) }
  warden.define_singleton_method(:session)        { |*_a| {} }
  tc.instance_variable_get(:@request).env["warden"] = warden
end

# One request through ActionController::TestCase#process under the hook-less
# warden. Never raises to the scenario driver; captures thrown/raised terminals
# the way the batch manifest does (template errors / RangeError become the 500
# they really are). Returns [status, body, thrown_or_nil].
def adv7_request(format:, params: {}, session: {}, headers: {}, uid: 9, tag: nil,
                 query_string: nil, expect: nil, skip_body: false)
  ctrl, tc = make_harness(ConversationsController)
  session.each { |k, v| tc.session[k] = v }
  headers.each { |k, v| tc.request.headers[k] = v }
  tc.request.env["QUERY_STRING"] = query_string if query_string
  install_hookless_warden(tc, uid)
  CompletionChecker.new_request! if defined?(CompletionChecker)
  ActiveRecord::Base.connection.clear_query_cache
  want = expect || 200
  thrown = nil
  begin
    thrown = catch(:warden) do
      tc.process(:index, method: :get, params: params, format: format)
      nil
    end
    status = ctrl.response.status
    body = thrown ? "" : ctrl.response.body.to_s
    warn "[adv7] #{tag} #{format} #{params.inspect} qs=#{query_string.inspect} uid=#{uid} -> #{thrown ? "THROWN #{thrown.inspect}" : status} (#{body.bytesize} B) fmt=#{ctrl.request.format.to_sym rescue '?'}"
    File.write(File.join(ADV7_DIR, "_bodies", "_body_#{tag}.txt"), body) if tag && !body.empty?
    [status, body, thrown]
  rescue ActionView::Template::Error, ActiveModel::RangeError => e
    # The controller-test rig has no exception-rendering middleware; a real 500
    # is produced by ActionDispatch's wrapper, which reads exception.message —
    # and for a NameError that inspects the view context and issues the `take`
    # read on the unloaded relation (A3-9b). Read the message ONCE here for the
    # same reason, then treat the request as the 500 it really is.
    warn "[adv7] #{tag} #{format} #{params.inspect} uid=#{uid} -> RAISED #{e.class}: #{e.message.to_s[0,160]}"
    e.message.to_s
    [500, "#{e.class}", nil]
  rescue Exception => e # rubocop:disable Lint/RescueException
    warn "[adv7] #{tag} #{format} #{params.inspect} uid=#{uid} -> RAISED #{e.class}: #{e.message.to_s[0,200]}"
    File.write(File.join(ADV7_DIR, "_bodies", "_err_#{tag}.txt"),
               "#{e.class}: #{e.message}\n#{e.backtrace.first(30).join("\n")}") if tag
    [500, "#{e.class}", nil]
  end
end

def adv7_scenarios(specs, targets: adv_targets)
  specs.map do |sp|
    { name: sp[:name], targets: targets, coverage_filter: %r{apps/diaspora/(app|lib)/}, body: sp[:body] }
  end
end
