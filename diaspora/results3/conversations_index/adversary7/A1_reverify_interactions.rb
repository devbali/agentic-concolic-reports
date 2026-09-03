# A7 / A1 — POST-AUTH re-verification of the eight standing endpoint wins that
# must STAY closed (C-5,6,7,8,12,13,15,18) and M-5 (locale three-armed), plus
# fresh format x cid x page interactions now that the boundary arms are gone.
# Hook-less warden: the ONLY users-table statement per request is the memoised
# principal SELECT (the symbolic fetch); every later statement is issued from
# inside the action frame (entrypoint verification, DISCIPLINE §15).
require_relative "_common"

adv_setup!("A1_reverify_interactions")
seed_people!                              # alice(9/1/11) + bob(2) + carol(3) + contact700 mutual
seed_batch_conversations!                 # conv1 (bob author, 3 vis, alice unread 1, 2 msgs) + conv2 (alice author, empty, unread 0)
seed_layout_rows!                         # aspects/notifications/services=1/tags/roles admin/reports (layout + C-13)
seed_principal!(10, 4, "dora")            # empty inbox (js full render terminal)
seed_principal!(11, 5, "fay")             # a fresh second principal
seed_principal!(30, 30, "zed", lang: "xx")# M-5: language present but NOT an available locale -> set_locale raises

# (no devise_warden_ready!: the hook-less warden needs no Warden::Manager.)

def r(tag, fmt, params = {}, opts = {})
  { tag: tag, fmt: fmt, params: params, opts: opts }
end

REQS = [
  # --- re-verifications -----------------------------------------------------
  r("c8_html_plain",       :html, {}),                                   # base html + full layout
  r("c7_html_page2_beyond",:html, { page: "2" }),                        # C-7 beyond-last-page (count>0 arm, empty rows)
  r("c5_html_cid1",        :html, { conversation_id: "1" }),             # C-5 set_read write (unread 1 -> 0)
  r("c8_json_plain",       :json, {}),
  r("json_cid1",           :json, { conversation_id: "1" }),             # cid on json: lookup + set_read then json body
  r("c6_html_cid_array",   :html, { conversation_id: ["1", "2"] }),      # C-6 IN (?, ?)
  r("c8_js_empty",         :js,   {}, uid: 10, expect: 500),             # C-8 js full render -> no_contacts Template::Error
  r("html_uid11_fresh",    :html, {}, uid: 11),
  r("c15_cid_empty_array", :html, {}, query_string: "conversation_id[]"),# C-15 AND 1=0
  r("c18_cid_oor",         :html, { conversation_id: "99999999999999999999" }, expect: 500), # C-18 RangeError
  r("m5_invalid_locale",   :html, {}, uid: 30, expect: 500),             # M-5 InvalidLocale before the action
  # --- fresh interactions (boundary arms gone) ------------------------------
  r("json_cid1_page2",     :json, { conversation_id: "1", page: "2" }),  # cid found + beyond page on json
  r("mobile_cid1",         :html, { conversation_id: "1" }, session: { mobile_view: true }), # mobile layout + cid + set_read
  r("mobile_plain",        :html, {}, session: { mobile_view: true }),   # mobile layout base
  r("html_cid2_nowrite",   :html, { conversation_id: "2" }),             # cid=2: visibility unread already 0 -> set_read save is a no-op (C-5 clean side)
  r("c7_page_abc",         :html, { page: "abc" }, expect: 500),         # C-7 InvalidPage (Integer("abc"))
  r("c7_page_zero",        :html, { page: "0" }, expect: 500),           # C-7 InvalidPage (0)
]

CONCRETE_SCENARIOS = adv7_scenarios([
  { name: "A1_reverify_interactions",
    body: lambda do
      REQS.each do |q|
        o = q[:opts] || {}
        adv7_request(format: q[:fmt], params: q[:params], tag: q[:tag],
                     uid: o[:uid] || 9, session: o[:session] || {},
                     query_string: o[:query_string], expect: o[:expect])
      end
    end },
])
