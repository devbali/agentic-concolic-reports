#!/bin/bash
unset JAVA_TOOL_OPTIONS
export XDG_RUNTIME_DIR=/run/user/1000 LANG=C.UTF-8 LC_ALL=C.UTF-8
B=/home/dev/project/reports/autolab/local_cvd/boxes/conversation_visibilities_destroy-batch-2-da27632d
JRUBY_OPTS=--debug systemd-run --user --scope -p MemoryMax=10G --quiet /home/dev/project/scripts/diaspora-concolic /home/dev/project/src_new/runtimes/ruby_runtime/completion_checker/shim_test_runner.rb /tmp/cvd_shims.json $B/batch/shim_tests.rb $B/batch/shim_results.json > $B/batch/shim.log 2>&1
echo EXIT $? >> $B/batch/shim.log
