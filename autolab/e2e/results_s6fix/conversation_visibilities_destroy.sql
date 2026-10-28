-- conversation_visibilities_destroy — SQL SELECT views rendered from the policy IR
--
-- 11 atoms in; 6 views out.
--   2 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   9 statements extracted, 6 distinct after the prune,
--   0 syntactically subsumed, 6 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   17 condition predicates did not resolve to a column; listed below.
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

-- NOTE: flag aggregate-as-rows
SELECT `people`.`id`, `conversation_visibilities`.`id`, `conversation_visibilities0`.`id`, `people0`.`id`, `users`.`id` FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0`, `users` WHERE `conversation_visibilities`.`conversation_id` = `conversation_visibilities0`.`conversation_id` AND `users`.`id` = _MY_UID AND `people0`.`owner_id` = `users`.`id` AND `conversation_visibilities0`.`person_id` = `people0`.`id`;

SELECT `conversations`.* FROM `conversations`, `conversation_visibilities`, `people`, `users` WHERE `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id` AND `conversation_visibilities`.`person_id` = `people`.`id`;

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `people`, `users` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 2 of 11 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- atom 7: access ActiveRecord::Base#destroy
--     terminates in DELETE, which is a write and not a select view
-- atom 11: access ActiveRecord::Base#destroy
--     terminates in DELETE, which is a write and not a select view

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 17 predicates
-- The IR keeps a path condition the renderer cannot resolve to a column;
-- this is where that loss is REPORTED rather than taken silently (DESIGN_IR §2).
-- ==========================================================================
-- atom 2: c1.language == "pl"
--     not implied by every branch of a 2-branch condition
-- atom 2: c1.language != "pl"
--     not implied by every branch of a 2-branch condition
-- atom 2: c1.language != "xx"
--     not implied by every branch of a 2-branch condition
-- atom 3: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 4: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 5: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 5: c4.not_found != true
--     no schema: `.not_found` on c4 cannot be confirmed to be a column of
--     `conversation_visibilities`, so it is not folded
-- atom 6: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 6: c4.not_found != true
--     no schema: `.not_found` on c4 cannot be confirmed to be a column of
--     `conversation_visibilities`, so it is not folded
-- atom 8: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 8: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 9: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 9: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 9: c3.not_found != true
--     no schema: `.not_found` on c3 cannot be confirmed to be a column of
--     `conversation_visibilities`, so it is not folded
-- atom 10: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 10: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 10: c3.not_found != true
--     no schema: `.not_found` on c3 cannot be confirmed to be a column of
--     `conversation_visibilities`, so it is not folded
