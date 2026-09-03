"""conversations_index — batch-local AssumptionSet (results3 completion drive,
2026-08-26; supersedes the 2026-08-18 file, whose universe no longer exists:
the loaded-relation reads removed the size_N/last_N/count-per-row families,
the real Devise resolution renamed the principal, and the persisted decision
added `_persisted` exprs).

THREE KINDS OF DECLARATION, each a structural claim the engine verifies
(concolic_engine/assumptions.py IndependenceAssumption; the completion
engine's derived flip-probe test — flip A, flip B, flip both; the
both-flipped run must add no target-call shape absent from the singles):

  TIER 0 — VARIANT EXCLUSIVITY. run_dse.rb's four request shapes
  (html/json x with/without conversation_id) are mutually exclusive per
  run (conversations_controller.rb:13 `if params[:conversation_id]`;
  `respond_with do |format|` html/json). Auto-derived from the label ->
  variant-set membership of every expr; disjoint sets => independent.

  TIER 1 — STRUCTURAL GATES. A gate G with closing value v makes a region
  of code unreachable; every decision Y recorded only inside that region is
  foreclosed by G=v. The gate table below names each gate's SOURCE LINE and
  CLOSING VALUE; the foreclosed family is derived from the corpus (Y is
  never co-evaluated with G=v, and is co-evaluated with G=!v), which is the
  honest way to name families here because this endpoint's `records`/`to_a`
  ordinals SHIFT with the sidebar gate (see "ordinal note" below). A gate
  expr that is not in the table raises — an undocumented gate is a bug in
  this file, never a silent declaration.

  TIER 2 — DISJOINT-OBJECT DECISIONS. Two decisions evaluated on DIFFERENT
  symbolic reps (different owner-rep var prefix) in this endpoint's render
  tree neither gate nor feed each other: every rep's decisions (its
  `_persisted` read in AR's find_target?, its `guid == ''`/`id == person_id`
  compares in person_link/person_image helpers, its `unread > 0` badge,
  its list length) are consumed by code that reads ONLY that rep, and every
  statement shape any of them can produce (a profile/person load keyed on
  that rep's own id) is produced by that rep's decisions alone. This is a
  disjointness claim, not a gate: it carries no closing value; the engine's
  flip-both probe is what licenses it. Decisions on the SAME rep stay
  dependent (small cliques the corpus covers in full).

Ordinal note (unchanged finding from the 2026-08-18 file): `records_N` /
`to_a_N` names are per-(class, method) call counters, so `records_1` is the
sidebar row's `messages` load when the sidebar renders and `_show.haml`'s
participants loop when it does not (K=False). No assumption below names an
ordinal as a GUARD with a fixed meaning — Tier 1 families are derived
per-polarity from the corpus (a foreclosure claim "Y never with G=v" is
sound whatever Y denotes elsewhere), and Tier 2 keys on the rep prefix,
which is the same object identity the PCs themselves name.

Source lines cited (read-only):
  app/controllers/conversations_controller.rb:13-23  `if params[:conversation_id]` / `if @conversation`
  app/models/conversation.rb:31-35   first_unread_message: `if visibility = ...first` -> `messages.to_a[-unread]`
  app/models/conversation.rb:37-42   set_read: `find_by` -> `return unless visibility`
  app/models/conversation.rb:52-56   last_author: `return unless ... messages.size > 0`; `Person.includes(:profile).find_by`
  app/views/conversations/index.haml:15-19   `- if @visibilities.count > 0` -> per-visibility partial
  app/views/conversations/index.haml:25-27   `- if @conversation` -> `render 'conversations/show'`
  app/views/conversations/_conversation.haml:5-6   `conversation = visibility.conversation` -> `conversation_path(conversation)`
  app/views/conversations/_conversation.haml:31-35 `messages.present?` -> `messages.last.message`
  app/helpers/people_helper.rb:36-37  person_image_tag: `return "" if person.nil? || person.profile.nil?`
  activerecord singular_association.rb find_target?: `!owner.new_record?` gates the association load
  concolic_targets.rb finder_mock: `not_found == true` -> nil (no rep, no attribute decisions)
"""

from __future__ import annotations

import re
from collections import defaultdict

from concolic_engine.assumptions import (AssumptionSet, IndependenceAssumption,
                                         SymbolicConstraintAssumption,
                                         OneSideUntrackedPathAssumption)

_VARIANTS = ("html_plain", "html_withcid", "json_plain", "json_withcid", "mobile_plain", "mobile_withcid", "js_plain", "js_withcid", "xml_plain", "xml_withcid")  # C-8: ten variants (js/xml added, adversary round 3)

