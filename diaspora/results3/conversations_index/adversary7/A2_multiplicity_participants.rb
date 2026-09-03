# A7 / A2 — fresh post-auth surface: per-request MULTIPLICITY (counts, not sets)
# on html cid=1 with MANY conversations, plus the per-conversation render
# branches the 2-row seed universe does not express:
#   * a conversation with NO other participants (other_participants empty ->
#     the `if other_participants.first.present?` FALSE arm; no participants_count)
#   * a conversation with FIVE participants (other_participants.count > 1 ->
#     the `.drop(1).take(15)` extra-avatars loop, many person_image_tags)
#   * conversations with/without messages, with/without unread
# and an ABSENT-PROFILE principal (person row present, profiles row missing).
# Hook-less warden: only the principal SELECT touches users; everything else is
# action-frame (entrypoint verification).
require_relative "_common"

adv_setup!("A2_multiplicity_participants")
seed_people!                 # alice(9/1/11) bob(2) carol(3) + contact700 alice-bob mutual
# extra people/profiles to act as conversation participants (not users)
(4..8).each do |pid|
  CE.insert("people", id: pid, guid: "p#{pid}guid", diaspora_handle: "p#{pid}@remote.example",
            serialized_public_key: "K#{pid}", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("profiles", id: 40 + pid, person_id: pid, first_name: "P#{pid}", last_name: "X", searchable: true, nsfw: false)
end
seed_layout_rows!            # layout reads for alice

# ---- many conversations for alice (person 1) -----------------------------
# conv 1: cid target — three participants (alice, bob, carol), alice unread 2,
# two messages (first_unread + set_read fire).
CE.insert("conversations", id: 1, subject: "hello alice", guid: "cg1", author_id: 2)
CE.insert("conversation_visibilities", id: 101, conversation_id: 1, person_id: 1, unread: 2)
CE.insert("conversation_visibilities", id: 102, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("conversation_visibilities", id: 103, conversation_id: 1, person_id: 3, unread: 0)
CE.insert("messages", id: 201, conversation_id: 1, author_id: 2, guid: "mg201", text: "first")
CE.insert("messages", id: 202, conversation_id: 1, author_id: 3, guid: "mg202", text: "second")

# conv 2: SELF-ONLY — alice is the only visibility/participant (other_participants empty).
CE.insert("conversations", id: 2, subject: "solo", guid: "cg2", author_id: 1)
CE.insert("conversation_visibilities", id: 110, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("messages", id: 210, conversation_id: 2, author_id: 1, guid: "mg210", text: "note to self")

# conv 3: FIVE participants (alice + p2..p5) -> drop(1).take(15) extra avatars, count>1.
CE.insert("conversations", id: 3, subject: "big group", guid: "cg3", author_id: 4)
[1, 2, 3, 4, 5].each_with_index do |pid, i|
  CE.insert("conversation_visibilities", id: 120 + i, conversation_id: 3, person_id: pid, unread: (pid == 1 ? 1 : 0))
end
CE.insert("messages", id: 230, conversation_id: 3, author_id: 4, guid: "mg230", text: "group hi")

# conv 4: no messages, no unread (empty side: messages.present? false, last_author nil).
CE.insert("conversations", id: 4, subject: "", guid: "cg4", author_id: 2)
CE.insert("conversation_visibilities", id: 140, conversation_id: 4, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 141, conversation_id: 4, person_id: 2, unread: 0)

# conv 5..12: eight more plain 2-party conversations (fill page 1, per_page 15).
(5..12).each do |cid|
  CE.insert("conversations", id: cid, subject: "conv #{cid}", guid: "cg#{cid}", author_id: 2)
  CE.insert("conversation_visibilities", id: 1500 + cid, conversation_id: cid, person_id: 1, unread: (cid.even? ? 1 : 0))
  CE.insert("conversation_visibilities", id: 1600 + cid, conversation_id: cid, person_id: 2, unread: 0)
  CE.insert("messages", id: 2500 + cid, conversation_id: cid, author_id: 2, guid: "mgc#{cid}", text: "hi #{cid}")
end

# ABSENT-PROFILE principal: person present, NO profiles row (degenerate but a
# fixture within the symbolic-user declaration). Layout render reads profiles.*
# and gets nothing.
seed_principal!(50, 60, "nop", profile: false)

def r(tag, fmt, params = {}, opts = {})
  { tag: tag, fmt: fmt, params: params, opts: opts }
end

REQS = [
  r("many_html_cid1",   :html, { conversation_id: "1" }),  # THE multiplicity request: 12 convs render + cid=1 set_read
  r("many_html_plain",  :html, {}),                        # all 12 render, no cid
  r("many_json_plain",  :json, {}),                        # json map(&:conversation) over 12
  r("many_mobile_cid1", :html, { conversation_id: "1" }, session: { mobile_view: true }), # mobile per-conv render
  # (absent-profile principal isolated into A3 — JVM-abort isolation, MEMORY.md)
]

CONCRETE_SCENARIOS = adv7_scenarios([
  { name: "A2_multiplicity_participants",
    body: lambda do
      REQS.each do |q|
        o = q[:opts] || {}
        adv7_request(format: q[:fmt], params: q[:params], tag: q[:tag],
                     uid: o[:uid] || 9, session: o[:session] || {}, expect: o[:expect])
      end
    end },
])
