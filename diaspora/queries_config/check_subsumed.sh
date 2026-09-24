#!/bin/bash
# Diaspora entry point for the generic subsumption checker.
#
# src/queries_from_runs/subsume is app-agnostic and REQUIRES an app config;
# this wrapper supplies diaspora's and forwards everything else unchanged.
#
#   ./check_subsumed.sh input.json      # or:  ... | ./check_subsumed.sh
#
# All SUBSUME_* env knobs of the generic checker apply.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export QFR_APP_CONFIG="${QFR_APP_CONFIG:-$HERE/app.json}"

exec "$HERE/../../../src/queries_from_runs/subsume/check_subsumed.sh" "$@"
