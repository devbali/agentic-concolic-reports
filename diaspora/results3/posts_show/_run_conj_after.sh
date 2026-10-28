#!/bin/bash
# Fire the conjunction-foreclosure price ONLY when nothing else of mine is on
# the box. `wait_alone` did not know about `_matched_ctx_check`, which is why
# the first attempt was stopped at 19:57 before it could collide.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
while pgrep -f "_matched_ctx_chec[k].py" >/dev/null; do sleep 20; done
exec bash "$B/_run_conj.sh"
