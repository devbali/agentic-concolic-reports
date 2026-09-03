# ROUND 9 / J02 — THE SECOND KEY'S CONSEQUENCE, A THIRD KEY, AND THE PER-ROW
# BRANCH THAT IS NOT KEYED ON THE AUTHOR ID.
#
# Attacks:
#  (1) M-16's repair deleted `_k2_not_found` and made the second key's outcome a
#      per-object decision. `needs_second_row?` walks the includes tree and
#      returns true on `has_one` / FK-less `belongs_to`. What it never
#      materialises is a THIRD representative row: the corpus holds 853 192
#      `_row2_` symbols and ZERO `_row3_`, and every `IN (…)` bind in it has
#      arity 2. Question: does a THIRD distinct key ever change a per-REQUEST
#      shape, or only an arity?
#  (4) N8-5 was closed "by construction": in the one-key state row 2's
#      `author_id` IS row 1's symbol. Question: is there a per-row branch that
#      must still distinguish two rows that share an author? The mobile partial
#      has one candidate (`comment.author == current_user.person`, the trash
#      link) and `person_link_class` has two more — all three keyed on the
#      author id, so the closure predicts they agree for both rows. Measured.
#  (5) row-count > key-count with THREE rows (A, B, A).
require_relative "_common9"
require_relative "_frames9"
adv_setup!("J02_keys_and_rows")
seed_core!

# three remote people WITH profiles, one WITHOUT (URI-hostile handle)
CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@other.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G", searchable: true, nsfw: false)
CE.insert("people", id: 8, guid: "wraithguid0000008", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("people", id: 10, guid: "specterguid000010", diaspora_handle: "specter@ba[d2.example",
          serialized_public_key: "KA", owner_id: nil, closed_account: false, fetch_status: 0)

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "j2cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

# 920 — THREE authors (2, 5, 6) all with profiles: `people.id IN (?,?,?)`
post!(920, "j02guid920000000001"); comment!(930, 920, 2); comment!(931, 920, 5); comment!(932, 920, 6)
# 921 — THREE authors, only the THIRD lacks a profile (8)
post!(921, "j02guid921000000001"); comment!(933, 921, 2); comment!(934, 921, 5); comment!(935, 921, 8)
# 922 — THREE authors, only the FIRST lacks a profile (mirror)
post!(922, "j02guid922000000001"); comment!(936, 922, 8); comment!(937, 922, 2); comment!(938, 922, 5)
# 923 — THREE rows, TWO distinct authors (A, B, A): rows > keys
post!(923, "j02guid923000000001"); comment!(939, 923, 2); comment!(940, 923, 5); comment!(941, 923, 2)
# 924 — signed-in per-row branch: row1 authored by the PRINCIPAL's person (1),
#       row2 by someone else (2). The trash link must appear on exactly one row.
post!(924, "j02guid924000000001"); comment!(942, 924, 1); comment!(943, 924, 2)
# 925 — mirror of 924 (row1 other, row2 principal)
post!(925, "j02guid925000000001"); comment!(944, 925, 2); comment!(945, 925, 1)
# 926 — TWO comments by the SAME author (the one-key state), signed-in, and that
#       author IS the principal: both rows must show the trash link.
post!(926, "j02guid926000000001"); comment!(946, 926, 1); comment!(947, 926, 1)
# 927 — ONE comment with THREE mentions: one dangling (99), one profile-less (8),
#       one live (7). Nested step sees a 3-key outer and a 2-key nested.
post!(927, "j02guid927000000001")
comment!(948, 927, 2, "x @{grace@other.example} y @{wraith@ba[d.example} z @{gone@ba[d3.example}")
mention!(950, 948, 7); mention!(951, 948, 8); mention!(952, 948, 99)
# 928 — ONE comment with THREE LIVE mentions (5, 6, 7), all with profiles
post!(928, "j02guid928000000001")
comment!(949, 928, 2, "x @{erin@other.example} y @{frank@third.example} z @{grace@other.example}")
mention!(953, 949, 5); mention!(954, 949, 6); mention!(955, 949, 7)

CONCRETE_SCENARIOS = adv_scenario("J02-keys-and-rows") do
  req!(post_id: "920", format: :json,   tag: "J02_920_three_authors_json")
  req!(post_id: "920", format: :mobile, tag: "J02_920_three_authors_mobile")
  req!(post_id: "921", format: :json,   tag: "J02_921_third_author_noprofile_json")
  req!(post_id: "921", format: :mobile, tag: "J02_921_third_author_noprofile_mobile")
  req!(post_id: "922", format: :json,   tag: "J02_922_first_author_noprofile_json")
  req!(post_id: "923", format: :json,   tag: "J02_923_three_rows_two_keys_json")
  req!(post_id: "923", format: :mobile, tag: "J02_923_three_rows_two_keys_mobile")
  req!(post_id: "924", format: :mobile, signed_in: true, tag: "J02_924_principal_row1_mobile")
  req!(post_id: "925", format: :mobile, signed_in: true, tag: "J02_925_principal_row2_mobile")
  req!(post_id: "926", format: :mobile, signed_in: true, tag: "J02_926_onekey_both_principal_mobile")
  req!(post_id: "927", format: :json,   tag: "J02_927_three_mentions_mixed_json")
  req!(post_id: "928", format: :json,   tag: "J02_928_three_live_mentions_json")
  req!(post_id: "928", format: :mobile, tag: "J02_928_three_live_mentions_mobile")
  dump_frames!("J02")
end
