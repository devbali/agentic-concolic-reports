-- admins_stats — SQL SELECT views rendered from the policy IR
--
-- 9 atoms in; 6 views out.
--   0 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   9 statements extracted, 6 distinct after the prune,
--   0 syntactically subsumed, 6 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   11 condition predicates did not resolve to a column; listed below.
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

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `taggings`.`id`, `tags`.`id` FROM `taggings` INNER JOIN `tags` ON `tags`.`id` = `taggings`.`tag_id` GROUP BY `tag`;

-- NOTE: flag aggregate-as-rows
SELECT `posts`.`id` FROM `posts` WHERE `posts`.`created_at` BETWEEN '2026-09-24 00:00:00 +0000' AND '2026-09-25 00:00:00 +0000';

-- NOTE: flag aggregate-as-rows
SELECT `posts`.`id` FROM `posts` WHERE `posts`.`created_at` BETWEEN '2026-09-25 00:00:00 +0000' AND '2026-09-26 00:00:00 +0000';

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 0 of 9 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- (none: every atom terminates in a SELECT)

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 11 predicates
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
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 5: c1.language == "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 6: c1.language == "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 7: c1.language != "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 7: c1.language != "xx"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.language != "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.language != "xx"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 9: c1.language != "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 9: c1.language != "xx"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
