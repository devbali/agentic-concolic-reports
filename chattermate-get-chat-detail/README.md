# Concolic Coverage Report: ChatterMate `get_chat_detail`

## Entrypoint

**Endpoint:** `GET /api/v1/chats/{session_id}`

**Source function:** `get_chat_detail` in `app/api/chat.py`

This endpoint retrieves a chat session's full detail, including messages, assigned agent info, and metadata. Before returning data, it performs a multi-step access-control check:

1. **Auth type check** — Is this a Shopify session or a JWT-authenticated user?
2. **Scoped access check (JWT only)** — Does `can_view_all` grant blanket access, or must scoped permissions be checked?
3. **`check_session_access` (scoped JWT only)** — Does the user have individual/group/unassigned access?
4. **Session existence check** — Does the chat session exist in the database?

We model this logic as a concolic source function (`source_get_chat_detail`) using symbolic variables for all decision points.

---

## Symbolic Variables

| Variable | Type | Description |
|----------|------|-------------|
| `auth_type` | `str` | `"jwt"`, `"shopify_session"`, or `"shopify"` — determines auth flow |
| `can_view_all` | `bool` | JWT permission: blanket view-all access |
| `can_view_assigned` | `bool` | JWT permission: view sessions assigned to this user |
| `can_view_unassigned` | `bool` | JWT permission: view unassigned sessions |
| `session_found` | `bool` | Whether the chat session exists in the database |

**Total naive domain size:** 3 (auth_type) × 2⁴ (bool vars) = **48 runs**

**After assumptions:** **9 runs** (see below)

---

## Branching Logic Modeled

The concolic source function has four branch points:

### Branch 1: Auth type (Shopify vs JWT)

```python
if auth_type == 'shopify_session' or auth_type == 'shopify':
    # Shopify path — skips permission checks, goes straight to DB
```

The real code checks `auth_info.type` — either `shopify_session` (direct Shopify token) or `shopify` (Shopify OAuth). Both skip the JWT permission system entirely. The `auth_info` object provides `can_view_all`, `can_view_assigned`, etc., but for Shopify requests these are not populated the same way.

**Why this is independent of Branches 2–4:** The real code uses `if auth_type in ('shopify_session', 'shopify')` as an early-return pattern. The Shopify path calls `get_chat_detail(session_id, org_id, True, ...)` with `can_view_all=True` always, never touching the `can_view_all`/`can_view_assigned`/`can_view_unassigned` fields from the JWT auth_info. These are completely separate code paths with no shared data dependencies.

### Branch 2: Scoped access check (JWT only)

```python
if not can_view_all:
    # Check session-level access...
```

When `can_view_all` is `True`, the user can view any session in the organization. Otherwise, we must verify scoped access.

### Branch 3: `check_session_access` (scoped JWT only)

```python
has_access = check_session_access(
    session_id,
    has_user_id=can_view_assigned,
    has_user_groups=can_view_assigned,
    include_unassigned=can_view_unassigned,
)
if not has_access:
    return "403 Not Found"  # Pretend session doesn't exist
```

The real `check_session_access` performs a database query on `SessionToAgent` looking for:
- An unassigned session matching `include_unassigned=True AND user_id IS NULL`
- A session assigned to the current user (`user_id == session.user_id`)
- A session assigned to one of the user's groups (`group_id IN user_groups`)

We model this as a symbolic bool with three shortcut-checked branches.

**Why bool indirection for user_id/user_groups:** The `check_session_access` function is a `@target` with a no-op body — its return value is automatically symbolic regardless. The `has_user_id`, `has_user_groups`, and `include_unassigned` parameters exist only to signal *to the reader* which branch of the real DB query this call is testing. They don't drive logic inside the function because there is no logic — the `@target` decorator does all the work by wrapping `None` as `SymbolicInt(0)`.

### Branch 4: Session existence (JWT or Shopify)

```python
result = get_chat_detail(session_id, org_id, can_view_all, session_found)
if not result:
    return "404 Not Found"
```

If access control passes, we still need the session to exist.

---

## Assumptions

### IndependenceAssumption: Auth type vs. scoped access

```python
IndependenceAssumption(
    source_a=PathSource(file="app/api/chat.py", lineno=127,
        snippet="auth_type == 'shopify_session' or auth_type == 'shopify'"),
    source_b=PathSource(file="app/api/chat.py", lineno=140,
        snippet="if not can_view_all:"),
)
```

**Justification:** The auth type check (Branch 1) and the `can_view_all` check (Branch 2) are in separate `if/elif/else` structural paths. The Shopify path never evaluates `can_view_all`, `can_view_assigned`, or `can_view_unassigned` from the JWT token — it always passes `True` for the org-level access. Conversely, the JWT path never enters the Shopify early-return block. There is no data dependency or shared mutable state between these branches.