# ---------------------------------------------------------------------------
# TIER 1 gate table: expr-regex -> (closing polarity, description, source)
# ---------------------------------------------------------------------------
GATE_TABLE = [
    (r"_FinderMethods_first_1_not_found == True\)$", True,
     "A: the action's @conversation lookup not found",
     "conversations_controller.rb:14-23 (`if @conversation` is skipped: no first_unread_message / set_read) "
     "+ index.haml:25-27 (`- if @conversation` right column not rendered) + _conversation.haml:8 "
     "(`@conversation.try(:id)` nil -> conversation_class's id compare short-circuits)"),
    (r"_FinderMethods_first_2_not_found == True\)$", True,
     "B: first_unread_message's unread visibility not found",
     "conversation.rb:32-33 (`if visibility = ...first` -> `self.messages.to_a[-visibility.unread]` skipped)"),
    (r"_Calculations_count_1_count > 0\)$", False,
     "K: sidebar empty (@visibilities.count > 0 is False)",
     "index.haml:15-16 (`- if @visibilities.count > 0` -> `render partial: 'conversations/conversation', "
     "collection: @visibilities` not rendered: no visibility row, no .conversation lookup, no sidebar "
     "messages/participants/last_author reads)"),
    (r"_Relation_convidx_conv_lookup_1_not_found == True\)$", True,
     "CONVIDX: visibility.conversation not found",
     "_conversation.haml:5-6 (`conversation = visibility.conversation`; `conversation_path(conversation)` "
     "is the first use — nil there raises before any later read of `conversation.*` in the partial)"),
    (r"_FinderMethods_find_by_1_not_found == True\)$", True,
     "set_read's visibility find_by not found",
     "conversation.rb:39 (`return unless visibility` -> no unread write / save)"),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_ActiveRecord__Relation_records_\d+_rows\)? > 0\)$", False,
     "messages empty (messages.size > 0 False)",
     "conversation.rb:53 (`return unless ... messages.size > 0` -> no pluck, no last_author "
     "Person.includes(:profile).find_by, no last_author.name)"),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_ActiveRecord__Relation_records_\d+_rows\)? != 0\)$", False,
     "messages empty (messages.present? False)",
     "_conversation.haml:33-35 (`- if conversation.messages.present?` -> `messages.last.message` skipped)"),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_ActiveRecord__Relation_to_a_\d+_rows\)? != 0\)$", False,
     "messages empty (messages.present? False)",
     "_conversation.haml:33-35 / _messages.haml collection render (empty collection: no per-message author reads)"),
    (r"_find_by_\d+_not_found == True\)$", True,
     "last_author's Person.includes(:profile).find_by not found",
     "concolic_targets.rb finder_mock (not_found -> nil: no rep, so no `_persisted`/attribute decision of that "
     "rep exists) + conversation.rb:56 `last_author.present?` False"),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_\d+_rows\)? > 0\)$", None,
     "the principal follows at least one tag (mobile drawer)",
     "_drawer.mobile.haml:28 `current_user.followed_tags.length > 0` on the loaded has_many-through proxy (C-13: "
     "answered from the loaded target, no second read); rendering-only — the `all followed tags` link."),
    (r"_devise_user_first_\d+_prev_login_first == True\)$", None,
     "the principal's previous login was its FIRST (last_sign_in_at == current_sign_in_at)",
     "trackable.rb `self.last_sign_in_at = old_current || new_current`: after a first-ever login both timestamps "
     "coincide, so the next login's `last_sign_in_at :=` old current is a no-op write and the column drops out of the "
     "SET list (measured on the real second cookie login). Read only on the cookie path (lazy mint)."),
    # trackable's C-5 change checks on the principal (cookie login, C-14)
    (r"_devise_user_first_\d+_current_sign_in_ip == StringVal\('[^']*'\)\)$", None,
     "the previous sign-in came from this request's IP (trackable: last_sign_in_ip unchanged iff so)",
     "devise/models/trackable.rb update_tracked_fields -> the C-5 dirty writer compares the new current_sign_in_ip "
     "with the stored one: equal -> last_sign_in_ip/current_sign_in_ip drop out of the SET list on a later login; "
     "first login in this model: they are written."),
    (r"_devise_user_first_\d+_last_sign_in_ip == SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_\d+_current_sign_in_ip\)$", None,
     "last_sign_in_ip already equals current_sign_in_ip (trackable's `last := old current` is a no-op write)",
     "trackable.rb `self.last_sign_in_ip = old_current || new_current` through the C-5 writer."),
    (r"_devise_user_first_\d+_sign_in_count == \(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_\d+_sign_in_count \+ 1\)\)$", None,
     "sign_in_count changed by trackable's increment (the C-5 change check; constant-false by construction)",
     "trackable.rb `self.sign_in_count += 1` -> the writer compares old with old+1 (a ConcolicIntValue named `(X + 1)`): never equal, always dirty."),
    # ---- adversary round 6: cookie age, spoofed IP, out-of-range cid, deleted principal ----
    (r"^\(SYM_PARAM_cookie_expired == True\)$", True,
     "the remember cookie is older than remember_for (2 weeks)",
     "run_dse.rb SYM_PARAM_cookie_expired -> models/rememberable.rb remember_me?: `remember_for.ago < generated_at` false "
     "-> the strategy passes -> throw :warden 401 after ONE users read, no write. Closes the request."),
    (r"^\(SYM_PARAM_cookie_older == True\)$", True,
     "the remember cookie predates the record's remember_created_at (re-remembered elsewhere since)",
     "run_dse.rb SYM_PARAM_cookie_older -> remember_me?: `generated_at > remember_created_at` false -> 401 after one read."),
    (r"^\(SYM_PARAM_cookie_future == True\)$", None,
     "the remember cookie is dated in the future (clock skew between nodes)",
     "run_dse.rb SYM_PARAM_cookie_future -> remember_me? passes even for a NOT-remembered principal "
     "(`generated_at > (remember_created_at || Time.now)`), and the rememberable hook's `remember_me!` writes "
     "remember_created_at (`User#remember_me` true, user.rb:594) BEFORE trackable — a third principal write. "
     "Both arms continue into the action."),
    (r"^\(SYM_PARAM_ip_spoof == True\)$", True,
     "X-Forwarded-For and Client-IP disagree (ActionDispatch::RemoteIp ip_spoofing_check)",
     "run_dse.rb SYM_PARAM_ip_spoof -> the middleware's own GetIp#calculate_ip raises IpSpoofAttackError at the "
     "request's first remote_ip call: trackable's extract_ip_from, after the users read and before any write "
     "(cookie arm only; a session fetch never reads remote_ip). Closes the request (500)."),
    (r"^\(SYM_PARAM_cid_out_of_range == True\)$", True,
     "params[:conversation_id] is a scalar beyond the column's integer range",
     "run_dse.rb SYM_PARAM_cid_out_of_range (nested under not-array) -> conversations_controller.rb:11-16 -> "
     "ActiveModel::Type::Integer#ensure_in_range raises ActiveModel::RangeError while the finder's binds are built: "
     "users, people.owner_id and the conversations SELECT (its sql event fires first) then a 500. The app's column is "
     "a 4-byte MySQL int (2^31); this rig's SQLite type reports 8 bytes, so the runner uses a value past 2^63 to reach "
     "the same code line. Closes the request."),
    (r"_devise_user_first_\d+_not_found == True\)$", True,
     "the session/cookie names a principal that no longer exists",
     "targets.rb devise_user_first not-found arm -> serialize_from_session / serialize_from_cookie get nil -> "
     "Devise fails the request: 401 after one users read, no write. Closes the request."),
    # ---- adversary round 5: the boundary's AUTHENTICATION sibling (C-14) and the cid domain (C-15) ----
    (r"^\(SYM_PARAM_via_cookie == True\)$", None,
     "the principal arrives by a remember-me COOKIE (authentication event), not a session (fetch)",
     "run_dse.rb SYM_PARAM_via_cookie -> Devise::Strategies::Rememberable validates the signed remember_user_token "
     "(reading remember_created_at: the `_remembered` decision) -> set_user(event: :authentication) -> the "
     "`except: :fetch` hooks run: trackable's UPDATE users SET sign_in_count, current_sign_in_at, last_sign_in_at, "
     "current_sign_in_ip, last_sign_in_ip, updated_at BEFORE lastseenable's. A cookie the record does not remember "
     "fails the chain -> throw :warden 401. Both arms otherwise continue into the action."),
    (r"^\(SYM_PARAM_cid_array_empty == True\)$", True,
     "params[:conversation_id] is an EMPTY array (`?conversation_id[]`)",
     "run_dse.rb SYM_PARAM_cid_array_empty (nested under cid_is_array): the guard is a truthiness check so the "
     "lookup is ENTERED and AR renders where(conversation_id: []) as `AND 1=0`; `.first` is nil -> the not-found "
     "arm: every decision on the selected conversation is foreclosed."),
    # ---- adversary round 4: the AUTHENTICATION BOUNDARY (real Warden, C-10/C-11) ----
    (r"_devise_user_first_\d+_last_seen_stale == True\)$", None,
     "the principal's users.last_seen is NULL or > 5 minutes old (devise_lastseenable)",
     "targets.rb devise_user_first -> real Warden after_set_user -> devise_lastseenable stamp!: "
     "`update_attribute(:last_seen, now) if last_seen.to_i < (now - 5.minutes).to_i` -> the C-5 dirty "
     "tracker DERIVES `UPDATE users SET last_seen, updated_at` (stale) or nothing (fresh). Both arms continue "
     "into the action; no other decision is foreclosed by either."),
    (r"_devise_user_first_\d+_locked == True\)$", True,
     "the principal is LOCKED (users.locked_at set; lock/unlock strategy :none)",
     "Devise activatable hook: active_for_authentication? false -> warden.logout -> before_logout -> "
     "forget_me! (its write derived from `_remembered`) -> throw :warden 401. The action, set_locale, "
     "people.owner_id and everything after the boundary never run: TRUE closes the whole request."),
    (r"_devise_user_first_\d+_remembered == True\)$", None,
     "the principal's users.remember_created_at is set",
     "minted LAZILY where it is read (R5-NM-1): `forget_me!` on the locked arm, and `remember_me?` on the "
     "remember-cookie login (C-14: a nil remember_created_at fails the cookie -> 401). On the locked arm the C-5 dirty tracker derives an "
     "`UPDATE users SET remember_created_at, updated_at` iff it WAS set, else BEGIN/COMMIT with no write."),
    (r"CollectionProxy_records_\d+_row_name == ''\)$", None,
     "an aspect/tag display name is empty (mobile drawer link text)",
     "_drawer.mobile.haml:20/27 link_to aspect.name / tag_link: rendering-only; pinned in round 4 (pin ledger `name`)"),
    # ---- NM-5: the layout's own collections (html/mobile only) ----
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_\d+_rows\)? != 0\)$", False,
     "the signed-in user's services / aspects collection is EMPTY (layout, UserPresenter)",
     "run_dse.rb layout access (NM-5) -> UserPresenter#to_json: `ServicePresenter.as_collection(user.services)`, "
     "`user.services.map(&:provider)` (configured_services) and `user.aspects` are has_many CollectionProxies "
     "iterated by the site chrome; an EMPTY collection yields no per-row presenter reads. Free decisions: no "
     "schema constraint bounds a user's services or aspects count. Never on json (no layout)."),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_[A-Za-z0-9_]+_rows(_beyond)?\)? < \d+\)$", True,
     "the loaded page holds FEWER rows than per_page (a partial last page)",
     "will_paginate-3.3.0 active_record.rb:68-78 total_entries: `loaded? and size < limit_value` -> "
     "`offset_value + size`, NO COUNT statement; a full page falls through to `count` (the COUNT). "
     "Reached from index.haml:21 `will_paginate @visibilities` once ConvLoadedRelation says loaded?. "
     "Under the declared length domain 0/1/many (hi=2 < 15) only the TRUE arm is satisfiable. "
     "`_rows_beyond` is the BeyondPageList (page beyond the last, cycle-4 NM-2): its 0 rows make the compare "
     "TRUE too, but will_paginate's `(current_page == 1 or size > 0)` is then FALSE, so it falls through to "
     "`count` — the real COUNT is still issued on a beyond page."),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_[A-Za-z0-9_]+_rows_beyond\)? > 0\)$", True,
     "will_paginate's second conjunct on a beyond-last-page list: are there rows on this page",
     "will_paginate-3.3.0 active_record.rb:70 `(current_page == 1 or size > 0)`, recorded by "
     "ConvPaginatedTotal on the BeyondPageList (page > 1). Its 0 rows make it FALSE, so the loaded "
     "shortcut is NOT taken and `count` runs — the real COUNT on a beyond page (cycle-4 NM-2). "
     "TRUE would close the COUNT; unreachable for a beyond list, so single-polarity by construction."),
    # ---- adversary round 3 wins (C-5 / C-6 / C-7) ----
    (r"^\(SYM_PARAM_page_invalid == True\)$", True,
     "params[:page] is not a valid page number (W3/C-7)",
     "run_dse.rb SYM_PARAM_page_invalid -> will_paginate PageNumber `Integer(value)` raises "
     "WillPaginate::InvalidPage INSIDE conversations_controller.rb:11, after the Devise users read and "
     "current_user.person_id's people.owner_id read and before any visibilities read: the request "
     "terminates on the measured 2-statement multiset {users, people.owner_id}"),
    (r"^\(SYM_PARAM_cid_is_array == True\)$", True,
     "params[:conversation_id] arrived as an Array (W2/C-6)",
     "run_dse.rb SYM_PARAM_cid_is_array -> conversations_controller.rb:14-18 puts the value straight into "
     "where(conversation_visibilities: {conversation_id: ...}), which AR renders as `conversation_id IN (?, ?)` "
     "instead of `= ?`; `resources :conversations` makes conversation_id a plain QUERY parameter"),
    (r"_find_by_\d+_unread == 0\)$", True,
     "the visibility row's unread is already 0, so set_read's write changes nothing (W1/C-5)",
     "targets.rb write_attribute: ActiveModel::Dirty marks an attribute dirty only when the value CHANGES, so "
     "conversation.rb:41 visibility.save issues NO UPDATE for an unchanged record (Rails partial writes; the "
     "timestamp callback does not fire) - the belongs_to presence validation SELECT and the transaction remain"),
    (r"^\(SYM_PARAM_page_beyond == True\)$", True,
     "page beyond the last page (params[:page])",
     "run_dse.rb SYM_PARAM_page_beyond -> targets.rb rows_list: the paginated visibilities list is EMPTY "
     "(index.haml:16 renders no row: no .conversation lookup, no sidebar messages/participants/last_author reads)"),
    (r"_text_has_dlink == True\)$", False,
     "message text carries no diaspora:// link",
     "targets.rb text shim -> message_renderer.rb:100-105 diaspora_links: DIASPORA_URL_REGEX never matches, "
     "no `== \"post\"` compare, no Post.exists?"),
    (r"_text_dlink_is_post == True\)$", False,
     "diaspora link entity is not 'post'",
     "message_renderer.rb:103 `Regexp.last_match(2) == \"post\"` False short-circuits: no Post.exists?(guid:)"),
    (r"_empty == True\)$", None, "contacts.mutual.empty? existence probe result (no_contacts)",
     "conversations_controller.rb:29 -> index.haml:33 `- if no_contacts` (renders the new-conversation form or the no-contacts well; display only)"),
    (r"_(any|none) == True\)$", None, "existence probe result", "Relation#any?/none? (display only)"),
    (r"_exists == True\)$", None, "Post.exists?(guid:) existence probe result",
     "message_renderer.rb:103 (`AppConfig.url_to` rewrite vs the raw match; display only)"),
    (r"_index_in_range == True\)$", False,
     "first-unread index beyond the messages list (unread > messages)",
     "conversation.rb:34 `messages.to_a[-unread]` -> nil -> `@first_unread_message_id` nil (no further read)"),
    (r"\(\(- SYM_RESULT_ActiveRecord__FinderMethods_first_2_unread\) == -1\)$", None,
     "first-unread index is the last message (unread == 1)", "conversation.rb:34 (SampledList#[] index -1)"),
    # (a beyond-the-last-page list no longer records an emptiness PC at all —
    #  targets.rb BeyondPageList, 2026-08-28: its emptiness is a CONSEQUENCE of
    #  SYM_PARAM_page_beyond, and one fact may only carry one decision.)
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_ActiveRecord__Calculations_pluck_\d+_plucked\)? != 0\)$", None,
     "pluck result list emptiness (contacts_data rows / last_author author ids)",
     "conversations_controller.rb:116 `.map {|contact_id, *name_attrs| …}` over the pluck (gon display) / "
     "conversation.rb:56 `pluck(:author_id).last`"),
    (r"_Calculations_count_\d+_count != 0\)$", None,
     "count-linked list emptiness (a materialization whose length IS the query's count)",
     "targets.rb SampledList.linked_to_count: iteration/`present?` over the rows the count counted (participants loop, mobile messages pluck)"),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_ActiveRecord__Relation_to_ary_\d+_rows\)? != 0\)$", False,
     "participants list empty (other_participants)",
     "_conversation.haml:11-16 `other_participants = conversation.ordered_participants - "
     "[current_user.person]` then `- if other_participants.first.present?` (no person_image_tag, "
     "no `other_participants.count > 1` badge, no drop(1).take(15) loop). Recorded by the to_ary "
     "mock's length decision (cycle 4, hardening_lint H4/D2: a ::Array's first/present? are "
     "concrete, so the emptiness carried no PC before)."),
    (r"_profile_not_found == True\)$", True,
     "has_one :profile not found (person without a profile row)",
     "singular_association find_target (batch redeclaration): nil profile -> people_helper.rb:37/43 "
     "`person.profile.nil?` returns '' (no image_url/name compares for that rep); Person#name -> "
     "fix_profile -> Discovery wall -> reload -> profile pinned found"),
    (r"_subject == ''\)$", None, "conversation subject blank",
     "conversation.rb:64 `self[:subject].blank? ? I18n.t(...) : self[:subject]` (display only)"),
    (r"_Calculations_count_\d+_count > 2\)$", None, "participants.size > 2 (mobile participant_count badge)",
     "_conversation.mobile.haml:20"),
    (r"_Calculations_count_\d+_count > 0\)$", False,
     "messages count is 0 (mobile: unloaded messages.size > 0 False)",
     "conversation.rb:53 last_author `return unless ... messages.size > 0` (no pluck, no Person.includes(:profile).find_by)"),
    (r"^\((len\(|SYM_LEN_)SYM_RESULT_[A-Za-z0-9_]+\)? > 1\)$", False,
     "B-7: the materialized list holds at most ONE row (cardinality 0/1/many)",
     "_conversation.haml:13-16 `- if other_participants.count > 1` (the "
     "`.participants` block, the `drop(1).take(15)` person_image_tag loop and the "
     "`count - 1` badge) and the preload predicate's IN-list form are recorded only "
     "on the MANY side; with one row the app takes the single-participant path and "
     "the preload renders `= $(...)`."),
    (r"^\(SYM_PARAM_user_available == True\)$", False,
     "T-f/M-5 (fallback name): the SAME set_locale availability decision, minted under its "
     "fallback name on the fetch's not-found arm (post-auth scope, A7-1)",
     "run_dse.rb `av_name = \"#{lang_var || 'SYM_PARAM_user'}_available\"`: when devise_user_first's "
     "not_found arm returns no rep, the principal has no language sym var to name the decision "
     "from, so the runner's fallback name carries it. Same closing polarity as "
     "_language_available (False raises I18n::InvalidLocale before the action). The "
     "auth-inclusive corpus never contained this name because a not-found principal threw "
     "WardenThrow401 before set_locale; post-auth (A7-0) the arm reaches the language check."),
    (r"_language_available == True\)$", False,
     "T-f/M-5: users.language is not an available locale (set_locale raises I18n::InvalidLocale)",
     "application_controller.rb:100-107 `I18n.locale = current_user.language` -> "
     "I18n enforce_available_locales! raises BEFORE the action body: the request issues ONLY the "
     "Devise users lookup and 500s, so EVERY decision of this endpoint (the visibilities join, the "
     "conversations finder, every row rep) is recorded only on the open (True) side. run_dse.rb "
     "mints the decision before `ctrl.send(:index)`; its False arm is the recorded terminal."),
    (r"_persisted == True\)$", False,
     "rep unpersisted (new_record? true)",
     "activerecord singular_association.rb find_target? (`!owner.new_record?` False -> the profile/person "
     "association is NOT loaded -> people_helper.rb:37 `person.profile.nil?` returns '' early: no "
     "guid/id compares of the person_link helpers for that rep)"),
    (r"_text_has_mention == True\)$", True,
     "message text carries a mention",
     "targets.rb text shim (seeded content) -> message_renderer.rb make_mentions_plain_text formats the "
     "mention with an EMPTY mentioned_people list (no people lookup either way)"),
    (r"_guid == ''\)$", None, "guid blank", "people_helper.rb person_link_class / remote_or_hovercard (guid.blank?)"),
    (r"_guid != StringVal\(''\)\)$", None, "guid present", "people_helper.rb (guid present?)"),
    (r"_unread > 0\)$", None, "visibility unread badge", "_conversation.haml:23 / conversations_helper.rb:5"),
    # INSTR-6 (adversary round 3): a SYM_RESULT ordinal names CALL ORDER, not a
    # call SITE. This was pinned to `count_3`; after A3-9(c) removed
    # will_paginate's second COUNT on partial pages the participants count
    # became `count_2` and the entry silently stopped matching. The FACT is
    # `_show.haml:7` `other_participants.count > 1`, the only `> 1` compare on a
    # COUNT var on this endpoint (verified: count_2's note is the people JOIN
    # conversation_visibilities COUNT), so the ordinal is not part of it.
    (r"_Calculations_count_\d+_count > 1\)$", None, "participants.count > 1", "_show.haml:7"),
    (r"== SYM_RESULT_ActiveRecord__FinderMethods_first_1_id\)$", None, "conversation selected compare", "conversations_helper.rb:6"),
    (r"_row_id == SYM_RESULT_ActiveRecord__Relation_records_\d+_row_author_id\)$", None,
     "ordered_participants uniq identity", "conversation.rb:61 `(messages.map(&:author).reverse + participants).uniq`"),
    # B-7 made the MANY side of the participants list reachable, so Array#uniq /
    # Array#- now compare the pair in the MIRRORED operand order as well (the
    # message author as receiver, the participant row as argument). Same app
    # compare, same source line: `uniq` walks the concatenation in both
    # directions once there is more than one row.
    (r"_row_author_id == SYM_RESULT_ActiveRecord__Relation_to_ary_\d+_row_id\)$", None,
     "ordered_participants uniq identity (mirrored operand order)",
     "conversation.rb:61 `(messages.map(&:author).reverse + participants).uniq` / "
     "_conversation.haml:11 `- [current_user.person]`"),
    (r"_row_author_id == SYM_RESULT_ActiveRecord__Relation_records_\d+_row_id\)$", None,
     "ordered_participants uniq identity (mirrored operand order)", "conversation.rb:61 uniq"),
    (r"_row_author_id == SYM_RESULT_ActiveRecord__Relation_to_a_\d+_row_id\)$", None,
     "ordered_participants uniq identity (mirrored operand order)", "conversation.rb:61 uniq"),
    (r"_row_id == SYM_RESULT_ActiveRecord__Relation_to_ary_\d+_row_id\)$", None,
     "participants uniq self/other identity", "conversation.rb:61 uniq"),
    (r"_devise_user_first_1_person_id == SYM_RESULT_ActiveRecord__Relation_records_\d+_row_author_id\)$", None,
     "ordered_participants uniq/self identity vs current person",
     "conversation.rb:61 uniq + _conversation.haml:11 `- [current_user.person]` (message author vs current person)"),
    (r"_devise_user_first_1_person_id == SYM_RESULT_ActiveRecord__Relation_to_a_\d+_row_author_id\)$", None,
     "self identity vs current person", "_conversation.haml person_link_class own-profile check"),
    (r"_person_id == SYM_RESULT_ActiveRecord__Relation_to_ary_\d+_row_id\)$", None,
     "other_participants minus current person", "_conversation.haml:11 `- [current_user.person]`"),
    (r"_author_id == SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id\)$", None,
     "message author is current person", "people_helper.rb person_link_class (own-profile class)"),
    (r"_row_id == SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id\)$", None,
     "participant is current person", "people_helper.rb person_link_class (own-profile class)"),
    (r"\(\(- SYM_RESULT_ActiveRecord__FinderMethods_first_2_unread\) == 0\)$", None,
     "messages.to_a[-unread] index", "conversation.rb:33 (SymbolicList#[] index check)"),
    (r"_row_id == SYM_RESULT_ActiveRecord__Relation_to_a_\d+_row_id\)$", None,
     "self-identity (uniq on one rep)", "conversation.rb:61 uniq"),
]


