# E01 — ROUND 6, brief item 3: break the M-7/M-8 DISTINCT-KEY model.
# Hypotheses under test (both corpus-side, both need real ground truth):
#  H1  the NESTED preload step's key count is DERIVED, not free: with N parents
#      actually loaded, the `profiles` step keys on N DISTINCT people.id values,
#      so `people.id IN (a,b)` can NEVER be followed by `profiles.person_id = ?`
#      on a tree whose parents all loaded.
#  H2  on the `mentions` tree the DISTINCT-KEY count IS the row count, because
#      `index_mentions_on_person_and_mc_id_and_mc_type` is UNIQUE on
#      (person_id, mentions_container_id, mentions_container_type) — two mention
#      rows on ONE comment cannot share a person_id, so `len(mentions) > 1`
#      with `people.id = ?` is not a database state.
# Plus the four shapes the brief names: 3 comments/2 authors, an author who is
# also the mentioned person, a nested step with 2 loaded + 1 missing parent, and
# the 1-distinct-key control.
require_relative "_common6"
adv_setup!("E01_key_model")
seed_core!

CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@remote.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G", searchable: true, nsfw: false)

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "e1cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

# 700: 3 comments, 2 distinct authors  -> people IN(2) / profiles IN(2), 3 rows
post!(700, "e01guid700000000001"); comment!(800, 700, 2); comment!(801, 700, 2); comment!(802, 700, 5)
# 701: 2 authors where ONE is also the mentioned person
post!(701, "e01guid701000000001"); comment!(803, 701, 2, "hello @{Erin; erin@other.example}"); comment!(804, 701, 5)
mention!(900, 803, 5)
# 702: nested step whose parents are 2 loaded + 1 MISSING (dangling mentions.person_id)
post!(702, "e01guid702000000001"); comment!(805, 702, 2, "three mentions")
mention!(901, 805, 5); mention!(902, 805, 6); mention!(903, 805, 995)
# 703: 2 live mentions, both with profiles -> IN then IN  (H1 disproof of IN->=)
post!(703, "e01guid703000000001"); comment!(806, 703, 2, "two live mentions")
mention!(904, 806, 5); mention!(905, 806, 6)
# 704: 4 comments, 4 distinct authors
post!(704, "e01guid704000000001")
[2, 5, 6, 7].each_with_index { |a, i| comment!(810 + i, 704, a) }
# 705: 2 comments, 1 author (M-7 control)
post!(705, "e01guid705000000001"); comment!(820, 705, 2); comment!(821, 705, 2)
# 706: 1 comment, 1 mention (control for the mentions tree at cardinality 1)
post!(706, "e01guid706000000001"); comment!(822, 706, 2, "one mention"); mention!(906, 822, 5)
# 707: 2 comments, ONE mention each, SAME person  (each relation has one row)
post!(707, "e01guid707000000001"); comment!(823, 707, 2, "m"); comment!(824, 707, 5, "m")
mention!(907, 823, 5); mention!(908, 824, 5)
# 708: signed-in, share-visible, 3 comments / 2 authors
post!(708, "e01guid708000000001", public_flag: false)
CE.insert("share_visibilities", id: 11, shareable_id: 708, shareable_type: "Post", user_id: 9, hidden: false)
comment!(830, 708, 2); comment!(831, 708, 2); comment!(832, 708, 6)

CONCRETE_SCENARIOS = adv_scenario("E01-key-model") do
  adv_request(post_id: "700", format: :json,   tag: "E01_700_3c_2authors")
  adv_request(post_id: "700", format: :mobile, tag: "E01_700_3c_2authors_mobile")
  adv_request(post_id: "701", format: :json,   tag: "E01_701_author_is_mentioned")
  adv_request(post_id: "701", format: :mobile, tag: "E01_701_author_is_mentioned_mobile")
  adv_request(post_id: "702", format: :json,   tag: "E01_702_3mentions_2loaded_1missing")
  adv_request(post_id: "703", format: :json,   tag: "E01_703_2live_mentions")
  adv_request(post_id: "703", format: :mobile, tag: "E01_703_2live_mentions_mobile")
  adv_request(post_id: "704", format: :json,   tag: "E01_704_4c_4authors")
  adv_request(post_id: "705", format: :json,   tag: "E01_705_2c_1author")
  adv_request(post_id: "706", format: :json,   tag: "E01_706_1mention")
  adv_request(post_id: "707", format: :json,   tag: "E01_707_two_comments_same_mentioned")
  adv_request(post_id: "708", format: :json, signed_in: true, tag: "E01_708_shared_3c_2authors_auth")
  adv_request(post_id: "708", format: :mobile, signed_in: true, tag: "E01_708_shared_3c_2authors_auth_mobile")
end
