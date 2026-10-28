-- aspect_memberships_destroy — SQL SELECT views rendered from the policy IR
--
-- 13 atoms in; 7 views out.
--   2 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   11 statements extracted, 7 distinct after the prune,
--   0 syntactically subsumed, 7 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   24 condition predicates did not resolve to a column; listed below.
--   Subsumption: SYNTACTIC ONLY (conjunct containment). The solver-backed
--   checker is not run from a render, so a statement it would have dropped
--   is still here: this over-reports the policy, never under-reports it.
--   no app config supplied: no schema, so a condition on a result field
--   cannot be confirmed to be a column and is reported rather than folded;
--   framework-default symbol conventions only
--
-- ==========================================================================
-- VIEWS
-- ==========================================================================

SELECT `aspects`.* FROM `aspects`, `aspect_memberships`, `contacts`, `aspect_memberships` AS `aspect_memberships0`, `users`, `aspects` AS `aspects0`, `aspect_memberships` AS `aspect_memberships1` WHERE `aspects`.`id` = `aspect_memberships`.`aspect_id` AND `users`.`id` = _MY_UID AND `contacts`.`user_id` = `users`.`id` AND `aspect_memberships`.`contact_id` = `contacts`.`id` AND `aspects0`.`user_id` = `users`.`id` AND `aspect_memberships`.`aspect_id` = `aspects0`.`id`;

SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts`, `aspect_memberships` AS `aspect_memberships0`, `users`, `aspects`, `aspect_memberships` AS `aspect_memberships1` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id` AND `aspect_memberships`.`aspect_id` = `aspects`.`id` AND `users`.`id` = _MY_UID AND `contacts`.`user_id` = `users`.`id` AND `aspects`.`user_id` = `users`.`id`;

SELECT `aspects`.* FROM `aspects` INNER JOIN `aspect_memberships` ON `aspect_memberships`.`aspect_id` = `aspects`.`id`, `users` WHERE `aspects`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `contacts`.* FROM `contacts` INNER JOIN `aspect_memberships` ON `aspect_memberships`.`contact_id` = `contacts`.`id`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 2 of 13 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- atom 7: access ActiveRecord::Base#destroy
--     terminates in DELETE, which is a write and not a select view
-- atom 12: access ActiveRecord::Base#destroy
--     terminates in DELETE, which is a write and not a select view

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 24 predicates
-- The IR keeps a path condition the renderer cannot resolve to a column;
-- this is where that loss is REPORTED rather than taken silently (DESIGN_IR §2).
-- ==========================================================================
-- atom 2: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 3: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 4: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 5: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 6: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 6: c4.not_found != true
--     no schema: `.not_found` on c4 cannot be confirmed to be a column of
--     `aspects`, so it is not folded
-- atom 6: c5.not_found != true
--     no schema: `.not_found` on c5 cannot be confirmed to be a column of
--     `contacts`, so it is not folded
-- atom 8: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 8: c4.not_found != true
--     no schema: `.not_found` on c4 cannot be confirmed to be a column of
--     `aspects`, so it is not folded
-- atom 8: c5.not_found != true
--     no schema: `.not_found` on c5 cannot be confirmed to be a column of
--     `contacts`, so it is not folded
-- atom 8: c8.not_found != true
--     no schema: `.not_found` on c8 cannot be confirmed to be a column of
--     `aspect_memberships`, so it is not folded
-- atom 9: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 9: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 10: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 10: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c2.not_found != true
--     no schema: `.not_found` on c2 cannot be confirmed to be a column of
--     `aspects`, so it is not folded
-- atom 11: c3.not_found != true
--     no schema: `.not_found` on c3 cannot be confirmed to be a column of
--     `contacts`, so it is not folded
-- atom 13: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 13: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 13: c2.not_found != true
--     no schema: `.not_found` on c2 cannot be confirmed to be a column of
--     `aspects`, so it is not folded
-- atom 13: c3.not_found != true
--     no schema: `.not_found` on c3 cannot be confirmed to be a column of
--     `contacts`, so it is not folded
-- atom 13: c6.not_found != true
--     no schema: `.not_found` on c6 cannot be confirmed to be a column of
--     `aspect_memberships`, so it is not folded
