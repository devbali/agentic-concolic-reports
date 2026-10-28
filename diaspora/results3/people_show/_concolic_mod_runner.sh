#!/usr/bin/env bash
# people_show-LOCAL copy of scripts/diaspora-concolic with ONE difference:
# RAILS_ENV defaults to concolic_mod instead of concolic (RC-1, 2026-09-19).
#
# Why local: the shared scripts/diaspora-concolic hardcodes
# `export RAILS_ENV=concolic`, and the coordinator deliberately left that
# default alone so other endpoints' in-flight campaigns are not disturbed.
# CLAUDE.md's prescribed remedy for exactly this case is a runner-local
# workaround, so this wrapper lives in the batch directory. Everything else
# (PATH, JAVA_HOME, GEM_HOME, cwd, exec line) is byte-identical to the
# shared script as of 2026-09-18.
#
# RC-1: app/models/profile.rb:8 gates `lazy_load :bio, :gender, :birthday,
# :location` on `Rails.env.include?("mod")`. Under RAILS_ENV=concolic that is
# false, so lazy_columns never installs its
# `default_scope { select(column_names - those_four) }` and every recorded
# `profiles` read carries all four columns. concolic_mod turns it on.
export PATH="/home/dev/tools/jdk-21.0.5/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH"
export JAVA_HOME="/home/dev/tools/jdk-21.0.5"
export GEM_HOME="/home/dev/.gem/jruby/2.6.0"
export RAILS_ENV="${RAILS_ENV_OVERRIDE:-concolic_mod}"

DIASPORA_APP="/home/dev/project/ruby_examples/dse-apps/apps/diaspora"

if [ $# -eq 0 ]; then
  echo "Usage: $0 <runner_script.rb>"
  exit 1
fi

cd "$DIASPORA_APP" || { echo "App directory not found"; exit 1; }
exec bundle exec jruby -I"$DIASPORA_APP" "$@"
