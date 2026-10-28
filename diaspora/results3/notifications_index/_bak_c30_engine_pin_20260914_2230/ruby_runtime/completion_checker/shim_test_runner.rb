# SHIM TEST RUNNER (Ruby-runtime-specific execution step of the completion
# engine). Driven by completion_checker.py — NOT agent-triggered: the
# engine extracts the shim list, this runner executes the agent-PROVIDED
# test per shim and verifies the shim contract, and the engine records
# every verdict in the completion report. A shim with no test entry and no
# waiver is a red verdict the agent cannot avoid by omission.
#
#   JRUBY_OPTS=--debug scripts/diaspora-concolic shim_test_runner.rb \
#     <shims.json> <batch>/shim_tests.rb <out_results.json>
#
# shim_tests.rb (agent-provided bodies, ENGINE-enumerated keys):
#   SHIM_TESTS = {
#     "h.image_path" => { targets: [[Mod, :meth], ...],   # zero-target set
#                         coverage_of: [Owner, :meth, :singleton|:instance],
#                         fixture: -> { ... } },
#     "Person.singleton_class.DYNAMIC" =>
#       { waiver: "kwargs-capture plumbing; wraps aliased find_by, no body of its own" },
#   }
# Keys are "<owner-as-extracted>.<method>". Verdicts per shim:
#   PASS (zero targets + 100% executable-line coverage of the REAL body)
#   FAIL-TARGETS / FAIL-COVERAGE / FAIL-ERROR
#   WAIVED (reason recorded)  |  NO-TEST (red — nothing provided)
require "coverage"
Coverage.start
require "json"
require "./config/environment"
require_relative "target_call_probe"

shims_path, tests_path, out_path = ARGV
abort "usage: shim_test_runner.rb <shims.json> <shim_tests.rb> <out.json>" unless out_path
shims = JSON.parse(File.read(shims_path))
load File.expand_path(tests_path)
abort "shim_tests.rb must define SHIM_TESTS" unless defined?(SHIM_TESTS)

