# M-18 (comments_index adversary round 9), ported batch-locally. The shared
# probe (reports/diaspora/tools/concrete_checker/concrete_run_probe.rb) is NOT
# touched.
#
# The rigs dispatch through `ActionController::TestCase#process`, which never
# runs `ActionDispatch::Executor`; Rails installs ActiveRecord's query cache as
# an EXECUTOR hook, so the rig caches nothing and every repeated identical
# statement is recorded twice. `ActionDispatch::Executor` IS in this app's
# middleware stack, so a real Rack request caches. The probe skips
# `payload[:cached]`, so a wrapped run records exactly what a real request's
# probe would record.
#
# `CI_EXECUTOR=1` turns it on; unset it and the manifest behaves exactly as
# before, so the same file produces BOTH ground truths.
def ci_wrap
  if ENV["CI_EXECUTOR"].to_s == "1" && defined?(Rails) && Rails.application.respond_to?(:executor)
    Rails.application.executor.wrap { yield }
  else
    yield
  end
end

warn "[ps-show-concrete] CI_EXECUTOR=#{ENV['CI_EXECUTOR'].inspect} " \
     "executor=#{(defined?(Rails) && Rails.application.respond_to?(:executor)) ? 'available' : 'MISSING'}"
