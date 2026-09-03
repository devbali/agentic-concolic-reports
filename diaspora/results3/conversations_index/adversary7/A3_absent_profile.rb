# A7 / A3 — ISOLATED (JVM-abort isolation, MEMORY.md): an ABSENT-PROFILE
# principal (users + people rows present, profiles row missing). A degenerate
# fixture within the symbolic-user declaration. Question: does the layout /
# JSON path issue any novel statement shape, or a novel terminal, that the
# corpus lacks? html renders the layout (UserPresenter -> person.as_api_response
# reads profile); json skips the layout.
require_relative "_common"

adv_setup!("A3_absent_profile")
seed_people!                              # alice full (unused principal, keeps schema warm)
seed_batch_conversations!
seed_principal!(50, 60, "nop", profile: false)   # person 60, NO profiles row

def r(tag, fmt, params = {}, opts = {})
  { tag: tag, fmt: fmt, params: params, opts: opts }
end

REQS = [
  r("absent_profile_json", :json, {}, uid: 50),               # no layout: content path only
  r("absent_profile_html", :html, {}, uid: 50, expect: 500),  # layout render reads the missing profile
]

CONCRETE_SCENARIOS = adv7_scenarios([
  { name: "A3_absent_profile",
    body: lambda do
      REQS.each do |q|
        o = q[:opts] || {}
        adv7_request(format: q[:fmt], params: q[:params], tag: q[:tag],
                     uid: o[:uid] || 9, session: o[:session] || {}, expect: o[:expect])
      end
    end },
])
