# ROUND 8 / H05 — ENTRYPOINT EVIDENCE for the fix_profile family, plus three
# states H02/H04 raised questions about.
#  (1) full BACKTRACE of the DiscoveryError, to prove `Person#fix_profile` and
#      `Discovery#fetch_and_save` are entered from the ACTION frame (post-auth,
#      principal concretely instantiated) and not from a filter or middleware;
#  (2) TWO comments by ONE author -- the real counterpart of the corpus's
#      `…_row_author_keys_many == False` state (5 683 dumps): the ONE emitted
#      `people.id = ?` covers BOTH rendered comments' authors;
#  (3) signed-in JSON on a SHARE-VISIBLE post: does the request read the
#      principal's own `people` row at all?
#  (4) a mentioned person who IS the comment author and has no profile.
require_relative "_common8"
require_relative "_frames8"
adv_setup!("H05_backtrace_and_states")
seed_core!

CE.insert("people", id: 8, guid: "wraithguid0000008", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "h5cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

# 860 — ONE comment, author 8 has no profiles row (backtrace subject)
post!(860, "h05guid860000000001"); comment!(870, 860, 8)
# 861 — TWO comments, ONE author (person 2). keys_many == False's real state.
post!(861, "h05guid861000000001"); comment!(871, 861, 2); comment!(872, 861, 2)
# 862 — TEN comments, ONE author
post!(862, "h05guid862000000001"); 10.times { |i| comment!(880 + i, 862, 2) }
# 863 — private post SHARED with user 9 (share_visibilities arm succeeds first)
post!(863, "h05guid863000000001", public_flag: false)
CE.insert("share_visibilities", id: 41, shareable_id: 863, shareable_type: "Post", user_id: 9, hidden: false)
comment!(890, 863, 2)
# 864 — the comment AUTHOR is also the MENTIONED person, and has no profile
post!(864, "h05guid864000000001")
comment!(891, 864, 8, "me @{wraith@ba[d.example} again"); mention!(895, 891, 8)
# 865 — author 2 (profile), mentioned person 8 (no profile), NAMED markup, json
post!(865, "h05guid865000000001")
comment!(892, 865, 2, "hi @{Wraith; wraith@ba[d.example}"); mention!(896, 892, 8)

# a request wrapper that keeps the FULL backtrace (adv_request truncates)
BT = {}
def req_bt!(tag:, **kw)
  $adv_tag = tag
  ctrl, tc = make_harness(CommentsController)
  kw[:signed_in] ? install_real_warden(tc, kw[:uid] || 9) : install_anon_warden(tc)
  begin
    tc.process(:index, method: :get, params: {post_id: kw[:post_id]}, format: kw[:format])
    warn "[adv8] #{tag} -> #{ctrl.response.status} (#{ctrl.response.body.to_s.bytesize} bytes)"
  rescue StandardError => e
    root = e
    root = root.cause while root.cause
    BT[tag] = {"class" => e.class.to_s, "message" => e.message.to_s[0, 300],
               "root_class" => root.class.to_s, "root_message" => root.message.to_s[0, 300],
               "backtrace" => root.backtrace.first(45)}
    warn "[adv8] #{tag} -> EXC #{e.class} (root #{root.class}); backtrace captured"
  end
  $adv_tag = nil
end

CONCRETE_SCENARIOS = adv_scenario("H05-backtrace-and-states") do
  req_bt!(tag: "H05_860_author_noprofile_json",   post_id: "860", format: :json)
  req_bt!(tag: "H05_860_author_noprofile_mobile", post_id: "860", format: :mobile)
  req_bt!(tag: "H05_864_author_is_mention_json",  post_id: "864", format: :json)
  req_bt!(tag: "H05_865_named_mention_noprofile_json", post_id: "865", format: :json)
  req_bt!(tag: "H05_865_named_mention_noprofile_mobile", post_id: "865", format: :mobile)
  req!(post_id: "861", format: :json,   tag: "H05_861_2c_1author_json")
  req!(post_id: "861", format: :mobile, tag: "H05_861_2c_1author_mobile")
  req!(post_id: "862", format: :json,   tag: "H05_862_10c_1author_json")
  req!(post_id: "863", format: :json,   signed_in: true, uid: 9, tag: "H05_863_sharevis_auth_json")
  req!(post_id: "863", format: :mobile, signed_in: true, uid: 9, tag: "H05_863_sharevis_auth_mobile")
  File.write(File.join(ADV_DIR, "runs", "_backtraces_H05.json"), JSON.pretty_generate(BT))
  warn "[adv8] backtraces written: #{BT.keys.inspect}"
  dump_frames!("H05")
end
