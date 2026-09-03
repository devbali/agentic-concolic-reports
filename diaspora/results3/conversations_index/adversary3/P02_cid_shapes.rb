# P02 — the SHAPE of params[:conversation_id]. It is a QUERY parameter of
# GET /conversations (routes.rb:79 `resources :conversations`), not a path
# segment, so `?conversation_id[]=1&conversation_id[]=2` reaches the action.
# conversations_controller.rb:13-18 puts it straight into
# `where(conversation_visibilities: {..., conversation_id: params[:conversation_id]})`,
# so an Array makes ActiveRecord build `IN (?, ?)`. run_dse.rb:266 models it as
# a single symint (SYM_PARAM_conversation_id) and the corpus contains ZERO
# `IN (...)` notes of any kind.
require_relative "_common"
adv_setup!("P02_cid_shapes"); seed_people!; seed_batch_conversations!

def req(tag, cid, fmt = :html, session = {})
  { name: "P02_#{tag}",
    body: -> { adv_request(format: fmt, params: { conversation_id: cid }, session: session, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("ctl_scalar1",   "1"),
  req("array_1_2",     %w[1 2]),
  req("array_one",     %w[1]),
  req("array_3",       %w[1 2 999]),
  req("array_miss",    %w[998 999]),
  req("array_json",    %w[1 2], :json),
  req("array_mobile",  %w[1 2], :html, { mobile_view: true }),
  req("empty_string",  ""),
  req("hash",          { "foo" => "1" }),
  req("nested_array",  [%w[1 2]]),
])