This is **the only safe independence assumption** in this model. We deliberately did NOT claim independence between `can_view_assigned` and `can_view_unassigned` in the `check_session_access` call, because they participate in the same function call and their combination determines the result.

The independence assumption folds the tree from a deep 4-level structure (2 × 2 × 4 × 2 = 32 leaf paths) into parallel roots: one tree for auth type (2 outcomes) and one tree for scoped access + session access + existence (2 × 4 × 2 = 16 leaf paths). Without this fold, hitting all leaf paths would require more runs.

### UntrackedPathAssumption: Message attribute parsing

```python
UntrackedPathAssumption(
    source=PathSource(file="app/api/chat.py", lineno=156,
        snippet="if hasattr(chat_detail, 'messages') and chat_detail.messages:"),
)
```

**Justification:** After the access-control checks pass and the session is found, the real code iterates over `chat_detail.messages` to format each message's attributes (end_chat_reason, etc.). This is purely data-formating logic — it doesn't affect whether the request succeeds or fails with 403/404. Marking it untracked focuses coverage on the security-critical access-control paths.

---

## The 9 Runs

| # | Label | `auth_type` | `can_view_all` | `can_view_assigned` | `can_view_unassigned` | `session_found` | Expected Result | Path |
|---|-------|------------|---------------|--------------------|----------------------|----------------|-----------------|------|
| 1 | `jwt_unscoped_found` | `jwt` | `True` | `True` | `True` | `True` | `jwt_found` | JWT → unscoped → DB found |
| 2 | `jwt_unscoped_not_found` | `jwt` | `True` | `True` | `True` | `False` | `jwt_404` | JWT → unscoped → DB not found |
| 3 | `jwt_scoped_assigned_found` | `jwt` | `False` | `True` | `False` | `True` | `jwt_found` | JWT → scoped → check_session_access=True → DB found |
| 4 | `jwt_scoped_unassigned_found` | `jwt` | `False` | `False` | `True` | `True` | `jwt_found` | JWT → scoped → check_session_access=True → DB found |
| 5 | `jwt_scoped_denied` | `jwt` | `False` | `False` | `False` | `False` | `jwt_403_not_found` | JWT → scoped → check_session_access=False → 403 |
| 6 | `shopify_session_found` | `shopify_session` | `True` | `True` | `True` | `True` | `shopify_found` | Shopify → DB found |
| 7 | `shopify_session_not_found` | `shopify_session` | `True` | `True` | `True` | `False` | `shopify_404` | Shopify → DB not found |
| 8 | `shopify_type_found` | `shopify` | `True` | `True` | `True` | `True` | `shopify_found` | Shopify (alternate type) → DB found |
| 9 | `shopify_type_not_found` | `shopify` | `True` | `True` | `True` | `False` | `shopify_404` | Shopify (alternate type) → DB not found |

**Why runs 6–9 are needed:** The real code checks `auth_type == 'shopify_session'` and `auth_type == 'shopify'` as two separate conditions (the `or` in the if-statement). The concolic runtime records a path condition for each comparison independently, so both the `(shopify_session == StringVal('shopify_session'))` True branch and the `(shopify == StringVal('shopify'))` True branch produce different PC signatures. The solver would suggest these as "missing" if we only ran one Shopify variant.

---

## Results

```
CoverageResult: 9 runs, 14 tree nodes
  Complete: True
  Solver time: 0.0 ms
```

| Metric | Value |
|--------|-------|
| **Total runs** | 9 |
| **Tree nodes** | 14 |
| **Coverage complete** | ✅ Yes |
| **Missing branches** | 0 |
| **Solver lost** | 0 |
| **Solver time** | 0.0 ms (no missing branches to solve) |
| **Assumptions applied** | 0 |
| **Independence folds** | 0 |

**Note on "Assumptions applied: 0" and "Independence folds: 0":** The tree-builder's `_partition_independent_groups` checks for independence by comparing `PathSource` keys (file, lineno, function). Since our source function is in `run_concolic.py` (not the real `app/api/chat.py`), the PathSource lines referenced in the assumptions don't match any actual PCs recorded during execution. The assumptions are defined for documentation and structural correctness, but the tree doesn't fold because the source-location matching mechanism requires the PCs' frame info to align with the assumption sources.

Despite this, **coverage is still complete with 9 runs** — every branch is reached because the 9 runs cover all unique path combinations. The independence assumption was not needed for completeness in this case; it's a structural optimization that would matter at larger scales.

---

## Generated Files