def _gate_info(expr):
    for rx, closing, desc, src in GATE_TABLE:
        if re.search(rx, expr):
            return closing, desc, src
    return "UNKNOWN", None, None


def _variant_of(label):
    label = label or ""
    for v in _VARIANTS:
        if label.startswith(v):
            return v
    return "unknown"


# Owner-rep prefix of an expr's LEFT variable: the var name minus its
# attribute suffix. `len(X_rows)` -> X_rows; `(- X_unread)` -> X.
_ATTR_SUFFIXES = ("_prev_login_first", "_current_sign_in_ip", "_last_sign_in_ip", "_sign_in_count", "_last_seen_stale", "_locked", "_remembered", "_username", "_name", "_language_available", "_not_found", "_persisted", "_text_has_mention", "_text_has_dlink", "_text_dlink_is_post",
                  "_text_dlink_guid", "_exists", "_empty", "_any", "_none", "_index_in_range", "_unread", "_guid", "_subject",
                  "_author_id", "_person_id", "_count", "_id", "_rows_beyond", "_rows", "_plucked")


def _strip_suffix(var):
    for suf in _ATTR_SUFFIXES:
        if var.endswith(suf):
            return var[: -len(suf)]
    return var


def _is_principal(var):
    return "person_id" in var or "devise_user_first" in var


