#!/bin/bash
# §76.5(c) — PRICE the conjunction-foreclosure inference on this endpoint's own
# demand. Batch-local: _exact_enum_conj.py is a copy of the batch's enumerator
# with the leaf-group-prefix "never" test added; src/ is untouched.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
L="$B/_conj_price.log"
wait_alone conjprice
cage pxconj.scope 3500M \
  env BATCH="$B" DUMP_LIST="$B/_snapshot_pruned_OD0911.txt" PYTHONPATH=/home/dev/project/src \
      JAVA_TOOL_OPTIONS= timeout 10800 python3 -u "$B/_conj_price.py" > "$L" 2>&1
echo "conj price exit=$?" >> "$L"
caged_verdict pxconj.scope "$L" '^CONJ PRICE DONE' >> "$L"