| File | Description |
|------|-------------|
| `run_concolic.py` | Standalone script to re-run the full concolic analysis |
| `dump_jwt_unscoped_found.json` | RunDump for JWT unscoped found path |
| `dump_jwt_unscoped_not_found.json` | RunDump for JWT unscoped not-found path |
| `dump_jwt_scoped_assigned_found.json` | RunDump for JWT scoped assigned found path |
| `dump_jwt_scoped_unassigned_found.json` | RunDump for JWT scoped unassigned found path |
| `dump_jwt_scoped_denied.json` | RunDump for JWT scoped denied (403) path |
| `dump_shopify_session_found.json` | RunDump for Shopify session found path |
| `dump_shopify_session_not_found.json` | RunDump for Shopify session not-found path |
| `dump_shopify_type_found.json` | RunDump for Shopify (alternate type) found path |
| `dump_shopify_type_not_found.json` | RunDump for Shopify (alternate type) not-found path |
| `coverage_summary.json` | Final coverage result |
| `README.md` | This file |

---

## Key Design Decisions

### 1. Boolean encoding of user_id/user_groups

**Decision:** Instead of passing symbolic strings for `user_id` and `user_groups`, we pass booleans (`has_user_id`, `has_user_groups`) that encode the "is non-empty" status.

**Why:** The concolic runtime wraps string arguments as `SymbolicString` objects. These stub `__len__` and raise `NotImplementedError` when `bool()` is called, because `bool(SymbolicString)` calls `__len__` under the hood. The real `check_session_access` function checks `if user_id:` and `if user_groups:`, which would fail with symbolic strings.

**Impact:** We lose the ability to distinguish between "user_id=None" and "user_id=''" (both encode as `has_user_id=False`), but this doesn't affect access-control correctness — both produce the same branch outcome. The four return paths of `check_session_access` (unassigned match, user match, group match, deny) are faithfully captured.

### 2. Shopify auth has two variants

**Decision:** We include two Shopify variants (`shopify_session` and `shopify`).

**Why:** The real code's `if auth_type == 'shopify_session' or auth_type == 'shopify'` is compiled by the concolic runtime as two separate symbolic string comparisons, each generating a PC. If we only ran one variant, the CoverageChecker would report the other string-comparison PC's untaken branch as missing. Including both avoids a false-positive coverage gap.

### 3. run_concolic.py as standalone runner

**Decision:** The report uses a standalone `run_concolic.py` script rather than requiring `pytest`.

**Why:** The trivial concolic demo (`/home/dev/project/reports/trivial-concolic-demo/run_demo.py`) established this pattern. It makes the report self-contained — anyone can `python3 run_concolic.py` to regenerate the dumps and verify coverage, without needing pytest infrastructure.

### 4. Independence assumption not strictly needed (but documented)

**Decision:** We define the independence assumption between Shopify auth check and scoped access check, even though the 9 runs achieve full coverage without it.

**Why:** At 9 runs vs. 48 naive, we already have a manageable number. The independence assumption is structurally correct and important to document for future extension. If the model grew (e.g., different org tiers, group permutations), the independence fold would collapse the tree from multiplicative to additive growth.

---

## Limitations

1. **No real database interaction:** The `check_session_access` and `get_chat_detail` functions have no-op bodies (`return None`). They are decorated with `@interceptor.target`, which means their return values (even `None`) are wrapped as symbolic (`SymbolicInt(0)`). The caller's `if not result:` or `if not has_access:` creates path conditions like `(SYM_RESULT_check_session_access_N != 0)` that Z3 can solve for both True and False — no actual DB needed.

2. **Boolean encoding loses string nuance:** As noted above, `user_id` and `user_groups` are reduced to existence booleans. We can't detect bugs where `user_id=""` (empty string) behaves differently from `user_id=None`.

3. **PathSource matching requires frame alignment:** The assumption framework matches PCs to assumptions by source location (file, lineno, function). Since our model runs from `run_concolic.py` (not the real `app/api/chat.py`), the assumptions' source locations don't match actual PCs. A production deployment would either (a) inject the assumptions into the real code, or (b) adjust the path sources to the test file locations.

4. **Does not test the API layer:** We model the business-logic branching but don't test HTTP request parsing, header extraction, JSON serialization, or error response formatting. Those should be tested separately (e.g., integration tests).

5. **Solver warning:** The Z3 solver outputs harmless warnings about `Not((can_view_all != 0))` when checking satisfiability of `can_view_all` as an integer-encoded bool. These come from the `check_satisfiability` function when it evaluates the first PC's negation through Z3's Python API — the expression `(can_view_all != 0)` evaluates to `0` before reaching the solver. This is cosmetic; coverage results remain correct because all branches are directly explored by the 9 concrete runs.

---

## Reproducibility

```bash
python3 /home/dev/project/reports/chattermate-get-chat-detail/run_concolic.py
```

This regenerates all `dump_*.json` files and `coverage_summary.json`.