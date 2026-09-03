# P05 — the LAYOUT. Every batch (and both earlier adversary rounds) sets
# `ConversationsController.layout(false)` as "render-config parity"; that is a
# MODELLING scope decision, not an app fact. The real action renders
# `layout proc { request.format == :mobile ? "application" : "with_header_with_footer" }`
# (application_controller.rb:45), which runs `include_gon` over the hash
# `gon_set_current_user` filled with `UserPresenter.new(current_user, ...)`
# (application_controller.rb:183-188). This scenario measures which statements
# the real layout adds. Fixtures are identical to the batch's own manifest.
require_relative "_common"          # ADV3_REAL_LAYOUT=1 keeps the real layout
adv_setup!("P05_real_layout"); seed_people!; seed_batch_conversations!

def req(tag, fmt, params = {}, session = {})
  { name: "P05_#{tag}",
    body: -> { adv_request(format: fmt, params: params, session: session, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("html_plain",  :html),
  req("html_cid1",   :html, { conversation_id: "1" }),
  req("mobile_plain", :html, {}, { mobile_view: true }),
  req("json_plain",  :json),
])
