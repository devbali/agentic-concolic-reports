-- streams_multi — SQL SELECT views rendered from the policy IR
--
-- 12 atoms in; 7 views out.
--   0 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   12 statements extracted, 7 distinct after the prune,
--   0 syntactically subsumed, 7 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   36 condition predicates did not resolve to a column; listed below.
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

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`invited_by_id`;

SELECT `invitation_codes`.* FROM `invitation_codes`, `users` WHERE `invitation_codes`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`invited_by_id` AND `users`.`id` = _MY_UID;

SELECT `users`.* FROM `users`, `users` AS `users0` WHERE `users`.`id` = `users0`.`invited_by_id` AND `users0`.`id` = _MY_UID;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 0 of 12 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- (none: every atom terminates in a SELECT)

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 36 predicates
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
-- atom 7: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 7: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
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
-- atom 10: c1.getting_started != true
--     no schema: `.getting_started` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 10: c1.invited_by_language != "pl"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 10: c1.invited_by_language != "xx"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 10: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 10: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 10: c6.first_name == ""
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 10: c6.last_name == ""
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 11: c1.getting_started != true
--     no schema: `.getting_started` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 11: c1.invited_by_language != "pl"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 11: c1.invited_by_language != "xx"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 11: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c6.first_name == ""
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 11: c6.last_name == ""
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 11: c8.not_found != true
--     c8 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 11: c8.token != ""
--     c8 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 12: c1.getting_started != true
--     no schema: `.getting_started` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 12: c1.invited_by_language != "pl"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 12: c1.invited_by_language != "xx"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 12: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 12: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 12: c6.first_name == ""
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 12: c6.last_name == ""
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 12: c8.not_found != true
--     c8 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 12: c8.token != ""
--     c8 is not joined into this statement, so the condition constrains
--     rows this view does not read