def _rep_key(expr):
    s = expr.strip()
    # var-vs-var compare (`(A == B)`): the decision belongs to the NON-principal
    # rep — the principal (devise session person) is a shared comparand, not the
    # subject. Two "is <rep> the current user?" compares on DIFFERENT reps are
    # DIFFERENT reps (disjoint), even though both name the principal operand.
    # A5-9: a VAR-vs-VAR compare has a VARIABLE on both sides. `(X == True)` also
    # matches `\w+ == \w+`, and with X the principal the branch picked the
    # right operand — keying every boolean decision on the principal
    # (`_locked`, `_last_seen_stale`, `_prev_login_first`, …) as the rep "True",
    # disjoint from the principal's other compares. Tier 2 then declared
    # `prev_login_first || current_sign_in_ip == '0.0.0.0'` independent, and the
    # engine's probe refuted it (the two jointly decide trackable's SET list).
    mvv = re.match(r"^\((SYM_[A-Za-z0-9_]*) (?:==|!=) (SYM_[A-Za-z0-9_]*)\)$", s)
    if mvv:
        l, r = mvv.group(1), mvv.group(2)
        cand = r if _is_principal(l) and not _is_principal(r) else (
               l if _is_principal(r) and not _is_principal(l) else l)
        return _strip_suffix(cand)
    m = re.match(r"^\(\(- ([A-Za-z_][A-Za-z0-9_]*)\)", s) or \
        re.match(r"^\(len\(([A-Za-z_][A-Za-z0-9_]*)\)", s) or \
        re.match(r"^\(SYM_LEN_([A-Za-z_][A-Za-z0-9_]*)", s) or \
        re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*)", s)
    var = m.group(1) if m else s
    return _strip_suffix(var)


