-- aspects_toggle_chat_privilege — SQL SELECT views rendered from the policy IR
--
-- 11 atoms in; 4 views out.
--   4 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   7 statements extracted, 4 distinct after the prune,
--   0 syntactically subsumed, 4 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   10 condition predicates did not resolve to a column; listed below.
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

SELECT `aspects`.* FROM `aspects`, `users` WHERE `aspects`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 4 of 11 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- atom 5: access ActiveRecord::Base#save
--     terminates in UPDATE, which is a write and not a select view
-- atom 6: access ActiveRecord::Base#save
--     terminates in UPDATE, which is a write and not a select view
-- atom 9: access ActiveRecord::Base#save
--     terminates in UPDATE, which is a write and not a select view
-- atom 10: access ActiveRecord::Base#save
--     terminates in UPDATE, which is a write and not a select view

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 10 predicates
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
-- atom 7: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 7: c4.not_found == true
--     c4 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 8: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c2.not_found == true
--     c2 is not joined into this statement, so the condition constrains
--     rows this view does not read
