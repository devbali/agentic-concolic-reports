# T1 probe (CHECKS.md Part I): observe DECLARED TARGET FUNCTIONS during a
# real-body run. The shim-mock contract is engine-native: a shim mock may
# replace only computation that reaches NO target function — targets are
# where the runtime mints evidence (events, notes, symbolic results), so a
# shim over a target-reaching body swallows evidence by construction. SQL
# is just the most important family of targets; assert it separately with
# statement_log.rb when a DB is wired.
#
#   targets = [[ActiveRecord::FinderMethods, :find_by],
#              [Person, :profile], ...]   # what the batch declare_target'ed
#   calls = CompletionChecker::TargetCallProbe.capture(targets: targets) do
#     <real body, shim disabled, concrete fixture values>
#   end
#   raise "not a shim mock: #{calls}" unless calls.empty?
#
# `raise_on_call: true` fails fast at the first target hit (useful when
# letting the real target proceed would crash, e.g. no DB behind it).
#
# Implementation: alias-and-restore wrappers (reliable on JRuby, unlike
# un-prepending); originals are restored in `ensure` even when the probe
# body raises. Zero coupling: nothing here requires the interceptor — the
# batch passes the same (module, method) pairs it declares.
module CompletionChecker
  class TargetCalled < StandardError; end

  module TargetCallProbe
    # The probe OBSERVES; it never alters flow. Targets always run for
    # real (raise_on_call: true is the one exception — it ABORTS at the
    # first hit, it does not fake a result). A mode that stubbed targets
    # was removed (Bali, 2026-08-25): real code + faked target boundary
    # is the concolic engine's own structure — a checker built that way
    # shares the failure mode of the thing it checks.
    def self.capture(targets:, raise_on_call: false)
      calls = []
      restores = []
      targets.each do |owner, meth|
        meth = meth.to_sym
        homes = []
        if owner.respond_to?(:method_defined?) &&
           (owner.method_defined?(meth) || owner.private_method_defined?(meth))
          homes << [owner, "#"]
        end
        homes << [owner.singleton_class, "."] if owner.respond_to?(meth)
        homes.each do |home, sep|
          original = home.instance_method(meth)
          label = "#{owner}#{sep}#{meth}"
          home.send(:define_method, meth) do |*args, &blk|
            depth = Thread.current[:cc_target_depth] ||= 0
            # depth: number of target frames already active. A depth>0 call
            # is an INNER call of another target's real body — under
            # concolic interception the outer mock fires first and the
            # inner never runs, so its evidence lives in the outer's note
            # (structural subsumption, used by concrete_checker).
            record = { "target" => label, "depth" => depth,
                       "args" => args.map { |a| a.inspect.to_s[0, 60] } }
            calls << record
            raise TargetCalled, label if raise_on_call
            begin
              Thread.current[:cc_target_depth] = depth + 1
              prev_frame = Thread.current[:cc_target_frame]
              Thread.current[:cc_target_frame] = label
              original.bind(self).call(*args, &blk)
            ensure
              Thread.current[:cc_target_depth] = depth
              Thread.current[:cc_target_frame] = prev_frame
            end
          end
          restores << [home, meth, original]
        end
      end
      begin
        yield
      rescue TargetCalled
        # fail-fast mode: the hit is already in `calls`
      end
      calls
    ensure
      restores.each { |home, m, original| home.send(:define_method, m, original) }
    end

    # Assertion form: raises unless the block reaches zero target functions.
    def self.assert_shim_mock!(targets:, &block)
      calls = capture(targets: targets, raise_on_call: true, &block)
      unless calls.empty?
        raise "T1 FAIL — not a valid shim mock, real body reached target function(s): " \
              "#{calls.map { |c| c['target'] }.uniq.join(', ')}"
      end
      true
    end
  end
end
