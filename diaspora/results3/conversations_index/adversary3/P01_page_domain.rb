# P01 — the DOMAIN of params[:page]. run_dse.rb models `page` as ONE boolean
# (`SYM_PARAM_page_beyond`: nil/page-1 vs page-2-beyond-the-end). will_paginate
# 3.3.0 `PageNumber#initialize` (page_number.rb:14-23) does `Integer(value)` and
# raises RangeError/ArgumentError/TypeError tagged `WillPaginate::InvalidPage`
# for anything that is not an integer >= 1 — INSIDE
# conversations_controller.rb:8-11 `.paginate(page: params[:page], ...)`, i.e.
# AFTER the ApplicationController filter chain (users read) and AFTER
# `current_user.person_id` (people.owner_id read) but BEFORE gon.contacts,
# before the visibilities count/load and before the contacts empty? probe.
require_relative "_common"
adv_setup!("P01_page_domain"); seed_people!; seed_batch_conversations!

def req(tag, page, fmt = :html, session = {})
  p = page.equal?(:none) ? {} : { page: page }
  { name: "P01_#{tag}", body: -> { adv_request(format: fmt, params: p, session: session, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("ctl_nil",      :none),
  req("ctl_page1",    "1"),
  req("page0",        "0"),
  req("page_minus1",  "-1"),
  req("page_abc",     "abc"),
  req("page_empty",   ""),
  req("page_array",   ["2"]),
  req("page_float",   "1.5"),
  req("page_huge",    "99999999999999999999"),
  req("page0_json",   "0", :json),
  req("page0_mobile", "0", :html, { mobile_view: true }),
  req("ctl_page2",    "2"),
])
