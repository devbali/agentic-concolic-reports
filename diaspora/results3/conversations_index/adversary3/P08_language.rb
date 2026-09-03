# P08 — the DOMAIN of users.language (coordinator matrix row T-f / M-5), on
# THIS endpoint. `ApplicationController#set_locale` (:100-108) runs before
# `authenticate_user!` and assigns `I18n.locale = current_user.language`; with
# `I18n.enforce_available_locales` a non-nil value that is not an available
# locale raises `I18n::InvalidLocale` before the action body. The batch models
# this as `<principal>_language_available` with a FALSE arm claiming EXACTLY
# ONE statement (the Devise users read); 13 corpus dumps carry the terminal.
# One user per arm so the harness's per-request warden never reuses a resolved
# User with its association cache.
require_relative "_common"
adv_setup!("P08_language"); seed_people!

USERS = { 10 => "xx", 11 => "", 12 => "pl", 13 => nil, 14 => "en-GB", 15 => "de" }
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

def req(tag, uid, fmt = :html)
  { name: "P08_#{tag}", body: -> { adv_request(format: fmt, params: {}, uid: uid, tag: tag) } }
end

CONCRETE_SCENARIOS = adv_scenarios([
  { name: "P08_domain_probe", body: lambda do
      warn "[adv3] enforce_available_locales=#{I18n.enforce_available_locales.inspect}"
      warn "[adv3] available=#{I18n.available_locales.map(&:to_s).sort.inspect}"
      warn "[adv3] AVAILABLE_LANGUAGE_CODES-avail=#{(AVAILABLE_LANGUAGE_CODES.map(&:to_s) - I18n.available_locales.map(&:to_s)).inspect}"
      warn "[adv3] inflected=#{I18n.available_locales.select { |l| I18n.inflector.inflected_locale?(l) }.inspect}"
      warn "[adv3] DEFAULT_LANGUAGE=#{DEFAULT_LANGUAGE.inspect}"
    end },
  req("ctl_en_user9", 9),
  req("lang_xx",      10),
  req("lang_empty",   11),
  req("lang_pl",      12),
  req("lang_null",    13),
  req("lang_enGB",    14),
  req("lang_de",      15),
  req("lang_xx_json", 10, :json),
])