def _tier0_variant_exclusivity(runs):
    expr_variants = {}
    for r in runs:
        v = _variant_of(r.label)
        for pc in r.path_conditions:
            expr_variants.setdefault(pc.expr, set()).add(v)
    by_set = {}
    for e, s in expr_variants.items():
        by_set.setdefault(frozenset(s), []).append(e)
    groups = sorted(by_set.items(), key=lambda kv: sorted(kv[0]))
    out = []
    for i, (set_a, exprs_a) in enumerate(groups):
        for set_b, exprs_b in groups[i + 1:]:
            if set_a & set_b:
                continue
            for a in exprs_a:
                for b in exprs_b:
                    out.append(IndependenceAssumption(
                        expr_a=a, expr_b=b,
                        description=f"variant exclusivity: {sorted(set_a)} vs {sorted(set_b)}",
                        agent_notes=(
                            "run_dse.rb's request variants fix format (html/json) and conversation_id "
                            "presence for a run's whole duration (conversations_controller.rb:13, "
                            "`respond_with do |format|`); expr_a is observed only under "
                            f"{sorted(set_a)}, expr_b only under {sorted(set_b)} — disjoint, so no single "
                            "run's path can contain both."),
                    ))
    return out


def _observations(runs):
    """expr -> {polarity -> set(run idx)}; and per run the recorded exprs."""
    pol_runs = defaultdict(lambda: defaultdict(set))
    run_exprs = []
    for i, r in enumerate(runs):
        seen = set()
        for pc in r.path_conditions:
            pol_runs[pc.expr][bool(pc.taken)].add(i)
            seen.add(pc.expr)
        run_exprs.append(seen)
    return pol_runs, run_exprs


def _tier1_gates(runs, pol_runs, run_exprs):
    """For every gate expr G with a documented closing polarity v: family =
    exprs Y never recorded in any run where G was recorded with polarity v
    but recorded in some run where G had polarity !v."""
    out = []
    declared = set()
    for g, pols in pol_runs.items():
        closing, desc, src = _gate_info(g)
        if closing == "UNKNOWN":
            raise RuntimeError(f"undocumented PC expr (add it to GATE_TABLE): {g}")
        if True not in pols or False not in pols:
            continue  # single-polarity expr: nothing to foreclose against
        for p in (True, False):
            closed_runs, open_runs = pols[p], pols[not p]
            exprs_when_closed = set().union(*(run_exprs[i] for i in closed_runs))
            exprs_when_open = set().union(*(run_exprs[i] for i in open_runs))
            for y in sorted(exprs_when_open - exprs_when_closed):
                if y == g or frozenset((g, y)) in declared:
                    continue
                declared.add(frozenset((g, y)))
                if closing is not None and p == closing:
                    why = (f"GATE {g} = {p} closes: {src}. {y} is recorded only on the open side "
                           f"(observed in {len(open_runs)} open-side runs, in none of the "
                           f"{len(closed_runs)} closed-side runs).")
                else:
                    # ORDINAL-ALIAS family: the expr named y is minted by a call
                    # site whose per-(class,method) ordinal only carries that
                    # name on the other side of g (the runtime's shared
                    # records/to_a/find_by counters shift when a gate skips a
                    # call) — the var behind y does not exist on this side.
                    why = (f"ORDINAL ALIAS: {y} names a variable minted only when {g} = {not p} "
                           f"(shared SYM_RESULT_<func>_<ordinal> counters, call_interceptor.rb:140: "
                           f"the call that mints it is skipped, or takes another ordinal, when {g} = {p}). "
                           f"Observed in {len(open_runs)} runs with {g} = {not p}, in none of the "
                           f"{len(closed_runs)} runs with {g} = {p}. Site of {g}: {src}.")
                out.append(IndependenceAssumption(
                    expr_a=g, expr_b=y,
                    description=f"{desc} ({g} = {p}) forecloses {y}",
                    agent_notes=why,
                ))
    return out, declared


