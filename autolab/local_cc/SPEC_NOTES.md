# sweep_local.json — notes the spec schema has no room for

`sweep.spec.parse_spec` is a CLOSED schema (`_closed(raw, _TOP_LEVEL_KEYS, "spec")`),
so a comment key is rejected outright. It is recorded here instead.

## boxes.md.max_wall_s: 5400 -> 14400

Raised 5400 -> 14400 at 2026-09-30T23:0x, AFTER the batch box's plan was built (so that box keeps its 90-minute ceiling) and BEFORE the check box's. Reason: the check worker's deadline gates the completion step, and this config configures two heavy gates whose own timeouts sum to 7800s (test_timeout 2400 + assumption_timeout 5400). At 5400 the pass would have reported 'the deadline was reached before the completion gate ran' and set wall_clock_terminated, which 12.1 treats as a disqualified closing run. The spec is not digested; the endpoint's config is unchanged.
