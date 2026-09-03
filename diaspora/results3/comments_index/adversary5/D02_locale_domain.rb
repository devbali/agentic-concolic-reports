# D02 — ROUND 5, brief item 2a: is the THREE-valued `users.language` chain
# complete?  The corpus encodes {"pl" -> inflected, "xx" -> I18n::InvalidLocale,
# else "en"}.  Attacked here:
#   * a locale that is AVAILABLE but has no gender inflection ("all" is a real
#     I18n locale created by config/locales/inflections/all.yml);
#   * malformed / wrong-case / over-long values;
#   * codes that are AVAILABLE but not offered, and codes that are OFFERED but
#     may not be available;
#   * the ANONYMOUS arm of `set_locale`, which the corpus does not model at all:
#     `http_accept_language.language_region_compatible_from AVAILABLE_LANGUAGE_CODES`
#     then `I18n.locale = locale` — a header-driven assignment that would raise
#     BEFORE any statement at all if the two lists disagree.
require_relative "_common5"
adv_setup!("D02_locale_domain")
seed_core!

CE.insert("posts", id: 350, author_id: 2, guid: "d02guid350000000001", type: "StatusMessage",
          text: "p350", public: true, comments_count: 1)
CE.insert("comments", id: 550, commentable_id: 350, commentable_type: "Post", author_id: 2,
          guid: "cguid550", text: "hello", created_at: "2020-01-01 00:00:01")

LANGS = {
  41 => "all",          # a real I18n locale (inflections/all.yml) — available AND inflected?
  42 => "PL",           # right code, wrong case
  43 => "pl-PL",        # region-qualified variant of an offered code
  44 => "pt-BR",        # offered, region-qualified, not inflected
  45 => "de_formal",    # offered, underscore variant
  46 => "en-US",        # a very common real-world value
  47 => " pl",          # leading whitespace
  48 => "z" * 250,      # over-long (column is a plain string)
  49 => "art-nvi"       # offered, exotic
}
LANGS.each do |uid, lang|
  seed_user!(uid: uid, username: "u#{uid}", language: lang,
             person_id: 100 + uid, person_guid: "d02pguid#{uid}00000", handle: "u#{uid}@localhost",
             profile_id: 200 + uid, gender: "male")
end

CONCRETE_SCENARIOS = adv_scenario("D02-locale-domain") do
  adv_probe("enforce_available_locales") { I18n.enforce_available_locales }
  adv_probe("available_locales_size")    { I18n.available_locales.size }
  adv_probe("offered_codes_size")        { AVAILABLE_LANGUAGE_CODES.size }
  adv_probe("OFFERED_MINUS_AVAILABLE") {
    AVAILABLE_LANGUAGE_CODES.map(&:to_s) - I18n.available_locales.map(&:to_s)
  }
  adv_probe("AVAILABLE_MINUS_OFFERED_sample") {
    (I18n.available_locales.map(&:to_s) - AVAILABLE_LANGUAGE_CODES.map(&:to_s)).sort.first(40)
  }
  adv_probe("inflected_locales_gender")  { I18n.inflector.inflected_locales(:gender).map(&:to_s).sort }
  adv_probe("ALL_inflected_locales") {
    I18n.available_locales.select { |l| I18n.inflector.inflected_locale?(l) rescue false }.map(&:to_s).sort
  }
  adv_probe("all_is_available")          { I18n.available_locales.include?(:all) }
  adv_probe("DEFAULT_LANGUAGE")          { DEFAULT_LANGUAGE }
  adv_probe("locale_settings_has_all")   { AVAILABLE_LANGUAGE_CODES.include?("all") }

  # signed-in: one uid per arm (the warden memo is per-uid)
  LANGS.each_key do |uid|
    adv_request(post_id: "350", format: :json, signed_in: true, uid: uid,
                tag: "D02_lang_#{uid}")
  end
  # controls in the same process
  adv_request(post_id: "350", format: :json, signed_in: true, uid: 9, tag: "D02_lang_control_en")

  # anonymous set_locale — header driven, no column involved
  [
    ["pl", "hdr_pl"],
    ["xx", "hdr_xx"],
    ["de_formal", "hdr_de_formal"],
    ["art-nvi;q=1.0, en;q=0.5", "hdr_artnvi"],
    ["*", "hdr_star"],
    [",,,;q=", "hdr_garbage"],
    ["", "hdr_empty"],
    [("aa-BB;q=0.9," * 400), "hdr_huge"],
    ["zh-TW,zh;q=0.9", "hdr_zhtw"]
  ].each do |val, tag|
    adv_request(post_id: "350", format: :json,
                headers: {"Accept-Language" => val}, tag: "D02_#{tag}")
  end
end
