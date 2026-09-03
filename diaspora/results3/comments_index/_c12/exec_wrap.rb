# M-18 (adversary round 9) — BATCH-LOCAL executor wrapping. The shared probe
# (`src/ruby_runtime/completion_checker/concrete_run_probe.rb`) is NOT touched.
#
# Why: the rigs dispatch through `ActionController::TestCase#process`, which
# never runs `ActionDispatch::Executor`; Rails installs ActiveRecord's query
# cache as an EXECUTOR hook, so the rig caches nothing and every repeated
# identical statement is recorded twice. `ActionDispatch::Executor` is in this
# app's middleware stack, so a real Rack request caches. The probe skips
# `payload[:cached]`, so a wrapped run records exactly what a real request's
# probe would record.
#
# Usage: wrap the single dispatch expression in `ci_wrap { ... }`.
# `CI_EXECUTOR=1` turns it on; unset it and the manifest behaves exactly as
# before, so the same file produces BOTH ground truths.
def ci_wrap
  if ENV["CI_EXECUTOR"].to_s == "1" && defined?(Rails) && Rails.application.respond_to?(:executor)
    Rails.application.executor.wrap { yield }
  else
    yield
  end
end

warn "[c12] CI_EXECUTOR=#{ENV['CI_EXECUTOR'].inspect} " \
     "executor=#{(defined?(Rails) && Rails.application.respond_to?(:executor)) ? 'available' : 'MISSING'}"
