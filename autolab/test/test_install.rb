# frozen_string_literal: true
#
# test_install.rb -- prove the auto lab's targets library ACTUALLY INSTALLS.
#
# WHY THIS TEST EXISTS, AND WHY IT IS NOT A GREP
# ----------------------------------------------
# The shared master this lab replaces was retired on 2026-09-25 because it had
# stopped loading under either runtime and nobody noticed. It looked FINE to a
# grep: all 67 of its declare_target sites carried the §5.0 `type:` argument,
# neatly, on every line. Not one carried the §4.1.1f `kind:`, so
# `ConcolicTargets.install!` raised MissingKind at its FIRST declaration and
# declared nothing at all.
#
# So this test does the only thing that would have caught that: it RUNS
# install!, against the REAL `CallInterceptor` from src_new, and reads back what
# the interceptor actually holds. It never looks at the source text.
#
# It also runs NEGATIVE CONTROLS (test 7): it takes the real core file, deletes
# one `kind:` argument from it, loads the mutant, and asserts MissingKind is
# raised -- and the same for `type:` and MissingType. A test that cannot fail is
# not evidence, and the mutant is the proof that this one can.
#
#   ruby  test/test_install.rb      (CRuby -- the runtime loads fine under it)
#   jruby test/test_install.rb      (JRuby -- what the sweep actually runs)
#
# WHAT IT DOES NOT PROVE. The diaspora app is not booted here. Rails and the
# app are stub modules (tools/stub_world.rb), so this test proves that every
# declaration satisfies the runtime's declaration-time contract and that
# install! runs to completion -- not that the mock BODIES behave correctly
# against real ActiveRecord. Only a run inside the app proves that.

require "json"
require "tmpdir"
require_relative "../tools/stub_world"

LAB = File.expand_path("..", __dir__)
R4  = "/home/dev/project/reports/diaspora/results4"

$failures = []
$checks = 0

def check(name)
  $checks += 1
  r = yield
  if r == true
    puts "  ok   #{name}"
  else
    $failures << "#{name}: #{r}"
    puts "  FAIL #{name}: #{r}"
  end
rescue StandardError, ScriptError => e
  $failures << "#{name}: #{e.class}: #{e.message}"
  puts "  FAIL #{name}: #{e.class}: #{e.message}"
end

def section(t)
  puts "\n== #{t}"
end

# ---------------------------------------------------------------------------
# Load every config into ONE process, then install each endpoint's stack onto
# its own fresh CallInterceptor.
# ---------------------------------------------------------------------------
ENDPOINTS = JSON.parse(File.read(File.join(LAB, "targets", "registry.json")))
CORE_FILE = File.join(LAB, ENDPOINTS["core"]["file"])

def scrape_consts(files)
  out = `ruby #{File.join(LAB, "tools", "scrape_constants.rb")} #{files.join(" ")}`
  raise "scrape_constants.rb failed" unless $?.success?
  JSON.parse(out)
end

# BOOTSTRAP, and the ORDER MATTERS. The config files define constants of their
# own (ConcolicSymbolicToSql, ConcreteSymbolicString, ConcolicDate, ...), so
# they must be LOADED BEFORE the stub world pre-creates anything, or a stub
# Module ends up where the file wants a Class. Only then are the app's
# constants stubbed -- and they have to be stubbed EAGERLY rather than left to
# const_missing, because `defined?(Stream::Aspect)` does not trigger
# const_missing and every guarded declaration would silently vanish.
ALL_FILES = [CORE_FILE] +
            ENDPOINTS["endpoints"].values.map { |s| File.join(LAB, s["file"]) }
ALL_FILES.each { |f| load f }
load File.join(LAB, "targets", "shared_shims.rb")
scrape_consts(ALL_FILES).each { |c| stub_const(c) rescue nil }
if Object.const_defined?(:Rails) && Rails.respond_to?(:__stub__)
  Rails.define_singleton_method(:root) { "/nonexistent-autolab-rails-root" }
  Rails.define_singleton_method(:application) { nil }
end

def install_endpoint(name)
  spec = ENDPOINTS["endpoints"][name]
  ci = CallInterceptor.new
  (ENDPOINTS["core"]["modules"] + spec["modules"]).each do |m|
    Object.const_get(m).install!(ci)
  end
  shim_report = AutolabSharedShims.install!(
    ci,
    groups: spec["shared_shim_groups"] || [],
    skip: (ci.instance_variable_get(:@declarations) || {}).keys
  )
  [ci, shim_report]
end

results = {}

section "1. every registered endpoint installs, end to end"
ENDPOINTS["endpoints"].keys.each do |ep|
  check("#{ep} installs without raising") do
    ci, rep = install_endpoint(ep)
    results[ep] = [ci, rep]
    d = ci.instance_variable_get(:@declarations) || {}
    d.empty? ? "install! declared NOTHING (the retired master's failure mode)" : true
  end
