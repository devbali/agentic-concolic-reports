# STANDING SELF-TEST for the concrete probe (run through the app-booting
# runner like any manifest; expects 2 recorded calls, depths 0 and 1, no
# error). Proves the probe is target-generic: arbitrary non-SQL module,
# real bodies execute under observation (the body asserts on the real
# return value), nesting depth tracked.
# Self-check: an ARBITRARY, non-SQL, non-AR target function. Verifies the
# concrete probe (a) records the invocation, (b) lets the REAL body run
# (we assert on its actual return value), (c) tracks nesting depth.
module ConcreteSelfCheck
  def self.compute(x)
    inner(x) * 2          # calls another target -> depth 1 record
  end
  def self.inner(x)
    x + 1
  end
end

CONCRETE_SCENARIOS = [
  { name: "arbitrary-target-selfcheck",
    targets: [[ConcreteSelfCheck, :compute], [ConcreteSelfCheck, :inner]],
    body: -> {
      result = ConcreteSelfCheck.compute(20)
      raise "real body did not run (got #{result})" unless result == 42
    } },
]
