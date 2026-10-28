-- profiles_edit — SQL SELECT views rendered from the policy IR
--
-- 4 atoms in; 4 views out.
--   0 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   4 statements extracted, 4 distinct after the prune,
--   0 syntactically subsumed, 4 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   9 condition predicates did not resolve to a column; listed below.
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

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles`, `people`, `users` WHERE `taggings`.`taggable_id` = `profiles`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id` AND `profiles`.`person_id` = `people`.`id`;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 0 of 4 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- (none: every atom terminates in a SELECT)

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 9 predicates
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