end

section "2. every declaration carries a kind the runtime accepts"
results.each do |ep, (ci, _)|
  decls = ci.instance_variable_get(:@declarations) || {}
  check("#{ep}: #{decls.size} declarations, all kinds in CallInterceptor::KINDS") do
    bad = decls.reject { |_t, k| CallInterceptor::KINDS.include?(k) }
    bad.empty? ? true : bad.inspect
  end
end

section "3. every declaration carries a §5.0 type the runtime accepts"
results.each do |ep, (ci, _)|
  types = ci.instance_variable_get(:@target_types) || {}
  decls = ci.instance_variable_get(:@declarations) || {}
  check("#{ep}: every declared target has a type") do
    missing = decls.keys.reject { |t| types.key?(t) }
    missing.empty? ? true : missing.inspect
  end
  check("#{ep}: every type passes CallInterceptor.valid_type?") do
    bad = types.reject { |_t, s| CallInterceptor.valid_type?(s) }
    bad.empty? ? true : bad.inspect
  end
end

section "4. `opaque` is an ADMISSION, never reachable by a policy"
results.each do |ep, (ci, _)|
  types = ci.instance_variable_get(:@target_types) || {}
  decls = ci.instance_variable_get(:@declarations) || {}
  check("#{ep}: no opaque on a TARGET_FUNCTION") do
    bad = types.select { |t, s| CallInterceptor.base_type_of(s) == "opaque" }
               .keys
               .select { |t| decls[t] == CallInterceptor::TARGET_FUNCTION }
    bad.empty? ? true : "opaque on TARGET_FUNCTION: #{bad.inspect} -- DESIGN_IR §5.2"
  end
  check("#{ep}: every opaque is behind a SHIM") do
    op = types.select { |_t, s| CallInterceptor.base_type_of(s) == "opaque" }.keys
    bad = op.reject { |t| decls[t] == CallInterceptor::SHIM }
    bad.empty? ? true : bad.inspect
  end
end

section "5. the library is byte-identical to the results4 gold it was copied from"
{
  File.join(LAB, "targets", "core.rb") =>
    File.join(R4, "aspect_memberships_create", "concolic_targets.rb"),
  File.join(LAB, "targets", "endpoints", "aspect_memberships_create.rb") =>
    File.join(R4, "aspect_memberships_create", "targets.rb"),
  File.join(LAB, "targets", "endpoints", "comments_index.rb") =>
    File.join(R4, "comments_index", "targets.rb"),
}.each do |mine, gold|
  check("#{File.basename(mine)} == #{gold.sub("/home/dev/project/", "")}") do
    File.read(mine) == File.read(gold) ? true : "DRIFTED"
  end
end
check("the shared core is identical in BOTH gold batches") do
  a = File.read(File.join(R4, "aspect_memberships_create", "concolic_targets.rb"))
  b = File.read(File.join(R4, "comments_index", "concolic_targets.rb"))
  a == b ? true : "the two results4 cores differ -- 'core' would mean nothing"
end

section "6. shared_shims is a measured NO-OP for the gold endpoints"
results.each do |ep, (_ci, rep)|
  check("#{ep}: shared_shims installed nothing") do
    rep[:installed].empty? ? true : "installed #{rep[:installed].inspect}"
  end
end
check("every AutolabSharedShims group is reachable and declares what it claims") do
  ci = CallInterceptor.new
  AutolabSharedShims::GROUPS.keys.each do |g|
    r = AutolabSharedShims.install!(ci, groups: [g], skip: [])
    got = (r[:installed] + r[:unavailable]).sort
    want = AutolabSharedShims::GROUPS[g].sort
    return "group #{g}: claims #{want.inspect}, reached #{got.inspect}" if got != want
  end
  true
end
check("an unknown group is refused, not silently ignored") do
  begin
    AutolabSharedShims.install!(CallInterceptor.new, groups: ["no_such_group"])
    "no ArgumentError raised"
  rescue ArgumentError
    true
  end
end

# ---------------------------------------------------------------------------
# 7. NEGATIVE CONTROLS. A test that cannot fail is not evidence.
# ---------------------------------------------------------------------------
section "7. negative controls -- the mutants this test must catch"

# The exact failure that retired the shared master: `type:` present everywhere,
# `kind:` missing. A grep over the mutant finds nothing wrong.
def mutant(src, pattern, replacement)
  raise "mutation pattern not found" unless src =~ pattern
  src.sub(pattern, replacement)
end

core_src = File.read(CORE_FILE)

