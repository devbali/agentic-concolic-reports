# P10 — `users.language = NULL`: the batch's ledger says NULL is the TRUE arm
# of `<principal>_language_available` ("nil leaves I18n at its default and
# renders 200, not a third state"). P08 showed a NULL-language principal
# issuing the principal `profiles` read that only an INFLECTED locale
# (`set_grammatical_gender`, application_controller.rb:120-131) should cause.
# `I18n.locale = nil` does not RESET the locale — `I18n.config.locale=` stores
# nil and the getter falls back to `default_locale`, but the inflector keeps
# its own notion — so the read may follow whatever the PREVIOUS request in the
# same thread set. Ordered alternation isolates it.
require_relative "_common"
adv_setup!("P10_locale_leak"); seed_people!

USERS = { 12 => "pl", 13 => nil, 15 => "de" }
USERS.each_with_index do |(uid, lang), ix|
  pid = 20 + ix
  CE.insert("users", id: uid, username: "u#{uid}", email: "u#{uid}@example.org",
            encrypted_password: "abcdefghijklmnopqrstuvwxyz0123456789",
            language: lang, getting_started: false, disable_mail: false, sign_in_count: 1)
  CE.insert("people", id: pid, guid: "pg#{pid}", diaspora_handle: "u#{uid}@localhost",
            serialized_public_key: "K#{pid}", owner_id: uid, closed_account: false, fetch_status: 0)
  CE.insert("profiles", id: 40 + ix, person_id: pid, first_name: "U#{uid}", last_name: "X",
            searchable: true, nsfw: false, gender: "female")
  CE.insert("conversation_visibilities", id: 80 + ix, conversation_id: 1, person_id: pid, unread: 0)
end
CE.insert("conversations", id: 1, subject: "shared", guid: "cg1", author_id: 1)
CE.insert("conversation_visibilities", id: 21, conversation_id: 1, person_id: 1, unread: 0)
CE.insert("messages", id: 31, conversation_id: 1, author_id: 1, guid: "mg1", text: "hello")

def req(tag, uid)
  { name: "P10_#{tag}", body: lambda do
      adv_request(format: :html, params: {}, uid: uid, tag: tag)
      warn "[adv3] after #{tag}: I18n.locale=#{I18n.locale.inspect} inflected?=#{I18n.inflector.inflected_locale?.inspect}"
    end }
end

CONCRETE_SCENARIOS = adv_scenarios([
  req("a_de_first",   15),
  req("b_null_after_de", 13),
  req("c_pl",         12),
  req("d_null_after_pl", 13),
  req("e_de_again",   15),
  req("f_null_after_de2", 13),
])
