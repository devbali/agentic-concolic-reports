-- photos_show — SQL SELECT views rendered from the policy IR
--
-- 13 atoms in; 15 views out.
--   0 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   17 statements extracted, 15 distinct after the prune,
--   0 syntactically subsumed, 15 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   32 condition predicates did not resolve to a column; listed below.
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

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `photos`.`id` AND `share_visibilities`.`shareable_type` = 'Photo', `people`, `users` WHERE `photos`.`author_id` = 15 AND `share_visibilities`.`user_id` = `people`.`id` AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:11 +0000' AND `users`.`id` = _MY_UID;

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `photos`.`id` AND `share_visibilities`.`shareable_type` = 'Photo', `people`, `users` WHERE `photos`.`author_id` = 15 AND `share_visibilities`.`user_id` = `people`.`id` AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:14 +0000' AND `users`.`id` = _MY_UID;

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `photos`.`id` AND `share_visibilities`.`shareable_type` = 'Photo', `people`, `users` WHERE `photos`.`author_id` = 15 AND `share_visibilities`.`user_id` = `people`.`id` AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:16 +0000' AND `users`.`id` = _MY_UID;

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `photos`.`id` AND `share_visibilities`.`shareable_type` = 'Photo', `people`, `users` WHERE `photos`.`author_id` = 15 AND `share_visibilities`.`user_id` = `people`.`id` AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:17 +0000' AND `users`.`id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `people`, `users` WHERE `photos`.`author_id` = 15 AND `photos`.`created_at` < `people`.`id` AND `photos`.`id` = '2026-09-26 13:06:15 +0000' AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `photos`.* FROM `photos`, `people`, `users` WHERE `photos`.`author_id` = 15 AND `photos`.`created_at` < `people`.`id` AND `photos`.`id` = '2026-09-26 13:06:17 +0000' AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `photos`.* FROM `photos`, `people`, `users` WHERE `photos`.`author_id` = 15 AND `photos`.`created_at` < `people`.`id` AND `photos`.`id` = '2026-09-26 13:06:18 +0000' AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos`, `people`, `users` WHERE `photos`.`author_id` = 15 AND `photos`.`public` = 't' AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:11 +0000' AND `users`.`id` = _MY_UID;

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos`, `people`, `users` WHERE `photos`.`author_id` = 15 AND `photos`.`public` = 't' AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:14 +0000' AND `users`.`id` = _MY_UID;

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos`, `people`, `users` WHERE `photos`.`author_id` = 15 AND `photos`.`public` = 't' AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:16 +0000' AND `users`.`id` = _MY_UID;

-- NOTE: flag outer-join-split
SELECT `photos`.* FROM `photos`, `people`, `users` WHERE `photos`.`author_id` = 15 AND `photos`.`public` = 't' AND `photos`.`created_at` < `users`.`id` AND `photos`.`id` = '2026-09-26 13:06:17 +0000' AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;

-- ==========================================================================
-- EXCLUDED ATOMS — 0 of 13 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- (none: every atom terminates in a SELECT)

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 32 predicates
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
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 5: c2.id == c4.id
--     no schema: `.id` on c2 cannot be confirmed to be a column of
--     `people`, so it is not folded
-- atom 5: c4.not_found != true
--     c4 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 6: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 6: c2.id != c4.id
--     c2 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 6: c4.not_found != true
--     no schema: `.not_found` on c4 cannot be confirmed to be a column of
--     `people`, so it is not folded
-- atom 7: c1.language == "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 7: c2.id != c4.id
--     c2 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 7: c4.not_found != true
--     no schema: `.not_found` on c4 cannot be confirmed to be a column of
--     `people`, so it is not folded
-- atom 8: c1.language != "pl"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 8: c1.language != "xx"
--     c1 is not joined into this statement, so the condition constrains
--     rows this view does not read
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
-- atom 10: c2.not_found != true
--     no schema: `.not_found` on c2 cannot be confirmed to be a column of
--     `people`, so it is not folded
-- atom 10: c3.id != c2.id
--     c3 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 11: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 11: c2.not_found != true
--     no schema: `.not_found` on c2 cannot be confirmed to be a column of
--     `people`, so it is not folded
-- atom 11: c3.id != c2.id
--     c3 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 12: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 12: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 12: c2.not_found != true
--     c2 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 12: c3.id == c2.id
--     no schema: `.id` on c3 cannot be confirmed to be a column of
--     `people`, so it is not folded
-- atom 13: c1.language != "pl"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 13: c1.language != "xx"
--     no schema: `.language` on c1 cannot be confirmed to be a column of
--     `users`, so it is not folded
-- atom 13: c2.not_found != true
--     c2 is not joined into this statement, so the condition constrains
--     rows this view does not read
-- atom 13: c3.id == c2.id
--     no schema: `.id` on c3 cannot be confirmed to be a column of
--     `people`, so it is not folded
