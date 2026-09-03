# Q02 — the `conversation_id` PARAM DOMAIN beyond string/array: an EMPTY
# array (`?conversation_id[]` -> [nil] -> deep_munge -> []), a HASH
# (`?conversation_id[a]=1`), the empty string, a non-numeric string, and a
# mixed valid/invalid array on each format.
require_relative "_common"
adv_setup!("Q02_cid_domain"); seed_people!(alice_extra: { last_seen: ts(Time.now) }); seed_batch_conversations!; seed_layout_rows!
devise_warden_ready!

def req(tag, fmt = :html, params = {}, opts = {})
  { name: "Q02_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("cid_empty_array_html",  :html, {}, query_string: "conversation_id[]"),
  req("cid_empty_array_json",  :json, {}, query_string: "conversation_id[]"),
  req("cid_empty_array_mobile", :html, {}, query_string: "conversation_id[]", session: { mobile_view: true }),
  req("cid_hash_html",         :html, {}, query_string: "conversation_id[a]=1"),
  req("cid_hash_json",         :json, {}, query_string: "conversation_id[a]=1"),
  req("cid_empty_string_html", :html, {}, query_string: "conversation_id="),
  req("cid_nonnumeric_html",   :html, { conversation_id: "1abc" }),
  req("cid_mixed_html",        :html, { conversation_id: ["999", "1"] }),
  req("cid_mixed_json",        :json, { conversation_id: ["2", "1"] }),
  req("cid_mixed_mobile",      :html, { conversation_id: ["1", "999", "2"] }, session: { mobile_view: true }),
  req("cid_array_with_nil",    :html, {}, query_string: "conversation_id[]=1&conversation_id[]"),
  req("cid_array_with_empty",  :html, {}, query_string: "conversation_id[]=1&conversation_id[]="),
  req("cid_nested_array",      :html, {}, query_string: "conversation_id[][]=1"),
])