def _separate(pol_runs, pair, ra, rb, subset, depth=0):
    """Gate tree [(g, p), ...] such that, restricting to `subset`, the two
    exprs' runs are separated: at each node either one expr lies entirely
    on the g = p side and the other is absent there (done), or one lies
    entirely on that side and the other spans it (recurse into it), or —
    when both span both sides of g — the pair is separated on EACH side
    (recurse into both; the node is recorded as (g, "split")). None if no
    tree of depth <= 5 separates them."""
    if not ra or not rb:
        return []
    if depth >= 5:
        return None
    for g, pols in pol_runs.items():
        if g in pair:
            continue
        gt, gf = pols[True] & subset, pols[False] & subset
        if not gt or not gf:
            continue
        for p, side in ((True, gt), (False, gf)):
            if not (ra <= side or rb <= side):
                continue
            ra2, rb2 = ra & side, rb & side
            if not ra2 or not rb2:
                return [(g, p)]
            if (ra2, rb2) != (ra, rb):
                tail = _separate(pol_runs, pair, ra2, rb2, side, depth + 1)
                if tail is not None:
                    return [(g, p)] + tail
    # split: both exprs span both sides of g — separate on each side
    for g, pols in pol_runs.items():
        if g in pair:
            continue
        gt, gf = pols[True] & subset, pols[False] & subset
        if not gt or not gf:
            continue
        rat, rbt, raf, rbf = ra & gt, rb & gt, ra & gf, rb & gf
        if not ((rat or rbt) and (raf or rbf)):
            continue
        if (rat, rbt) == (ra, rb) or (raf, rbf) == (ra, rb):
            continue
        t1 = _separate(pol_runs, pair, rat, rbt, gt, depth + 1)
        if t1 is None:
            continue
        t2 = _separate(pol_runs, pair, raf, rbf, gf, depth + 1)
        if t2 is None:
            continue
        return [(g, "split")] + t1 + t2
    return None


def _tier1b_never_coevaluated(runs, pol_runs, run_exprs, already):
    """Pairs never recorded in one run that Tier 1 did not already pair
    through a documented gate. In EVERY variant where both occur, the pair
    must be SEPARATED by a gate G: within that variant's runs, all runs
    recording X have G = p and all runs recording Y have G = !p (an ordinal
    alias: two decisions that only exist on opposite sides of G, typically
    the same shared-counter name denoting different objects). A pair with
    no separating gate in some shared variant raises — it would be a
    coverage hole hidden as an assumption."""
    out = []
    exprs = sorted(pol_runs)
    runs_of = {e: pols[True] | pols[False] for e, pols in pol_runs.items()}
    variant_runs = defaultdict(set)
    for i, r in enumerate(runs):
        variant_runs[_variant_of(r.label)].add(i)
    for i, a in enumerate(exprs):
        for b in exprs[i + 1:]:
            if frozenset((a, b)) in already:
                continue
            if runs_of[a] & runs_of[b]:
                continue  # co-evaluated somewhere: Tier 2's business
            seps = []
            for v, vruns in variant_runs.items():
                ra, rb = runs_of[a] & vruns, runs_of[b] & vruns
                if not ra or not rb:
                    continue  # not a shared variant (Tier 0 covers it)
                chain = _separate(pol_runs, (a, b), ra, rb, vruns)
                if chain is None:
                    raise RuntimeError(f"never co-evaluated pair with no separating gate chain in {v}: {a} || {b}")
                seps.append((v, chain))
            if not seps:
                continue  # disjoint variant sets: Tier 0 already declared it
            already.add(frozenset((a, b)))
            why = "; ".join(
                f"in {v}: " + " and then, within that side, ".join(
                    (f"the pair is separated on each side of {g}" if p == "split" else
                     f"one of the two is recorded only with {g} = {p} and the other never there")
                    + f" (site of {g}: {_gate_info(g)[2]})" for g, p in chain)
                for v, chain in seps)
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description="separated by " + "/".join(
                    "+".join(_gate_info(g)[1] for g, _ in chain) for _, chain in seps),
                agent_notes=("Never co-evaluated: " + why + ". The two names are decisions of code "
                             "regions on opposite sides of that gate (shared-counter ordinal aliases, "
                             "call_interceptor.rb:140) — no single path can evaluate both."),
            ))
    return out


def _len_bounds(pol_runs):
    """Collection lengths are non-negative: `len(X) > 0` False and
    `len(X) != 0` True is Z3-satisfiable only with a negative length, a
    state SymbolicList (list.rb concrete_length) cannot take."""
    names = set()
    for e in pol_runs:
        for m in re.finditer(r"(?:len\(|SYM_LEN_)(SYM_RESULT_[A-Za-z0-9_]+_rows)\)?", e):
            names.add(m.group(1))
    return [SymbolicConstraintAssumption(
        z3_expr=f"SYM_LEN_{n} >= 0",
        description=f"collection length non-negative: {n}",
        agent_notes="src/ruby_runtime/list.rb: a SymbolicList's length is its concrete row count "
                    "(0 or 1 for a sampled list); `len(X) <= 0 AND len(X) != 0` is unrealizable.",
    ) for n in sorted(names)]


def _list_and_own_row(list_key, other_key):
    """True when list_key names a row LIST (…_N, from `len(…_N_rows)`) and
    other_key is a decision of that list's own row (…_N_row…)."""
    return other_key.startswith(list_key + "_row")


def _boundary_family(e):
    """Request-level decisions and the principal rep's decisions: the family
    that jointly determines the authentication boundary's statements.

    A6-13 (round 6, n1-n4 zero-closure diagnosis): membership follows
    `_rep_key`, not a substring test. A var-vs-var compare BELONGS TO ITS
    NON-PRINCIPAL REP (the A5-9 rule `_rep_key` itself documents): a content
    row's "is this row the current user?" compare (`person_id ==
    to_ary_1_row_id`, `person_id == records_1_row_author_id`, ...) names the
    principal as a shared comparand but decides that ROW's render shape, not
    the boundary's statements. The substring test swept those compares into
    the boundary family, the 21c withdrawal then made them pairwise-dependent
    with the whole boundary clique, and the checker demanded combinations
    that are transitively UNOBSERVABLE: `person==to_ary_row(T) AND
    person==records_author(T)` forces `to_ary_row==records_author` True, and
    under that identity the uniq dedup (targets.rb class-constant `hash`,
    conversation.rb:61 / _conversation.haml:11) removes the element whose
    compare would have recorded the second expr — ground truth 0/10,312
    gate-True runs evaluate it (mirror order: 0/1,179). Probes A6-12/A6-13
    (three single-root traces) all diverged at exactly that gate. With
    rep-key scoping the row compares return to tier-2 content pairs
    (request x content: declared, gate-tested — accepted scoping), and the
    principal's OWN compares (trackable columns, IP equality, StringVal
    gates) plus SYM_PARAM_* stay boundary."""
    if e.startswith("(SYM_PARAM_"):
        return True
    if "_FinderMethods_devise_user_first_" not in e:
        return False
    return _is_principal(_rep_key(e))


