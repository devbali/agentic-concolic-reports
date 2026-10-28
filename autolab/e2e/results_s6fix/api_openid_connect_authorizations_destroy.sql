-- api_openid_connect_authorizations_destroy — SQL SELECT views rendered from the policy IR
--
-- 2 atoms in; 1 views out.
--   1 atoms do not terminate in a SELECT and are
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

SELECT `authorizations`.* FROM `authorizations`;

-- ==========================================================================
-- EXCLUDED ATOMS — 1 of 2 do not terminate in a SELECT
-- `supports()` returned False for each. Named, never silently skipped.
-- ==========================================================================
-- atom 2: access ActiveRecord::Base#destroy
--     terminates in DELETE, which is a write and not a select view

-- ==========================================================================
-- CONDITIONS NOT RENDERED — 0 predicates
-- The IR keeps a path condition the renderer cannot resolve to a column;
-- this is where that loss is REPORTED rather than taken silently (DESIGN_IR §2).
-- ==========================================================================
-- (none: every condition predicate resolved to a column)
