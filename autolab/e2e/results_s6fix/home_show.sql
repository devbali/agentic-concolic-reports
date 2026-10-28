-- home_show — SQL SELECT views rendered from the policy IR
--
-- 1 atoms in; 1 views out.
--   0 atoms do not terminate in a SELECT and are
--   excluded — every one is named below, never merely counted
--   (DESIGN_DOMAIN_LAYER §3A.3).
--   1 statements extracted, 1 distinct after the prune,
--   0 syntactically subsumed, 1 views.
--   PC predicates: 0 folded, 0 kept — a predicate the
--   policy shows this shape running BOTH WITH AND WITHOUT does not
--   constrain it and is dropped.
--   0 condition predicates did not resolve to a column; listed below.
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

SELECT `roles`.* FROM `roles` WHERE `roles`.`name` = 'admin';

-- ==========================================================================
-- EXCLUDED ATOMS — 0 of 1 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- (none: every atom terminates in a SELECT)

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 0 predicates
-- The IR keeps a path condition the renderer cannot resolve to a column;
-- this is where that loss is REPORTED rather than taken silently (DESIGN_IR §2).
-- ==========================================================================
-- (none: every condition predicate resolved to a column)