check("deleting one kind: makes install! raise MissingKind") do
  Dir.mktmpdir do |d|
    m = mutant(core_src,
               /interceptor\.declare_target\(core, :find,     kind: CallInterceptor::TARGET_FUNCTION, /,
               "interceptor.declare_target(core, :find,     ")
    path = File.join(d, "mutant_kind.rb")
    File.write(path, m.sub("module ConcolicTargets", "module MutantKindTargets"))
    load path
    begin
      MutantKindTargets.install!(CallInterceptor.new)
      "install! SURVIVED a declaration with no kind: -- this test is blind"
    rescue CallInterceptor::MissingKind
      true
    end
  end
end

check("a grep for `kind:` would NOT have caught that mutant") do
  # The point of the control: the mutant still has 58 other `kind:` sites, so
  # any source-text check that asks 'does this file mention kind:' passes.
  m = mutant(core_src,
             /interceptor\.declare_target\(core, :find,     kind: CallInterceptor::TARGET_FUNCTION, /,
             "interceptor.declare_target(core, :find,     ")
  m.include?("kind: CallInterceptor::TARGET_FUNCTION") ? true : "mutant lost all kind: sites"
end

check("deleting one type: makes install! raise MissingType") do
  Dir.mktmpdir do |d|
    m = mutant(core_src,
               /interceptor\.declare_target\(core, :find_by!, kind: CallInterceptor::TARGET_FUNCTION, type: "obj<\?>", /,
               'interceptor.declare_target(core, :find_by!, kind: CallInterceptor::TARGET_FUNCTION, ')
    path = File.join(d, "mutant_type.rb")
    File.write(path, m.sub("module ConcolicTargets", "module MutantTypeTargets"))
    load path
    begin
      MutantTypeTargets.install!(CallInterceptor.new)
      "install! SURVIVED a declaration with no type: -- this test is blind"
    rescue CallInterceptor::MissingType
      true
    end
  end
end

check("an ill-spelled type is refused by the runtime, not by this test") do
  begin
    CallInterceptor.new.declare_target(stub_const("AutolabProbeKlass"), :whatever,
                                       kind: CallInterceptor::SHIM, type: "T??")
    "valid_type? accepted 'T??'"
  rescue CallInterceptor::MissingType
    true
  end
end

check("the opaque-on-TARGET_FUNCTION check in test 4 can actually fire") do
  ci = CallInterceptor.new
  ci.declare_target(stub_const("AutolabProbeKlass2"), :whatever,
                    kind: CallInterceptor::TARGET_FUNCTION, type: "opaque")
  types = ci.instance_variable_get(:@target_types)
  decls = ci.instance_variable_get(:@declarations)
  bad = types.select { |_t, s| CallInterceptor.base_type_of(s) == "opaque" }
             .keys.select { |t| decls[t] == CallInterceptor::TARGET_FUNCTION }
  bad.empty? ? "the check found nothing in a case that IS a violation" : true
end

# ---------------------------------------------------------------------------
section "8. the measured counts the manifest publishes"
manifest = JSON.parse(File.read(File.join(LAB, "inventory", "manifest.json")))
results.each do |ep, (ci, _)|
  want = manifest["counts"]["per_endpoint"][ep]["total_declared"]
  got = (ci.instance_variable_get(:@declarations) || {}).size
  check("#{ep}: installed #{got} targets, manifest says #{want}") do
    got == want ? true : "manifest is stale -- rerun tools/build_inventory.py"
  end
end
check("core declares what the manifest says (#{manifest["counts"]["core_declarations"]})") do
  ci = CallInterceptor.new
  ConcolicTargets.install!(ci)
  n = (ci.instance_variable_get(:@declarations) || {}).size
  tf = (ci.instance_variable_get(:@declarations) || {})
       .count { |_t, k| k == CallInterceptor::TARGET_FUNCTION }
  sh = (ci.instance_variable_get(:@declarations) || {})
       .count { |_t, k| k == CallInterceptor::SHIM }
  c = manifest["counts"]
  if n == c["core_declarations"] && tf == c["core_target_function"] && sh == c["core_shim"]
    true
  else
    "measured #{n} (#{tf} TF + #{sh} SHIM), manifest says " \
      "#{c["core_declarations"]} (#{c["core_target_function"]} + #{c["core_shim"]})"
  end
end

section "8b. the dormant W2 site, and why it is harmless"
# The probe and this test run in a stub world where every guard is forced
# true, so BOTH `head` declarations install here. The booted app installs only
# one -- `ActionController::Metal.instance_methods.include?(:head)` is false,
# because `head` lives in ActionController::Head and that module is never mixed
# into Metal. The whole maximal-vs-observed difference is that one name
# (inventory/app_reconciliation.json). What this test can check is the reason
# it costs nothing: the two declarations are TWINS.
results.each do |ep, (ci, _)|
  check("#{ep}: Metal#head and Head#head are declared with the same contract") do
    d = ci.instance_variable_get(:@declarations) || {}
    t = ci.instance_variable_get(:@target_types) || {}
    a = "ActionController::Metal#head"
    b = "ActionController::Head#head"
    next "#{a} not declared in the stub world" unless d.key?(a)
    next "#{b} not declared -- the app would lose `head` entirely!" unless d.key?(b)
    if [d[a], t[a]] == [d[b], t[b]]
      true
    else
      "#{a} is #{[d[a], t[a]].inspect} but #{b} is #{[d[b], t[b]].inspect}; " \
        "the dormant W2 site is only harmless while they agree"
    end
  end
end

# ---------------------------------------------------------------------------
section "9. the loader itself -- Autolab::Targets.install!"
# The thing a sweep actually calls. Exercised here in the stub world, so this
# proves its wiring (registry order, layer reporting, the shared_shims skip
# list), not that the diaspora app boots.
require_relative "../autolab_targets"

check("the loader lists exactly the registered endpoints") do
  Autolab::Targets.endpoints == ENDPOINTS["endpoints"].keys.sort ? true :
    Autolab::Targets.endpoints.inspect
end

check("an unregistered endpoint is refused with a pointer to candidates.json") do
  begin
    Autolab::Targets.install!("people_stream", interceptor: CallInterceptor.new)
    "no UnknownEndpoint raised for an endpoint that was only MINED"
  rescue Autolab::Targets::UnknownEndpoint => e
    e.message.include?("candidates.json") ? true : "message lost the pointer"
  end
end

# The parity check runs in a FRESH PROCESS, using the SAME interpreter this
# test is running under, because install! is not idempotent and this process
# has already installed both endpoints several times.
def loader_in_fresh_process(ep, repeats = 1)
  helper = File.join(LAB, "test", "_loader_in_fresh_process.rb")
  out = `#{RbConfig.ruby} #{helper} #{ep} #{repeats} 2>/dev/null`
  raise "helper failed for #{ep}" unless $?.success?
  JSON.parse(out)
end

ENDPOINTS["endpoints"].keys.each do |ep|
  check("loader drives #{ep} to the count the manifest publishes (fresh process)") do
    rep = loader_in_fresh_process(ep).first
    want = manifest["counts"]["per_endpoint"][ep]["total_declared"]
    next "loader declared #{rep["declared_total"]}, manifest says #{want}" \
      if rep["declared_total"] != want
    layers = rep["layers"].map { |l| l["module"] }
    want_layers = ENDPOINTS["core"]["modules"] + ENDPOINTS["endpoints"][ep]["modules"]
    next "layer order #{layers.inspect} != #{want_layers.inspect}" if layers != want_layers
    next "core layer declared nothing" if rep["layers"].first["new"].empty?
    next "first install already reports drift" unless rep["repeat_install_drift"].nil?
    true
  end
  check("#{ep}: the loader REPORTS its double declarations rather than hiding them") do
    rep = Autolab::Targets.install!(ep, interceptor: CallInterceptor.new)
    dd = rep["double_declared"]
    dd.is_a?(Array) && !dd.empty? ? true : "double_declared = #{dd.inspect}"
  end
end

# REGRESSION GUARD for the one non-idempotent site in the corpus
# (targets/endpoints/comments_index.rb:881, a declare_target inside an
# `unless defined?(::ConcolicThroughLoadProbe)` block). If the guard is ever
# fixed this check should be deleted, not silenced -- but it must never fail
# QUIETLY, which is what it did before the loader learned to detect it.
check("the loader detects comments_index's repeat-install drift, and names it") do
  reps = loader_in_fresh_process("comments_index", 2)
  first, second = reps
  next "the 2nd install matched the 1st -- install! became idempotent; " \
       "delete this check and the warning in autolab_targets.rb" \
    if second["repeat_install_drift"].nil?
  lost = second["repeat_install_drift"]["lost"]
  next "drift reported, but lost #{lost.inspect}" \
    if lost != ["ConcolicThroughLoadProbe.load_intermediate"]
  first["declared_total"] - second["declared_total"] == 1 ? true :
    "expected exactly one target lost"
end

check("aspect_memberships_create IS repeat-install stable (the control)") do
  reps = loader_in_fresh_process("aspect_memberships_create", 2)
  reps[1]["repeat_install_drift"].nil? ? true : reps[1]["repeat_install_drift"].inspect
end

puts
puts "#{$checks - $failures.size}/#{$checks} checks passed"
unless $failures.empty?
  puts "FAILURES:"
  $failures.each { |f| puts "  - #{f}" }
  exit 1
end
puts "OK"
