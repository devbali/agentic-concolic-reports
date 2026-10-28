-- users_getting_started — SQL SELECT views rendered from the policy IR
--
-- 9 atoms in; 9 views out.
--   0 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   9 statements extracted, 9 distinct after the prune,
--   0 syntactically subsumed, 9 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   39 condition predicates did not resolve to a column; listed below.
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

SELECT `contacts`.* FROM `contacts`, `users`, `people` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`invited_by_id`;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`invited_by_id`;

SELECT `blocks`.* FROM `blocks`, `users` WHERE `blocks`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`invited_by_id` AND `users`.`id` = _MY_UID;

SELECT `users`.* FROM `users`, `users` AS `users0` WHERE `users`.`id` = `users0`.`invited_by_id` AND `users0`.`id` = _MY_UID;

SELECT `aspect_memberships`.* FROM `aspect_memberships` WHERE `aspect_memberships`.`contact_id` = ?;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 0 of 9 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- (none: every atom terminates in a SELECT)

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 39 predicates
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
--     not implied by every branch of a 2-branch condition
-- atom 3: c1.language != "pl"
--     not implied by every branch of a 2-branch condition
-- atom 3: c1.language != "xx"
--     not implied by every branch of a 2-branch condition
-- atom 4: c1.language == "pl"
--     not implied by every branch of a 2-branch condition
-- atom 4: c1.language != "pl"
--     not implied by every branch of a 2-branch condition
-- atom 4: c1.language != "xx"
--     not implied by every branch of a 2-branch condition
-- atom 5: c1.language == "pl"
--     not implied by every branch of a 2-branch condition
-- atom 5: c1.language != "pl"
--     not implied by every branch of a 2-branch condition
-- atom 5: c1.language != "xx"
--     not implied by every branch of a 2-branch condition
-- atom 6: c1.language == "pl"
--     not implied by every branch of a 2-branch condition
-- atom 6: c1.language != "pl"
--     not implied by every branch of a 2-branch condition
-- atom 6: c1.language != "xx"
--     not implied by every branch of a 2-branch condition
-- atom 7: c1.invited_by_language != "pl"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 7: c1.invited_by_language != "xx"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 7: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 7: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 7: c6.id != c2.id
--     no schema: `.id` on c6 cannot be confirmed to be a column of
--     `people`, so it is not folded
-- atom 7: c7.first_name == ""
--     c7 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 7: c7.last_name == ""
--     c7 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.invited_by_language != "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.invited_by_language != "xx"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.language != "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.language != "xx"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c6.id != c2.id
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c7.first_name == ""
--     c7 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c7.last_name == ""
--     c7 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c8.not_found != true
--     c8 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 9: c1.invited_by_language != "pl"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 9: c1.invited_by_language != "xx"
--     no schema: `.invited_by_language` on c1 cannot be confirmed to be a
--     column of `users`, so it is not folded
-- atom 9: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 9: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 9: c6.id != c2.id
--     c6 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 9: c7.first_name == ""
--     c7 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 9: c7.last_name == ""
--     c7 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 9: c8.not_found != true
--     c8 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 9: len(c9.rows) != 0
--     the constrained term is not a field of a produced row, so it names
--     no column (DESIGN_IR §2)
