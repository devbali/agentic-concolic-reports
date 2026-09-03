# P12 — completes W1's derivation. `set_read` (conversation.rb:37-42) writes iff
# the visibility row is DIRTY, i.e. iff its `unread` is not already 0.
#  * unread = 0  -> no UPDATE (P04)
#  * unread = 3  -> UPDATE   (P04)
#  * unread = -3 -> UPDATE, while `first_unread_message`'s
#    `where('unread > 0').first` still returns NOTHING — i.e. the corpus's
#    `…_first_2_not_found == True` state paired with a real UPDATE, the exact
#    opposite of the unread = 0 case it is currently welded to.
#    `unread` is `integer default 0 NOT NULL` with no CHECK constraint
#    (db/schema.rb:143) and no app path writes a negative value
#    (`Message#increase_unread` only increments, `set_read` writes 0), so this
#    is legacy/hand-edited data — the same standing M-6 established for an
#    out-of-tree STI `type`.
require_relative "_common"
adv_setup!("P12_unread_negative"); seed_people!

CE.insert("conversations", id: 1, subject: "negative unread", guid: "cg1", author_id: 2)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: -3)
CE.insert("conversation_visibilities", id: 22, conversation_id: 1, person_id: 2, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 2, guid: "mg1", text: "one")
CE.insert("conversations", id: 2, subject: "zero unread", guid: "cg2", author_id: 2)
CE.insert("conversation_visibilities", id: 23, conversation_id: 2, person_id: 1, unread: 0)
CE.insert("conversation_visibilities", id: 24, conversation_id: 2, person_id: 2, unread: 0)
CE.insert("messages", id: 32, conversation_id: 2, author_id: 2, guid: "mg2", text: "two")

def req(tag, cid, fmt = :html)
  { name: "P12_#{tag}",
    body: -> { adv_request(format: fmt, params: { conversation_id: cid }, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("cid1_unread_minus3", "1"),
  req("cid1_now0_again",    "1"),
  req("ctl_cid2_unread0",   "2"),
])
