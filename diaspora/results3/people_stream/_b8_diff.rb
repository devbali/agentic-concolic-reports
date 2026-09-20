# GROUND-TRUTH DIFFERENTIAL for the B-8 pending-note repair (DISCIPLINE: a
# check must be a differential, not an instance test). Same scenario, same
require "./config/environment"
# seed, the ONLY difference is which concolic_targets.rb is loaded.
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
CompletionChecker::ConcreteEnv.setup!(db: ARGV[1])
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
load ARGV[0]
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
# force the NOT-FOUND arm of the shared finder mock — the arm that returns nil
ConcolicTargets.seed_overrides = {
  "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found" => true,
}
dump = $interceptor.run(lambda { Person.all.find_by(guid: "nosuchguid"); :ok }, {},
                        label: "b8probe", script: "b8_diff.rb")
(dump["events"] || []).each do |e|
  next unless e["type"] == "symbolic_call"
  puts "EVENT target=#{e['target']} result=#{e['result_name']} note=#{(e['note'] || '').to_s[0, 100].inspect}"
end
