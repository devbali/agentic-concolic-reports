# P11 — what the `layout(false)` scope pin excludes. P05 showed the real layout
# cannot render on this rig (sprockets: "couldn't find file 'underscore'"), so
# the layout's own reads are measured here with an IN-PROCESS PROBE instead:
# `gon_set_current_user` (application_controller.rb:183-188) pushes a
# `UserPresenter`, and the layout's `include_gon` serializes it. This scenario
# calls `UserPresenter#to_json` on the real principal and records the statements.
# These are PROBE statements, not endpoint statements — see INSTR-5.
require_relative "_common"
adv_setup!("P11_layout_gon"); seed_people!; seed_batch_conversations!
CE.insert("aspects", id: 1, user_id: 9, name: "Friends", contacts_visible: true, order_id: 1) rescue warn "[adv3] aspects insert failed"
CE.insert("notifications", id: 1, target_id: 1, target_type: "Post", recipient_id: 9, unread: true, type: "Notifications::Mentioned") rescue warn "[adv3] notifications insert failed"

CONCRETE_SCENARIOS = adv_scenarios([
  { name: "P11_userpresenter_to_json_PROBE", body: lambda do
      u = User.find(9)
      json = UserPresenter.new(u, []).to_json
      warn "[adv3] UserPresenter#to_json -> #{json.to_s.bytesize} bytes"
    end },
  { name: "P11_control_html", body: -> { adv_request(format: :html, params: {}, tag: "P11_html") } },
])
