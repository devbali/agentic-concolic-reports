# R02 — the parameter domains beyond the corpus's arms: integers outside the
# 4-byte column range (ActiveModel::Type::Integer#ensure_in_range raises
# ActiveModel::RangeError while the finder builds its binds — BEFORE any
# statement reaches the DB), the OFFSET domain, [""] arrays, nested hashes,
# a conflicting scalar/array query string. Session principal (fetch) so the
# boundary contributes nothing new.
require_relative "_common"
adv_setup!("R02_cid_overflow"); seed_people!(alice_extra: { last_seen: ts(Time.now) }); seed_batch_conversations!; seed_layout_rows!
devise_warden_ready!
def req(tag, fmt = :html, params = {}, opts = {})
  { name: "R02_#{tag}", body: -> { adv_request({ format: fmt, params: params, tag: tag }.merge(opts)) } }
end
CONCRETE_SCENARIOS = adv_scenarios([
  req("cid_2p31_html",        :html, {}, query_string: "conversation_id=2147483648"),
  req("cid_2p31_json",        :json, {}, query_string: "conversation_id=2147483648"),
  req("cid_huge_html",        :html, {}, query_string: "conversation_id=99999999999999999999"),
  req("cid_neg_2p31_html",    :html, {}, query_string: "conversation_id=-2147483649"),
  req("cid_2p31m1_html",      :html, {}, query_string: "conversation_id=2147483647"),  # in range: = ? not found
  req("cid_array_2p31_html",  :html, {}, query_string: "conversation_id[]=1&conversation_id[]=2147483648"),
  req("cid_array1_2p31_html", :html, {}, query_string: "conversation_id[]=2147483648"),
  req("cid_1_9_html",         :html, {}, query_string: "conversation_id=1.9"),        # casts to 1 -> found
  req("cid_array_emptystr",   :html, {}, query_string: "conversation_id[]="),          # [""]
  req("cid_array_two_emptystr", :html, {}, query_string: "conversation_id[]=&conversation_id[]="),
  req("cid_hash_nested_arr",  :html, {}, query_string: "conversation_id[a][]=1"),
  req("cid_scalar_then_array", :html, {}, query_string: "conversation_id=1&conversation_id[]=2"), # Rack TypeError
  req("page_huge_html",       :html, {}, query_string: "page=99999999999999999999"),
  req("page_2p31_html",       :html, {}, query_string: "page=2147483648"),
  req("page_hex_html",        :html, {}, query_string: "page=0x2"),                   # Integer("0x2") == 2
  req("page_2p31_json",       :json, {}, query_string: "page=2147483648"),
])
