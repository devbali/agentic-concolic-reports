# declaration_probe.rb -- run a REAL `install!` against the REAL
# `CallInterceptor` from src_new and record every declaration it makes.
#
# This is the measurement instrument behind inventory/manifest.json. It is NOT
# a grep: `ConcolicTargets.install!` really executes, `declare_target` really
# runs, and `MissingKind` / `MissingType` / `valid_type?` are the runtime's own.
# What is faked is only the WORLD the config declares against -- see
# stub_world.rb, which this file requires.
#
# CONSEQUENCE, and it is the honest caveat on every count in this lab: the
# probe measures the MAXIMAL declaration set -- what the config declares when
# every guarded constant and method is present. Against the real app an
# eager-load failure can leave a guard false and one declaration dormant.
# The probe cannot see that; only a JRuby run inside the app can.
#
#   ruby declaration_probe.rb <spec.json>
#     spec = {"lenient": false, "consts": [...],
#             "steps": [{"file": "...", "modules": ["ConcolicTargets"]}, ...]}
#   lenient: true  -- for pre-`kind:` corpora (results3). A declaration missing
#     kind:/type: is RECORDED as needing repair and retried with placeholders so
#     the rest of install! still runs. Placeholders are flagged, never trusted.

require_relative "stub_world"

# Log EVERY declare_target call (the real one still runs and still validates).
$DT_LOG = []
$DT_MOD = nil
module DeclareTargetLogger
  def declare_target(klass, method, returns: nil, kind: nil, type: nil)
    site = caller_locations(1, 12).find { |l| l.path.end_with?("targets.rb") }
    $DT_LOG << { "klass_raw" => (klass.respond_to?(:name) ? klass.name : klass.to_s),
                 "method" => method.to_s, "kind" => kind, "type" => type,
                 "has_returns" => !returns.nil?,
                 "module" => $DT_MOD,
                 "site" => site ? "#{site.path}:#{site.lineno}" : nil }
    rec = $DT_LOG.last
    ok_kind = CallInterceptor::KINDS.include?(kind)
    ok_type = CallInterceptor.valid_type?(type)
    if $LENIENT && !(ok_kind && ok_type)
      rec["needs_repair"] = true
      rec["missing"] = [(ok_kind ? nil : "kind"), (ok_type ? nil : "type")].compact
      r = super(klass, method, returns: returns,
                kind: ok_kind ? kind : CallInterceptor::SHIM,
                type: ok_type ? type : "opaque")
    else
      r = super
    end
    rec["target"] = CallInterceptor.target_name(klass, method)
    r
  end
end
CallInterceptor.prepend(DeclareTargetLogger)

records = []
ci = CallInterceptor.new
errors = []

spec = JSON.parse(File.read(ARGV[0]))
$LENIENT = !!spec["lenient"]   # {"consts":[...], "steps":[{"file":..,"modules":[..]}]}

spec["steps"].each do |st|
  next unless st["file"]
  begin
    load st["file"]
  rescue Exception => e
    errors << "load #{st["file"]}: #{e.class}: #{e.message[0, 200]}"
  end
end

(spec["consts"] || []).each { |c| stub_const(c) rescue nil }

# `Rails.root` is File.join'd by several configs; nil would TypeError.
if Object.const_defined?(:Rails) && Rails.respond_to?(:__stub__)
  Rails.define_singleton_method(:root) { "/nonexistent-autolab-rails-root" }
  Rails.define_singleton_method(:application) { nil }
end

spec["steps"].each do |st|
  (st["modules"] || []).each do |modname|
    decls0 = (ci.instance_variable_get(:@declarations) || {}).dup
    types0 = (ci.instance_variable_get(:@target_types) || {}).dup
    $DT_MOD = modname
    begin
      Object.const_get(modname).install!(ci)
    rescue CallInterceptor::MissingKind, CallInterceptor::MissingType => e
      puts JSON.generate({ "fatal" => e.class.to_s, "module" => modname, "message" => e.message[0, 600] })
      exit 4
    rescue Exception => e
      errors << "install #{modname}: #{e.class}: #{e.message[0, 200]}"
      errors << "  at " + (e.backtrace || []).select { |l| l.include?("targets") }.first(3).join(" | ")
    end
    decls = ci.instance_variable_get(:@declarations) || {}
    types = ci.instance_variable_get(:@target_types) || {}
    decls.each do |t, k|
      if !decls0.key?(t)
        records << { "target" => t, "kind" => k, "type" => types[t], "file" => st["file"],
                     "module" => modname, "event" => "new" }
      elsif decls0[t] != k || types0[t] != types[t]
        records << { "target" => t, "kind" => k, "type" => types[t], "file" => st["file"],
                     "module" => modname, "event" => "redeclared_changed",
                     "prev_kind" => decls0[t], "prev_type" => types0[t] }
      end
    end
  end
end

decls = ci.instance_variable_get(:@declarations) || {}
types = ci.instance_variable_get(:@target_types) || {}
puts JSON.pretty_generate({
  "spec" => spec["steps"],
  "errors" => errors,
  "final_count" => decls.size,
  "events" => records,
  "calls" => $DT_LOG,
  "final" => decls.keys.sort.map { |t| { "target" => t, "kind" => decls[t], "type" => types[t] } }
})
