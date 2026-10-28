# `reports/autolab/` — endpoint store index

The store is `reports/autolab/endpoints/<endpoint>/<provenance>/<run>/` with `policy/`, `traces/`, `evidence/`, `rendered.sql` and `stats.json` in each run. This file and `EXCEPTIONS.md` are the corpus-level rollup; `../README.md` is the map.

Generated 2026-10-07T18:08:38Z by `reports/autolab/tools/build_store.py`. Regenerated in full on every build; do not hand-edit.

- endpoints in the corpus: **161**
- endpoints with a finished artefact set: **161**
- runs finished: **164** (excluded 14 — see `EXCEPTIONS.json`)
- dump IR stored: **860** in both forms (rejected 0)
  - text equivalent to the JSON: **782**; text equivalent to `to_text_domain(JSON)`: **78** — see README, *Fidelity*
- policy IR stored: **164** in both forms, all round-tripping verbatim
- `rendered.sql` GENERATED from the stored policy at build time: **38** (and 126 fell back to the evidence store's copy because the render raised); of these **38** came out byte-identical to the evidence store's frozen copy and the rest did not — the copy had stopped matching the renderer
- endpoints whose dumps came from a cloud box: **2**
- policies produced BY a cloud agent: **0** — every policy here was built by a locally-run pipeline
- cloud attempts recorded: **80** across **68** endpoints, **6.8703** box hours — per endpoint in its `cloud.json`; an attempt is a box launched FOR an endpoint, NOT the provenance of its artefacts
- **certified-complete endpoints: 0**, and this cannot be anything else here; see README.

| endpoint | sources | runs | dumps | atoms | outcome |
|---|---|---|---|---|---|
| `active_storage_blobs_show` | local | 1 | 1 | 0 | UNDECIDED |
| `active_storage_direct_uploads_create` | local | 1 | 2 | 0 | UNDECIDED |
| `active_storage_disk_show` | local | 1 | 2 | 0 | UNDECIDED |
| `active_storage_disk_update` | local | 1 | 2 | 0 | UNDECIDED |
| `active_storage_representations_show` | local | 1 | 1 | 0 | UNDECIDED |
| `admin_pods_index` | local | 1 | 5 | 5 | UNDECIDED |
| `admin_pods_recheck` | local | 1 | 5 | 5 | UNDECIDED |
| `admin_users_close_account` | local | 1 | 9 | 21 | UNDECIDED |
| `admin_users_lock_account` | local | 1 | 9 | 11 | UNDECIDED |
| `admin_users_make_admin` | local | 1 | 3 | 3 | UNDECIDED |
| `admin_users_make_moderator` | local | 1 | 3 | 3 | UNDECIDED |
| `admin_users_make_spotlight` | local | 1 | 3 | 3 | UNDECIDED |
| `admin_users_remove_admin` | local | 1 | 3 | 3 | UNDECIDED |
| `admin_users_remove_moderator` | local | 1 | 3 | 3 | UNDECIDED |
| `admin_users_remove_spotlight` | local | 1 | 3 | 3 | UNDECIDED |
| `admin_users_unlock_account` | local | 1 | 9 | 7 | UNDECIDED |
| `admins_add_invites` | local | 1 | 5 | 5 | UNDECIDED |
| `admins_admin_inviter` | local | 1 | 9 | 5 | UNDECIDED |
| `admins_dashboard` | local | 1 | 3 | 3 | UNDECIDED |
| `admins_stats` | local | 1 | 3 | 9 | UNDECIDED |
| `admins_user_search` | local | 1 | 5 | 3 | UNDECIDED |
| `admins_weekly_user_stats` | local | 1 | 3 | 3 | UNDECIDED |
| `api_openid_connect_authorizations_create` | local | 1 | 1 | 0 | UNDECIDED |
| `api_openid_connect_authorizations_destroy` | local | 1 | 2 | 2 | UNDECIDED |
| `api_openid_connect_authorizations_new` | local | 1 | 5 | 5 | UNDECIDED |
| `api_openid_connect_clients_create` | local | 1 | 1 | 0 | UNDECIDED |
| `api_openid_connect_clients_find` | local | 1 | 2 | 1 | UNDECIDED |
| `api_openid_connect_discovery_configuration` | local | 1 | 1 | 0 | UNDECIDED |
| `api_openid_connect_id_tokens_jwks` | local | 1 | 1 | 0 | UNDECIDED |
| `api_openid_connect_token_endpoint_create` | local | 1 | 1 | 0 | UNDECIDED |
| `api_openid_connect_user_applications_index` | local | 1 | 3 | 3 | UNDECIDED |
| `api_openid_connect_user_info_show` | local | 1 | 3 | 3 | UNDECIDED |
| `aspect_memberships_create` | local | 1 | 23 | 56 | UNDECIDED |
| `aspect_memberships_destroy` | local | 1 | 11 | 13 | UNDECIDED |
| `aspects_create` | local | 1 | 5 | 3 | UNDECIDED |
| `aspects_destroy` | local | 1 | 7 | 13 | UNDECIDED |
| `aspects_show` | local | 1 | 5 | 5 | UNDECIDED |
| `aspects_toggle_chat_privilege` | local | 1 | 11 | 11 | UNDECIDED |
| `aspects_update` | local | 1 | 9 | 5 | UNDECIDED |
| `aspects_update_order` | local | 1 | 3 | 3 | UNDECIDED |
| `blocks_create` | local | 1 | 5 | 5 | UNDECIDED |
| `blocks_destroy` | local | 1 | 3 | 5 | UNDECIDED |
| `comments_create` | local | 1 | 12 | 16 | UNDECIDED |
| `comments_destroy` | local | 1 | 9 | 6 | UNDECIDED |
| `comments_index` | cloud+local | 3 | 23 | 2, 2, 38 | UNDECIDED |
| `comments_new` | local | 1 | 3 | 3 | UNDECIDED |
| `contacts_index` | local | 1 | 13 | 13 | UNDECIDED |
| `contacts_spotlight` | local | 1 | 3 | 3 | UNDECIDED |
| `conversation_visibilities_destroy` | local | 1 | 7 | 11 | UNDECIDED |
| `conversations_create` | local | 1 | 3 | 3 | UNDECIDED |
| `conversations_index` | local | 1 | 10 | 17 | UNDECIDED |
| `conversations_new` | local | 1 | 3 | 3 | UNDECIDED |
| `conversations_raw` | local | 1 | 10 | 18 | UNDECIDED |
| `conversations_show` | local | 1 | 10 | 18 | UNDECIDED |
| `devise_passwords_create` | local | 1 | 1 | 0 | UNDECIDED |
| `devise_passwords_edit` | local | 1 | 1 | 0 | UNDECIDED |
| `devise_passwords_new` | local | 1 | 1 | 0 | UNDECIDED |
| `devise_passwords_update` | local | 1 | 1 | 0 | UNDECIDED |
| `diaspora_federation_fetch_fetch` | local | 1 | 1 | 0 | UNDECIDED |
| `diaspora_federation_h_card_hcard` | local | 1 | 9 | 1 | UNDECIDED |
| `diaspora_federation_receive_private` | local | 1 | 4 | 2 | UNDECIDED |
| `diaspora_federation_receive_public` | local | 1 | 1 | 0 | UNDECIDED |
| `diaspora_federation_webfinger_host_meta` | local | 1 | 1 | 0 | UNDECIDED |
| `diaspora_federation_webfinger_webfinger` | local | 1 | 2 | 0 | UNDECIDED |
| `help_faq` | local | 1 | 1 | 0 | UNDECIDED |
| `home_force_mobile` | local | 1 | 1 | 0 | UNDECIDED |
| `home_podmin` | local | 1 | 1 | 0 | UNDECIDED |
| `home_show` | local | 1 | 1 | 1 | UNDECIDED |
| `home_toggle_mobile` | local | 1 | 1 | 0 | UNDECIDED |
| `invitation_codes_show` | local | 1 | 1 | 0 | UNDECIDED |
| `invitations_create` | local | 1 | 5 | 3 | UNDECIDED |
| `invitations_new` | local | 1 | 7 | 5 | UNDECIDED |
| `likes_create` | local | 1 | 12 | 16 | UNDECIDED |
| `likes_destroy` | local | 1 | 7 | 6 | UNDECIDED |
| `likes_index` | local | 1 | 10 | 8 | UNDECIDED |
| `links_resolve` | local | 1 | 1 | 0 | UNDECIDED |
| `manifest_show` | local | 1 | 1 | 0 | UNDECIDED |
| `messages_create` | local | 1 | 7 | 5 | UNDECIDED |
| `node_info_document` | local | 1 | 1 | 0 | UNDECIDED |
| `node_info_jrd` | local | 1 | 1 | 0 | UNDECIDED |
| `node_info_statistics` | local | 1 | 1 | 0 | UNDECIDED |
| `notifications_index` | local | 1 | 5 | 7 | UNDECIDED |
| `notifications_read_all` | local | 1 | 3 | 7 | UNDECIDED |
| `notifications_update` | local | 1 | 7 | 5 | UNDECIDED |
| `participations_create` | local | 1 | 9 | 10 | UNDECIDED |
| `participations_destroy` | local | 1 | 5 | 7 | UNDECIDED |
| `people_hovercard` | local | 1 | 3 | 3 | UNDECIDED |
| `people_index` | local | 1 | 3 | 3 | UNDECIDED |
| `people_refresh_search` | local | 1 | 3 | 3 | UNDECIDED |
| `people_retrieve_remote` | local | 1 | 3 | 3 | UNDECIDED |
| `people_show` | local | 1 | 3 | 3 | UNDECIDED |
| `people_stream` | local | 1 | 3 | 4 | UNDECIDED |
| `photos_create` | local | 1 | 5 | 3 | UNDECIDED |
| `photos_destroy` | local | 1 | 5 | 5 | UNDECIDED |
| `photos_index` | local | 1 | 16 | 41 | UNDECIDED |
| `photos_make_profile_photo` | local | 1 | 5 | 6 | UNDECIDED |
| `photos_show` | local | 1 | 10 | 13 | UNDECIDED |
| `poll_participations_create` | local | 1 | 9 | 12 | UNDECIDED |
| `posts_destroy` | cloud+local | 2 | 28 | 25, 25 | UNDECIDED |
| `posts_mentionable` | local | 1 | 15 | 12 | UNDECIDED |
| `posts_oembed` | local | 1 | 1 | 0 | UNDECIDED |
| `posts_show` | local | 1 | 17 | 45 | UNDECIDED |
| `profiles_edit` | local | 1 | 5 | 4 | UNDECIDED |
| `profiles_show` | local | 1 | 9 | 14 | UNDECIDED |
| `profiles_update` | local | 1 | 5 | 3 | UNDECIDED |
| `registrations_create` | local | 1 | 2 | 0 | UNDECIDED |
| `registrations_new` | local | 1 | 1 | 0 | UNDECIDED |
| `registrations_registrations_closed` | local | 1 | 1 | 0 | UNDECIDED |
| `report_create` | local | 1 | 5 | 3 | UNDECIDED |
| `report_destroy` | local | 1 | 7 | 7 | UNDECIDED |
| `report_index` | local | 1 | 3 | 3 | UNDECIDED |
| `report_update` | local | 1 | 5 | 7 | UNDECIDED |
| `reshares_create` | local | 1 | 17 | 49 | UNDECIDED |
| `reshares_index` | local | 1 | 10 | 8 | UNDECIDED |
| `search_search` | local | 1 | 3 | 3 | UNDECIDED |
| `services_create` | local | 1 | 3 | 3 | UNDECIDED |
| `services_destroy` | local | 1 | 5 | 7 | UNDECIDED |
| `services_failure` | local | 1 | 3 | 3 | UNDECIDED |
| `services_index` | local | 1 | 3 | 3 | UNDECIDED |
| `sessions_create` | local | 1 | 1 | 0 | UNDECIDED |
| `sessions_destroy` | local | 1 | 1 | 0 | UNDECIDED |
| `sessions_new` | local | 1 | 1 | 0 | UNDECIDED |
| `share_visibilities_update` | local | 1 | 12 | 38 | UNDECIDED |
| `social_relay_well_known` | local | 1 | 1 | 0 | UNDECIDED |
| `status_messages_bookmarklet` | local | 1 | 3 | 3 | UNDECIDED |
| `status_messages_create` | local | 1 | 7 | 3 | UNDECIDED |
| `status_messages_new` | local | 1 | 21 | 30 | UNDECIDED |
| `streams_activity` | local | 1 | 13 | 7 | UNDECIDED |
| `streams_aspects` | local | 1 | 13 | 7 | UNDECIDED |
| `streams_commented` | local | 1 | 13 | 7 | UNDECIDED |
| `streams_followed_tags` | local | 1 | 13 | 9 | UNDECIDED |
| `streams_liked` | local | 1 | 13 | 7 | UNDECIDED |
| `streams_mentioned` | local | 1 | 13 | 7 | UNDECIDED |
| `streams_multi` | local | 1 | 14 | 12 | UNDECIDED |
| `streams_public` | local | 1 | 1 | 0 | UNDECIDED |
| `tag_followings_create` | local | 1 | 3 | 3 | UNDECIDED |
| `tag_followings_destroy` | local | 1 | 5 | 7 | UNDECIDED |
| `tag_followings_index` | local | 1 | 3 | 5 | UNDECIDED |
| `tag_followings_manage` | local | 1 | 3 | 3 | UNDECIDED |
| `tags_index` | local | 1 | 2 | 0 | UNDECIDED |
| `tags_show` | local | 1 | 3 | 3 | UNDECIDED |
| `two_factor_authentications_confirm_2fa` | local | 1 | 5 | 3 | UNDECIDED |
| `two_factor_authentications_confirm_and_activate_2fa` | local | 1 | 3 | 3 | UNDECIDED |
| `two_factor_authentications_create` | local | 1 | 5 | 3 | UNDECIDED |
| `two_factor_authentications_destroy` | local | 1 | 3 | 3 | UNDECIDED |
| `two_factor_authentications_recovery_codes` | local | 1 | 3 | 5 | UNDECIDED |
| `two_factor_authentications_show` | local | 1 | 3 | 3 | UNDECIDED |
| `users_auth_token` | local | 1 | 3 | 3 | UNDECIDED |
| `users_confirm_email` | local | 1 | 3 | 3 | UNDECIDED |
| `users_destroy` | local | 1 | 3 | 3 | UNDECIDED |
| `users_download_photos` | local | 1 | 3 | 3 | UNDECIDED |
| `users_download_profile` | local | 1 | 3 | 3 | UNDECIDED |
| `users_edit` | local | 1 | 3 | 5 | UNDECIDED |
| `users_export_photos` | local | 1 | 3 | 5 | UNDECIDED |
| `users_export_profile` | local | 1 | 3 | 5 | UNDECIDED |
| `users_getting_started` | local | 1 | 14 | 9 | UNDECIDED |
| `users_getting_started_completed` | local | 1 | 3 | 5 | UNDECIDED |
| `users_privacy_settings` | local | 1 | 3 | 5 | UNDECIDED |
| `users_public` | local | 1 | 4 | 2 | UNDECIDED |
| `users_update` | local | 1 | 3 | 3 | UNDECIDED |
| `users_update_privacy_settings` | local | 1 | 3 | 3 | UNDECIDED |