def method_line_range(owner, meth, singleton)
  m = singleton == :singleton ? owner.method(meth) : owner.instance_method(meth)
  file, start = m.source_location
  return nil unless file && File.exist?(file)
  lines = File.readlines(file)
  depth = 0
  opener = /\b(def|do|if|unless|case|while|until|begin|class|module)\b/
  fin = start
  (start - 1).upto(lines.size - 1) do |i|
    l = lines[i].sub(/#.*$/, "")
    depth += l.scan(opener).size - l.scan(/\bend\b/).size
    # modifier if/unless don't open blocks — but `x = if ...`, `(if ...`,
    # `|| if`, `return if` DO open one (found 2026-08-26: `result = if size`
    # in Profile#image_url was miscounted as a modifier, truncating the
    # range and reporting 100% over lines that never ran)
    mods = l.scan(/\S\s+(if|unless|while|until)\s/).size
    mods -= l.scan(/(=|\(|\|\||&&|,|return)\s+(if|unless|while|until)\s/).size
    depth -= mods if mods > 0
    if depth <= 0
      fin = i + 1
      break
    end
  end
  [file, start, fin]
end

# Is this stub a mock over APPLICATION code, or the synthetic representative
# object's own machinery? (DISCIPLINE Rule S, 2026-08-27 — decided at RUNTIME
# from the real class, never from prose.) A stub is machinery when the real
# class does not define the method at all (`concolic_attrs`, `convidx_dirty`)
# or defines it only through the AR / Ruby object PROTOCOL
# (`read_attribute`, `attributes`, `persisted?`, `hash`, `inspect`, a plain
# column reader). Anything with a body of its own — an app method, a gem
# method we stand in for — is a shim and must be RUN in a test.
# Generated attribute/association modules ARE the AR protocol: a column
# reader lives in `Message::GeneratedAttributeMethods`, an association reader
# in `…::GeneratedAssociationMethods` (conversations_index, 2026-08-28).
# NOTE the generated modules are ANONYMOUS INSTANCES — `owner.to_s` reads
# `#<ActiveRecord::AttributeMethods::GeneratedAttributeMethods:0x65227bd6>`,
# so neither a leading `\AActiveRecord` nor a trailing `…Methods\z` anchor
# matches (conversations_index, 2026-08-28). Match unanchored.
PROTOCOL_OWNERS = /((\A|<)(ActiveRecord|ActiveModel|Object|Kernel|BasicObject|Module|Class)\b|Generated(Attribute|Association)Methods)/

# The protocol API a symbolic representative must implement to look like a
# record at all: ActiveRecord's attribute/persistence surface, Ruby's object
# protocol, and the runtime's own bookkeeping. Engine-owned and auditable —
# a batch cannot extend it by writing prose. Anything NOT on this list (an
# app method like `image_url`, a presenter helper like `post_location`) is a
# shim over real code and needs a real test, even when the receiver is a
# local whose class cannot be resolved statically.
PROTOCOL_API = %w[
  read_attribute _read_attribute write_attribute _write_attribute
  attributes attribute_names [] []= id to_param to_key
  persisted? new_record? destroyed? frozen? readonly?
  hash eql? == inspect to_s class
].freeze
PROTOCOL_API_RE = /\A(concolic_\w+|\w*_dirty)\z/   # runtime bookkeeping

def machinery?(shim)
  return false unless shim["kind"] == "rep_plumbing" || shim["kind"] == "value_class"
  m = shim["method"].to_s
  return true if PROTOCOL_API.include?(m) || m =~ PROTOCOL_API_RE
  owner_name = shim["real_class"] || shim["owner"]
  klass = (Object.const_get(owner_name) rescue nil)
  return false if klass.nil?     # unresolvable receiver + not protocol => test it
  sym = m.to_sym
  # AR defines attribute methods LAZILY: `Message.method_defined?(:text)` is
  # false until something touches them, which made a plain column reader look
  # like "a body of its own" (conversations_index, 2026-08-28).
  klass.define_attribute_methods if klass.respond_to?(:define_attribute_methods)
  # A COLUMN is the protocol, by definition — the surest fact available, and
  # it does not depend on how the generated module happens to print itself.
  if klass.respond_to?(:column_names)
    base = m.sub(/[?=!]\z/, "")
    return true if (klass.column_names.include?(base) rescue false)
  end
  # A method the real class does not define AT ALL is the rep's own
  # machinery (`concolic_attrs`, `convidx_dirty`) — the doc rule above.
  return true unless klass.method_defined?(sym) || klass.private_method_defined?(sym)
  klass.instance_method(sym).owner.to_s =~ PROTOCOL_OWNERS ? true : false
rescue StandardError
  false
end

# A STRAIGHT-LINE body has no branch of any kind: no conditional, loop,
# rescue, ternary or short-circuit operator. Such a body cannot be partially
# executed — if its entry line ran, every expression in it ran. JRuby's
# Coverage attributes a multi-line literal (a presenter's `as_json` hash,
# an array literal) to its FIRST line and reports 0 for the continuation
# lines, so line coverage understates a body that in fact executed
# completely (comments_index `CommentPresenter.as_json`: 28.6% with all six
# keys demonstrably produced). For straight-line bodies only, entry-line
# execution IS full coverage; anything with a branch keeps the 100% bar.
# (Rule S, 2026-08-28 — a measurement limit answered with a stronger
# structural claim, never with a waiver.)
# A GENERATED method (AR's association/attribute readers are built with
# `mixin.class_eval <<-CODE, __FILE__, __LINE__+1`) reports a source_location
# inside the BUILDER TEMPLATE, whose lines never execute — line coverage is
# structurally 0% for every such method, in every batch
# (associations/builder/association.rb:105-110). Coverage is therefore not a
# measurable property of these methods; what IS measurable is that the method
# actually ran, which the runner observes with a TracePoint. (Rule S,
# 2026-08-28 — an unmeasurable instrument replaced, not waived.)
def generated_method?(file, line, owner = nil, meth = nil)
  # owner-based: AR's generated modules are definitive
  if owner && meth
    k = (owner.is_a?(Module) ? owner : (Object.const_get(owner.to_s) rescue nil))
    if k && k.method_defined?(meth.to_sym)
      return true if k.instance_method(meth.to_sym).owner.to_s =~ /::Generated(Attribute|Association)Methods\z/
    end
  end
  return true unless file && File.exist?(file)
  src = File.readlines(file)[line - 1].to_s
  return true if src =~ /def\s+\#\{/     # an INTERPOLATED def: a builder template
  !(src =~ /\bdef\s+/)
rescue StandardError
  false
end

def observe_invocation(owner, meth, kind)
  invoked = false
  tp = TracePoint.new(:call) do |t|
    invoked = true if t.method_id.to_s == meth.to_s
  end
  tp.enable
  yield
  invoked
ensure
  tp.disable rescue nil
end

def straight_line_body?(file, s0, f0)
  src = File.readlines(file)[(s0 - 1)...f0].join
  code = src.gsub(/#[^\n]*/, "")           # comments
             .gsub(/"(\\.|[^"\\])*"/, '""')  # string literals
             .gsub(/'(\\.|[^'\\])*'/, "''")
             .gsub(/:[a-zA-Z_][a-zA-Z_0-9]*[?!]?/, ":sym")   # symbols (incl. :foo?)
             .sub(/\A\s*def\b[^\n]*\n/, "")               # the def line itself
  return false if code =~ /\b(if|unless|case|when|elsif|else|while|until|for|rescue|ensure|and|or|loop|each|map|select|reject|detect|find|any\?|all\?)\b/
  return false if code =~ /(\?|&&|\|\||\bthen\b)/
  true
end

results = shims.map do |shim|
  key = "#{shim['owner']}.#{shim['method']}"
  spec = SHIM_TESTS[key]
  base = shim.merge("key" => key)
  # A batch may state the CLASS a rep stands for — `{ real_class: "Comment" }`
  # — instead of a test. That is a fact the runner CHECKS against the real
  # class (is `Comment#text` defined only by the AR attribute protocol?), not
  # prose: if the class does not back the claim, it falls through and the
  # shim still needs a test.
  if spec && spec[:real_class] && spec[:fixture].nil?
    if machinery?(shim.merge("real_class" => spec[:real_class].to_s, "kind" => "rep_plumbing"))
      next base.merge("verdict" => "PROTOCOL",
                      "detail" => "#{spec[:real_class]}##{shim['method']} is defined by the " \
                                  "AR/Ruby protocol — verified against the real class")
    else
      next base.merge("verdict" => "FAIL-NOT-PROTOCOL",
                      "detail" => "#{spec[:real_class]}##{shim['method']} has a body of its own — " \
                                  "this is a shim over app code and needs a test")
    end
  end
  if machinery?(shim) && spec.nil?
    next base.merge("verdict" => "PROTOCOL",
                    "detail" => "runtime rep machinery: the real class defines this only through " \
                                "the AR/Ruby protocol (or not at all) — no app body to run against")
  end
  if spec.nil?
    next base.merge("verdict" => "NO-TEST",
                    "detail" => "engine-extracted shim with no test and no waiver")
  end
  if spec[:waiver]
    # Waivers are no longer a passing verdict (2026-08-27, Bali): a shim must
    # be RUN. If it cannot run as-is, the test supplies the minimal mocks
    # needed to run it concretely and justifies each one. The reason text is
    # kept so the report says what was claimed.
    next base.merge("verdict" => "FAIL-WAIVER-NOT-ALLOWED", "detail" => spec[:waiver])
  end
  begin
    invoked = false
    _owner, _meth, _kind = spec[:coverage_of]
    tp = TracePoint.new(:call, :c_call) do |t|
      invoked = true if _meth && t.method_id.to_s == _meth.to_s
    end
    tp.enable
    calls = CompletionChecker::TargetCallProbe.capture(
      targets: spec[:targets], &spec[:fixture])
    tp.disable
    cov = Coverage.peek_result
    owner, meth, kind = spec[:coverage_of]
    range = method_line_range(owner, meth, kind || :instance)
    if range
      file, s0, f0 = range
      counts = (cov[file] || [])[s0 - 1...f0] || []
      executable = counts.each_index.select { |i| counts[i] }
      missed = executable.select { |i| counts[i] == 0 }.map { |i| s0 + i }
      cov_pct = executable.empty? ? 0 :
                (100.0 * (executable.size - missed.size) / executable.size).round(1)
    else
      cov_pct, missed, executable = 0, [], []
    end
    # A DISPATCH/NAMING layer (a byte-faithful prepend, a loaded?-branch
    # dispatcher) cannot reach zero targets — reaching the declared target IS
    # its job. For those the test declares `reaches:` and the claim tested is
    # EQUALITY: the layer reaches exactly the declared target(s), nothing
    # else. Everything else keeps the zero-target bar. (Rule S, 2026-08-27:
    # the point is that the true claim is tested, not that the bar is waived.)
    reached = calls.map { |c| c["target"].to_s }.uniq.sort
    declared = (spec[:reaches] || []).map(&:to_s).uniq.sort
    target_ok = spec[:reaches] ? (reached == declared) : calls.empty?
    verdict =
      if !target_ok
        spec[:reaches] ? "FAIL-REACHES" : "FAIL-TARGETS"
      elsif spec[:coverage_waiver] then "FAIL-COVERAGE"  # coverage waivers are not accepted either
      elsif executable.empty?
        (range && generated_method?(file, s0, _owner, _meth) && invoked) ? "PASS" : "FAIL-COVERAGE"
      elsif !missed.empty?
        entry_ran = (counts[executable.first] || 0) > 0
        if range && generated_method?(file, s0, _owner, _meth) && invoked
          "PASS"   # generated method: coverage unmeasurable, invocation observed
        elsif range && entry_ran && straight_line_body?(file, s0, f0)
          "PASS"   # straight-line body: entry line ran => whole body ran
        else "FAIL-COVERAGE"
        end
      else "PASS"
      end
    base.merge("verdict" => verdict,
               "targets_reached" => reached,
               "targets_declared" => (spec[:reaches] ? declared : []),
               "coverage_pct" => cov_pct,
               "invoked" => invoked,
               "generated" => (range ? generated_method?(file, s0, _owner, _meth) : nil),
               "coverage_waiver" => spec[:coverage_waiver],
               "missed_lines" => missed.first(10))
  rescue => e
    base.merge("verdict" => "FAIL-ERROR", "detail" => "#{e.class}: #{e.message[0, 120]}")
  end
end

File.write(out_path, JSON.pretty_generate(results))
results.each { |r| puts format("%-14s %s", r["verdict"], r["key"]) }