def _page_and_list(a, b):
    """a is a request-level PAGE decision; b is a decision on a list's count,
    length or rows (any ordinal — an ordinal names call order, INSTR-6)."""
    if not re.match(r"^\(SYM_PARAM_page_(beyond|invalid) == True\)$", a):
        return False
    return bool(re.search(r"Calculations_count_\d+_count|SYM_LEN_|len\(|Relation_to_a(ry)?_\d+_row|_rows_beyond", b))


def _tier2_disjoint_reps(pol_runs, already):
    out = []
    exprs = sorted(pol_runs)
    for i, a in enumerate(exprs):
        for b in exprs[i + 1:]:
            if frozenset((a, b)) in already:
                continue
            ka, kb = _rep_key(a), _rep_key(b)
            if ka == kb:
                continue  # same rep: stays dependent (small clique, covered in full)
            # WITHDRAWN (cycle 4, engine assumption gate: 3 FAIL): a list's
            # LENGTH decision vs a decision on that list's OWN row
            # (`len(X_rows) != 0` x `X_row_text_dlink_is_post`, ...) — the row
            # decision only matters when a row exists, and the COMBINATION is
            # where the row's query (Post.exists?) fires: a shape neither
            # single flip produces. The whole class (length x any decision of
            # the same list's row, nested reps included) stays dependent and
            # the coverage checker demands the combinations. Never re-declared.
            if _list_and_own_row(ka, kb) or _list_and_own_row(kb, ka):
                continue
            # WITHDRAWN (round 4, cycles 16-17, engine assumption gate: 1 FAIL,
            # twice): a REQUEST-LEVEL PAGE decision (`SYM_PARAM_page_beyond`,
            # `SYM_PARAM_page_invalid`) vs any decision on a LIST's count, length
            # or rows. The page decides WHICH rows the paginated relation holds
            # (its OFFSET); the count/length decides whether it is loaded at all;
            # the COMBINATION (beyond page x `count > 0` false) is where the
            # unloaded beyond-page relation is re-read by the `.js` exception
            # renderer (`take … LIMIT 15 OFFSET 15`) — a shape neither single flip
            # produces. Same class as the withdrawal above, one level up: the
            # whole class stays dependent and the coverage checker demands the
            # combinations (present in the corpus: the `_pb` replay dumps).
            if _page_and_list(a, b) or _page_and_list(b, a):
                continue
            # WITHDRAWN (round 6, cycle 21b, engine assumption gate: 2 FAIL) — the
            # A4-8 rule generalised: a REQUEST-LEVEL parameter decision
            # (`SYM_PARAM_*`: how the principal arrived, the cookie's age, the cid
            # domain's arms, the page domain's arms, a spoofed IP) is not a "rep".
            # Its arms TERMINATE the request (out-of-range cid after three
            # statements; an expired cookie after one) or change the ORDER of a
            # later write (cookie ∧ stale ⇒ `updated_at, last_seen`, C-16), so
            # "neither gates the other" is false by construction. The probe
            # refuted `cid_out_of_range || page_beyond` and
            # `via_cookie || last_seen_stale`. Request-level decisions are left
            # to tier 1 (documented closing polarities) and to the coverage
            # checker, which demands their combinations.
            # Scoped (cycle 21c): excluding EVERY pair with a request-level decision
            # merged the boundary decisions into the content cliques — the coverage
            # pass ran 60+ minutes enumerating 2^k combinations of cookie age ×
            # message text that no statement depends on. The dependence is the
            # BOUNDARY FAMILY's: request-level decisions (SYM_PARAM_*) and the
            # principal rep's decisions jointly fix the boundary's writes,
            # terminals and write ORDER (both refuted pairs are inside it). A
            # request-level decision vs a CONTENT row/list decision stays a tier-2
            # claim — the render's reads do not depend on how the principal
            # arrived — except the page-vs-list class withdrawn at A4-8 above.
            if _boundary_family(a) and _boundary_family(b):
                continue
            _, da, sa = _gate_info(a)
            _, db, sb = _gate_info(b)
            out.append(IndependenceAssumption(
                expr_a=a, expr_b=b,
                description=f"disjoint reps: {da} [{ka}] || {db} [{kb}]",
                agent_notes=(
                    f"Decisions on two different symbolic reps ({ka} vs {kb}). Site A: {sa}. Site B: {sb}. "
                    "Neither gates the other (both are co-evaluated in both polarities somewhere in the "
                    "corpus) and neither feeds the other's operands; every statement shape either can "
                    "produce is keyed on its own rep's id and is produced by that rep's decisions alone. "
                    "Disjointness claim — licensed by the engine's flip-both access-trace probe."),
            ))
    return out


def _formatter_guid_oneside(pol_runs):
    """Rails' journey formatter (action_dispatch/journey/formatter.rb:41)
    compares a route segment `!= ''` ONLY on the blank path, where it is
    necessarily False — the non-blank path is handled by an earlier branch
    and never reaches this compare (verified: seeding any rep's guid to a
    non-blank value makes the `!= StringVal('')` PC disappear entirely,
    leaving only blank?'s `== ''` False). So the True side of every
    `<rep>_guid != StringVal('')` is structurally unreachable — a framework
    constant, not an app decision. One-side-untracked, tracked side
    not_taken (the engine verifies: flip the guid non-blank and the expr is
    never recorded, so the taken side is unreachable by construction)."""
    out = []
    for e in sorted(pol_runs):
        if re.search(r"_guid != StringVal\(''\)\)$", e):
            if pol_runs[e].get(True):
                continue  # if the True side ever occurs, do NOT untrack it
            out.append(OneSideUntrackedPathAssumption(
                expr=e, tracked_side="not_taken",
                description=f"formatter guid-blank compare, True side unreachable: {e}",
                agent_notes="action_dispatch/journey/formatter.rb:41 reaches `segment != ''` only on "
                            "the blank-guid path (the non-blank path is handled earlier and skips this "
                            "compare) — the compare is then always False. Verified: seeding the rep's "
                            "guid non-blank removes this PC entirely. Rails-internal, not app policy."))
    return out


_COUNT_NE_RE = re.compile(r"^\((SYM_RESULT_[A-Za-z0-9_]*_Calculations_count_\d+_count) != 0\)$")


