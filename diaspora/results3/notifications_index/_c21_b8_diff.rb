# GROUND-TRUTH DIFFERENTIAL for the C21 B-8 CACHE-REPLAY repair.
# DISCIPLINE: a check must be a DIFFERENTIAL against ground truth, not an
# instance test. Same Rails env, same fixture DB, same interceptor, same seed
# forcing the NOT-FOUND arm; the ONLY difference between the two runs is which
# concolic_targets.rb is loaded (ARGV[0]).
#
# Unlike people_stream's _b8_diff.rb this probe calls the SAME finder TWICE in
# ONE run: the first call is the fact-cache MISS (already repaired, publishes
# its note), the second is the REPLAY that this round repairs.
require "./config/environment"
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
CompletionChecker::ConcreteEnv.setup!(db: ARGV[1])
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
# NotificationsIndexTargets supplies one_fact/remember_fact (the per-run fact
# cache the replay arm reads). `install!` is NOT called: no target is declared
# by targets.rb here, only the module's cache helpers are needed.
load "/home/dev/project/reports/diaspora/results3/notifications_index/targets.rb"
load ARGV[0]
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
NotificationsIndexTargets.reset_fact_cache! if
  NotificationsIndexTargets.respond_to?(:reset_fact_cache!)
ConcolicTargets.seed_overrides = {
  "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_not_found" => true,
}
dump = $interceptor.run(lambda {
  Block.all.find_by(user_id: 9)     # MISS  -> not_found arm  (publishes)
  Block.all.find_by(user_id: 9)     # REPLAY-> one_fact hit, fval nil
  Block.all.find_by(user_id: 9)     # REPLAY again
  :ok
}, {}, label: "c21b8probe", script: "_c21_b8_diff.rb")
n = 0
(dump["events"] || []).each do |e|
  next unless e["type"] == "symbolic_call"
  n += 1
  puts "EVENT #{n} target=#{e['target']} result=#{e['result_name'].inspect} " \
       "value=#{e['result_value'].inspect} note=#{(e['note'] || '').to_s[0, 90].inspect}"
end
vars = (dump["symbolic_vars"] || {}).keys
puts "VARS #{vars.length}: #{vars.sort.join(' ')}"
pcs = (dump["events"] || []).select { |e| e["type"] == "path_condition" }
puts "PCS #{pcs.length}: " + pcs.map { |e| "#{e['expr']}::#{e['taken']}" }.join(" | ")
