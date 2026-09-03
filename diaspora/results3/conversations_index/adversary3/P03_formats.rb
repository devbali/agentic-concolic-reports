# P03 — every response format. `respond_to :html, :mobile, :json, :js`
# (conversations_controller.rb:5) with a `respond_with` block that registers
# only html and json (:26-30). format_coverage_audit only judges html/json/
# mobile; :js is declared TEMPLATELESS. Undeclared formats (:xml, :atom, :csv,
# :text) go through `respond_with` too. Each is one request, so the statement
# multiset up to the raise is attributable.
require_relative "_common"
adv_setup!("P03_formats"); seed_people!; seed_batch_conversations!

def req(tag, fmt, params = {}, headers = {})
  { name: "P03_#{tag}",
    body: -> { adv_request(format: fmt, params: params, headers: headers, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("ctl_html",  :html),
  req("js",        :js),
  req("js_cid",    :js, { conversation_id: "1" }),
  req("xml",       :xml),
  req("xml_cid",   :xml, { conversation_id: "1" }),
  req("atom",      :atom),
  req("csv",       :csv),
  req("text",      :text),
  req("accept_xml", :html, {}, { "HTTP_ACCEPT" => "application/xml" }),
  req("mobile_explicit", :mobile),
])