def _count_gate_oneside(runs, pol_runs):
    """`(X_count != 0)` whose FALSE side the app's own `X_count > 0` gate
    forecloses (cycle 5, 2026-08-28).

    `Conversation#last_author` (conversation.rb:55-56) is
    `return unless @last_author.present? || messages.size > 0` and only THEN
    `messages.pluck(:author_id).last`. `messages.size` on an unloaded relation
    is `count(:all)`, and the pluck of the SAME query is linked to that count
    (SampledList.linked_to_count — one fact, one variable), so `#last`'s
    emptiness check re-examines the very variable the app has already branched
    on ONE LINE ABOVE: reaching the compare at all requires `count > 0`, and
    its False side is unreachable by construction.

    This is DERIVED, never assumed: an expr qualifies only when (a) its False
    side is observed in NO run of the corpus and (b) in EVERY run that records
    it, `(<same var> > 0)` was recorded TRUE strictly earlier. The sibling
    family `(count_N != 0)` under `_show.haml:7`'s `participants.count > 1`
    does NOT qualify — that gate does not force non-emptiness and the corpus
    duly carries both polarities (11 691 / 951) — so it stays fully covered.

    The engine's derived test is the proof: seed the count to 0 and the PC is
    never recorded at all ("the other side is unreachable by construction").
    """
    out = []
    for e in sorted(pol_runs):
        m = _COUNT_NE_RE.match(e)
        if not m or pol_runs[e].get(False):
            continue
        gate = f"({m.group(1)} > 0)"
        seen = 0
        for r in runs:
            seq = [(pc.expr, bool(pc.taken)) for pc in r.path_conditions]
            here = [i for i, (x, _t) in enumerate(seq) if x == e]
            if not here:
                continue
            seen += 1
            g = [i for i, (x, t) in enumerate(seq) if x == gate and t]
            if not g or min(g) > min(here):
                seen = 0
                break
        if not seen:
            continue
        out.append(OneSideUntrackedPathAssumption(
            expr=e, tracked_side="taken",
            description=f"count-gated list emptiness, False side unreachable: {e}",
            agent_notes=(
                f"conversation.rb:55 `return unless ... messages.size > 0` records {gate} = True; "
                f"conversation.rb:56 `messages.pluck(:author_id).last` then reaches SampledList#last on a "
                f"list whose length IS that count (targets.rb SampledList.linked_to_count), so {e} is "
                f"evaluated only on paths where the same variable is already known positive. Derived from "
                f"the corpus: {seen} runs record it, every one of them with {gate} = True strictly earlier, "
                f"and the False side occurs in none. Verified by the engine's flip probe: seeding the count "
                f"to 0 removes the PC entirely.")))
    return out




_REM_EXPR = "(SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_remembered == True)"
_CF_EXPR = "(SYM_PARAM_cookie_future == True)"
_PRE_TERMINAL = ("SYM_PARAM_via_cookie", "SYM_PARAM_cookie_expired", "SYM_PARAM_cookie_older",
                 "SYM_PARAM_cookie_future", "SYM_PARAM_ip_spoof",
                 "_devise_user_first_1_not_found", "_last_seen_stale", "_locked",
                 "_devise_user_first_1_remembered")


def _auth_terminal_observability(runs):
    """A6-14 (round 6, n6/n7 zero-closure diagnosis): the cookie-auth 401
    terminal makes one two-variable cell jointly unobservable with ANY
    post-terminal decision.

    Mechanism (app + harness, both documented at the site): a cookie login on
    a NOT-remembered principal (`_remembered` False => `remember_created_at`
    nil) passes Devise rememberable's `remember_me?` ONLY through the
    future-dated-cookie arm — `generated_at > (remember_created_at ||
    Time.now)` (models/rememberable.rb:105-120; run_dse.rb R6-NM-1/NM-2
    comment). A fresh/plain cookie (`cookie_future` False) on that principal
    fails the strategy chain -> `throw :warden` -> WardenThrow401 BEFORE the
    action: every post-terminal decision (trackable's prev_login/IP compares,
    locale, page and cid arms, the person/profile reps, all content) is never
    evaluated. So no single run can record `remembered == False AND
    cookie_future == False` TOGETHER WITH any post-terminal expr — while each
    PAIR is co-observed (401 runs record both cookie arms and `remembered`
    False; the future arm gives full-content runs with `remembered` False;
    password/session runs give `cookie_future` absent) — a three-way
    evaluation-order foreclosure that pairwise independence cannot express.
    The engine's exemption tool for this is the SymbolicConstraintAssumption
    (coverage.py: "extra Z3 constraint - infeasible combos exempt").

    DERIVED FROM THE CORPUS, not asserted: emitted only when the runs show
    (a) both exprs observed, (b) at least one run observes each surviving
    cell (rem=F/cf=T, rem=T/cf=F, rem=T/cf=T) evaluating a post-terminal
    expr, and (c) ZERO runs observe the closed cell (rem=F AND cf=F) while
    evaluating any post-terminal expr. If a counter-example run ever appears,
    the constraint silently withdraws itself and the checker demands the
    combinations again. (2026-08-31 ground truth: cells among runs that
    evaluated `SYM_PARAM_page_beyond`: F/T 3,524 - T/F 3,280 - T/T 4,993 -
    F/F 0, over 30,410 dumps.)"""
    cells = {(False, False): 0, (False, True): 0, (True, False): 0, (True, True): 0}
    seen_any = 0
    for r in runs:
        rem = cf = None
        post = False
        for pc in r.path_conditions:
            e = pc.expr
            if e == _REM_EXPR:
                rem = bool(pc.taken) if rem is None else (rem or bool(pc.taken))
            elif e == _CF_EXPR:
                cf = bool(pc.taken) if cf is None else (cf or bool(pc.taken))
            elif not any(p in e for p in _PRE_TERMINAL):
                post = True
        if rem is None or cf is None or not post:
            continue
        seen_any += 1
        cells[(rem, cf)] += 1
    if not seen_any:
        return []
    if cells[(False, False)] or not (cells[(False, True)] and cells[(True, False)] and cells[(True, True)]):
        return []  # pattern not present (or refuted): declare nothing
    rem_var = "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_remembered"
    return [SymbolicConstraintAssumption(
        z3_expr=f"Or({rem_var}, SYM_PARAM_cookie_future)",
        description=("cookie-auth 401 terminal: remembered=False AND cookie_future=False "
                     "forecloses every post-terminal decision (observability exemption)"),
        agent_notes=(
            "Derived from the corpus at build time: among runs that evaluated BOTH "
            f"`remembered` and `cookie_future` and at least one post-terminal expr, the cells are "
            f"F/T {cells[(False, True)]}, T/F {cells[(True, False)]}, T/T {cells[(True, True)]}, "
            f"F/F {cells[(False, False)]} (must be 0 for this constraint to be emitted; a single "
            "counter-example withdraws it). Mechanism: models/rememberable.rb remember_me? "
            "`generated_at > (remember_created_at || Time.now)` - a not-remembered principal "
            "(remember_created_at nil) passes only with a future-dated cookie; otherwise "
            "`throw :warden` 401 before the action (run_dse.rb R6-NM-1/NM-2). Scope note: sound "
            "because every clique containing both vars also contains post-terminal exprs "
            "(the boundary family is pairwise dependent with prev_login/page/cid), so no demanded "
            "combination consists of pre-terminal exprs alone; the 401 runs' own auth-prefix "
            "coverage is carried by their recorded pairs, which the checker still sees.")
    )]


def build(runs=None) -> AssumptionSet:
    aset = AssumptionSet()
    if not runs:
        return aset
    for ia in _tier0_variant_exclusivity(runs):
        aset.add(ia)
    pol_runs, run_exprs = _observations(runs)
    t1, declared = _tier1_gates(runs, pol_runs, run_exprs)
    for ia in t1:
        aset.add(ia)
    for ia in _tier1b_never_coevaluated(runs, pol_runs, run_exprs, declared):
        aset.add(ia)
    for ia in _tier2_disjoint_reps(pol_runs, declared):
        aset.add(ia)
    # (len(X) >= 0 is a variable BOUND now — coverage_report.apply_len_bounds
    # sets low=0 on every SYM_LEN_* var — not a SymbolicConstraintAssumption.)
    for u in _formatter_guid_oneside(pol_runs):
        aset.add(u)
    for u in _count_gate_oneside(runs, pol_runs):
        aset.add(u)
    for c in _auth_terminal_observability(runs):
        aset.add(c)
    return aset
