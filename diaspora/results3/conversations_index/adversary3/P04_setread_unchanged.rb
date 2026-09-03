# P04 — `Conversation#set_read` (conversation.rb:37-42):
#     visibility = conversation_visibilities.find_by(person_id: user.person.id)
#     return unless visibility
#     visibility.unread = 0
#     visibility.save
# TWO claims of the corpus are tested here.
# (1) OVER-EMISSION: the corpus's `ActiveRecord::Base.save` target carries the
#     single note `UPDATE "conversation_visibilities" SET "unread" = ?,
#     "updated_at" = ? WHERE ... id = $(...)` on EVERY cid request. Rails
#     partial writes issue NO UPDATE when the record is unchanged, i.e. when
#     the visibility's `unread` is ALREADY 0 — a state every second request on
#     the same conversation reaches (the first one zeroed it).
# (2) IMPOSSIBLE STATE: `..._find_by_1_not_found == True` (a recorded decision
#     with both polarities in the corpus) requires set_read's find_by to return
#     nil — but the conversation was found only BECAUSE a visibility row with
#     (person_id = mine, conversation_id = cid) exists
#     (conversations_controller.rb:14-18), and (conversation_id, person_id) is
#     UNIQUE (schema.rb:146). The row set_read looks for is the row that
#     selected the conversation.
require_relative "_common"
adv_setup!("P04_setread"); seed_people!

# conv 1: my visibility unread = 0 from the start (never any UPDATE)
CE.insert("conversations", id: 1, subject: "already read", guid: "cg1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "mg1", text: "one")
# conv 2: my visibility unread = 3 (first cid request UPDATEs, second must not)
CE.insert("conversations", id: 2, subject: "unread three", guid: "cg2", author_id: 2)
CE.insert("conversation_visibilities", id: 23, conversation_id: 2, person_id: 1, unread: 3)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 2, unread: 0)
CE.insert("messages", id: 32, conversation_id: 2, author_id: 2, guid: "mg2", text: "a")
CE.insert("messages", id: 33, conversation_id: 2, author_id: 2, guid: "mg3", text: "b")
CE.insert("messages", id: 34, conversation_id: 2, author_id: 1, guid: "mg4", text: "c")
CE.insert("messages", id: 35, conversation_id: 2, author_id: 2, guid: "mg5", text: "d")

def req(tag, cid, fmt = :html, session = {})
  { name: "P04_#{tag}",
    body: -> { adv_request(format: fmt, params: { conversation_id: cid }, session: session, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("cid1_unread0_html",   "1"),        # unchanged save -> BEGIN/COMMIT, no UPDATE
  req("cid1_unread0_again",  "1"),
  req("cid1_unread0_json",   "1", :json),
  req("cid1_unread0_mobile", "1", :html, { mobile_view: true }),
  req("cid2_unread3_first",  "2"),        # UPDATE issued
  req("cid2_now0_second",    "2"),        # same request again: must NOT UPDATE
  req("cid2_now0_third",     "2", :json),
])
