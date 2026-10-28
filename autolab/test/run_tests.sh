#!/usr/bin/env bash
# run_tests.sh -- the auto lab's test suite.
#
#   test_install.rb   installs the library against the REAL CallInterceptor and
#                     fails loudly on MissingKind / MissingType / opaque-on-a-
#                     target-function. Includes negative controls: it mutates
#                     the real core file and asserts the mutant is caught.
#   test_inventory.py the paperwork agrees with itself and is not stale.
#   reconcile_with_app.py  the probe measures a MAXIMAL set; real dumps say what
#                     the booted app installs. This is the diff, and it must be
#                     nothing but the pinned dormant declaration.
#   check_citations.py every file:line the prose argues from still lands on the
#                     pattern it was written for. The curated files get revised.
#   test_cost.py      tools/cost.py's join of workers.jsonl, the queue's box
#                     records and the price catalog -- chiefly that an unknown
#                     price stays NULL and never becomes 0.
#
# The Ruby test runs under JRuby when the scripts/diaspora-concolic toolchain is
# on disk (that is what a sweep actually runs) and under CRuby otherwise. It
# does NOT boot the diaspora app -- see README, "What is NOT verified".
set -u
cd "$(dirname "$0")/.." || exit 1
LAB="$PWD"
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
JRUBY=/home/dev/tools/jruby-9.3.0.0/bin/jruby
JAVA=/home/dev/tools/jdk-21.0.5

rc=0

if [ -x "$JRUBY" ] && [ -d "$JAVA" ]; then
  echo "### test_install.rb  (JRuby -- the runtime a sweep uses)"
  PATH="$JAVA/bin:$(dirname "$JRUBY"):$PATH" JAVA_HOME="$JAVA" \
    GEM_HOME="/home/dev/.gem/jruby/2.6.0" \
    "$JRUBY" "$LAB/test/test_install.rb" || rc=1
else
  echo "### JRuby not found at $JRUBY -- skipping the JRuby pass"
fi

echo
echo "### test_install.rb  (CRuby $(ruby -e 'print RUBY_VERSION'))"
ruby "$LAB/test/test_install.rb" || rc=1

echo
echo "### reconcile_with_app.py  (probe's maximal set vs what the booted app installs)"
"$PY" "$LAB/tools/reconcile_with_app.py" || rc=1

echo
echo "### check_citations.py  (every file:line the prose argues from)"
"$PY" "$LAB/tools/check_citations.py" || rc=1

echo
echo "### test_inventory.py"
"$PY" "$LAB/test/test_inventory.py" || rc=1

echo
echo "### test_cost.py  (the attempts -> VM -> price join)"
"$PY" "$LAB/test/test_cost.py" || rc=1

echo
if [ "$rc" -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "SUITE FAILURES -- see above"; fi
exit $rc
