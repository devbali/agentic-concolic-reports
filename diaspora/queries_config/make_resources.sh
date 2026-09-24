#!/bin/bash
# Regenerate the DERIVED parts of diaspora's app config.
#
#   resources/diaspora-ddl.sql   <- ruby_examples/dse-apps/schemas/diaspora-schema.rb
#   resources/pk.txt             <- same (Rails' implicit `id` pk, one line per table)
#
# HAND-MAINTAINED (not regenerated, no machine-readable source in the app):
#   resources/fk.txt          foreign keys, adapted from blockaid's own
#                             src/test/resources/DiasporaTest/fk.txt (schema.rb
#                             carries no FK constraints for this app);
#   resources/deps.sql        app invariants expressed as query containments,
#                             copied verbatim from the same blockaid fixture;
#   resources/const-decls.txt principal/now bind declarations (_MY_UID:int;).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" "$HERE/../../../src/queries_from_runs/subsume/gen_ddl.py" \
    --app-config "$HERE/app.json" --with-pk "$@"
