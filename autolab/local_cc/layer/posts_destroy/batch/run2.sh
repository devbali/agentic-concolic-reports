export JAVA_HOME=/home/dev/tools/jdk-21.0.5
export PATH=$JAVA_HOME/bin:/home/dev/tools/jruby-9.3.0.0/bin:$PATH
export GEM_HOME=/home/dev/.gem/jruby/2.6.0
export RAILS_ENV=concolic
cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora
MAX_RUNS=250 TIME_BUDGET=2400 DUMP_OUT=/home/dev/project/reports/autolab/local_cc/boxes/posts_destroy-batch-2-a64eb674/out/packet/dumps bundle exec jruby -I. /home/dev/project/reports/autolab/entrypoints/scaffold/posts_destroy/run_dse.rb
